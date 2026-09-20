#!/usr/bin/env bash
set -euo pipefail

config_dir=/usr/local/share/session-stack-greeter/current

if [[ $(id -un) != greeter ]]; then
    echo "Session Stack Greeter must run as the greetd greeter account." >&2
    exit 1
fi
if [[ -z ${GREETD_SOCK:-} || ! -S ${GREETD_SOCK} ]]; then
    echo "GREETD_SOCK is unavailable; refusing live mode." >&2
    exit 1
fi
if [[ ! -r $config_dir/shell.qml ]]; then
    echo "Installed QuickShell greeter package is unavailable." >&2
    exit 1
fi

# Store transient state in XDG_RUNTIME_DIR, including D-Bus-activated services.
if [[ -z ${XDG_RUNTIME_DIR:-} || ! -d $XDG_RUNTIME_DIR ]]; then
    echo "XDG_RUNTIME_DIR is unavailable; refusing live mode." >&2
    exit 1
fi
greeter_state_dir="$XDG_RUNTIME_DIR/state"
install -d -m 0700 -- "$greeter_state_dir"
export XDG_STATE_HOME=$greeter_state_dir
systemctl --user set-environment XDG_STATE_HOME="$XDG_STATE_HOME"

if env SESSION_STACK_GREETER_MODE=live \
        quickshell --no-duplicate --path "$config_dir"; then
    # Clear VT text and hide its cursor during the compositor handoff.
    greeter_vt_number=${XDG_VTNR:-1}
    if [[ $greeter_vt_number =~ ^[0-9]+$ ]]; then
        greeter_vt="/dev/tty${greeter_vt_number}"
        if [[ -w $greeter_vt ]]; then
            printf '\033[H\033[2J\033[3J\033[?25l' > "$greeter_vt" || true
        fi
    fi
    exit 0
else
    launcher_status=$?
    greeter_vt_number=${XDG_VTNR:-1}
    if [[ $greeter_vt_number =~ ^[0-9]+$ ]]; then
        greeter_vt="/dev/tty${greeter_vt_number}"
        if [[ -w $greeter_vt ]]; then
            printf '\033[?25h' > "$greeter_vt" || true
        fi
    fi
    exit "$launcher_status"
fi
