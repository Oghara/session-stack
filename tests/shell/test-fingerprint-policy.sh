#!/usr/bin/env bash
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d --tmpdir session-stack-fingerprint-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir "$test_root/rules"
account=$(id -un)
target="$test_root/rules/49-session-stack-fingerprint-$(id -u).rules"

run_isolated() {
    bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / --proc /proc --dev /dev \
        --bind "$test_root/rules" /etc/polkit-1/rules.d \
        python3 "$project_root/scripts/manage-fingerprint-policy.py" "$@" "$account"
}

run_isolated apply >/dev/null
[[ $(stat -c '%a' "$target") == 644 ]]
cp "$target" "$test_root/original"
run_isolated apply >/dev/null
cmp "$target" "$test_root/original"

printf '\n// Local modification\n' >> "$target"
cp "$target" "$test_root/modified"
for action in apply remove; do
    if run_isolated "$action" >"$test_root/error" 2>&1; then
        echo "Policy setup accepted a modified rule during $action." >&2
        exit 1
    fi
    cmp "$target" "$test_root/modified"
done

cp "$test_root/original" "$target"
run_isolated remove >/dev/null
[[ ! -e $target ]]
ln -s "$test_root/original" "$target"
if run_isolated apply >"$test_root/error" 2>&1; then
    echo 'Policy setup accepted a symlink target.' >&2
    exit 1
fi
[[ -L $target ]]
echo 'Isolated fingerprint policy installation, modified-file protection and removal passed.'
