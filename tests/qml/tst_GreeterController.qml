import QtQuick
import QtTest
import "../../quickshell/session-stack-greeter"

TestCase {
    id: testCase
    name: "GreeterController"

    property var controller: null
    property var backendRef: backend

    QtObject {
        id: backend
        property bool available: true
        property int state: 0
        property string user: ""
        property bool responseAllowed: false
        property int createCount: 0
        property int cancelCount: 0
        property int respondCount: 0
        property int launchCount: 0
        property string response: ""
        property var responses: []

        signal authMessage(string message, bool error, bool responseRequired,
            bool echoResponse)
        signal authFailure(string message)
        signal readyToLaunch()
        signal launched()
        signal error(string message)

        function createSession(username) {
            createCount += 1;
            user = username;
            state = 1;
        }
        function cancelSession() {
            cancelCount += 1;
            responseAllowed = false;
            state = 0;
        }
        function prompt(message, echoResponse) {
            responseAllowed = true;
            authMessage(message, false, true, echoResponse || false);
        }
        function respond(value) {
            testCase.verify(responseAllowed, "Response before PAM requested one");
            responseAllowed = false;
            respondCount += 1;
            response = value;
            responses.push(value);
        }
        function succeed() {
            responseAllowed = false;
            state = 2;
            readyToLaunch();
        }
        function launch(command) {
            testCase.compare(state, 2, "Launch before authentication completed");
            state = 3;
            launchCount += 1;
        }
    }

    Component {
        id: controllerComponent

        GreeterController {
            backend: testCase.backendRef
            methodSelectorEnabled: biometricSelectionEnabled
        }
    }

    function init() {
        backend.available = true;
        backend.state = 0;
        backend.user = "";
        backend.responseAllowed = false;
        backend.createCount = 0;
        backend.cancelCount = 0;
        backend.respondCount = 0;
        backend.launchCount = 0;
        backend.response = "";
        backend.responses = [];
        controller = controllerComponent.createObject(testCase);
        verify(controller !== null);
        controller.faceAuthenticationEnabled = true;
        controller.fingerprintAuthenticationEnabled = true;
    }

    function cleanup() {
        controller.destroy();
        controller = null;
    }

    function test_biometricsWaitForExplicitMethodSelection() {
        controller.biometricSelectionEnabled = true;

        verify(controller.begin("alpha", ["one"]));
        compare(backend.createCount, 0);
        compare(controller.authenticationMethod, "pending");
        verify(controller.beginFaceAuthentication());
        compare(backend.createCount, 1);
        compare(backend.respondCount, 0);
        backend.prompt("Authentication method:", false);
        compare(backend.response, "session-stack-greeter:face:v1");
        verify(controller.faceWorking);
    }

    function test_fingerprintMissOffersFaceOrPassword() {
        controller.biometricSelectionEnabled = true;
        verify(controller.begin("alpha", ["one"]));
        verify(controller.retryBiometrics());
        compare(backend.respondCount, 0);
        verify(controller.selectorPending);

        backend.prompt("Authentication method:", false);
        compare(backend.response,
            "session-stack-greeter:fingerprint:v1");
        verify(controller.fingerprintWorking);

        backend.prompt("Authentication method:", false);
        compare(controller.authenticationMethod, "pending");
        verify(controller.selectorPending);
        compare(controller.phase, GreeterController.Authenticating);

        verify(controller.submit("secret"));
        compare(backend.responses[1], "session-stack-greeter:password:v1");
        backend.prompt("Password:", false);
        compare(backend.responses[2], "secret");
        verify(controller.busy);
    }

    function test_passwordDuringBiometricQueuesForPamFallback() {
        controller.biometricSelectionEnabled = true;
        verify(controller.begin("alpha", ["one"]));
        verify(controller.retryBiometrics());
        backend.prompt("Authentication method:", false);

        verify(controller.submit("secret"));
        compare(backend.cancelCount, 0);
        compare(backend.createCount, 1);
        compare(controller.queuedPassword, "secret");
        verify(controller.passwordQueued);
        verify(!controller.busy);

        backend.prompt("Authentication method:", false);
        compare(backend.responses[1], "session-stack-greeter:password:v1");
        backend.prompt("Password:", false);
        compare(backend.responses[2], "secret");
        compare(controller.phase, GreeterController.Authenticating);
        verify(controller.busy);
        verify(!controller.passwordQueued);
    }

    function test_queuedPasswordFollowsQueuedFaceMiss() {
        controller.biometricSelectionEnabled = true;
        verify(controller.begin("alpha", ["one"]));
        verify(controller.retryBiometrics());
        backend.prompt("Authentication method:", false);

        verify(controller.submit("secret"));
        verify(controller.beginFaceAuthentication());
        compare(controller.queuedMethod, "face");
        compare(backend.cancelCount, 0);
        compare(backend.createCount, 1);

        backend.prompt("Authentication method:", false);
        compare(backend.responses[1], "session-stack-greeter:face:v1");
        backend.prompt("Authentication method:", false);
        compare(backend.responses[2], "session-stack-greeter:password:v1");
        backend.prompt("Password:", false);
        compare(backend.responses[3], "secret");
    }

    function test_unexpectedReadyBeforeSelectorFailsClosed() {
        controller.biometricSelectionEnabled = true;
        verify(controller.begin("alpha", ["one"]));
        verify(controller.beginFaceAuthentication());
        backend.succeed();
        compare(controller.phase, GreeterController.InfrastructureError);
        compare(backend.cancelCount, 1);
        verify(!controller.conversationActive);
    }

    function test_launchStateMismatchDoesNotStickLaunching() {
        verify(controller.begin("alpha", ["one"]));
        verify(controller.submit("secret"));
        backend.prompt("Password:", false);
        backend.succeed();
        backend.state = 0;

        verify(!controller.commitLaunch());
        compare(controller.phase, GreeterController.InfrastructureError);
        compare(backend.launchCount, 0);
        verify(!controller.conversationActive);
    }

    function test_launchAcknowledgementIsBounded() {
        verify(controller.begin("alpha", ["one"]));
        verify(controller.submit("secret"));
        backend.prompt("Password:", false);
        backend.succeed();
        controller.launchTimer.interval = 1;

        verify(controller.commitLaunch());
        tryCompare(controller, "phase", GreeterController.InfrastructureError);
        verify(!controller.conversationActive);
        verify(!controller.backendReusable);
    }

    function test_transportErrorClearsQueuedPassword() {
        controller.biometricSelectionEnabled = true;
        verify(controller.begin("alpha", ["one"]));
        verify(controller.retryBiometrics());
        backend.prompt("Authentication method:", false);
        verify(controller.submit("secret"));
        compare(controller.queuedPassword, "secret");

        backend.error("socket failed");
        compare(controller.phase, GreeterController.InfrastructureError);
        compare(controller.queuedMethod, "");
        compare(controller.queuedPassword, "");
        verify(!controller.selectorPending);
        verify(!controller.conversationActive);
    }

    function test_lateCallbacksAfterCancelAreIgnored() {
        verify(controller.begin("alpha", ["one"]));
        verify(controller.submit("secret"));
        controller.cancel();
        backend.state = 2;
        backend.readyToLaunch();
        compare(controller.phase, GreeterController.Idle);
        verify(!controller.authenticationComplete);
    }
    function test_disabledMethodsCannotStartOrRespond() {
        controller.passwordAuthenticationEnabled = false;
        controller.faceAuthenticationEnabled = false;
        controller.fingerprintAuthenticationEnabled = true;
        controller.biometricSelectionEnabled = true;
        verify(controller.begin("alpha", ["one"]));
        verify(!controller.submit("secret"));
        verify(!controller.beginFaceAuthentication());
        verify(!controller.startConversation("alpha", ["one"], "password", "secret"));
        verify(!controller.startConversation("alpha", ["one"], "face", ""));
        compare(backend.createCount, 0);
        verify(controller.retryBiometrics());
        backend.prompt("Authentication method:", false);
        compare(backend.response, "session-stack-greeter:fingerprint:v1");
        backend.prompt("Authentication method:", false);
        verify(!controller.submit("secret"));
        verify(!controller.selectPendingMethod("password"));
        verify(!controller.selectPendingMethod("face"));
        compare(backend.respondCount, 1);
        compare(controller.queuedPassword, "");
        verify(controller.retryBiometrics());
        compare(backend.response, "session-stack-greeter:fingerprint:v1");
        backend.succeed();
        compare(controller.phase, GreeterController.Ready);
    }

}
