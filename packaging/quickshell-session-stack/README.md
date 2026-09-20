# Patched QuickShell package

This package starts from the official Arch QuickShell 0.3.0 recipe and applies
only the code changes from upstream commit `897fcda`. That commit is the
session-lock output teardown fix merged after the 0.3.0 release.

The package provides this versioned capability:

```text
quickshell-session-lock-output-teardown=1
```

Session Stack checks this capability before selecting QuickShell as the primary
lock. The included policy already permits patched QuickShell. Without the
capability, the launcher selects Hyprlock instead. Run `./session-stack check`
from the project directory to see which backend it selects.

From the project directory, build and inspect the package. Use a clean Arch
build environment when possible.

```sh
cd packaging/quickshell-session-stack
makepkg --cleanbuild --syncdeps
pacman -Qip quickshell-session-stack-*.pkg.tar.zst
pacman -Qlp quickshell-session-stack-*.pkg.tar.zst
```

Install the inspected package with `sudo pacman -U` followed by its file path.

Before enabling automatic locking, complete the
[attended lock and recovery checks](../../docs/lockscreen.md#before-enabling-automatic-locking),
including display sleep, suspend/resume and monitor reconnection with TTY
recovery available.
