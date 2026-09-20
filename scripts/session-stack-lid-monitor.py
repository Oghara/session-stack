#!/usr/bin/python3
"""Emit the current UPower lid state and every subsequent change."""

import signal
import sys

from gi.repository import Gio, GLib, GLibUnix


UPOWER_NAME = "org.freedesktop.UPower"
UPOWER_PATH = "/org/freedesktop/UPower"
UPOWER_INTERFACE = "org.freedesktop.UPower"


def main() -> int:
    once = sys.argv[1:] == ["--once"]
    if sys.argv[1:] and not once:
        print(f"Usage: {sys.argv[0]} [--once]", file=sys.stderr)
        return 2

    try:
        proxy = Gio.DBusProxy.new_for_bus_sync(
            Gio.BusType.SYSTEM,
            Gio.DBusProxyFlags.NONE,
            None,
            UPOWER_NAME,
            UPOWER_PATH,
            UPOWER_INTERFACE,
            None,
        )
    except GLib.Error as error:
        print(f"Could not connect to UPower: {error.message}", file=sys.stderr)
        return 1

    def emit_lid_state() -> None:
        value = proxy.get_cached_property("LidIsClosed")
        if value is None:
            print("unknown", flush=True)
            return
        print("closed" if value.unpack() else "open", flush=True)

    emit_lid_state()
    if once:
        return 0

    event_loop = GLib.MainLoop()

    def properties_changed(_proxy, changed, invalidated) -> None:
        changed_names = changed.unpack()
        if "LidIsClosed" in changed_names or "LidIsClosed" in invalidated:
            emit_lid_state()

    proxy.connect("g-properties-changed", properties_changed)

    def stop() -> bool:
        event_loop.quit()
        return GLib.SOURCE_REMOVE

    for stop_signal in (signal.SIGTERM, signal.SIGINT):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, stop_signal, stop)
    event_loop.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
