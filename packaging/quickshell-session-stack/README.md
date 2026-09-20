# QuickShell output-lifecycle backport

This package starts from the official Arch QuickShell 0.3.0 recipe and applies
only the code changes from upstream commit `897fcda`. That commit is the
reviewed session-lock output-lifecycle repair merged after the 0.3.0 release.

The package provides the versioned virtual capability below.

```text
quickshell-session-lock-output-teardown=1
```

Session Stack checks this capability before selecting QuickShell as the primary
lock. The included policy already permits patched QuickShell. Without the
capability, the launcher selects Hyprlock instead. Run `./session-stack check`
from the project directory to see which backend it selects.

Build in a clean Arch environment when possible.

```sh
makepkg --cleanbuild --syncdeps
pacman -Qip quickshell-session-stack-*.pkg.tar.zst
pacman -Qlp quickshell-session-stack-*.pkg.tar.zst
```

Before enabling automatic locking, complete the
[attended lock and recovery checks](../../docs/lockscreen.md#before-enabling-automatic-locking),
including display sleep, suspend/resume and monitor reconnection with TTY
recovery available.
