import QtQml

QtObject {
    enum Result {
        NoResult,
        Checking,
        Accepted,
        Rejected,
        InfrastructureError
    }

    enum ChannelPhase {
        Inactive,
        Waiting,
        Working,
        Paused,
        Accepted,
        Rejected,
        Error
    }

    required property bool passwordEnabled
    required property bool biometricsEnabled
    required property bool lifecycleManaged
    required property string initialStatusText

    property int result: LockAuthState.NoResult
    property bool passwordBusy: false
    property bool passwordResponseSent: false
    property bool awaitingResponse: false
    property bool responseSecret: true
    property bool accepted: false
    property string authenticationMethod: ""
    property bool biometricWorkersStarted: false
    property bool faceRequested: false
    property bool lidStateKnown: false
    property bool lidClosed: true
    property bool biometricPauseFromLid: false
    property bool facePaused: false
    property bool fingerprintPaused: false
    property int faceFailures: 0
    property int fingerprintFailures: 0
    property string faceFailureReason: ""
    property string fingerprintFailureReason: ""
    property int clearGeneration: 0
    // Epochs reject late PAM callbacks from aborted attempts.
    property int passwordGeneration: 0
    property int biometricGeneration: 0
    property string pendingSecret: ""
    property int passwordPhase: passwordEnabled
        ? LockAuthState.Waiting : LockAuthState.Inactive
    property int facePhase: biometricsEnabled
        ? LockAuthState.Waiting : LockAuthState.Inactive
    property int fingerprintPhase: biometricsEnabled
        ? LockAuthState.Waiting : LockAuthState.Inactive
    property string passwordStatus: passwordEnabled
        ? "Password ready" : "Password inactive"
    property string faceStatus: biometricsEnabled ? (lifecycleManaged
        ? "Waiting for terminal activation" : "Waiting for secure start")
        : "Face inactive"
    property string fingerprintStatus: biometricsEnabled ? (lifecycleManaged
        ? "Waiting for terminal activation" : "Waiting for secure start")
        : "Fingerprint inactive"
    property string statusText: initialStatusText

    function setPasswordInfrastructureError(message) {
        const firstReport = result !== LockAuthState.InfrastructureError;
        clearPendingPassword();
        result = LockAuthState.InfrastructureError;
        passwordPhase = LockAuthState.Error;
        passwordStatus = message;
        if (firstReport)
            clearGeneration += 1;
    }

    function clearPendingPassword() {
        pendingSecret = "";
        passwordBusy = false;
        passwordResponseSent = false;
        awaitingResponse = false;
        responseSecret = true;
    }

    function invalidatePasswordAttempt() {
        passwordGeneration += 1;
        clearPendingPassword();
    }

    function isPasswordAttemptCurrent(attemptGeneration) {
        return attemptGeneration === passwordGeneration;
    }

    function invalidateBiometricAttempts() {
        biometricGeneration += 1;
        faceFailureReason = "";
        fingerprintFailureReason = "";
    }

    function isBiometricAttemptCurrent(attemptGeneration) {
        return attemptGeneration === biometricGeneration;
    }

    function resetBiometricFailureState() {
        faceFailures = 0;
        fingerprintFailures = 0;
        facePaused = false;
        fingerprintPaused = false;
        faceFailureReason = "";
        fingerprintFailureReason = "";
    }
}
