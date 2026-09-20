import QtQuick
import QtTest
import "../../quickshell/common" as Common

TestCase {
    name: "SessionInput"
    when: windowShown
    width: 1600; height: 1000
    Component {
        id: fixture
        Item {
            width: 1600; height: 1000
            property alias flow: flow
            property alias credentials: credentials
            property alias screen: screen
            Common.CredentialState { id: credentials }
            Common.SwitchboardFlow { id: flow }
            Common.SessionSurface {
                id: screen
                anchors.fill: parent
                flow: parent.flow
                credentials: parent.credentials
                previewMode: true
                displayName: "TEST"
                passwordStatus: "Password ready"
                faceStatus: "Face ready"
                fingerprintStatus: "Fingerprint ready"
                availableMethods: [0, 1]
                busy: false
            }
        }
    }
    Component { id: displays; Common.DisplayState { screens: [] } }
    property var ui
    function init() { ui = createTemporaryObject(fixture, this); }

    function test_wakeTypingAndSharedDraft() {
        ui.screen.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(ui.credentials.text, "");
        keyClick(Qt.Key_A);
        keyClick(Qt.Key_B);
        compare(ui.credentials.text, "ab");
        ui.flow.advance(3);
        keyClick(Qt.Key_C);
        compare(ui.credentials.text, "abc");
        // A second output receives the existing draft and edits the same state.
        const second = createTemporaryObject(fixture, this);
        second.screen.credentials = ui.credentials;
        second.flow.reducedMotion = true;
        second.screen.wake();
        keyClick(Qt.Key_D);
        compare(ui.credentials.text, "abcd");
        keyClick(Qt.Key_Escape);
        compare(ui.credentials.text, "");
        second.screen.credentials = second.credentials;
    }

    function test_idleClearsDraftButWaitsForAuthentication() {
        ui.flow.reducedMotion = true;
        ui.flow.idleTimeout = 40;
        ui.screen.wake();
        ui.credentials.text = "unfinished";
        ui.flow.idleBlocked = true;
        wait(80);
        verify(ui.flow.inputReady);
        ui.flow.idleBlocked = false;
        tryCompare(ui.flow, "sceneTime", 0);
        compare(ui.credentials.text, "");
        ui.screen.wake();
        ui.flow.busy = true;
        ui.flow.advance(3);
        ui.flow.busy = false;
        ui.flow.awaitingResponse = true;
        verify(ui.flow.inputReady);
        wait(80);
        verify(ui.flow.inputReady);
        verify(!ui.flow.sleep());
    }

    function test_outputChoiceSurvivesRemoval() {
        const state = createTemporaryObject(displays, this, {
            screens: [{name: "eDP-1"}, {name: "DP-1"}]
        });
        compare(state.keyboardScreen, "DP-1");
        state.request("eDP-1");
        compare(state.keyboardScreen, "eDP-1");
        state.screens = [{name: "DP-1"}];
        compare(state.keyboardScreen, "DP-1");
    }
}
