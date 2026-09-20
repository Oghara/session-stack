# Optional initial login

This is the full package's greetd entry point. Installing only the lockscreen
requires none of these steps. The current target uses Hyprland's Lua API and
ReGreet as the recovery greeter. It is not an SDDM theme.

Run `./session-stack login-preview` first. Its demo accounts and sessions are
fictional. It never connects to greetd or launches a desktop. Live mode refuses
the demo inventory.

Install greetd, ReGreet, Hyprland, QuickShell, Python 3.11 or newer, PAM development
headers and a C compiler. The existing lockscreen prerequisites cover Qt and
fonts. Howrs or fprintd are optional and require enrolled accounts.

Copy `greeter.toml` to `greeter.local.toml` for local preferences. Password is on
by default. Each biometric method accepts `auto`, `on` or `off`. Auto offers only
usable methods for the selected account; on also refuses staging when no account
can use that method. With password disabled, every discovered account must have
a usable biometric method. Unknown manual usernames cannot use biometric routes.

Staging discovers host accounts and desktop session files, writes a host-only
inventory outside the checkout, compiles the login PAM module, and installs a
root-owned release. Shared QML becomes a regular directory in that release.
Staging updates the `current` release link, so it affects the next invocation if
Session Stack is already your active greeter. It does not restart greetd.

```sh
sudo ./scripts/manage-greeter.sh stage
sudo ./scripts/manage-greeter.sh status
```

Before activating, confirm you can log in on a TTY and that ReGreet works. The
following explicit command installs the greetd, Hyprland and PAM configuration
and keeps backups. It does not log you out or restart the display manager.

```sh
sudo ./scripts/manage-greeter.sh activate --recovery-ready
```

Then perform an attended login test with TTY access available. Authentication
must succeed before the animation can request the chosen session. A failed or
broken live conversation exits to ReGreet after recovery because this QuickShell
greetd connection cannot be safely reused. Recovery itself never logs in.

A successful fingerprint match authenticates the selected account and starts
the selected desktop session. It does not require a password as well. A failed
match does not log in. Password-encrypted keyrings may still need their own
password afterward; fingerprint authentication does not supply that password.

To restore the prior configuration:

```sh
sudo ./scripts/manage-greeter.sh rollback
```

Review `system/greetd/` and `system/pam.d/greetd-*` before installing on a different
host. These scripts write specific Arch/Hyprland paths and retain pre-activation backups.
They do not configure SDDM, enroll biometrics or install an idle-lock policy.
