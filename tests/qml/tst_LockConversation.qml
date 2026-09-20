import QtQuick
import QtTest
import "../../quickshell/session-stack-lock" as Lock

TestCase {
    name: "LockConversation"
    Component {
        id: channelFactory
        QtObject {
            property bool active: false
            property int starts: 0
            property string response: ""
            signal prompt(string text, bool required, bool visible)
            signal completed(bool success)
            signal failed(string reason)
            function start() { starts++; active = true; return true; }
            function respond(text) { response = text; }
            function abort() { active = false; }
        }
    }
    Component {
        id: lidFactory
        QtObject {
            property bool running: false
            signal stateRead(string state)
            signal stopped()
        }
    }
    Component {
        id: authFactory
        Lock.LockAuthController {
            requestedMode: "auth-check"
            passwordEnabled: true
            biometricsEnabled: false
            realLock: false
            sessionSecure: false
            localAuthCheck: true
            faceEnabled: false
            fingerprintEnabled: false
            initialStatusText: "Ready"
        }
    }
    property var auth
    property var password
    function init() {
        password = createTemporaryObject(channelFactory, this);
        auth = createTemporaryObject(authFactory, this, {
            passwordChannel: password,
            faceChannel: createTemporaryObject(channelFactory, this),
            fingerprintChannel: createTemporaryObject(channelFactory, this),
            lidMonitor: createTemporaryObject(lidFactory, this)
        });
    }
    function requestSecondPrompt() {
        auth.submit("first");
        password.prompt("Password:", true, false);
        compare(password.response, "first");
        password.prompt("Verification code:", true, true);
        verify(auth.awaitingResponse);
        verify(!auth.passwordBusy);
        verify(!auth.responseSecret);
        verify(!auth.accepted);
    }
    function test_followupUsesExistingConversation() {
        requestSecondPrompt();
        auth.submit("123456");
        compare(password.starts, 1);
        compare(password.response, "123456");
        verify(auth.passwordBusy);
        verify(!auth.awaitingResponse);
        password.active = false;
        password.completed(true);
        verify(auth.accepted);
        verify(auth.responseSecret);
    }
    function test_rejectionResetsPromptState() {
        requestSecondPrompt();
        password.active = false;
        password.completed(false);
        verify(auth.rejected);
        verify(!auth.awaitingResponse);
        verify(auth.responseSecret);
        verify(!auth.accepted);
    }
    function test_sleepInvalidatesPendingResponse() {
        requestSecondPrompt();
        auth.pauseForSleep();
        verify(!password.active);
        verify(!auth.awaitingResponse);
        password.completed(true);
        verify(!auth.accepted);
        auth.submit("late response");
        compare(password.starts, 1);
    }
}
