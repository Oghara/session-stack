# Lockscreen setup

Keep this directory in a permanent location. Run commands as your desktop user.

## Dependencies and setup

The current target is Arch with Hyprland's Lua configuration API, Qt 6.11 and
QuickShell 0.3.0 with the session-lock output teardown patch. Other compositors
and distributions have not been tested. Lockscreen setup does not need greetd.
Initial login is a separate component in the full package.

Install Hyprlock, jq, DejaVu fonts, Python GObject bindings and UPower using your
distribution's packages. The launcher also uses Bash, coreutils, util-linux and
procps-ng. For development, Qt Declarative supplies `qmllint` and `qmltestrunner`.

The [QuickShell package recipe](../packaging/quickshell-session-stack/README.md)
includes the upstream monitor teardown fix. Build and inspect it before
installing it. The launcher requires its package capability; without it, the
launcher selects Hyprlock. `./session-stack check` reports the selected backend.

For real authentication, install the dedicated PAM files. The preview does not
need them.

```sh
sudo ./scripts/manage-quickshell-lock-pam.sh apply
```

This adds Session Stack's PAM services, a separate failure tally and a tmpfiles
rule. It refuses to overwrite unexpected files. It does not edit your login,
sudo or Hyprlock PAM policies. Three rejected passwords within 15 minutes impose
a 10-minute lock-service delay; that tally does not disable TTY login or sudo.

For Face ID, install and enroll Howrs and make its enrollment readable by your
desktop account. Fingerprint additionally needs fprintd and enrollment. These
optional modules are never called by the password-only profile. The installer
does not enroll biometrics or change device permissions for you.

## Preview and authentication

```sh
./session-stack preview
```

`preview` uses no PAM and does not lock. Wake the screen, then use `demo` for the
success animation or another word for rejection. F5/F6 also stage these outcomes.
After rejection, click ICEbreaker, or Tab to it and press Enter, to recover.
Recovery returns to credential entry and replaces destroyed processes in the
animation. It never authenticates.

Then check authentication and lock the session:

```sh
./session-stack auth-check
./session-stack check
./session-stack lock
```

`auth-check` uses real authentication in an ordinary window. Close the window to
exit. Escape clears the credential field.
`lock` acquires the compositor lock on every output. It requires successful
authentication to release it. QuickShell failure starts the bundled Hyprlock
recovery screen. The launcher restores Hyprland's prior lock-recovery setting
when it exits.

The default profile is password-only. Select the methods your PC supports:

```sh
SESSION_STACK_AUTH_METHODS=password-face ./session-stack auth-check
SESSION_STACK_AUTH_METHODS=password-face ./session-stack lock
SESSION_STACK_AUTH_METHODS=all ./session-stack preview
```

Face ID starts when you select Face. Use `password-fingerprint` for password and
fingerprint, or `all` for all three. Real authentication requires the requested
hardware and enrollment. Preview permits unavailable hardware for layout inspection.
`SESSION_STACK_LOCK_REDUCED_MOTION=1` skips the transition animations.

Copy `lock.toml` to `lock.local.toml` to save your preferences. Keep password
enabled and set supported biometric methods to `"auto"`.

## Fingerprint under UWSM

UWSM and other systemd user-service launchers can run the lock outside a logind
session. In that context fprintd may deny verification, even when the reader
works from a desktop terminal. Detection reports permission denial, failed
probes and timeouts on stderr. If a service starts the lock, those messages
appear in its journal.

Keep password enabled. Set `fingerprint = "auto"` in `lock.local.toml`, then
review this optional rule as your desktop user:

```sh
python3 scripts/manage-fingerprint-policy.py show "$USER"
```

The rule grants only `net.reactivated.fprint.device.verify` to that account's
`user-<uid>.service`. It covers **all processes in the user manager**, not just
Session Stack. It does not require an active local session. Processes started
remotely through the same user manager receive the same permission; a denied
probe directly from SSH is not proof of remote isolation. It does not grant
enrollment, deletion or verification as another account, and a fingerprint match
is still required to authenticate.

If that scope fits your machine, install it explicitly from your desktop user's
terminal. The account name is expanded before sudo runs:

```sh
sudo python3 scripts/manage-fingerprint-policy.py apply "$USER"
```

This writes a root-owned `49-session-stack-fingerprint-<uid>.rules` file under
`/etc/polkit-1/rules.d/`. Polkit reloads it automatically. The helper refuses to
overwrite modified files or symlinks. It generates the rule using your account's
name and UID.

Repeat a normal lock through your usual launcher and test fingerprint unlock.
Successful detection alone does not verify the PAM worker or unlock sequence.
To remove only this permission:

```sh
sudo python3 scripts/manage-fingerprint-policy.py remove "$USER"
```

Existing host rules may still grant access after removal. If your machine
already has an equivalent rule, you do not need another.

## Before enabling automatic locking

1. Verify that you can log in on a TTY and that Hyprlock can unlock independently.
2. Run `auth-check` from your desktop terminal without sudo. Check password and
   each enabled biometric method.
3. Run `check`, then `lock` while present. Check every monitor and unlock.
4. With TTY recovery available, check monitor reconnect, DPMS and suspend/resume.
   Deliberately terminate only this lock's QuickShell process from the TTY and
   confirm that the launcher starts Hyprlock and your password unlocks it.

Once those pass, bind the absolute path to `session-stack lock` in your desktop
configuration. Set `SESSION_STACK_AUTH_METHODS=password-face` in that command
if appropriate. `prepare-sleep` waits for compositor security and biometric
shutdown; it does not suspend the PC. This package does not install idle timers,
sleep policy, keybindings or services automatically.
