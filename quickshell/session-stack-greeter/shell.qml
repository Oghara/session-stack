import QtQuick
import "common" as Common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

ShellRoot {
    id: root

    readonly property string requestedMode:
        Quickshell.env("SESSION_STACK_GREETER_MODE") || "preview"
    readonly property bool liveMode: requestedMode === "live"
    readonly property bool protocolTestMode: requestedMode === "protocol-test"
    readonly property bool biometricProtocolTest: protocolTestMode
        && Quickshell.env("SESSION_STACK_GREETER_BIOMETRIC_TEST") === "1"
    readonly property bool passwordAuthenticationEnabled: !liveMode
        || selection.passwordAuthenticationEnabled
    readonly property bool faceAuthenticationEnabled: (liveMode
        && selection.faceAuthenticationEnabled)
        || biometricProtocolTest
    readonly property bool fingerprintAuthenticationEnabled: (liveMode
        && selection.fingerprintAuthenticationEnabled)
        || biometricProtocolTest
    readonly property bool biometricSelectionEnabled: faceAuthenticationEnabled
        || fingerprintAuthenticationEnabled
    readonly property bool fakeMode: requestedMode === "preview"
    readonly property bool ordinaryWindow: !liveMode
    readonly property var currentSelection: selection
    Common.CredentialState { id: credentialState }
    property string openMenu: ""
    Connections {
        target: selection
        function onSelectionGenerationChanged() { credentialState.clear(); }
    }
    Connections {
        target: controller
        function onClearGenerationChanged() { credentialState.clear(); }
    }

    function prepareSelectedAuthentication() {
        if (!selection.ready) {
            if (controller.conversationActive)
                return false;
            controller.username = "";
            controller.command = [];
            controller.phase = GreeterController.InfrastructureError;
            controller.statusText = "IDENTITY OR SYSTEM ROUTE INCOMPLETE";
            return false;
        }
        return controller.begin(selection.selectedUsername,
            selection.selectedSystem.command);
    }

    function submitSelected(response) {
        if (!controller.conversationActive && !prepareSelectedAuthentication())
            return false;
        const accepted = controller.submit(response);
        if (accepted)
            credentialState.clear();
        return accepted;
    }

    function startSelectedFace() {
        if (!controller.conversationActive && !prepareSelectedAuthentication())
            return false;
        return controller.beginFaceAuthentication();
    }

    function startSelectedFingerprint() {
        if (!controller.conversationActive && !prepareSelectedAuthentication())
            return false;
        return controller.retryBiometrics();
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        if (liveMode && selection.generatedData.isDemo) {
            console.error("Live mode refused: stage a host inventory first");
            Qt.callLater(function() { Qt.exit(1); });
            return;
        }
        if (!fakeMode && !Greetd.available) {
            console.error("greetd-backed mode refused: GREETD_SOCK is unavailable");
            Qt.callLater(function() { Qt.exit(1); });
            return;
        }
    }

    GreeterSelectionState {
        id: selection
        selectionEnabled: controller.backendReusable
            && !controller.conversationActive
            && !controller.authenticationComplete
    }

    FakeGreetdBackend {
        id: fakeBackend
    }

    GreeterController {
        id: controller
        backend: root.fakeMode ? fakeBackend : Greetd
        biometricSelectionEnabled: root.biometricSelectionEnabled
        methodSelectorEnabled: !root.fakeMode
        passwordAuthenticationEnabled: root.passwordAuthenticationEnabled
        faceAuthenticationEnabled: root.faceAuthenticationEnabled
        fingerprintAuthenticationEnabled: root.fingerprintAuthenticationEnabled

        onLaunchAcknowledged: {
            if (!root.fakeMode)
                Qt.quit();
            else
                statusText = "PREVIEW SESSION ACKNOWLEDGED // NO PROCESS STARTED";
        }

        onRecoveryRequired: {
            if (!root.fakeMode)
                Qt.exit(1);
        }
    }

    Common.SwitchboardFlow {
        id: sceneFlow
        accepted: controller.authenticationComplete
        rejected: controller.authenticationRejected
        failed: controller.authenticationError
        busy: controller.busy
        awaitingResponse: controller.responseRequired
        idleBlocked: controller.conversationActive || root.openMenu !== ""
        reducedMotion: Quickshell.env("SESSION_STACK_LOCK_REDUCED_MOTION") === "1"
        onCompleted: controller.commitLaunch()
        onRecovered: {
            if (root.fakeMode) {
                controller.backendReusable = true;
                controller.phase = GreeterController.Idle;
                controller.statusText = "GREETER LINK IDLE";
            } else Qt.exit(1);
        }
    }

    readonly property var availableMethods: {
        const methods = [];
        if (passwordAuthenticationEnabled) methods.push(0);
        if (faceAuthenticationEnabled) methods.push(1);
        if (fingerprintAuthenticationEnabled) methods.push(2);
        return methods;
    }
    Component {
        id: greeterSurfaceComponent
        Common.SessionSurface {
            id: greeterSurface
            flow: sceneFlow
            credentials: credentialState
            previewMode: root.ordinaryWindow
            authenticationMode: true
            displayName: selection.selectedSystem ? selection.selectedSystem.label : "SELECT SESSION"
            userLabel: selection.selectedUserLabel
            passwordStatus: controller.promptText
            faceStatus: controller.faceStatus
            fingerprintStatus: controller.fingerprintStatus
            faceWorking: controller.faceWorking
            fingerprintWorking: controller.fingerprintWorking
            availableMethods: root.availableMethods
            busy: controller.busy
            queued: controller.passwordQueued
            awaitingResponse: controller.responseRequired
            responseSecret: controller.promptSecret
            reducedMotion: sceneFlow.reducedMotion
            menuOpen: root.openMenu !== ""
            onCloseMenuRequested: root.openMenu = ""
            footerContent: Component {
                LoginMenus {
                    selection: root.currentSelection
                    openMenu: root.openMenu
                    onMenuRequested: name => root.openMenu = name
                    onInteracted: greeterSurface.interact()
                }
            }
            onSubmitted: secret => root.submitSelected(secret)
            onFaceAuthenticationRequested: root.startSelectedFace()
            onBiometricRetryRequested: root.startSelectedFingerprint()
        }
    }

    FloatingWindow {
        id: previewWindow
        visible: root.ordinaryWindow
        onClosed: {
            controller.cancel();
            Qt.quit();
        }
        implicitWidth: 1280
        implicitHeight: 760
        color: "#07090c"
        title: root.fakeMode
            ? "Session Stack login preview. Password: demo"
            : "Session Stack login protocol test"

        Loader {
            id: previewLoader
            anchors.fill: parent
            active: root.ordinaryWindow
            sourceComponent: greeterSurfaceComponent
        }
    }

    Loader {
        id: liveSurfacesLoader
        active: root.liveMode && !selection.generatedData.isDemo
            && Greetd.available
        source: "LiveGreeterSurfaces.qml"
        onLoaded: item.greeterSurfaceComponent = greeterSurfaceComponent
    }

    IpcHandler {
        target: "sessionStackGreeter"

        function status(): string {
            return JSON.stringify({
                mode: root.requestedMode,
                phase: controller.phase,
                busy: controller.busy,
                passwordEnabled: root.passwordAuthenticationEnabled,
                faceEnabled: root.faceAuthenticationEnabled,
                fingerprintEnabled: root.fingerprintAuthenticationEnabled,
                user: selection.selectedUsername,
                system: selection.selectedSystem
                    ? selection.selectedSystem.id : ""
            });
        }

        function capturePreview(path: string): string {
            if (!root.fakeMode || !previewLoader.item)
                return "refused";
            previewLoader.item.grabToImage(result => result.saveToFile(path));
            return "capturing";
        }

        function menu(name: string): string {
            if (!root.ordinaryWindow || !previewLoader.item)
                return "refused";
            if (name !== "user" && name !== "system" && name !== "")
                return "invalid";
            sceneFlow.wake();
            root.openMenu = name;
            return name === "" ? "closed" : name;
        }

        function submit(response: string): string {
            if (!root.protocolTestMode)
                return "refused";
            return root.submitSelected(response) ? "submitted" : "not-ready";
        }

        function retryAuthentication(): string {
            if (!root.protocolTestMode || !previewLoader.item)
                return "refused";
            if (!controller.authenticationRejected || !sceneFlow.inject())
                return "not-ready";
            return "retrying";
        }

        function selectUser(username: string): string {
            if (!root.protocolTestMode)
                return "refused";
            return selection.selectManualUser(username) ? "selected" : "locked";
        }

        function selectSystem(systemId: string): string {
            if (!root.protocolTestMode)
                return "refused";
            for (let index = 0; index < selection.systems.length; index += 1) {
                if (selection.systems[index].id === systemId) {
                    return selection.selectSystem(index)
                        ? "selected" : "locked";
                }
            }
            return "invalid";
        }

        function closePreview(): string {
            if (!root.ordinaryWindow)
                return "refused";
            controller.cancel();
            Qt.quit();
            return "closing";
        }
    }
}
