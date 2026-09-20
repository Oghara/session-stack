// Only the managed launcher should set
// the acknowledgement and marker that enable WlSessionLock.
import QtQuick
import QtQuick.Window
import "common" as Common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string requestedMode: Quickshell.env("SESSION_STACK_LOCK_MODE") || "preview"
    readonly property string lockAcknowledgement: Quickshell.env("SESSION_STACK_LOCK_ACK") || ""
    readonly property string unlockMarkerPath: Quickshell.env("SESSION_STACK_UNLOCK_MARKER") || ""
    readonly property string localPamDirectory: Quickshell.env("SESSION_STACK_TEST_PAM_DIR") || ""
    readonly property bool localAuthCheck: requestedMode === "local-auth-check"
    readonly property bool motionSurfaceRequested:
        Quickshell.env("SESSION_STACK_LOCK_MOTION_PREVIEW") === "1"
    readonly property bool motionPreview: requestedMode === "preview"
        && motionSurfaceRequested
    readonly property bool motionAuthCheck: requestedMode === "auth-check"
        && motionSurfaceRequested
    readonly property bool motionPreviewAutoUnlock:
        Quickshell.env("SESSION_STACK_LOCK_MOTION_AUTO_UNLOCK") !== "0"
    readonly property bool motionPreviewDanger:
        Quickshell.env("SESSION_STACK_LOCK_MOTION_DANGER") === "1"
    readonly property bool lockGuardValid: lockAcknowledgement === "I_HAVE_TTY_RECOVERY"
        && unlockMarkerPath !== ""
    readonly property bool realLock: requestedMode === "lock" && lockGuardValid
    readonly property bool authenticatingMode: requestedMode === "pam-check"
        || requestedMode === "auth-check" || localAuthCheck || realLock
    readonly property var enabledMethods: (Quickshell.env("SESSION_STACK_ENABLED_METHODS") || "password").split(",")
    readonly property bool passwordEnabled: authenticatingMode && enabledMethods.includes("password")
    readonly property bool faceEnabled: enabledMethods.includes("face")
    readonly property bool fingerprintEnabled: enabledMethods.includes("fingerprint")
    readonly property bool biometricsEnabled: authenticatingMode && (faceEnabled || fingerprintEnabled)
    readonly property var availableMethods: {
        const methods = [];
        if (enabledMethods.includes("password")) methods.push(0);
        if (faceEnabled) methods.push(1);
        if (fingerprintEnabled) methods.push(2);
        return methods;
    }
    readonly property string initialStatusText: requestedMode === "lock" && !lockGuardValid
        ? "Lock guard refused. Showing a preview."
        : requestedMode === "auth-check" || localAuthCheck
            ? "Authentication test. Your session is not locked."
            : requestedMode === "pam-check"
                ? "Password test. Your session is not locked."
                : requestedMode === "preview"
                    ? "Preview. No authentication or screen locking."
                    : "Requesting the compositor session lock…"
    readonly property string statusText: auth.statusText
    readonly property string passwordStatus: auth.passwordStatus
    readonly property string faceStatus: auth.faceStatus
    readonly property string fingerprintStatus: auth.fingerprintStatus
    readonly property bool faceRequested: auth.faceRequested
    readonly property bool faceWorking: auth.faceWorking
    readonly property bool fingerprintWorking: auth.fingerprintWorking
    readonly property bool unlockCommitted: auth.accepted
    readonly property string authenticationMethod: auth.authenticationMethod
    readonly property int clearGeneration: auth.clearGeneration
    readonly property bool passwordBusy: auth.passwordBusy
    property int workerCleanupChecks: 0
    property var desktopRevealGrabResult: null

    Common.CredentialState { id: credentialState }
    Common.DisplayState { id: displays; screens: Quickshell.screens }
    Connections {
        target: auth
        function onClearGenerationChanged() { credentialState.clear(); }
        function onAcceptedChanged() { if (auth.accepted) credentialState.clear(); }
    }

    function beginDesktopReveal(surfaceItem) {
        if (!surfaceItem || !previewWindow.visible)
            return;

        const targetScreen = previewWindow.screen;
        const started = surfaceItem.grabToImage(function(result) {
            if (!result || String(result.url) === "") {
                console.warn("Live desktop reveal could not capture the completed lock frame");
                return;
            }

            root.desktopRevealGrabResult = result;
            desktopAccess.present(result.url, targetScreen);
        });

        if (!started)
            console.warn("Live desktop reveal capture did not start");
    }

    function finishUnlock(method) {
        auth.statusText = method + " accepted. Unlocking…";
        sessionLock.locked = false;
        workerCleanupChecks = 0;
        unlockCleanupTimer.restart();
    }

    // Inject service objects so the controller remains testable with fakes.
    readonly property string pamDirectory: root.localAuthCheck
        ? root.localPamDirectory : "/etc/pam.d"

    LockPamChannel {
        id: passwordPamChannel
        config: "session-stack-lock-password"
        configDirectory: root.pamDirectory
    }

    LockPamChannel {
        id: facePamChannel
        config: "session-stack-lock-face"
        configDirectory: root.pamDirectory
    }

    LockPamChannel {
        id: fingerprintPamChannel
        config: "session-stack-lock-fingerprint"
        configDirectory: root.pamDirectory
    }

    // The controller consumes readings; the shell only controls process lifetime.
    LockLidMonitor {
        id: lidStateMonitor
        shouldRun: auth.lidMonitorShouldRun
    }

    LockAuthController {
        id: auth
        requestedMode: root.requestedMode
        passwordEnabled: root.passwordEnabled
        biometricsEnabled: root.biometricsEnabled
        realLock: root.realLock
        sessionSecure: sessionLock.secure
        localAuthCheck: root.localAuthCheck
        faceEnabled: root.faceEnabled
        fingerprintEnabled: root.fingerprintEnabled
        initialStatusText: root.initialStatusText
        passwordChannel: passwordPamChannel
        faceChannel: facePamChannel
        fingerprintChannel: fingerprintPamChannel
        lidMonitor: lidStateMonitor
        lifecycleManaged: root.authenticatingMode

        onAuthenticationAccepted: method => unlockHandoff.queue(method)
    }

    Common.SwitchboardFlow {
        id: sceneFlow
        accepted: root.unlockCommitted
        rejected: auth.rejected
        failed: auth.infrastructureError
        busy: root.passwordBusy
        awaitingResponse: auth.awaitingResponse
        idleBlocked: auth.workersActive
        preview: root.requestedMode === "preview"
        sleepPending: auth.systemSleepPending
        reducedMotion: Quickshell.env("SESSION_STACK_LOCK_REDUCED_MOTION") === "1"
        onQuarantineRequested: auth.enterQuarantine()
        onRecovered: auth.leaveQuarantine(false)
        onCompleted: {
            // Acceptance queues the handoff later in the same signal delivery.
            if (root.realLock) Qt.callLater(unlockHandoff.complete);
            else root.beginDesktopReveal(previewLoader.item);
        }
    }

    LockUnlockHandoff {
        id: unlockHandoff
        enabled: root.realLock
        onReleaseRequested: method => root.finishUnlock(method)
    }

    Component.onCompleted: {
        // Never replace a live ext-session-lock client through hot reload.
        Quickshell.watchFiles = false;

        if (requestedMode === "lock" && !lockGuardValid) {
            console.error("Real lock refused: launch it through the managed session-stack-lock helper");
        } else if (requestedMode === "auth-check" || localAuthCheck) {
            Qt.callLater(auth.beginBiometricWorkers);
        }
    }

    Timer {
        id: unlockCleanupTimer
        interval: 100
        repeat: true
        onTriggered: {
            root.workerCleanupChecks += 1;

            if (!auth.workersActive) {
                stop();
                unlockMarkerWriter.running = true;
            } else if (root.workerCleanupChecks >= 50) {
                console.warn("Timed out waiting for PAM worker cleanup after unlock");
                stop();
                unlockMarkerWriter.running = true;
            }
        }
    }

    Process {
        id: unlockMarkerWriter
        command: ["/usr/bin/touch", root.unlockMarkerPath]
        onExited: Qt.quit()
    }

    IpcHandler {
        target: "lockPrototype"

        function status(): string {
            if (root.requestedMode === "lock" && !root.realLock)
                return "guard-refused";
            if (root.realLock)
                return sessionLock.secure ? "secure" : "requesting-lock";
            return root.requestedMode;
        }

        function authStatus(): string {
            return JSON.stringify({
                password: root.passwordStatus,
                face: root.faceStatus,
                fingerprint: root.fingerprintStatus,
                accepted: root.unlockCommitted,
                sleepPending: auth.systemSleepPending,
                workersActive: auth.workersActive
            });
        }

        function prepareForSleep(): string {
            return auth.pauseForSleep() ? "paused" : "stopping";
        }

        function retryBiometrics(): string {
            return auth.resumeFromSleep() ? "retrying" : "stopping";
        }

        function previewScene(time: real, outcome: string, recovery: bool): string {
            if (root.requestedMode !== "preview" || !previewLoader.item)
                return "refused";
            const scene = sceneFlow;
            scene.paused = true;
            scene.outcome = outcome === "success" ? "success" : "failure";
            scene.recovering = recovery;
            scene.sceneTime = Math.max(0, Math.min(13.2, time));
            return "ready";
        }

        function capturePreview(path: string): string {
            if (root.requestedMode !== "preview" || !previewLoader.item)
                return "refused";
            previewLoader.item.grabToImage(result => result.saveToFile(path));
            return "capturing";
        }

        function closePreview(): string {
            if (root.realLock)
                return "refused: real lock requires successful authentication";

            auth.shutdownAuthentication();
            Qt.quit();
            return "closing";
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: root.realLock

        onSecureChanged: {
            auth.handleSessionSecurityChanged(secure);
        }

        WlSessionLockSurface {
            id: lockSurface
            color: "#11111b"

            Common.SessionSurface {
                flow: sceneFlow
                anchors.fill: parent
                ownsKeyboard: displays.keyboardScreen === displayName
                onFocusRequested: displays.request(displayName)
                Window.onActiveChanged: { if (Window.active) displays.request(displayName); }
                previewMode: false
                authenticationMode: true
                displayName: lockSurface.screen ? lockSurface.screen.name : "display"
                passwordStatus: root.passwordStatus
                faceStatus: root.faceStatus
                fingerprintStatus: root.fingerprintStatus
                availableMethods: root.availableMethods
                busy: root.passwordBusy
                credentials: credentialState
                awaitingResponse: auth.awaitingResponse
                responseSecret: auth.responseSecret
                reducedMotion: sceneFlow.reducedMotion
                userLabel: Quickshell.env("USER")
                faceWorking: auth.faceWorking
                fingerprintWorking: auth.fingerprintWorking
                demoUnlock: false
                demoDanger: false
                onTerminalPhaseChanged: auth.setSurfaceActive(
                    lockSurface, terminalPhase === "active")
                onSubmitted: secret => auth.submit(secret)
                onBiometricRetryRequested: auth.retryBiometricWorkers()
                onFaceAuthenticationRequested: auth.requestFaceAuthentication()
                Component.onDestruction: auth.unregisterSurface(lockSurface)
            }
        }
    }

    DesktopAccessSequence {
        id: desktopAccess

        onPrepared: previewWindow.visible = false
        onRevealFinished: {
            root.desktopRevealGrabResult = null;
            if (!root.realLock)
                Qt.quit();
        }
        onFailed: reason => {
            console.warn("Live desktop reveal failed: " + reason);
            abortAndHide();
            root.desktopRevealGrabResult = null;
        }
    }

    FloatingWindow {
        id: previewWindow
        visible: !root.realLock
        implicitWidth: 960
        implicitHeight: 680
        color: "#11111b"
        title: "Session Stack lock test window"
        onClosed: {
            auth.shutdownAuthentication();
            Qt.quit();
        }

        Loader {
            id: previewLoader
            anchors.fill: parent
            active: !root.realLock
            sourceComponent: motionSurfaceComponent

            Component {
                id: motionSurfaceComponent

                Common.SessionSurface {
                    flow: sceneFlow
                    previewMode: true
                    authenticationMode: root.requestedMode !== "preview"
                    displayName: root.requestedMode === "preview"
                        ? "preview" : "authentication test"
                    passwordStatus: root.passwordStatus
                    faceStatus: root.faceStatus
                    fingerprintStatus: root.fingerprintStatus
                    availableMethods: root.availableMethods
                    busy: root.passwordBusy
                    credentials: credentialState
                    awaitingResponse: auth.awaitingResponse
                    responseSecret: auth.responseSecret
                    reducedMotion: sceneFlow.reducedMotion
                    userLabel: Quickshell.env("USER")
                    faceWorking: auth.faceWorking
                    fingerprintWorking: auth.fingerprintWorking
                    demoUnlock: root.motionPreview && root.motionPreviewAutoUnlock
                    demoDanger: root.motionPreview && root.motionPreviewDanger
                    onTerminalPhaseChanged: auth.setSurfaceActive(
                        previewWindow, terminalPhase === "active")
                    onSubmitted: secret => auth.submit(secret)
                    onBiometricRetryRequested: auth.retryBiometricWorkers()
                    onFaceAuthenticationRequested: auth.requestFaceAuthentication()
                }
            }
        }
    }
}
