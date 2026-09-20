#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )); then
    echo "Run the Session Stack lock as the desktop user, not root." >&2
    exit 1
fi

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd)
project_root=$(cd -- "$script_dir/.." && pwd)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
config_dir=${SESSION_STACK_LOCK_CONFIG_DIR:-"${config_home}/quickshell/session-stack-lock"}
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
lid_monitor=${SESSION_STACK_LID_MONITOR:-"${HOME}/.local/bin/session-stack-lid-monitor"}
hyprlock_owner_marker="${runtime_dir}/session-stack-hyprlock.owner"
lock_policy_file="${project_root}/system/session-stack-lock-policy"
quickshell_lock_capability='quickshell-session-lock-output-teardown>=1'
# Seven seconds plus three capped queries stays below the guard's 12-second limit.
prepare_sleep_budget_seconds=7
compositor_query_timeout=1
compositor_query_kill_after=0.25

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command is missing: $1" >&2
        return 1
    fi
}

read_primary_lock_policy() {
    local policy

    [[ -r $lock_policy_file ]] || return 1
    policy=$(sed -n 's/^primary_lock_policy=//p' "$lock_policy_file")
    case "$policy" in
        recovery-only|patched-primary-allowed)
            printf '%s\n' "$policy"
            ;;
        *)
            return 1
            ;;
    esac
}

quickshell_output_lifecycle_capable() {
    command -v pacman >/dev/null 2>&1 \
        && pacman -T "$quickshell_lock_capability" >/dev/null 2>&1
}

select_lock_backend() {
    local policy

    policy=$(read_primary_lock_policy) || policy=recovery-only
    if [[ $policy == patched-primary-allowed ]] \
            && quickshell_output_lifecycle_capable; then
        printf '%s\n' quickshell
    else
        printf '%s\n' managed-hyprlock
    fi
}

check_pam_service() {
    local service_name=$1
    local source_file="${project_root}/system/pam.d/${service_name}"
    local target_file="/etc/pam.d/${service_name}"

    if [[ ! -f $target_file ]] || ! cmp --silent "$source_file" "$target_file"; then
        echo "Dedicated PAM service is missing or stale: $target_file" >&2
        return 1
    fi

    if [[ $(stat -c '%U:%G:%a' "$target_file") != "root:root:644" ]]; then
        echo "Unsafe PAM service owner or mode: $target_file" >&2
        return 1
    fi
}

check_faillock_isolation() {
    local source_file="${project_root}/system/security/session-stack-faillock.conf"
    local target_file=/etc/security/session-stack-faillock.conf

    if [[ ! -f $target_file ]] || ! cmp --silent "$source_file" "$target_file"; then
        echo "Dedicated lock faillock configuration is missing or stale: $target_file" >&2
        return 1
    fi
    if [[ $(stat -c '%U:%G:%a' "$target_file") != root:root:644 ]]; then
        echo "Unsafe lock faillock configuration owner or mode: $target_file" >&2
        return 1
    fi
    if [[ $(stat -c '%U:%G:%a' /run/session-stack-faillock 2>/dev/null) != root:root:755 ]]; then
        echo "Dedicated lock faillock directory is missing or unsafe." >&2
        return 1
    fi
}

lock_ipc_call() {
    timeout --kill-after="$compositor_query_kill_after" \
        "$compositor_query_timeout" \
        quickshell ipc --any-display --path "$config_dir" \
            call lockPrototype "$1" 2>/dev/null || true
}

read_session_locked() {
    [[ $(timeout --kill-after="$compositor_query_kill_after" \
        "$compositor_query_timeout" hyprctl locked 2>/dev/null) == true ]]
}

hyprlock_start_time() {
    local hyprlock_pid=$1

    awk '{print $22}' "/proc/$hyprlock_pid/stat" 2>/dev/null
}

managed_hyprlock_active() {
    local recorded_pid
    local recorded_start

    [[ -r $hyprlock_owner_marker ]] || return 1
    read -r recorded_pid recorded_start <"$hyprlock_owner_marker"
    [[ $recorded_pid =~ ^[0-9]+$ && $recorded_start =~ ^[0-9]+$ ]] \
        || return 1
    [[ -r /proc/$recorded_pid/comm \
            && $(</proc/$recorded_pid/comm) == hyprlock ]] || return 1
    [[ $(hyprlock_start_time "$recorded_pid") == "$recorded_start" ]]
}

run_managed_hyprlock() {
    local hyprlock_pid
    local hyprlock_start
    local marker_record
    local marker_temp
    local recovery_status
    local -a recovery_args=(--no-fade-in)
    if [[ -n ${SESSION_STACK_HYPRLOCK_CONFIG:-} ]]; then
        recovery_args+=(--config "$SESSION_STACK_HYPRLOCK_CONFIG")
    fi

    if [[ ! -d $runtime_dir || ! -O $runtime_dir ]]; then
        exec hyprlock "${recovery_args[@]}"
    fi

    hyprlock "${recovery_args[@]}" &
    hyprlock_pid=$!
    hyprlock_start=$(hyprlock_start_time "$hyprlock_pid")
    if [[ $hyprlock_start =~ ^[0-9]+$ ]]; then
        marker_record="$hyprlock_pid $hyprlock_start"
        marker_temp="${hyprlock_owner_marker}.new.$$"
        printf '%s\n' "$marker_record" >"$marker_temp"
        mv -T -- "$marker_temp" "$hyprlock_owner_marker"
    fi

    if wait "$hyprlock_pid"; then
        recovery_status=0
    else
        recovery_status=$?
    fi
    if [[ -n ${marker_record:-} && -r $hyprlock_owner_marker \
            && $(<"$hyprlock_owner_marker") == "$marker_record" ]]; then
        unlink -- "$hyprlock_owner_marker"
    fi
    return "$recovery_status"
}

start_recovery_lock() {
    if ! command -v hyprlock >/dev/null 2>&1; then
        echo "Hyprlock recovery is unavailable; the session could not be locked." >&2
        return 1
    fi

    if pgrep -x hyprlock >/dev/null 2>&1; then
        if managed_hyprlock_active; then
            echo "Managed Hyprlock already owns or is requesting the session lock."
            return 0
        fi
        if read_session_locked; then
            echo "An existing Hyprlock process owns the compositor lock."
            return 0
        fi
        echo "An unverified Hyprlock process exists, but the compositor is not locked." >&2
        return 1
    fi

    echo "Starting Hyprlock recovery because the primary lock is unavailable." >&2
    run_managed_hyprlock
}

read_lock_restore_value() {
    hyprctl -j getoption misc:allow_session_lock_restore \
        | jq -er '
            if has("bool") then
                if .bool then 1 else 0 end
            elif has("int") then
                .int
            else
                error("missing bool/int option value")
            end
        '
}

set_lock_restore_value() {
    local requested_value=$1
    local expected_value
    local hyprland_value

    case "$requested_value" in
        1|true)
            expected_value=1
            hyprland_value=true
            ;;
        0|false)
            expected_value=0
            hyprland_value=false
            ;;
        *)
            echo "Invalid session-lock restore value: $requested_value" >&2
            return 1
            ;;
    esac

    hyprctl eval \
        "hl.config({ misc = { allow_session_lock_restore = ${hyprland_value} } })" \
        >/dev/null
    [[ $(read_lock_restore_value) == "$expected_value" ]]
}

preflight() {
    local command_name
    local qml_file
    local service_name
    local lock_source_dir="${project_root}/quickshell/session-stack-lock"
    local -a required_qml_files=()

    mapfile -t required_qml_files < <(
        find -L "$lock_source_dir" -type f \
            \( -name '*.qml' -o -name '*.js' \) -printf '%P\n' | sort
    )

    for command_name in cmp find flock hyprctl hyprlock jq mktemp pgrep quickshell sleep stat timeout; do
        require_command "$command_name" || return 1
    done

    if [[ ! -x $lid_monitor ]]; then
        echo "Session Stack lid monitor is missing or not executable: $lid_monitor" >&2
        return 1
    fi

    if [[ -z ${WAYLAND_DISPLAY:-} || -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        echo "Run the Session Stack lock from the active Hyprland session." >&2
        return 1
    fi

    if [[ ! -d $runtime_dir || ! -O $runtime_dir ]]; then
        echo "Unsafe or unavailable runtime directory: $runtime_dir" >&2
        return 1
    fi

    if (( ${#required_qml_files[@]} == 0 )); then
        echo "No Session Stack lock components were found in $lock_source_dir" >&2
        return 1
    fi

    for qml_file in "${required_qml_files[@]}"; do
        if [[ ! -f "${config_dir}/${qml_file}" ]]; then
            echo "Session Stack lock component is not deployed: ${config_dir}/${qml_file}" >&2
            return 1
        fi
        if ! cmp --silent \
                "${lock_source_dir}/${qml_file}" \
                "${config_dir}/${qml_file}"; then
            echo "Session Stack lock component is stale: ${config_dir}/${qml_file}" >&2
            return 1
        fi
    done

    check_pam_service session-stack-lock-password || return 1
    if [[ ,${SESSION_STACK_ENABLED_METHODS:-password}, == *,face,* ]]; then
        check_pam_service session-stack-lock-face || return 1
        if [[ ! -r "/var/lib/howrs/$(id -un)/faces.bin" ]]; then
            echo "Howrs enrollment is unavailable to $(id -un)." >&2
            return 1
        fi
    fi
    if [[ ,${SESSION_STACK_ENABLED_METHODS:-password}, == *,fingerprint,* ]]; then
        check_pam_service session-stack-lock-fingerprint || return 1
    fi
    check_faillock_isolation || return 1

    restore_value=$(read_lock_restore_value)
    if [[ $restore_value != "0" && $restore_value != "1" ]]; then
        echo "Could not read misc:allow_session_lock_restore." >&2
        return 1
    fi
}

case "${1:-lock}" in
    --print-backend)
        select_lock_backend
        exit 0
        ;;
    --check)
        selected_backend=$(select_lock_backend)
        if [[ $selected_backend == quickshell ]]; then
            preflight
        else
            for command_name in flock hyprctl hyprlock pgrep timeout; do
                require_command "$command_name"
            done
        fi
        echo "Session Stack production lock preflight passed with backend: $selected_backend"
        exit 0
        ;;
    --prepare-sleep)
        "$script_path" lock &

        SECONDS=0
        while (( SECONDS < prepare_sleep_budget_seconds )); do
            lock_status=$(lock_ipc_call status)
            session_locked=0
            if read_session_locked; then
                session_locked=1
            fi

            if [[ $lock_status == "secure" || $session_locked == "1" ]]; then
                pause_status=$(lock_ipc_call prepareForSleep)
                if [[ $pause_status == "paused" ]]; then
                    echo "QuickShell secured the compositor and paused biometrics before sleep."
                    exit 0
                fi

                if (( session_locked )) && managed_hyprlock_active; then
                    echo "Hyprlock secured the compositor before sleep; no QuickShell biometric workers are active."
                    exit 0
                fi
            fi
            sleep 0.1
        done

        echo "No lock client reported both compositor security and biometric shutdown within ${prepare_sleep_budget_seconds}s." >&2
        exit 1
        ;;
    lock)
        ;;
    *)
        echo "Usage: $0 [--check|--prepare-sleep|--print-backend]" >&2
        exit 2
        ;;
esac

for command_name in flock hyprctl hyprlock pgrep timeout; do
    require_command "$command_name" || exit 1
done
if [[ ! -d $runtime_dir || ! -O $runtime_dir ]]; then
    echo "Unsafe or unavailable runtime directory: $runtime_dir" >&2
    exit 1
fi

exec 9>"${runtime_dir}/session-stack-lock-launcher.lock"
if ! flock --nonblock 9; then
    echo "Session Stack lock launcher is already active."
    exit 0
fi

if pgrep -x hyprlock >/dev/null 2>&1; then
    start_recovery_lock
    exit $?
fi

selected_backend=$(select_lock_backend)
if [[ $selected_backend == managed-hyprlock ]]; then
    echo "Session Stack lock policy selected managed Hyprlock."
    start_recovery_lock
    exit $?
fi

if ! preflight; then
    start_recovery_lock
    exit $?
fi

marker_dir=$(mktemp -d --tmpdir="$runtime_dir" session-stack-lock.XXXXXX)
unlock_marker="$marker_dir/unlocked"
original_restore=$(read_lock_restore_value)
restore_pending=0

cleanup() {
    local cleanup_status=$?

    if (( restore_pending )); then
        if ! set_lock_restore_value "$original_restore"; then
            echo "Could not restore misc:allow_session_lock_restore=$original_restore" >&2
            cleanup_status=1
        fi
    fi

    if [[ $marker_dir == "$runtime_dir"/session-stack-lock.* ]]; then
        [[ ! -e $unlock_marker ]] || unlink -- "$unlock_marker"
        rmdir -- "$marker_dir" 2>/dev/null || true
    fi

    exit "$cleanup_status"
}
trap cleanup EXIT

echo "Enabling guarded session-lock recovery."
restore_pending=1
set_lock_restore_value 1

set +e
env \
    SESSION_STACK_LOCK_MODE=lock \
    SESSION_STACK_LOCK_ACK=I_HAVE_TTY_RECOVERY \
    SESSION_STACK_UNLOCK_MARKER="$unlock_marker" \
    quickshell --no-duplicate --path "$config_dir"
quickshell_status=$?
set -e

if [[ -f $unlock_marker ]]; then
    echo "QuickShell explicitly released the compositor lock."
    if [[ $quickshell_status -ne 0 ]]; then
        echo "QuickShell exited with status $quickshell_status after explicit unlock." >&2
        exit 1
    fi
    exit 0
fi

echo "QuickShell exited without an unlock marker; starting hyprlock recovery." >&2
set +e
run_managed_hyprlock
recovery_status=$?
set -e

if [[ $recovery_status -ne 0 ]]; then
    echo "hyprlock recovery exited with status $recovery_status." >&2
fi
if [[ $quickshell_status -ne 0 ]]; then
    echo "QuickShell exited with status $quickshell_status." >&2
fi

exit 1
