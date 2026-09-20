#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run this script as root." >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir="${script_dir}/../system/pam.d"
faillock_source="${script_dir}/../system/security/session-stack-faillock.conf"
faillock_target=/etc/security/session-stack-faillock.conf
tmpfiles_source="${script_dir}/../system/tmpfiles.d/session-stack.conf"
tmpfiles_target=/etc/tmpfiles.d/session-stack.conf
previous_password_sha=73923f10011569b66602e366d10bc8137ecd1932d9b738ccfd62247f92a66891
service_names=(
    session-stack-lock-password
    session-stack-lock-face
    session-stack-lock-fingerprint
)

install_service() {
    local service_name=$1
    local source_file="${source_dir}/${service_name}"
    local target_file="/etc/pam.d/${service_name}"

    install --owner=root --group=root --mode=0644 "$source_file" "$target_file"
    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$target_file"
    fi
    echo "Installed $target_file"
}

validate_service_target() {
    local service_name=$1
    local source_file="${source_dir}/${service_name}"
    local target_file="/etc/pam.d/${service_name}"
    local current_sha

    [[ ! -e $target_file ]] && return
    cmp --silent "$source_file" "$target_file" && return

    if [[ $service_name == session-stack-lock-password ]]; then
        current_sha=$(sha256sum "$target_file" | awk '{print $1}')
        [[ $current_sha == "$previous_password_sha" ]] && return
    fi

    echo "Refusing to replace unexpected PAM service: $target_file" >&2
    return 1
}

validate_auxiliary_target() {
    local source_file=$1
    local target_file=$2

    if [[ -e $target_file ]] && ! cmp --silent "$source_file" "$target_file"; then
        echo "Refusing to replace unexpected lock-auth support file: $target_file" >&2
        return 1
    fi
}

install_auxiliary_files() {
    install --owner=root --group=root --mode=0644 "$faillock_source" "$faillock_target"
    install --owner=root --group=root --mode=0644 "$tmpfiles_source" "$tmpfiles_target"
    systemd-tmpfiles --create "$tmpfiles_target"

    if [[ $(stat -c '%U:%G:%a' /run/session-stack-faillock) != root:root:755 ]]; then
        echo "Unsafe lock faillock directory owner or mode." >&2
        return 1
    fi
}

# Hyprlock delegates to this service, so removing it would break lock recovery.
hyprlock_depends_on_password_service() {
    local hyprlock_file=${1:-/etc/pam.d/hyprlock}

    [[ -e $hyprlock_file ]] || return 1
    grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+session-stack-lock-password' \
        "$hyprlock_file"
}

remove_service() {
    local service_name=$1
    local source_file="${source_dir}/${service_name}"
    local target_file="/etc/pam.d/${service_name}"

    if [[ ! -e $target_file ]]; then
        echo "Already absent: $target_file"
        return
    fi

    if ! cmp --silent "$source_file" "$target_file"; then
        echo "Refusing to remove modified PAM service: $target_file" >&2
        return 1
    fi

    unlink -- "$target_file"
    echo "Removed $target_file"
}

show_status() {
    local mapping
    local service_name
    local source_file
    local target_file

    for service_name in "${service_names[@]}"; do
        source_file="${source_dir}/${service_name}"
        target_file="/etc/pam.d/${service_name}"

        if [[ ! -e $target_file ]]; then
            echo "missing: $target_file"
        elif cmp --silent "$source_file" "$target_file"; then
            echo "current: $target_file"
        else
            echo "different: $target_file"
        fi
    done

    for mapping in \
        "$faillock_source|$faillock_target" \
        "$tmpfiles_source|$tmpfiles_target"; do
        source_file=${mapping%%|*}
        target_file=${mapping#*|}
        if [[ ! -e $target_file ]]; then
            echo "missing: $target_file"
        elif cmp --silent "$source_file" "$target_file"; then
            echo "current: $target_file"
        else
            echo "different: $target_file"
        fi
    done
}

validate_targets() {
    local service_name

    for service_name in "${service_names[@]}"; do
        validate_service_target "$service_name"
    done
}

case "${1:-apply}" in
    apply)
        validate_targets
        validate_auxiliary_target "$faillock_source" "$faillock_target"
        validate_auxiliary_target "$tmpfiles_source" "$tmpfiles_target"
        install_auxiliary_files
        for service_name in "${service_names[@]}"; do
            install_service "$service_name"
        done
        ;;
    remove)
        validate_targets
        if hyprlock_depends_on_password_service; then
            echo "Refusing to remove: /etc/pam.d/hyprlock still includes session-stack-lock-password." >&2
            echo "Restore your previous Hyprlock PAM configuration before removing these services." >&2
            exit 1
        fi
        for service_name in "${service_names[@]}"; do
            remove_service "$service_name"
        done
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 [apply|remove|status]" >&2
        exit 2
        ;;
esac
