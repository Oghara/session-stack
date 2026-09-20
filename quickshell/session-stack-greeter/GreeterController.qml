import QtQuick

QtObject {
    id: controller

    enum Phase {
        Idle,
        Authenticating,
        AwaitingResponse,
        Ready,
        Launching,
        Failed,
        InfrastructureError
    }

    required property var backend
    property bool biometricSelectionEnabled: false
    // The PAM selector prompts even with biometrics disabled.
    required property bool methodSelectorEnabled
    property bool passwordAuthenticationEnabled: true
    property bool faceAuthenticationEnabled: false
    property bool fingerprintAuthenticationEnabled: false
    property int phase: GreeterController.Idle
    property string username: ""
    property var command: []
    property string authenticationMethod: "password"
    property bool selectorPending: false
    property bool methodPromptReady: false
    property string queuedMethod: ""
    property string queuedPassword: ""
    property bool credentialSubmitted: false
    property bool conversationActive: false
    property bool backendReusable: true
    property string faceStatus: biometricSelectionEnabled
        ? "Face ID ready — click to scan" : "Login biometric channel not configured"
    property string fingerprintStatus: biometricSelectionEnabled
        ? "Fingerprint ready — click to scan"
        : "Login biometric channel not configured"
    property string statusText: "GREETER LINK IDLE"
    property string promptText: "Waiting for greetd"
    property bool promptSecret: true
    property bool responseRequired: false
    property int clearGeneration: 0

    readonly property bool busy: credentialSubmitted
        || phase === GreeterController.Launching
    readonly property bool passwordQueued: conversationActive
        && queuedPassword !== "" && !credentialSubmitted
    readonly property bool authenticationComplete: phase === GreeterController.Ready
        || phase === GreeterController.Launching
    readonly property bool authenticationRejected: phase === GreeterController.Failed
    readonly property bool authenticationError:
        phase === GreeterController.InfrastructureError

    signal authenticationAccepted()
    signal launchAcknowledged()
    signal recoveryRequired()

    function clearPrompt() {
        responseRequired = false;
        methodPromptReady = false;
        promptSecret = true;
        clearGeneration += 1;
    }

    function clearSecrets() {
        selectorPending = false;
        queuedMethod = "";
        queuedPassword = "";
        credentialSubmitted = false;
        clearPrompt();
    }

    function enterInfrastructureError(message, cancelActive) {
        const shouldCancel = cancelActive && conversationActive;
        conversationActive = false;
        backendReusable = false;
        launchTimer.stop();
        clearSecrets();
        phase = GreeterController.InfrastructureError;
        statusText = message || "GREETD TRANSPORT ERROR";
        if (shouldCancel && backend)
            backend.cancelSession();
        recoveryRequired();
    }

    readonly property bool faceWorking: biometricSelectionEnabled
        && authenticationMethod === "face"
        && !selectorPending
        && phase === GreeterController.Authenticating
    readonly property bool fingerprintWorking: biometricSelectionEnabled
        && authenticationMethod === "fingerprint"
        && !selectorPending
        && phase === GreeterController.Authenticating

    function methodEnabled(method) {
        if (method === "password")
            return passwordAuthenticationEnabled;
        if (method === "face")
            return biometricSelectionEnabled && faceAuthenticationEnabled;
        if (method === "fingerprint")
            return biometricSelectionEnabled && fingerprintAuthenticationEnabled;
        return false;
    }

    function methodSelector(method) {
        return "session-stack-greeter:" + method + ":v1";
    }

    function startConversation(selectedUsername, selectedCommand,
                               selectedMethod, initialQueuedPassword) {
        if (!backend || !backend.available || conversationActive || !backendReusable)
            return false;
        if (backend.state !== undefined && Number(backend.state) !== 0) {
            enterInfrastructureError("GREETD CHANNEL IS NOT IDLE", true);
            return false;
        }

        const method = String(selectedMethod || "password");
        if (!methodEnabled(method))
            return false;

        username = selectedUsername;
        command = Array.from(selectedCommand);
        authenticationMethod = method;
        selectorPending = methodSelectorEnabled;
        queuedPassword = initialQueuedPassword || "";
        credentialSubmitted = false;
        clearPrompt();
        phase = GreeterController.Authenticating;
        conversationActive = true;
        if (authenticationMethod === "face") {
            faceStatus = "Starting camera…";
            statusText = "STARTING FACE ID // " + username.toUpperCase();
        } else if (authenticationMethod === "fingerprint") {
            fingerprintStatus = "Touch the fingerprint reader";
            statusText = "SCANNING FINGERPRINT // " + username.toUpperCase();
        } else {
            statusText = "OPENING PASSWORD CHANNEL // " + username.toUpperCase();
        }
        promptText = "Waiting for authentication prompt";
        backend.createSession(username);
        return true;
    }

    function begin(selectedUsername, selectedCommand) {
        const normalizedUser = String(selectedUsername || "").trim();
        if (normalizedUser === "" || !selectedCommand || selectedCommand.length === 0) {
            phase = GreeterController.InfrastructureError;
            statusText = "IDENTITY OR SYSTEM ROUTE INCOMPLETE";
            return false;
        }
        if (!backend || !backend.available) {
            phase = GreeterController.InfrastructureError;
            statusText = "GREETD SOCKET UNAVAILABLE";
            return false;
        }

        if (conversationActive || phase === GreeterController.Ready
                || phase === GreeterController.Launching) {
            statusText = "AUTHENTICATION ALREADY IN PROGRESS";
            return false;
        }
        if (!backendReusable) {
            statusText = "FRESH GREETER CONNECTION REQUIRED";
            return false;
        }

        username = normalizedUser;
        command = Array.from(selectedCommand);
        authenticationMethod = biometricSelectionEnabled
            ? "pending" : "password";
        clearSecrets();
        phase = GreeterController.Idle;
        faceStatus = biometricSelectionEnabled
            ? "Face ID ready — click to scan"
            : "Login biometric channel not configured";
        fingerprintStatus = biometricSelectionEnabled
            ? "Fingerprint ready — click to scan"
            : "Login biometric channel not configured";
        statusText = biometricSelectionEnabled
            ? "SELECT AUTH VECTOR // " + username.toUpperCase()
            : "ENTER CREDENTIAL // " + username.toUpperCase();
        promptText = "Select an authentication method";
        return true;
    }

    function beginFaceAuthentication() {
        if (!faceAuthenticationEnabled || username === "" || command.length === 0)
            return false;
        if (conversationActive) {
            if (selectorPending) {
                queuedMethod = "";
                authenticationMethod = "face";
                faceStatus = "Starting camera…";
                statusText = "STARTING FACE ID // " + username.toUpperCase();
                return methodPromptReady ? selectPendingMethod("face") : true;
            }
            if (phase === GreeterController.Authenticating
                    && authenticationMethod !== "password") {
                queuedMethod = "face";
                faceStatus = "Face ID queued — waiting for current scan";
                statusText = "FACE ID QUEUED // WAITING FOR "
                    + authenticationMethod.toUpperCase();
                return true;
            }
            statusText = "AUTH METHOD CANNOT CHANGE AFTER PASSWORD PROMPT";
            return false;
        }
        return startConversation(username, command, "face", "");
    }

    function retryBiometrics() {
        if (!fingerprintAuthenticationEnabled || username === "" || command.length === 0)
            return false;
        faceStatus = "Face ID ready — click to scan";
        fingerprintStatus = "Touch the fingerprint reader";
        if (conversationActive) {
            if (selectorPending) {
                queuedMethod = "";
                authenticationMethod = "fingerprint";
                statusText = "SCANNING FINGERPRINT // " + username.toUpperCase();
                return methodPromptReady
                    ? selectPendingMethod("fingerprint") : true;
            }
            if (phase === GreeterController.Authenticating
                    && authenticationMethod !== "password") {
                queuedMethod = "fingerprint";
                fingerprintStatus =
                    "Fingerprint retry queued — waiting for current scan";
                statusText = "FINGERPRINT QUEUED // WAITING FOR "
                    + authenticationMethod.toUpperCase();
                return true;
            }
            statusText = "AUTH METHOD CANNOT CHANGE AFTER PASSWORD PROMPT";
            return false;
        }
        return startConversation(username, command, "fingerprint", "");
    }

    function selectPendingMethod(method) {
        if (!conversationActive || !selectorPending || !methodPromptReady
                || phase !== GreeterController.Authenticating)
            return false;
        if (!methodEnabled(method))
            return false;

        authenticationMethod = method;
        selectorPending = false;
        methodPromptReady = false;
        backend.respond(methodSelector(method));
        if (method === "face") {
            faceStatus = "Scanning face…";
            statusText = "FACE ID ACTIVE // " + username.toUpperCase();
        } else if (method === "fingerprint") {
            fingerprintStatus = "Touch the fingerprint reader";
            statusText = "FINGERPRINT ACTIVE // " + username.toUpperCase();
        } else {
            statusText = "OPENING PASSWORD CHANNEL // " + username.toUpperCase();
        }
        return true;
    }

    function submit(response) {
        if (!passwordAuthenticationEnabled)
            return false;
        const password = String(response);
        if (password === "")
            return false;

        if (!conversationActive) {
            if (username === "" || command.length === 0 || !backendReusable)
                return false;
            return startConversation(username, command, "password", password);
        }

        if (methodSelectorEnabled
                && phase === GreeterController.Authenticating) {
            if (selectorPending) {
                queuedMethod = "";
                queuedPassword = password;
                authenticationMethod = "password";
                statusText = "OPENING PASSWORD CHANNEL // "
                    + username.toUpperCase();
                return methodPromptReady
                    ? selectPendingMethod("password") : true;
            }
            if (authenticationMethod !== "password") {
                // Queue within this PAM conversation. A cancel/create race can
                // misread the cancellation acknowledgement as auth success.
                queuedMethod = "password";
                queuedPassword = password;
                statusText = "PASSWORD QUEUED // WAITING FOR BIOMETRIC RESULT";
                return true;
            }
            queuedPassword = password;
            statusText = selectorPending
                ? "PASSWORD QUEUED // WAITING FOR METHOD PROMPT"
                : "PASSWORD QUEUED // WAITING FOR PASSWORD PROMPT";
            return true;
        }

        if (phase !== GreeterController.AwaitingResponse || !responseRequired) {
            statusText = "AUTH CHANNEL NOT READY";
            clearGeneration += 1;
            return false;
        }

        responseRequired = false;
        methodPromptReady = false;
        phase = GreeterController.Authenticating;
        credentialSubmitted = true;
        statusText = "AUTHENTICATING // " + username.toUpperCase();
        backend.respond(String(response));
        clearGeneration += 1;
        return true;
    }

    function commitLaunch() {
        if (phase !== GreeterController.Ready)
            return false;
        if (!conversationActive
                || (backend.state !== undefined && Number(backend.state) !== 2)
                || (backend.user !== undefined && String(backend.user) !== ""
                    && String(backend.user) !== username)) {
            enterInfrastructureError("GREETD LAUNCH STATE MISMATCH", true);
            return false;
        }
        phase = GreeterController.Launching;
        statusText = "LAUNCHING SESSION // " + username.toUpperCase();
        // Exit only after greetd acknowledges launch; failures use ReGreet.
        launchTimer.restart();
        backend.launch(command, [], false);
        return true;
    }

    function cancel() {
        const shouldCancel = conversationActive;
        conversationActive = false;
        backendReusable = false;
        launchTimer.stop();
        username = "";
        command = [];
        clearSecrets();
        phase = GreeterController.Idle;
        statusText = "GREETER LINK IDLE";
        if (backend && shouldCancel)
            backend.cancelSession();
    }

    property Connections backendConnections: Connections {
        target: controller.backend
        ignoreUnknownSignals: true

        function onAuthMessage(message, error, required, echoResponse) {
            if (!controller.conversationActive
                    || controller.phase === GreeterController.Ready
                    || controller.phase === GreeterController.Launching)
                return;
            controller.promptText = message;
            if (error) {
                controller.statusText = message;
                return;
            }
            if (!required)
                return;

            controller.methodPromptReady = true;
            if (controller.selectorPending) {
                if (!controller.selectPendingMethod(
                    controller.authenticationMethod)) {
                    controller.enterInfrastructureError(
                        "AUTH METHOD PROMPT STATE MISMATCH", true);
                }
                return;
            }

            if (controller.biometricSelectionEnabled
                    && controller.authenticationMethod !== "password") {
                const failedMethod = controller.authenticationMethod;
                if (failedMethod === "face")
                    controller.faceStatus = "Face not matched";
                else
                    controller.fingerprintStatus =
                        "Fingerprint not matched";

                controller.selectorPending = true;
                if (controller.queuedMethod !== "") {
                    const method = controller.queuedMethod;
                    controller.queuedMethod = "";
                    if (!controller.selectPendingMethod(method)) {
                        controller.enterInfrastructureError(
                            "AUTH METHOD RETRY STATE MISMATCH", true);
                    }
                    return;
                }
                if (controller.queuedPassword !== "") {
                    if (!controller.selectPendingMethod("password")) {
                        controller.enterInfrastructureError(
                            "PASSWORD FALLBACK STATE MISMATCH", true);
                    }
                    return;
                }
                controller.authenticationMethod = "pending";
                controller.statusText =
                    "SELECT AN ENABLED AUTH METHOD // "
                    + controller.username.toUpperCase();
                controller.promptText = controller.passwordAuthenticationEnabled
                    ? "Scan missed; retry an enabled method or enter password"
                    : "Scan missed; retry an enabled biometric method";
                return;
            }

            if (controller.queuedPassword !== "") {
                const password = controller.queuedPassword;
                controller.queuedPassword = "";
                controller.phase = GreeterController.Authenticating;
                controller.credentialSubmitted = true;
                controller.methodPromptReady = false;
                controller.statusText = "AUTHENTICATING // "
                    + controller.username.toUpperCase();
                controller.backend.respond(password);
                controller.clearGeneration += 1;
                return;
            }

            controller.credentialSubmitted = false;
            controller.responseRequired = true;
            controller.promptSecret = !echoResponse;
            controller.phase = GreeterController.AwaitingResponse;
            controller.statusText = "CREDENTIAL REQUIRED // "
                + controller.username.toUpperCase();
        }

        function onAuthFailure(message) {
            if (!controller.conversationActive
                    || controller.phase === GreeterController.Launching)
                return;
            controller.conversationActive = false;
            // QuickShell 0.3.0 reports idle before cancellation is acknowledged.
            // Recovery must open a fresh connection.
            controller.backendReusable = false;
            controller.launchTimer.stop();
            controller.clearSecrets();
            controller.phase = GreeterController.Failed;
            controller.statusText = message || "AUTHENTICATION REJECTED";
        }

        function onReadyToLaunch() {
            if (!controller.conversationActive
                    || controller.phase !== GreeterController.Authenticating
                    || controller.selectorPending
                    || controller.responseRequired) {
                if (controller.conversationActive)
                    controller.enterInfrastructureError(
                        "UNEXPECTED AUTH COMPLETION", true);
                return;
            }
            controller.clearSecrets();
            controller.phase = GreeterController.Ready;
            controller.statusText = "IDENTITY ACCEPTED // SESSION ARMED";
            controller.authenticationAccepted();
        }

        function onLaunched() {
            if (!controller.conversationActive
                    || controller.phase !== GreeterController.Launching)
                return;
            controller.launchTimer.stop();
            controller.conversationActive = false;
            controller.launchAcknowledged();
        }

        function onError(message) {
            controller.enterInfrastructureError(
                message || "GREETD TRANSPORT ERROR", false);
        }
    }

    property Timer launchTimer: Timer {
        interval: 10000
        repeat: false
        onTriggered: {
            if (controller.phase === GreeterController.Launching)
                controller.enterInfrastructureError(
                    "SESSION LAUNCH ACKNOWLEDGEMENT TIMED OUT", false);
        }
    }
}
