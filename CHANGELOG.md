# Changelog

## Unreleased

### Fingerprint detection under UWSM

On Verdandi, fingerprint was missing from the lockscreen after reboot despite a
working reader and enrollment. UWSM started the lock through the systemd user
manager, outside a local logind session. fprintd denied the discovery probe and
would also deny the PAM worker's verification request.

Detection now reports permission denial, failed probes and timeouts on stderr.
It still disables fingerprint when discovery fails; a denied request is never
treated as successful detection.

An optional setup helper now generates a verification-only PolicyKit rule for
the chosen desktop account. Normal PAM setup does not install it. See
[setup, permission scope and removal](docs/lockscreen.md#fingerprint-under-uwsm).
The rule covers every process in that account's user manager, including services
started remotely. It is not a local-session or lockscreen-only restriction.

Verdandi's original host fix was Arch commit `971fb9f`. Its user-manager probe
listed the enrolled fingers, while a direct SSH probe remained denied. That
check demonstrates different process contexts, not remote isolation. The
public helper uses the selected account's name and UID instead of shipping
Verdandi's hardcoded values or requiring wheel membership.

The user subsequently confirmed fingerprint-only login and unlock after the
host policy change, including password fallback after a fingerprint failure.

### Related host fixes

These changes belong to other components and are not bundled with Session Stack.

- Tide Island revision 30, commit `4532824`, changed charge-control authorization
  from `allow_any=no` to `auth_admin_keep`. Requests from user services can now
  ask for administrator authentication. Authorization may be cached briefly, so
  later requests need not show another prompt. The host verification report
  recorded a successful authenticated request with battery thresholds unchanged.
- Arch commit `5fb0340` allowed NetworkManager's Wi-Fi scan action for Verdandi's
  configured administrative account. This fixed nm-applet's startup prompt.
  The rule has no local-session check and also covers that account's SSH
  processes. It does not grant connection editing, radio control or saved-secret
  access. The host report recorded a successful rescan without an auth prompt.

### Validation record

The user confirmed password, Face ID and fingerprint-only authentication on the
installed `0af2b5a` screens, including initial login/session launch and password
fallback after a fingerprint failure. The earlier attempt with three
`verify-no-match` results was followed by successful fingerprint-only testing.
No greeter authentication code was changed for those misses.

The user also confirmed suspend/resume, display sleep, monitor reconnection and
QuickShell crash recovery through Hyprlock on Verdandi. These results apply to
the installed screens and host policy. The later public policy setup helper and
diagnostic changes have automated verification.

Still required before calling this a stable release:

- Test installation on a fresh account without the development machine's
  existing PAM files, PolicyKit rules or releases, including installation and
  removal of the optional fingerprint rule.

The automated suite and isolated installation checks do not establish that
fresh-install result. The release remains experimental.
