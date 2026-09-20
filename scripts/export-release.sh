#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
if [[ $# != 2 || ( $1 != lock && $1 != all ) || $2 != *.zip ]]; then
    echo 'Usage: scripts/export-release.sh lock|all OUTPUT.zip' >&2
    exit 2
fi
if [[ -e $2 ]]; then
    echo "Refusing to overwrite $2" >&2
    exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
    echo 'Commit or set aside working changes before exporting HEAD.' >&2
    exit 1
fi
paths=()
if [[ $1 == lock ]]; then
    paths=(README.md CHANGELOG.md LICENSE THIRD_PARTY.md .gitignore lock.toml session-stack
        docs/lockscreen.md docs/development.md docs/images
        quickshell/common quickshell/session-stack-lock fallback packaging
        scripts/auth_config.py scripts/lock-settings.py scripts/check-native.sh
        scripts/manage-quickshell-lock-pam.sh scripts/open-session-lock.sh
        scripts/manage-fingerprint-policy.py
        scripts/session-stack-lid-monitor.py
        system/pam.d/session-stack-lock-face system/pam.d/session-stack-lock-fingerprint
        system/pam.d/session-stack-lock-password system/security
        system/session-stack-lock-policy system/tmpfiles.d
        tests/qml/tst_LockConversation.qml tests/qml/tst_SessionInput.qml
        tests/qml/tst_SwitchboardFlow.qml)
fi
git archive --format=zip --prefix=session-stack/ --output="$2" HEAD "${paths[@]}"
printf 'Exported %s from %s\n' "$1" "$(git rev-parse --short HEAD)"
