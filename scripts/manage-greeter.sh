#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd -- "$script_dir/.." && pwd)
source_config="$project_root/quickshell/session-stack-greeter"
install_base=/usr/local/share/session-stack-greeter
release_base="$install_base/releases"
current_link="$install_base/current"
launcher_dir=/usr/local/lib/session-stack-greeter
launcher_target="$launcher_dir/launch-greeter"
biometric_helper_target="$launcher_dir/authenticate-biometric"
pam_module_target="$launcher_dir/pam_session_stack_greeter.so"
pam_module_manifest_target="$launcher_dir/pam_session_stack_greeter.manifest"
greetd_target=/etc/greetd/hyprland.lua
greetd_backup=/etc/greetd/hyprland.lua.pre-session-stack-greeter
greetd_config_target=/etc/greetd/config.toml
greetd_config_source="$project_root/system/greetd/config.toml"
greetd_config_backup=/etc/greetd/config.toml.pre-session-stack-greeter
candidate_lua="$project_root/system/greetd/hyprland-session-stack.lua"
recovery_lua="$project_root/system/greetd/hyprland-regreet.lua"
pam_target=/etc/pam.d/greetd
pam_backup=/etc/pam.d/greetd.pre-session-stack-greeter
candidate_pam="$project_root/system/pam.d/greetd-session-stack"
recovery_pam="$project_root/system/pam.d/greetd-recovery"

require_root() {
    if (( EUID != 0 )); then
        echo "Run this command with sudo." >&2
        exit 1
    fi
}

tree_digest() {
    local tree=$1
    find "$tree" -type f -printf '%P\0' | sort -z \
        | while IFS= read -r -d '' relative_path; do
            printf '%s  %s\n' \
                "$(sha256sum "$tree/$relative_path" | awk '{print $1}')" \
                "$relative_path"
        done | sha256sum | awk '{print $1}'
}

materialize_release() {
    local target=$1
    cp -a -- "$source_config/." "$target/"
    unlink -- "$target/common"
    cp -a -- "$project_root/quickshell/common" "$target/common"
    "$project_root/scripts/generate-system-data.py" \
        --output "$target/GeneratedSystemData.qml"
}

release_tree_is_immutable() {
    local tree=$1
    [[ -z $(find "$tree" ! -user root -print -quit) ]] \
        && [[ -z $(find "$tree" ! -group root -print -quit) ]] \
        && [[ -z $(find "$tree" ! -type d ! -type f -print -quit) ]] \
        && [[ -z $(find "$tree" -type d ! -perm 0555 -print -quit) ]] \
        && [[ -z $(find "$tree" -type f ! -perm 0444 -print -quit) ]]
}

stage_release() {
    local digest
    local release_dir
    local stage_dir
    local next_link
    local pam_module_stage
    local pam_manifest_stage

    cleanup_stage() {
        if [[ -n ${stage_dir:-} && -d $stage_dir \
                && $stage_dir == "$release_base"/.stage.* ]]; then
            chmod -R u+w "$stage_dir"
            rm -rf -- "$stage_dir"
        fi
        if [[ -n ${pam_module_stage:-} && -f $pam_module_stage \
                && $pam_module_stage == "$launcher_dir"/.pam-module.* ]]; then
            rm -f -- "$pam_module_stage"
        fi
        if [[ -n ${pam_manifest_stage:-} && -f $pam_manifest_stage \
                && $pam_manifest_stage == "$launcher_dir"/.pam-manifest.* ]]; then
            rm -f -- "$pam_manifest_stage"
        fi
    }

    require_root
    install -d -o root -g root -m 0755 "$release_base" "$launcher_dir"
    stage_dir=$(mktemp -d --tmpdir="$release_base" .stage.XXXXXX)
    trap cleanup_stage EXIT
    materialize_release "$stage_dir"
    digest=$(tree_digest "$stage_dir")
    release_dir="$release_base/${digest:0:20}"

    chown -R root:root "$stage_dir"
    find "$stage_dir" -type d -exec chmod 0755 {} +
    find "$stage_dir" -type f -exec chmod 0644 {} +
    chmod -R a-w "$stage_dir"

    if [[ ! -e $release_dir && ! -L $release_dir ]]; then
        mv -- "$stage_dir" "$release_dir"
        stage_dir=""
    elif [[ -d $release_dir && ! -L $release_dir ]]; then
        if [[ $(tree_digest "$release_dir") != "$digest" ]] \
                || ! release_tree_is_immutable "$release_dir"; then
            mv --exchange --no-copy -T -- "$stage_dir" "$release_dir"
        fi
        cleanup_stage
        stage_dir=""
    else
        echo "Refusing to replace unsafe release path: $release_dir" >&2
        exit 1
    fi

    install -o root -g root -m 0755 \
        "$project_root/scripts/launch-greeter.sh" "$launcher_target"
    install -o root -g root -m 0755 \
        "$project_root/scripts/authenticate-greeter-biometric.sh" \
        "$biometric_helper_target"
    pam_module_stage=$(mktemp --tmpdir="$launcher_dir" .pam-module.XXXXXX)
    TMPDIR="$launcher_dir" cc -std=c17 -O2 -fPIC -shared \
        -Wall -Wextra -Werror \
        -Wl,-z,relro,-z,now \
        "$project_root/src/pam_session_stack_greeter.c" -lpam \
        -o "$pam_module_stage"
    chown root:root "$pam_module_stage"
    chmod 0644 "$pam_module_stage"
    mv -f -- "$pam_module_stage" "$pam_module_target"
    pam_module_stage=""
    pam_manifest_stage=$(mktemp --tmpdir="$launcher_dir" .pam-manifest.XXXXXX)
    printf '%s %s\n' \
        "$(sha256sum "$project_root/src/pam_session_stack_greeter.c" | awk '{print $1}')" \
        "$(sha256sum "$pam_module_target" | awk '{print $1}')" \
        > "$pam_manifest_stage"
    chown root:root "$pam_manifest_stage"
    chmod 0644 "$pam_manifest_stage"
    mv -f -- "$pam_manifest_stage" "$pam_module_manifest_target"
    pam_manifest_stage=""
    next_link="$install_base/.current.$$"
    ln -s "releases/${digest:0:20}" "$next_link"
    mv -Tf -- "$next_link" "$current_link"
    trap - EXIT
    echo "Staged greeter release ${digest:0:20}."
}

status() {
    local result=0
    local expected_dir
    local expected_digest
    local expected_release_name
    local expected_link_target
    local current_release
    local status_tmp_base=${TMPDIR:-/tmp}

    if [[ ! -d $status_tmp_base || ! -w $status_tmp_base ]]; then
        status_tmp_base=$release_base
    fi
    expected_dir=$(mktemp -d --tmpdir="$status_tmp_base" .status.XXXXXX)
    cleanup_status() {
        if [[ -n ${expected_dir:-} && -d $expected_dir ]]; then
            rm -rf -- "$expected_dir"
        fi
    }
    trap cleanup_status EXIT
    materialize_release "$expected_dir"
    expected_digest=$(tree_digest "$expected_dir")
    expected_release_name=${expected_digest:0:20}
    expected_link_target="releases/$expected_release_name"
    current_release=$(readlink -f -- "$current_link" 2>/dev/null || true)

    if [[ -L $current_link && -r $current_link/shell.qml ]]; then
        echo "staged: $(readlink -f -- "$current_link")"
    else
        echo "staged: unavailable"
        result=1
    fi

    if [[ -L $current_link ]] \
            && [[ $(readlink -- "$current_link") == "$expected_link_target" ]] \
            && [[ -d $current_release ]] \
            && [[ $(tree_digest "$current_release") == "$expected_digest" ]] \
            && release_tree_is_immutable "$current_release"; then
        echo "QML release: current"
    else
        echo "QML release: missing or stale"
        result=1
    fi

    if [[ -f $launcher_target ]] \
            && cmp --silent "$project_root/scripts/launch-greeter.sh" "$launcher_target"; then
        echo "launcher: current"
    else
        echo "launcher: missing or stale"
        result=1
    fi

    if [[ -f $biometric_helper_target ]] \
            && cmp --silent "$project_root/scripts/authenticate-greeter-biometric.sh" \
                "$biometric_helper_target"; then
        echo "biometric helper: current"
    else
        echo "biometric helper: missing or stale"
        result=1
    fi

    local recorded_source_digest=""
    local recorded_module_digest=""
    if [[ -r $pam_module_manifest_target ]]; then
        read -r recorded_source_digest recorded_module_digest \
            < "$pam_module_manifest_target" || true
    fi
    if [[ -f $pam_module_target ]] \
            && [[ $(stat -c '%U:%G:%a' "$pam_module_target") == root:root:644 ]] \
            && [[ $recorded_source_digest == \
                "$(sha256sum "$project_root/src/pam_session_stack_greeter.c" \
                    | awk '{print $1}')" ]] \
            && [[ $recorded_module_digest == \
                "$(sha256sum "$pam_module_target" | awk '{print $1}')" ]]; then
        echo "PAM selector module: current"
    else
        echo "PAM selector module: missing or unsafe"
        result=1
    fi

    if cmp --silent "$candidate_lua" "$greetd_target"; then
        echo "greetd: Session Stack Greeter selected for next greeter start"
    elif cmp --silent "$recovery_lua" "$greetd_target"; then
        echo "greetd: ReGreet recovery selected"
    else
        echo "greetd: externally managed configuration"
    fi

    if cmp --silent "$candidate_pam" "$pam_target"; then
        echo "PAM: Session Stack biometric selection enabled"
    elif cmp --silent "$recovery_pam" "$pam_target"; then
        echo "PAM: standard password recovery policy selected"
    else
        echo "PAM: externally managed configuration"
    fi
    cleanup_status
    trap - EXIT
    return "$result"
}

activate() {
    require_root
    if [[ ${1:-} != --recovery-ready ]]; then
        echo "Refusing activation without --recovery-ready." >&2
        echo "First verify a TTY login and keep a root shell available." >&2
        exit 2
    fi
    stage_release
    install -d -o root -g root -m 0755 /etc/greetd
    if [[ ! -e $greetd_config_target ]]; then
        install -o root -g root -m 0644 "$greetd_config_source" "$greetd_config_target"
    elif ! grep -Fq '/etc/greetd/hyprland.lua' "$greetd_config_target"; then
        if [[ ! -e $greetd_config_backup ]]; then
            install -o root -g root -m 0644 "$greetd_config_target" "$greetd_config_backup"
        fi
        install -o root -g root -m 0644 "$greetd_config_source" "$greetd_config_target"
    fi
    if [[ ! -e $greetd_backup ]]; then
        if [[ -e $greetd_target ]]; then
            install -o root -g root -m 0644 "$greetd_target" "$greetd_backup"
        fi
    fi
    if [[ ! -e $pam_backup ]]; then
        install -o root -g root -m 0644 "$pam_target" "$pam_backup"
    fi
    install -o root -g root -m 0644 "$candidate_pam" "$pam_target"
    install -o root -g root -m 0644 "$candidate_lua" "$greetd_target"
    echo "Session Stack Greeter will be used on the next greetd start."
    echo "greetd was not restarted. Roll back with: sudo $0 rollback"
}

rollback() {
    require_root
    if [[ -f $greetd_config_backup ]]; then
        install -o root -g root -m 0644 "$greetd_config_backup" "$greetd_config_target"
        echo "Restored the pre-Session-Stack greetd configuration."
    fi
    if [[ -f $greetd_backup ]]; then
        install -o root -g root -m 0644 "$greetd_backup" "$greetd_target"
        echo "Restored the pre-Session-Stack greetd configuration."
    else
        install -o root -g root -m 0644 "$recovery_lua" "$greetd_target"
        echo "Selected the packaged ReGreet recovery configuration."
    fi
    if [[ -f $pam_backup ]]; then
        install -o root -g root -m 0644 "$pam_backup" "$pam_target"
    else
        install -o root -g root -m 0644 "$recovery_pam" "$pam_target"
    fi
    echo "Restored the pre-Session-Stack greetd PAM policy."
    echo "greetd was not restarted; the change applies at its next start."
}

case "${1:-}" in
    stage)
        stage_release
        ;;
    status)
        status
        ;;
    activate)
        activate "${2:-}"
        ;;
    rollback)
        rollback
        ;;
    *)
        echo "Usage: $0 stage|status|activate --recovery-ready|rollback" >&2
        exit 2
        ;;
esac
