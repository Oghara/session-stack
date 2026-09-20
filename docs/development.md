# Development

## Ownership

`quickshell/common/SessionSurface.qml` handles input and layout.
`SwitchboardFlow.qml` owns scene timing, the computed frame, monitoring feeds and
clock. Outputs share that state; only ambient motion is local to each screen.
`SwitchboardModel.js` computes the approved sequence, replacement process
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
scanner does not import outside that directory. Login staging copies it into an
immutable release. Keep the symlinks when extracting or moving the source tree.

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

The suite has 24 Qt behavior cases, 14 Python checks, four native greetd scenarios
and helper/deployment checks. Each layer has a specific job:

- Native greetd tests cover login, rejection/recovery, extra prompts, selection
  locking and the exact session command. Avoid duplicating these with a fake backend.
- Qt controller tests cover biometric queueing, cancellation, stale callbacks,
  disabled methods and failed launches. Screen tests cover shared input, focus,
  dormancy, output removal, authentication gating and the CRT recovery contract.
- Python tests protect configuration and inventory privacy. Isolated deployment
  tests exercise real PAM routing, release integrity and rollback.

Basic property/getter checks and source-text matching were removed. Keep a new
regression test where it reproduces the failure most directly.

A two-output probe over 200 timeline changes measured 400 model evaluations
before the review and 200 afterward. In 2.2 dormant seconds, clock updates fell
from four to zero. Feeds now share one timer; the clock updates on minute
boundaries while awake. These are operation counts, not CPU/GPU benchmarks.
All 36 deterministic comparisons matched exactly across landscape/portrait,
password-only/all-method layouts, takeover and CRT recovery. The model itself
is unchanged. Temporary measurement instrumentation is not shipped.

Attended lock/unlock and initial login/session launch were confirmed on Verdandi
with `0af2b5a`. A UWSM fingerprint permission issue appeared after reboot; the
host policy was corrected. The user subsequently confirmed fingerprint-only
login and unlock, password fallback after a failed fingerprint attempt,
suspend/resume, display sleep, monitor reconnection and crash-to-Hyprlock
recovery. The later setup helper and diagnostic changes passed automated checks.
Installation on a fresh account without prior host configuration remains to test.

For paused inspection, in lock preview only:

```sh
quickshell ipc --path quickshell/session-stack-lock \
  call lockPrototype previewScene 12.96 failure true
```

Arguments are time, outcome and recovery. `capturePreview PATH` saves the item.
Login preview exposes `sessionStackGreeter menu user` and `capturePreview PATH`.
Capture is refused during real authentication. Native rasterization differs from
the browser; browser pixel parity is not claimed.

## Sharing

From a clean, committed full checkout:

```sh
./scripts/export-release.sh lock /tmp/session-stack-lock.zip
./scripts/export-release.sh all /tmp/session-stack.zip
```

Exports contain current committed files without Git history, local settings or
installed state. Lock exports omit login code and its tests. Keep host inventories
and biometric enrollment outside the checkout. Nothing is uploaded automatically.
