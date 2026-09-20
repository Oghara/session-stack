import QtQuick
import "LockAuthPolicy.js" as AuthPolicy

Item {
    id: controller

    required property string requestedMode
    required property bool passwordEnabled
    required property bool biometricsEnabled
    required property bool realLock
    required property bool sessionSecure
    required property bool localAuthCheck
    required property bool faceEnabled
    required property bool fingerprintEnabled
    required property string initialStatusText
    required property var passwordChannel
    required property var faceChannel
    required property var fingerprintChannel
    required property var lidMonitor
    property bool lifecycleManaged: false
    property bool surfaceActive: !lifecycleManaged
    property bool systemSleepPending: false
    property bool quarantined: false
    property bool shuttingDown: false
    property bool biometricRetryPending: false
    property int biometricRetryChecks: 0
    property var activeSurfaceTokens: []

    property alias result: authState.result
    property alias passwordBusy: authState.passwordBusy
    property alias awaitingResponse: authState.awaitingResponse
    property alias responseSecret: authState.responseSecret
    property alias passwordResponseSent: authState.passwordResponseSent
    property alias accepted: authState.accepted
    property alias authenticationMethod: authState.authenticationMethod
    property alias biometricWorkersStarted: authState.biometricWorkersStarted
    property alias faceRequested: authState.faceRequested
    property alias lidStateKnown: authState.lidStateKnown
    property alias lidClosed: authState.lidClosed
    property alias biometricPauseFromLid: authState.biometricPauseFromLid
    property alias facePaused: authState.facePaused
    property alias fingerprintPaused: authState.fingerprintPaused
    property alias faceFailures: authState.faceFailures
    property alias fingerprintFailures: authState.fingerprintFailures
    property alias faceFailureReason: authState.faceFailureReason
    property alias fingerprintFailureReason: authState.fingerprintFailureReason
    property alias clearGeneration: authState.clearGeneration
    property alias passwordGeneration: authState.passwordGeneration
    property alias biometricGeneration: authState.biometricGeneration
    property alias passwordPhase: authState.passwordPhase
    property alias facePhase: authState.facePhase
    property alias fingerprintPhase: authState.fingerprintPhase
    property alias pendingSecret: authState.pendingSecret
    property alias passwordStatus: authState.passwordStatus
    property alias faceStatus: authState.faceStatus
    property alias fingerprintStatus: authState.fingerprintStatus
    property alias statusText: authState.statusText

    readonly property bool workersActive: controller.passwordChannel.active
        || controller.faceChannel.active || controller.fingerprintChannel.active
    // A stopped monitor counts as an unreadable lid while it should be running.
    readonly property bool lidMonitorShouldRun: biometricsEnabled && surfaceActive
        && !systemSleepPending && !accepted && !shuttingDown
    readonly property bool rejected: result === LockAuthState.Rejected
    readonly property bool infrastructureError:
        result === LockAuthState.InfrastructureError
    readonly property bool faceWorking: facePhase === LockAuthState.Working
    readonly property bool fingerprintWorking:
        fingerprintPhase === LockAuthState.Working
    readonly property int maxBiometricFailures: 3
    readonly property string quarantineNotice:
        "Black ICE quarantine — jack in the ICEbreaker to restore authentication"
    property int activePasswordGeneration: -1
    property int activeFaceGeneration: -1
    property int activeFingerprintGeneration: -1

    signal authenticationAccepted(string method)

    visible: false
    width: 0
    height: 0

    LockAuthState {
        id: authState
        passwordEnabled: controller.passwordEnabled
        biometricsEnabled: controller.biometricsEnabled
        lifecycleManaged: controller.lifecycleManaged
        initialStatusText: controller.initialStatusText
    }

    function biometricWorkersShouldRun() {
        return AuthPolicy.biometricWorkersShouldRun(controller);
    }

    function setSurfaceActive(surfaceToken, active) {
        if (!lifecycleManaged || surfaceToken === null
                || surfaceToken === undefined)
            return;

        const nextTokens = activeSurfaceTokens.slice();
        const tokenIndex = nextTokens.indexOf(surfaceToken);
        if (active && tokenIndex < 0)
            nextTokens.push(surfaceToken);
        else if (!active && tokenIndex >= 0)
            nextTokens.splice(tokenIndex, 1);
        else
            return;

        activeSurfaceTokens = nextTokens;
        applySurfaceActivity(nextTokens.length > 0);
    }

    function unregisterSurface(surfaceToken) {
        setSurfaceActive(surfaceToken, false);
    }

    function applySurfaceActivity(active) {
        if (surfaceActive === active)
            return;

        surfaceActive = active;
        if (!active) {
            stopBiometricWorkers();
            authState.resetBiometricFailureState();
            faceRequested = false;
            lidStateKnown = false;
            lidClosed = true;
            biometricPauseFromLid = false;
            if (!accepted) {
                faceStatus = "Waiting for terminal activation";
                fingerprintStatus = "Waiting for terminal activation";
                facePhase = LockAuthState.Waiting;
                fingerprintPhase = LockAuthState.Waiting;
                statusText = "Terminal dormant — biometric hardware is unloaded";
            }
            return;
        }

        if (accepted || quarantined)
            return;

        faceStatus = "Waiting for lid state";
        fingerprintStatus = "Waiting for lid state";
        facePhase = LockAuthState.Waiting;
        fingerprintPhase = LockAuthState.Waiting;
    }

    function handleSessionSecurityChanged(secure) {
        if (!realLock || accepted || shuttingDown)
            return;

        if (!secure) {
            if (biometricWorkersStarted || controller.faceChannel.active
                    || controller.fingerprintChannel.active) {
                pauseBiometricWorkers(
                    "Biometrics paused until compositor security is restored");
            } else {
                statusText = "Waiting for compositor lock security";
            }
            return;
        }

        if (systemSleepPending)
            return;

        statusText = "Compositor lock secured — all authentication paths are available";
        if (biometricWorkersStarted)
            retryBiometricWorkers();
        else
            beginBiometricWorkers();
    }

    function handleLidState(state) {
        if (!AuthPolicy.isKnownLidState(state)) {
            lidStateKnown = false;
            lidClosed = true;
            biometricPauseFromLid = true;
            pauseBiometricWorkers("Biometrics disabled because lid state is unavailable");
            return;
        }

        const wasKnown = lidStateKnown;
        const wasClosed = lidClosed;
        lidStateKnown = true;
        lidClosed = state === "closed";

        if (lidClosed) {
            biometricPauseFromLid = true;
            pauseBiometricWorkers("Biometrics disabled while lid is closed");
            return;
        }

        if (!wasKnown || wasClosed || biometricPauseFromLid) {
            biometricPauseFromLid = false;
            if (lifecycleManaged)
                statusText = "Terminal active — biometric authentication is available";
            retryBiometricWorkers(true);
        }
    }

    function submit(secret) {
        if (passwordBusy || accepted || shuttingDown)
            return;

        if (realLock && !sessionSecure) {
            statusText = "Waiting for the compositor to secure every output";
            clearGeneration += 1;
            return;
        }

        if (systemSleepPending) {
            statusText = "Authentication paused for system sleep";
            clearGeneration += 1;
            return;
        }

        if (quarantined) {
            statusText = quarantineNotice;
            return;
        }

        if (!passwordEnabled) {
            statusText = "Preview submission received; no authentication was performed";
            clearGeneration += 1;
            return;
        }

        if (secret.length === 0) {
            passwordStatus = "Enter the account password";
            return;
        }

        if (awaitingResponse) {
            if (!passwordChannel.active) return;
            awaitingResponse = false;
            passwordBusy = true;
            passwordPhase = LockAuthState.Working;
            passwordChannel.respond(secret);
            return;
        }

        result = LockAuthState.Checking;
        passwordPhase = LockAuthState.Working;
        passwordBusy = true;
        passwordResponseSent = false;
        pendingSecret = secret;
        passwordStatus = "Checking…";
        activePasswordGeneration = passwordGeneration;

        if (!controller.passwordChannel.start()) {
            authState.setPasswordInfrastructureError("PAM could not start");
        }
    }

    function beginBiometricWorkers() {
        if (!biometricWorkersShouldRun() || biometricWorkersStarted)
            return;

        biometricWorkersStarted = true;
        startFaceWorker();
        startFingerprintWorker();
    }

    function startFaceWorker() {
        if (!faceEnabled) {
            facePhase = LockAuthState.Inactive;
            faceStatus = "Face disabled";
            return;
        }

        if (!faceRequested) {
            facePhase = LockAuthState.Waiting;
            faceStatus = "Face ID ready — click to scan";
            return;
        }

        const decision = AuthPolicy.biometricStartDecision(
            biometricWorkersShouldRun(), facePaused, controller.faceChannel.active);
        if (decision === AuthPolicy.BiometricStart.Skip)
            return;
        if (decision === AuthPolicy.BiometricStart.Defer) {
            faceRetryTimer.restart();
            return;
        }

        faceStatus = "Starting camera…";
        facePhase = LockAuthState.Working;
        activeFaceGeneration = biometricGeneration;
        if (!controller.faceChannel.start())
            handleFaceFailure("Face PAM could not start");
    }

    function requestFaceAuthentication() {
        if (!faceEnabled || accepted || shuttingDown)
            return false;

        if (systemSleepPending) {
            statusText = "Face ID is unavailable during system sleep";
            return false;
        }

        if (quarantined) {
            statusText = quarantineNotice;
            return false;
        }

        if (!biometricWorkersShouldRun()) {
            statusText = lidStateKnown && lidClosed
                ? "Face ID is unavailable while the lid is closed"
                : "Wake the secure terminal before starting Face ID";
            return false;
        }

        if (controller.faceChannel.active) {
            statusText = "Face ID scan is already active";
            return false;
        }

        faceRequested = true;
        faceFailures = 0;
        facePaused = false;
        faceFailureReason = "";
        faceStatus = "Face ID requested";
        statusText = "Face ID camera starting by request";
        startFaceWorker();
        return true;
    }

    function startFingerprintWorker() {
        if (!fingerprintEnabled) {
            fingerprintPhase = LockAuthState.Inactive;
            fingerprintStatus = "Fingerprint disabled";
            return;
        }

        const decision = AuthPolicy.biometricStartDecision(
            biometricWorkersShouldRun(), fingerprintPaused,
            controller.fingerprintChannel.active);
        if (decision === AuthPolicy.BiometricStart.Skip)
            return;
        if (decision === AuthPolicy.BiometricStart.Defer) {
            fingerprintRetryTimer.restart();
            return;
        }

        fingerprintStatus = "Starting reader…";
        fingerprintPhase = LockAuthState.Working;
        activeFingerprintGeneration = biometricGeneration;
        if (!controller.fingerprintChannel.start())
            handleFingerprintFailure("Fingerprint PAM could not start");
    }

    function updateBiometricPauseStatus() {
        if (facePaused && fingerprintPaused && !accepted)
            statusText = "Biometrics paused after repeated failures — password remains available; select a method to retry";
    }

    function handleFaceFailure(message) {
        if (facePaused || !biometricWorkersShouldRun())
            return;

        faceFailures += 1;
        if (faceFailures >= maxBiometricFailures) {
            facePaused = true;
            facePhase = LockAuthState.Paused;
            faceStatus = message + "; paused";
            faceRetryTimer.stop();
            updateBiometricPauseStatus();
        } else {
            facePhase = LockAuthState.Working;
            faceStatus = message + "; retrying…";
            faceRetryTimer.restart();
        }
    }

    function handleFingerprintFailure(message) {
        if (fingerprintPaused || !biometricWorkersShouldRun())
            return;

        fingerprintFailures += 1;
        if (fingerprintFailures >= maxBiometricFailures) {
            fingerprintPaused = true;
            fingerprintPhase = LockAuthState.Paused;
            fingerprintStatus = message + "; paused";
            fingerprintRetryTimer.stop();
            updateBiometricPauseStatus();
        } else {
            fingerprintPhase = LockAuthState.Working;
            fingerprintStatus = message + "; retrying…";
            fingerprintRetryTimer.restart();
        }
    }

    function abortBiometricChannels() {
        if (controller.faceChannel.active)
            controller.faceChannel.abort();
        if (controller.fingerprintChannel.active)
            controller.fingerprintChannel.abort();
    }

    function pauseBiometricWorkers(reason) {
        authState.invalidateBiometricAttempts();
        biometricRetryPending = false;
        biometricRetryChecks = 0;
        faceRequested = false;
        facePaused = true;
        fingerprintPaused = true;
        faceRetryTimer.stop();
        fingerprintRetryTimer.stop();
        manualBiometricRetryTimer.stop();
        abortBiometricChannels();

        faceStatus = reason;
        fingerprintStatus = reason;
        facePhase = LockAuthState.Paused;
        fingerprintPhase = LockAuthState.Paused;
        statusText = reason + " — password remains available; select a method to retry";
    }

    function pauseForSleep() {
        systemSleepPending = true;
        authState.invalidatePasswordAttempt();
        if (controller.passwordChannel.active)
            controller.passwordChannel.abort();
        // Require a fresh lid reading after sleep.
        lidStateKnown = false;
        lidClosed = true;
        pauseBiometricWorkers("Biometrics paused for system sleep");
        return !controller.passwordChannel.active
            && !controller.faceChannel.active
            && !controller.fingerprintChannel.active
            && !controller.lidMonitor.running;
    }

    function enterQuarantine() {
        quarantined = true;
        pauseBiometricWorkers(quarantineNotice);
        statusText = quarantineNotice;
    }

    function leaveQuarantine(retryWorkers) {
        quarantined = false;
        if (retryWorkers)
            retryBiometricWorkers();
        else
            statusText = "ICEbreaker complete — authentication channels restored";
    }

    function retryBiometricWorkers(preserveFailureState) {
        if (quarantined) {
            statusText = quarantineNotice;
            return;
        }

        if (!biometricWorkersShouldRun())
            return;

        biometricWorkersStarted = true;
        if (!preserveFailureState && (controller.faceChannel.active
                || controller.fingerprintChannel.active)) {
            biometricRetryPending = true;
            biometricRetryChecks = 0;
            authState.invalidateBiometricAttempts();
            abortBiometricChannels();
            manualBiometricRetryTimer.restart();
            return;
        }

        biometricRetryPending = false;
        biometricRetryChecks = 0;
        manualBiometricRetryTimer.stop();
        if (preserveFailureState) {
            facePaused = faceFailures >= maxBiometricFailures;
            fingerprintPaused = fingerprintFailures >= maxBiometricFailures;
        } else {
            faceFailures = 0;
            fingerprintFailures = 0;
            facePaused = false;
            fingerprintPaused = false;
        }
        if (!facePaused) {
            faceStatus = "Manual retry requested";
            facePhase = LockAuthState.Working;
        }
        if (!fingerprintPaused) {
            fingerprintStatus = "Manual retry requested";
            fingerprintPhase = LockAuthState.Working;
        }
        statusText = realLock
            ? "Compositor lock secured — restarting biometric authentication"
            : lifecycleManaged
                ? "Terminal active — restarting biometric authentication"
                : "Restarting biometric authentication check";
        startFaceWorker();
        startFingerprintWorker();
    }

    function completePendingBiometricRetry() {
        if (biometricRetryPending && !controller.faceChannel.active && !controller.fingerprintChannel.active)
            retryBiometricWorkers();
    }

    function resumeFromSleep() {
        if (shuttingDown)
            return false;

        const wasPending = systemSleepPending;
        systemSleepPending = false;
        if (wasPending) {
            facePaused = faceFailures >= maxBiometricFailures;
            fingerprintPaused = fingerprintFailures >= maxBiometricFailures;
            retryBiometricWorkers(true);
        }
        return true;
    }

    function stopBiometricWorkers() {
        faceRetryTimer.stop();
        fingerprintRetryTimer.stop();
        manualBiometricRetryTimer.stop();
        biometricRetryPending = false;
        biometricRetryChecks = 0;
        // Invalidate callbacks before aborting their contexts.
        authState.invalidateBiometricAttempts();
        abortBiometricChannels();

        biometricWorkersStarted = false;
    }

    function shutdownAuthentication() {
        shuttingDown = true;
        authState.invalidatePasswordAttempt();
        if (controller.passwordChannel.active)
            controller.passwordChannel.abort();
        stopBiometricWorkers();
        authState.resetBiometricFailureState();
    }

    function commitAuthentication(method) {
        if (accepted || quarantined)
            return;

        if (systemSleepPending || shuttingDown) {
            result = LockAuthState.NoResult;
            statusText = "Authentication completion ignored during system sleep";
            return;
        }

        if (realLock && !sessionSecure) {
            result = LockAuthState.NoResult;
            statusText = method
                + " completed while compositor security was unavailable — retry after the lock is secured";
            return;
        }

        authenticationMethod = method.toLowerCase();
        accepted = true;
        result = LockAuthState.Accepted;
        shutdownAuthentication();

        statusText = method + " accepted";
        if (!realLock)
            statusText += " — authentication workers stopped; the session stayed unlocked";
        authenticationAccepted(method);
    }

    Connections {
        target: controller.lidMonitor

        function onStateRead(state) {
            controller.handleLidState(state);
        }

        function onStopped() {
            if (controller.lidMonitorShouldRun)
                controller.handleLidState("unknown");
        }
    }

    Connections {
        target: controller.passwordChannel

        function onPrompt(text, responseRequired, responseVisible) {
            if (!authState.isPasswordAttemptCurrent(
                    controller.activePasswordGeneration)) {
                controller.passwordChannel.abort();
                return;
            }

            if (!responseRequired) {
                if (text !== "")
                    controller.passwordStatus = text;
                return;
            }

            if (controller.passwordResponseSent) {
                controller.passwordStatus = text || "Additional response required";
                controller.responseSecret = !responseVisible;
                controller.passwordBusy = false;
                controller.awaitingResponse = true;
                controller.clearGeneration += 1;
                return;
            }

            controller.passwordResponseSent = true;
            controller.passwordChannel.respond(controller.pendingSecret);
            controller.pendingSecret = "";
        }

        function onCompleted(success) {
            const currentAttempt = authState.isPasswordAttemptCurrent(
                    controller.activePasswordGeneration)
                && !controller.systemSleepPending && !controller.shuttingDown;
            const infrastructureFailure = controller.result
                === LockAuthState.InfrastructureError;
            authState.clearPendingPassword();
            if (!infrastructureFailure)
                controller.clearGeneration += 1;

            if (!currentAttempt)
                return;

            if (success) {
                controller.passwordPhase = LockAuthState.Accepted;
                controller.passwordStatus = "Password accepted";
                controller.commitAuthentication("Password");
            } else if (!controller.accepted
                    && controller.result !== LockAuthState.InfrastructureError) {
                controller.result = LockAuthState.Rejected;
                controller.passwordPhase = LockAuthState.Rejected;
                controller.passwordStatus = "Password rejected \u2014 retry available";
            }
        }

        function onFailed(reason) {
            if (!authState.isPasswordAttemptCurrent(
                    controller.activePasswordGeneration)
                    || controller.systemSleepPending || controller.shuttingDown)
                return;
            authState.setPasswordInfrastructureError("PAM error: " + reason);
        }
    }

    Connections {
        target: controller.faceChannel

        function onPrompt(text, responseRequired) {
            if (!authState.isBiometricAttemptCurrent(
                    controller.activeFaceGeneration)) {
                controller.faceChannel.abort();
                return;
            }

            if (responseRequired) {
                const failure = "Unexpected face PAM prompt; worker aborted";
                controller.faceFailureReason = failure;
                controller.faceStatus = failure;
                controller.facePhase = LockAuthState.Error;
                controller.faceChannel.abort();
            } else if (text !== "") {
                controller.faceStatus = text;
                controller.facePhase = LockAuthState.Working;
            }
        }

        function onCompleted(success) {
            if (!authState.isBiometricAttemptCurrent(
                    controller.activeFaceGeneration)) {
                Qt.callLater(controller.completePendingBiometricRetry);
                return;
            }
            if (success) {
                controller.faceFailureReason = "";
                controller.faceStatus = "Face accepted";
                controller.facePhase = LockAuthState.Accepted;
                controller.commitAuthentication("Face");
            } else {
                const failure = controller.faceFailureReason !== ""
                    ? controller.faceFailureReason : "Face not matched";
                controller.faceFailureReason = "";
                controller.handleFaceFailure(failure);
            }
        }

        function onFailed(reason) {
            if (!authState.isBiometricAttemptCurrent(
                    controller.activeFaceGeneration))
                return;
            controller.faceFailureReason = "Face PAM error: " + reason;
            controller.faceStatus = controller.faceFailureReason;
            controller.facePhase = LockAuthState.Error;
        }
    }

    Connections {
        target: controller.fingerprintChannel

        function onPrompt(text, responseRequired) {
            if (!authState.isBiometricAttemptCurrent(
                    controller.activeFingerprintGeneration)) {
                controller.fingerprintChannel.abort();
                return;
            }

            if (responseRequired) {
                const failure =
                    "Unexpected fingerprint PAM prompt; worker aborted";
                controller.fingerprintFailureReason = failure;
                controller.fingerprintStatus = failure;
                controller.fingerprintPhase = LockAuthState.Error;
                controller.fingerprintChannel.abort();
            } else if (text !== "") {
                controller.fingerprintStatus = text;
                controller.fingerprintPhase = LockAuthState.Working;
            }
        }

        function onCompleted(success) {
            if (!authState.isBiometricAttemptCurrent(
                    controller.activeFingerprintGeneration)) {
                Qt.callLater(controller.completePendingBiometricRetry);
                return;
            }
            if (success) {
                controller.fingerprintFailureReason = "";
                controller.fingerprintStatus = "Fingerprint accepted";
                controller.fingerprintPhase = LockAuthState.Accepted;
                controller.commitAuthentication("Fingerprint");
            } else {
                const failure = controller.fingerprintFailureReason !== ""
                    ? controller.fingerprintFailureReason
                    : "Fingerprint not matched";
                controller.fingerprintFailureReason = "";
                controller.handleFingerprintFailure(failure);
            }
        }

        function onFailed(reason) {
            if (!authState.isBiometricAttemptCurrent(
                    controller.activeFingerprintGeneration))
                return;
            controller.fingerprintFailureReason =
                "Fingerprint PAM error: " + reason;
            controller.fingerprintStatus = controller.fingerprintFailureReason;
            controller.fingerprintPhase = LockAuthState.Error;
        }
    }

    Timer {
        id: faceRetryTimer
        interval: 5000
        repeat: false
        onTriggered: controller.startFaceWorker()
    }

    Timer {
        id: fingerprintRetryTimer
        interval: 3000
        repeat: false
        onTriggered: controller.startFingerprintWorker()
    }

    Timer {
        id: manualBiometricRetryTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (!controller.biometricRetryPending)
                return;

            if (!controller.faceChannel.active && !controller.fingerprintChannel.active) {
                controller.retryBiometricWorkers();
                return;
            }

            controller.biometricRetryChecks += 1;
            if (controller.biometricRetryChecks < 40) {
                restart();
                return;
            }

            controller.biometricRetryPending = false;
            controller.statusText = "Biometric restart timed out; select a method to retry";
        }
    }
}
