#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd -- "$script_dir/.." && pwd)
config_dir="$project_root/quickshell/session-stack-greeter"

case "${1:-}" in
    preview)
        exec env -u GREETD_SOCK SESSION_STACK_GREETER_MODE=preview \
            quickshell --no-duplicate --path "$config_dir"
        ;;
    check)
        "$project_root/scripts/generate-system-data.py" --demo --check
        python3 -m unittest discover -s "$project_root/tests/python" -v
        "$project_root/scripts/check-native.sh"
        "$project_root/tests/protocol/fake-greetd-server.py"
        for shell_test in "$project_root"/tests/shell/*.sh; do
            bash "$shell_test"
        done
        echo "Session Stack Greeter checks passed."
        ;;
    *)
        echo "Usage: $0 preview|check" >&2
        echo "The preview uses password: demo and never contacts greetd." >&2
        exit 2
        ;;
esac
