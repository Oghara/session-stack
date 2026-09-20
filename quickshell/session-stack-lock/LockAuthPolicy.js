.pragma library

function biometricWorkersShouldRun(state) {
    return state.biometricsEnabled
        && !state.accepted
        && !state.shuttingDown
        && state.surfaceActive
        && !state.systemSleepPending
        && state.lidStateKnown
        && !state.lidClosed
        && (state.requestedMode === "auth-check" || state.localAuthCheck
            || (state.realLock && state.sessionSecure));
}

function isKnownLidState(state) {
    return state === "open" || state === "closed";
}

var BiometricStart = {
    Skip: 0,
    Defer: 1,
    Start: 2
};

// Wait for an aborted PAM context to unwind before replacing it.
function biometricStartDecision(shouldRun, paused, workerActive) {
    if (!shouldRun || paused)
        return BiometricStart.Skip;

    return workerActive ? BiometricStart.Defer : BiometricStart.Start;
}
