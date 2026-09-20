// `running` reflects the process, not requested state, so sleep cannot attest
// teardown before the monitor exits.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: monitor

    property bool shouldRun: false
    readonly property bool running: process.running

    signal stateRead(string state)
    signal stopped()

    visible: false
    width: 0
    height: 0

    Process {
        id: process
        command: [Quickshell.env("SESSION_STACK_LID_MONITOR")
            || Quickshell.env("HOME") + "/.local/bin/session-stack-lid-monitor"]
        running: monitor.shouldRun

        stdout: SplitParser {
            onRead: state => monitor.stateRead(String(state).trim())
        }

        onExited: monitor.stopped()
    }
}
