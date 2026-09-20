import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: access

    property url snapshotSource: ""
    property var captureScreen: null
    property real revealProgress: 0
    property bool readySent: false

    readonly property real originX: width * 0.5
    readonly property real originY: height * 0.5
    readonly property real easedProgress: revealProgress < 0.5
        ? 4 * revealProgress * revealProgress * revealProgress
        : 1 - Math.pow(-2 * revealProgress + 2, 3) / 2
    // Reveal the live desktop through an aperture in the frozen lock frame.
    readonly property real revealWidth: {
        if (easedProgress <= 0.16)
            return width * 0.42 * easedProgress / 0.16;
        return width * (0.42 + 0.64
            * (easedProgress - 0.16) / 0.84);
    }
    readonly property real revealHeight: {
        if (easedProgress <= 0.16)
            return Math.max(2, height * 0.006 * easedProgress / 0.16);
        const openProgress = (easedProgress - 0.16) / 0.84;
        return height * 1.08 * openProgress;
    }
    readonly property real apertureChamfer: Math.max(0, Math.min(22,
        revealWidth * 0.06, revealHeight * 0.22))

    signal prepared()
    signal revealFinished()
    signal failed(string reason)

    visible: false
    screen: captureScreen
    color: "transparent"
    focusable: false
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        right: true
        bottom: true
        left: true
    }

    mask: Region {}
    surfaceFormat.opaque: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "session-stack-desktop-reveal"
    HyprlandWindow.visibleMask: apertureVisibleRegion

    function present(sourceUrl, targetScreen) {
        revealAnimation.stop();
        snapshotSource = sourceUrl;
        captureScreen = targetScreen;
        revealProgress = 0;
        readySent = false;
        visible = true;
        readyTimeout.restart();
        Qt.callLater(checkReady);
    }

    function checkReady() {
        if (!visible || readySent)
            return;
        if (!backingWindowVisible || snapshot.status !== Image.Ready)
            return;

        readySent = true;
        readyTimeout.stop();
        prepared();
        Qt.callLater(function() {
            if (access.visible)
                revealAnimation.restart();
        });
    }

    function abortAndHide() {
        revealAnimation.stop();
        readyTimeout.stop();
        visible = false;
        snapshotSource = "";
        readySent = false;
        revealProgress = 0;
    }

    onBackingWindowVisibleChanged: checkReady()

    Timer {
        id: readyTimeout
        interval: 2000
        onTriggered: {
            if (access.visible && !access.readySent)
                access.failed("desktop reveal did not become ready");
        }
    }

    Image {
        id: snapshot
        anchors.fill: parent
        source: access.snapshotSource
        cache: false
        fillMode: Image.Stretch
        onStatusChanged: {
            if (status === Image.Error && access.visible)
                access.failed("lock snapshot failed to load");
            else
                access.checkReady();
        }
    }

    Region {
        id: apertureVisibleRegion
        width: access.width
        height: access.height

        // Rectangular subtraction preserves the lock UI's clipped geometry.
        Region {
            x: access.originX - access.revealWidth * 0.5
            y: access.originY - access.revealHeight * 0.5
                + access.apertureChamfer
            width: access.revealWidth
            height: Math.max(0,
                access.revealHeight - access.apertureChamfer * 2)
            intersection: Intersection.Subtract
        }

        Region {
            x: access.originX - access.revealWidth * 0.5
                + access.apertureChamfer
            y: access.originY - access.revealHeight * 0.5
            width: Math.max(0,
                access.revealWidth - access.apertureChamfer * 2)
            height: access.apertureChamfer
            intersection: Intersection.Subtract
        }

        Region {
            x: access.originX - access.revealWidth * 0.5
                + access.apertureChamfer
            y: access.originY + access.revealHeight * 0.5
                - access.apertureChamfer
            width: Math.max(0,
                access.revealWidth - access.apertureChamfer * 2)
            height: access.apertureChamfer
            intersection: Intersection.Subtract
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: access
        property: "revealProgress"
        from: 0
        to: 1
        duration: 580
        easing.type: Easing.Linear
        onFinished: {
            access.visible = false;
            access.snapshotSource = "";
            access.revealFinished();
        }
    }
}
