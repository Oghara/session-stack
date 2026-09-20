import QtQuick

QtObject {
    id: controller

    required property bool enabled
    property int watchdogInterval: 12000
    property string pendingMethod: ""
    property bool releaseStarted: false

    signal releaseRequested(string method)

    function queue(method) {
        if (!enabled || releaseStarted || pendingMethod !== "")
            return false;

        pendingMethod = method;
        watchdog.restart();
        return true;
    }

    function complete() {
        if (!enabled || releaseStarted || pendingMethod === "")
            return false;

        const method = pendingMethod;
        releaseStarted = true;
        pendingMethod = "";
        watchdog.stop();
        releaseRequested(method);
        return true;
    }

    property Timer watchdog: Timer {
        interval: controller.watchdogInterval
        repeat: false
        onTriggered: controller.complete()
    }
}
