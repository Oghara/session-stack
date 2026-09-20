# Changelog

## Current release

- Native QuickShell lockscreen with optional greetd login, account selection and
  desktop session selection.
- Password, Face ID and fingerprint support, with separate settings for lock
  and login. Biometric methods require compatible hardware and enrollment.
- Hyprlock recovery if the lock client fails, and ReGreet recovery if the login
  conversation fails.
- Optional fingerprint permission helper for locks launched through UWSM or a
  systemd user service. See the [permission scope and removal instructions](docs/lockscreen.md#fingerprint-under-uwsm)
  before enabling it.
- Fingerprint detection reports permission errors, failed probes and timeouts
  instead of silently treating them as missing hardware.

## Known limitations

This release targets Arch Linux, Hyprland's Lua configuration API and patched
QuickShell 0.3.0. Other environments have not been tested.

Installation on a fresh account without existing PAM files or host-specific
PolicyKit rules remains unverified. The release is experimental.
