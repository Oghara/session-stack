#!/usr/bin/env bash
set -euo pipefail

# PAM passes a method marker and account name, never a password.
authentication_method=${1:-}
target_user=${2:-}

if (( EUID != 0 )) || [[ -z $target_user ]] \
        || ! getent passwd "$target_user" >/dev/null; then
    exit 1
fi

case "$authentication_method" in
    session-stack-greeter:face:v1)
        exec /usr/bin/timeout --foreground --signal=TERM --kill-after=2s 12s \
            /usr/bin/howrs test --user "$target_user"
        ;;
    session-stack-greeter:fingerprint:v1)
        exec /usr/bin/timeout --foreground --signal=TERM --kill-after=2s 20s \
            /usr/bin/fprintd-verify -f any -- "$target_user"
        ;;
    *)
        exit 1
        ;;
esac
