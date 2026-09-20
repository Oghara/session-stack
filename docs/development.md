# Development

## Ownership

`quickshell/common/SessionSurface.qml` handles input and layout.
`SwitchboardFlow.qml` owns scene timing, the computed frame, monitoring feeds and
clock. Outputs share that state; only ambient motion is local to each screen.
`SwitchboardModel.js` computes the animation, replacement process
identities and CRT shutdown. Common components import Qt, not PAM or greetd.

`quickshell/session-stack-lock/` owns PAM workers, lid/sleep handling and
`WlSessionLock`. The managed launcher verifies compositor security and runs
Hyprlock if the native client fails. Only authenticated completion releases the
lock and writes its unlock marker. Extra PAM prompts reuse the active worker.

`quickshell/session-stack-greeter/` owns account/session selection and the greetd
conversation. It launches the selected command only after greetd reports
readiness. Recovery opens a fresh connection through ReGreet; it cannot log in.
The checked-in account and session inventory contains demo values only.

Each entry point links `common` into its config directory because QuickShell's
scanner does not import outside that directory. Login staging copies it into a
read-only release. Keep the symlinks when extracting or moving the source tree.

## Input and output behavior

`CredentialState.qml` holds the shared draft. Escape, dormancy, recovery and
backend clear requests erase it. Idle dormancy starts after 18 seconds; workers,
queued responses, open login menus and extra prompts block it.

`DisplayState.qml` prefers an external display and falls back when an output
vanishes. Login assigns layer-shell keyboard ownership explicitly. Lock focus
belongs to the compositor. Actual input and window activation determine which
output runs ambient motion and distortion. Mirroring a menu never claims focus.

## Checks

```sh
./scripts/check-native.sh       # QML, shell syntax and behavior tests
./scripts/test-greeter.sh check # Full package; includes the native check
```

Keep tests focused on credentials, lifecycle and deployment failures. The full
check also covers host-inventory privacy, configuration, native greetd socket
exchanges, helper failures and isolated Bubblewrap deployment/rollback. These
checks cannot establish real PAM, compositor or boot-login behavior.

Each test layer has a specific job:

- Native greetd tests cover login, rejection/recovery, extra prompts, selection
  locking and the exact session command. Avoid duplicating these with a fake backend.
- Qt controller tests cover biometric queueing, cancellation, stale callbacks,
  disabled methods and failed launches. Screen tests cover shared input, focus,
  dormancy, output removal, authentication gating and the CRT shutdown sequence.
- Python tests protect configuration and inventory privacy. Isolated deployment
  tests exercise real PAM routing, release integrity and rollback.

Add regression tests where they reproduce the failure most directly. For changes
to authentication or lock handling, also run the
[manual lock and recovery checks](lockscreen.md#before-enabling-automatic-locking).

For paused inspection, in lock preview only:

```sh
quickshell ipc --path "$PWD/quickshell/session-stack-lock" \
  call lockPrototype previewScene 12.96 failure true
```

Arguments are time, outcome and recovery. `capturePreview PATH` saves the item.
Login preview exposes `sessionStackGreeter menu user` and `capturePreview PATH`.
Capture is refused during real authentication. Use the same QuickShell `--path`
for launch and IPC; a different path alias identifies a different instance.

## Sharing

From a clean, committed Git checkout of the full package:

```sh
./scripts/export-release.sh lock /tmp/session-stack-lock.zip
./scripts/export-release.sh all /tmp/session-stack.zip
```

Exports contain current committed files without Git history, local settings or
installed state. Lock exports omit login code and its tests. Keep host inventories
and biometric enrollment outside the checkout. Nothing is uploaded automatically.
