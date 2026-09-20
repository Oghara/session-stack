#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd -- "$script_dir/../.." && pwd)
test_root=$(mktemp -d --tmpdir session-stack-greeter-test.XXXXXX)

cleanup() {
    local status=$?
    trap - EXIT
    if [[ $test_root == /tmp/session-stack-greeter-test.* ]]; then
        chmod -R u+w "$test_root" 2>/dev/null || true
        rm -rf -- "$test_root"
    fi
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$test_root/etc-greetd" "$test_root/etc-pam.d" \
    "$test_root/local-share" "$test_root/local-lib"
cp -- "$project_root/system/greetd/hyprland-regreet.lua" \
    "$test_root/etc-greetd/hyprland.lua"
cp -- "$project_root/system/pam.d/greetd-recovery" \
    "$test_root/etc-pam.d/greetd"
cp -- "$project_root/tests/pam.d/system-local-login" \
    "$test_root/etc-pam.d/system-local-login"

run_isolated() {
    local extra_mounts=()
    if [[ -n ${test_project_override:-} ]]; then
        extra_mounts=(--ro-bind "$test_project_override" "$project_root")
    fi
    bwrap \
        --unshare-user \
        --uid 0 \
        --gid 0 \
        --ro-bind / / \
        --proc /proc \
        --dev /dev \
        --bind "$test_root/etc-greetd" /etc/greetd \
        --bind "$test_root/etc-pam.d" /etc/pam.d \
        --bind "$test_root/local-share" /usr/local/share \
        --bind "$test_root/local-lib" /usr/local/lib \
        "${extra_mounts[@]}" \
        --chdir "$project_root" \
        "$@"
}

run_isolated_with_source_config() {
    bwrap \
        --unshare-user \
        --uid 0 \
        --gid 0 \
        --ro-bind / / \
        --proc /proc \
        --dev /dev \
        --bind "$test_root/etc-greetd" /etc/greetd \
        --bind "$test_root/etc-pam.d" /etc/pam.d \
        --bind "$test_root/local-share" /usr/local/share \
        --bind "$test_root/local-lib" /usr/local/lib \
        --ro-bind "$test_root/source-config" \
            "$project_root/quickshell/session-stack-greeter" \
        --chdir "$project_root" \
        "$@"
}

run_isolated ./scripts/manage-greeter.sh stage >/dev/null
run_isolated ./scripts/manage-greeter.sh status >/dev/null

current_link="$test_root/local-share/session-stack-greeter/current"
cp -a -- "$project_root/quickshell/session-stack-greeter" \
    "$test_root/source-config"
chmod u+w "$test_root/source-config/shell.qml"
printf '\n' >> "$test_root/source-config/shell.qml"
if run_isolated_with_source_config \
        ./scripts/manage-greeter.sh status >/dev/null; then
    echo "Greeter status accepted unstaged source QML." >&2
    exit 1
fi

active_release=$(readlink -f -- "$current_link")
cp -a -- "$active_release" \
    "$test_root/local-share/session-stack-greeter/releases/wrong-release"
ln -sfn releases/wrong-release "$current_link"
if run_isolated ./scripts/manage-greeter.sh status >/dev/null; then
    echo "Greeter status accepted the wrong active release name." >&2
    exit 1
fi
run_isolated ./scripts/manage-greeter.sh stage >/dev/null
run_isolated ./scripts/manage-greeter.sh status >/dev/null

run_isolated chmod u+w \
    /usr/local/share/session-stack-greeter/current/shell.qml
run_isolated truncate -s 0 \
    /usr/local/share/session-stack-greeter/current/shell.qml
if run_isolated ./scripts/manage-greeter.sh status >/dev/null; then
    echo "Greeter status accepted a truncated current/shell.qml." >&2
    exit 1
fi
run_isolated ./scripts/manage-greeter.sh stage >/dev/null
run_isolated ./scripts/manage-greeter.sh status >/dev/null

[[ -L $current_link && -r $current_link/shell.qml ]]
[[ -x $test_root/local-lib/session-stack-greeter/launch-greeter ]]
[[ -x $test_root/local-lib/session-stack-greeter/authenticate-biometric ]]
[[ $(run_isolated stat -c '%U:%G:%a' \
    /usr/local/lib/session-stack-greeter/pam_session_stack_greeter.so) \
    == root:root:644 ]]
[[ $(run_isolated stat -c '%U:%G:%a' \
    /usr/local/lib/session-stack-greeter/pam_session_stack_greeter.manifest) \
    == root:root:644 ]]
[[ -z $(find -L "$current_link" -perm /022 -print -quit) ]]

run_isolated ./scripts/manage-greeter.sh activate --recovery-ready >/dev/null
cmp --silent "$project_root/system/greetd/hyprland-session-stack.lua" \
    "$test_root/etc-greetd/hyprland.lua"
cmp --silent "$project_root/system/greetd/hyprland-regreet.lua" \
    "$test_root/etc-greetd/hyprland.lua.pre-session-stack-greeter"
cmp --silent "$project_root/system/pam.d/greetd-session-stack" \
    "$test_root/etc-pam.d/greetd"
cmp --silent "$project_root/system/pam.d/greetd-recovery" \
    "$test_root/etc-pam.d/greetd.pre-session-stack-greeter"

run_isolated env TMPDIR=/usr/local/lib/session-stack-greeter \
    cc -std=c17 -fPIC -shared -Wall -Wextra -Werror \
    tests/pam-password-fixture.c -lpam \
    -o /usr/local/lib/session-stack-greeter/pam_password_fixture.so
run_isolated env TMPDIR=/usr/local/lib/session-stack-greeter \
    cc -std=c17 -D_GNU_SOURCE -Wall -Wextra -Werror \
    tests/pam-selector-conversation.c -lpam \
    -o /usr/local/lib/session-stack-greeter/test-pam-conversation
run_isolated /usr/local/lib/session-stack-greeter/test-pam-conversation \
    session-stack-greeter:password:v1 2 "$(id -un)"
run_isolated /usr/local/lib/session-stack-greeter/test-pam-conversation \
    session-stack-greeter:password:v1 2 "$(id -un)" reject

# A biometric miss returns to method selection within the same conversation.
run_isolated cp -- /usr/bin/false \
    /usr/local/lib/session-stack-greeter/authenticate-biometric
run_isolated /usr/local/lib/session-stack-greeter/test-pam-conversation \
    session-stack-greeter:fingerprint:v1 3 "$(id -un)"

# Successful biometrics must skip the password stack.
run_isolated cp -- /usr/bin/true \
    /usr/local/lib/session-stack-greeter/authenticate-biometric
run_isolated /usr/local/lib/session-stack-greeter/test-pam-conversation \
    session-stack-greeter:fingerprint:v1 1 "$(id -un)"
run_isolated /usr/local/lib/session-stack-greeter/test-pam-conversation \
    session-stack-greeter:face:v1 1 "$(id -un)"

# Stage the explicit password-only profile, then reject a profile with no methods.
test_project_override="$test_root/password-only-project"
mkdir -p "$test_project_override"
cp -a -- "$project_root"/{quickshell,scripts,system,src,greeter.toml} "$test_project_override/"
cat > "$test_project_override/greeter.local.toml" <<'TOML'
[authentication]
password = true
face = "off"
fingerprint = "off"
TOML
run_isolated ./scripts/manage-greeter.sh stage >/dev/null
run_isolated ./scripts/manage-greeter.sh status >/dev/null
for expected in 'passwordAuthenticationEnabled: true' \
        'faceAuthenticationEnabled: false' 'fingerprintAuthenticationEnabled: false'; do
    grep -Fq "$expected" "$current_link/GeneratedSystemData.qml"
done
password_only_release=$(readlink "$current_link")
sed -i 's/password = true/password = false/' "$test_project_override/greeter.local.toml"
if run_isolated ./scripts/manage-greeter.sh stage >"$test_root/invalid-config.log" 2>&1; then
    echo "Staging accepted a profile with no authentication methods." >&2
    exit 1
fi
grep -Fq 'At least one authentication method must be enabled' "$test_root/invalid-config.log"
[[ $(readlink "$current_link") == "$password_only_release" ]]
test_project_override=""

run_isolated ./scripts/manage-greeter.sh rollback >/dev/null
cmp --silent "$project_root/system/greetd/hyprland-regreet.lua" \
    "$test_root/etc-greetd/hyprland.lua"
cmp --silent "$project_root/system/pam.d/greetd-recovery" \
    "$test_root/etc-pam.d/greetd"

echo "Isolated greeter stage/activate/rollback integration passed."
