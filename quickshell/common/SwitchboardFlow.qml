import QtQuick
import "SwitchboardModel.js" as Model

QtObject {
    id: flow
    property bool accepted: false
    property bool rejected: false
    property bool failed: false
    property bool busy: false
    property bool awaitingResponse: false
    property bool idleBlocked: false
    property int idleTimeout: 18000
    property bool preview: false
    property bool reducedMotion: false
    property bool sleepPending: false
    property real sceneTime: 0
    property real endpoint: 0
    property bool recovering: false
    property string outcome: 'failure'
    property int generation: 1
    property bool paused: false
    property bool handoffSent: false
    property bool demoAccepted: false
    property date localTime: new Date()
    property var hostLines: []
    property var runnerLines: []
    property int logSequence: 0
    property string lastLogPhase: ''
    readonly property var frame: Model.frame(sceneTime, outcome, recovering, generation)
    readonly property bool inputReady: sceneTime === 2.8 && !recovering && !accepted && !demoAccepted && !sleepPending
    readonly property string terminalPhase: sceneTime === 0 ? 'dormant' : sceneTime < 2.8 ? 'waking' : 'active'
    signal quarantineRequested()
    signal recovered()
    signal completed()
    signal enteredDormancy()

    function interact() {
        if (sceneTime === 0) wake();
        if (idleTimer.running) idleTimer.restart();
    }
    function updateFeeds() {
        const script = frame.console;
        if (lastLogPhase !== script.key) {
            lastLogPhase = script.key;
            hostLines = script.host.slice(-7);
            runnerLines = script.runner.slice(-7);
        } else {
            hostLines = hostLines.concat(script.host[logSequence % script.host.length]).slice(-7);
            runnerLines = runnerLines.concat(script.runner[logSequence % script.runner.length]).slice(-7);
        }
        logSequence += 1;
    }
    function sleep() {
        if (!inputReady || busy || idleBlocked || awaitingResponse || paused) return false;
        sceneTime = 0;
        endpoint = 0;
        enteredDormancy();
        return true;
    }
    function awaitResponse() {
        if (accepted || sleepPending) return;
        if (sceneTime > 2.8) generation += 1;
        endpoint = 2.8;
        sceneTime = 2.8;
        recovering = false;
        paused = false;
    }
    function wake() {
        if (sceneTime !== 0 || sleepPending) return;
        sceneTime = reducedMotion ? 2.8 : 0.001;
        endpoint = 2.8;
    }
    function beginAttempt() {
        if (!inputReady || sleepPending) return;
        endpoint = 4.9;
        paused = false;
    }
    function resolve(success) {
        // Only PAM acceptance or an explicitly non-authenticating preview can win.
        if (sleepPending || (success && !accepted && !preview)) return false;
        outcome = success ? 'success' : 'failure';
        demoAccepted = success && preview;
        recovering = false;
        paused = false;
        if (sceneTime < 2.8 || sceneTime > 8.8) sceneTime = 2.8;
        endpoint = 8.8;
        if (!success) quarantineRequested();
        if (reducedMotion) { sceneTime = 8.8; finish(); }
        return true;
    }
    function inject() {
        if (sleepPending || accepted || demoAccepted || recovering || sceneTime !== 8.8 || outcome !== 'failure') return false;
        recovering = true;
        endpoint = 13.2;
        paused = false;
        if (reducedMotion) { sceneTime = 13.2; finish(); }
        return true;
    }
    function advance(seconds) {
        if (paused || sleepPending || sceneTime >= endpoint) return;
        sceneTime = Math.min(endpoint, sceneTime + Math.max(0, seconds));
        if (sceneTime === endpoint) finish();
    }
    function finish() {
        if (recovering && sceneTime >= 13.2) {
            recovering = false;
            generation += 1;
            outcome = 'failure';
            sceneTime = 2.8;
            endpoint = 2.8;
            recovered();
        } else if (sceneTime >= 8.8 && outcome === 'success' && !handoffSent && (accepted || demoAccepted)) {
            handoffSent = true;
            completed();
        }
    }
    onReducedMotionChanged: {
        if (reducedMotion && sceneTime < endpoint) {
            sceneTime = endpoint;
            finish();
        }
    }
    onFrameChanged: { if (frame.console.key !== lastLogPhase) updateFeeds(); }
    onAwaitingResponseChanged: { if (awaitingResponse) awaitResponse(); }
    onBusyChanged: { if (busy) beginAttempt(); }
    onAcceptedChanged: { if (accepted) resolve(true); }
    onRejectedChanged: { if (rejected && !accepted) resolve(false); }
    onFailedChanged: { if (failed && !accepted) resolve(false); }
    onSleepPendingChanged: {
        if (!sleepPending || accepted) return;
        // Aborted attempts cannot resume with dead PIDs or an old credential.
        if (sceneTime > 2.8) generation += 1;
        recovering = false;
        outcome = 'failure';
        endpoint = sceneTime === 0 ? 0 : 2.8;
        sceneTime = endpoint;
    }
    property Timer idleTimer: Timer {
        interval: flow.idleTimeout
        running: flow.inputReady && !flow.busy && !flow.idleBlocked && !flow.awaitingResponse && !flow.paused
        onTriggered: flow.sleep()
    }
    property Timer feedTimer: Timer {
        interval: 800
        repeat: true
        running: flow.sceneTime > 0 && !flow.paused && !flow.sleepPending
        onTriggered: flow.updateFeeds()
    }
    property Timer clockTimer: Timer {
        // The display shows minutes. Align the next update to the minute boundary.
        interval: 60000 - flow.localTime.getTime() % 60000
        repeat: true
        triggeredOnStart: true
        running: flow.sceneTime > 0 && !flow.sleepPending
        onTriggered: flow.localTime = new Date()
    }
    property FrameAnimation animation: FrameAnimation {
        running: !flow.paused && !flow.sleepPending && !flow.reducedMotion && flow.sceneTime < flow.endpoint
        onTriggered: flow.advance(Math.min(frameTime, 0.1))
    }
}
