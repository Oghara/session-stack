# Third-party notices

Session Stack application code is licensed under [MIT](LICENSE).

## Visual reference

Vladimír Vilimovský's [Cyberpunk 2077 UI portfolio](https://www.behance.net/gallery/118663901/Cyberpunk-2077User-Interface-(Part-1))
is the art-direction reference. This package contains no portfolio images.
The interface is drawn with QML shapes and text. This does not establish
independent authorship of every shape or grant rights to third-party names
or artwork. Cyberpunk 2077 and Militech appear as an unaffiliated fan concept.

DejaVu Sans Mono is used from the system; no font file is bundled.

## QuickShell

`packaging/quickshell-session-stack/897fcda-session-lock-output-lifecycle.patch`
contains code from upstream QuickShell commit `897fcda`, under LGPL-3.0-only.
The [upstream source](https://git.outfoxxed.me/quickshell/quickshell) and its
license are separate from the MIT application. The package recipe downloads
the original source with a pinned checksum. No QuickShell binary is bundled.

The recipe derives from the official Arch Linux QuickShell 0.3.0 recipe;
its upstream attribution is retained in the file.
