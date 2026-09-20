#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for source in "$project_dir"/quickshell/{common,session-stack-lock,session-stack-greeter}/*.{qml,js}; do
    [[ -f $source ]] || continue
    qmllint "$source"
done
bash -n "$project_dir/session-stack"
for source in "$project_dir"/scripts/*.sh; do bash -n "$source"; done
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input "$project_dir/tests/qml" -o -,txt
