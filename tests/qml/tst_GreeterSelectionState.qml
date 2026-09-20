import QtQuick
import QtTest
import "../../quickshell/session-stack-greeter"

TestCase {
    id: testCase
    name: "GreeterSelectionState"
    when: windowShown
    visible: true
    width: 1200; height: 700

    property var selection: null
    property string openMenu: ""
    Component {
        id: menuComponent
        LoginMenus {
            width: 600; height: 30; y: 500
            selection: testCase.selection
            openMenu: testCase.openMenu
            onMenuRequested: name => testCase.openMenu = name
        }
    }
    Component { id: interactionSpy; SignalSpy { signalName: "interacted" } }

    Component {
        id: selectionComponent

        GreeterSelectionState {
            users: [
                { username: "alpha", label: "ALPHA", role: "PRIMARY" },
                { username: "beta", label: "BETA", role: "SECONDARY" }
            ]
            systems: [
                { id: "one", label: "ONE", detail: "A", command: ["one"] },
                { id: "two", label: "TWO", detail: "B", command: ["two"] }
            ]
        }
    }

    function init() {
        selection = selectionComponent.createObject(testCase);
        verify(selection !== null);
    }

    function cleanup() {
        selection.destroy();
        selection = null;
    }

    function test_sharedMenuDoesNotStealKeyboardOwnership() {
        const first = createTemporaryObject(menuComponent, this);
        const second = createTemporaryObject(menuComponent, this, {x: 600});
        const firstInput = createTemporaryObject(interactionSpy, this, {target: first});
        const secondInput = createTemporaryObject(interactionSpy, this, {target: second});
        mouseClick(first, 450, 15);
        compare(openMenu, "user");
        compare(second.openMenu, "user");
        compare(firstInput.count, 1);
        compare(secondInput.count, 0);
        openMenu = "";
        first.destroy();
        second.destroy();
        wait(0);
    }

    function test_selectionLockRejectsEveryMutation() {
        selection.selectionEnabled = false;
        verify(!selection.selectUser(1));
        verify(!selection.selectSystem(1));
        verify(!selection.selectManualUser("gamma"));
        compare(selection.selectedUsername, "alpha");
        compare(selection.selectedSystem.id, "one");
        compare(selection.selectionGeneration, 0);
    }

    function test_biometricsFollowSelectedAndManuallyEnteredAccount() {
        selection.users = [
            {username: "alpha", faceAuthenticationEnabled: true, fingerprintAuthenticationEnabled: false},
            {username: "beta", faceAuthenticationEnabled: false, fingerprintAuthenticationEnabled: true}
        ];
        verify(selection.faceAuthenticationEnabled);
        verify(!selection.fingerprintAuthenticationEnabled);
        verify(selection.selectUser(1));
        verify(!selection.faceAuthenticationEnabled);
        verify(selection.fingerprintAuthenticationEnabled);
        verify(selection.selectManualUser(" alpha "));
        verify(selection.faceAuthenticationEnabled);
        verify(!selection.fingerprintAuthenticationEnabled);
        verify(selection.selectManualUser("unknown"));
        verify(!selection.faceAuthenticationEnabled);
        verify(!selection.fingerprintAuthenticationEnabled);
        verify(selection.passwordAuthenticationEnabled);
        verify(selection.selectManualUser(""));
        verify(!selection.ready);
    }

}
