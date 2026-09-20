#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd -- "$script_dir/../.." && pwd)
helper="$project_root/scripts/authenticate-greeter-biometric.sh"

if "$helper" 'session-stack-greeter:password:v1' "$(id -un)"; then
    echo "Password selection unexpectedly completed biometric authentication." >&2
    exit 1
fi

if "$helper" 'invalid-selector' "$(id -un)"; then
    echo "Invalid biometric selector was accepted." >&2
    exit 1
fi

if "$helper" 'session-stack-greeter:fingerprint:v1' 'missing-login-account'; then
    echo "Biometric helper accepted an unknown account." >&2
    exit 1
fi

echo "Biometric selector helper fail-closed checks passed."
