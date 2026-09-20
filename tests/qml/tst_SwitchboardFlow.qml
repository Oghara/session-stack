import QtQuick
import QtTest
import "../../quickshell/common" as Lock
import "../../quickshell/common/SwitchboardModel.js" as Model

TestCase {
    name: 'SwitchboardFlow'
    Component { id: factory; Lock.SwitchboardFlow {} }
    SignalSpy { id: completion; signalName: 'completed' }
    SignalSpy { id: recovery; signalName: 'recovered' }
    property var flow
    function init() {
        flow = createTemporaryObject(factory, this);
        completion.target = flow;
        recovery.target = flow;
        completion.clear(); recovery.clear();
    }
    function test_onlyAuthenticationCompletes() {
        flow.wake(); flow.advance(3);
        verify(flow.inputReady);
        verify(!flow.resolve(true));
        flow.outcome = 'success'; flow.sceneTime = 8.8; flow.finish();
        compare(completion.count, 0);
        flow.sceneTime = 2.8; flow.busy = true; flow.advance(30);
        compare(flow.sceneTime, 4.9);
        compare(completion.count, 0);
        flow.accepted = true; flow.advance(30);
        compare(completion.count, 1);
        flow.finish(); compare(completion.count, 1);
        verify(!flow.inputReady);
    }
    function test_recoveryKeepsFreshProcessesAndStaysLocked() {
        flow.wake(); flow.advance(3);
        flow.rejected = true; flow.advance(30);
        const dead = Model.frame(flow.sceneTime, flow.outcome, false, flow.generation);
        verify(dead.workers.every(w => w.dead));
        verify(flow.inject());
        flow.advance(4.39);
        const replacement = Model.frame(flow.sceneTime, flow.outcome, true, flow.generation);
        verify(replacement.workers.every((w,i) => w.replacement && w.pid !== dead.workers[i].pid));
        flow.advance(1);
        compare(flow.generation, 2);
        compare(recovery.count, 1);
        compare(completion.count, 0);
        verify(flow.inputReady);
        const ready = Model.frame(flow.sceneTime, flow.outcome, false, flow.generation);
        verify(ready.workers.every((w,i) => w.pid === replacement.workers[i].pid));
        verify(!ready.portOpen);
    }
    function test_sleepAbortsTheAttemptWithoutUnlocking() {
        flow.wake(); flow.advance(3);
        flow.busy = true; flow.advance(3);
        flow.sleepPending = true;
        verify(!flow.inputReady);
        compare(flow.sceneTime, 2.8);
        verify(!flow.resolve(true));
        flow.advance(30); compare(completion.count, 0);
        flow.busy = false; flow.sleepPending = false;
        verify(flow.inputReady);
        compare(flow.generation, 2);
    }
    function test_reducedMotionStillRequiresAuthentication() {
        flow.reducedMotion = true;
        flow.wake(); compare(flow.sceneTime, 2.8);
        flow.rejected = true; compare(flow.sceneTime, 8.8);
        verify(flow.inject());
        compare(flow.sceneTime, 2.8);
        compare(recovery.count, 1); compare(completion.count, 0);
        flow.accepted = true; compare(completion.count, 1);
    }
    function test_crtShutdownOrder() {
        const line = Model.breakerDeparture({t: 12.96, recovering: true});
        const pinch = Model.breakerDeparture({t: 13.05, recovering: true});
        const dot = Model.breakerDeparture({t: 13.15, recovering: true});
        compare(line.collapse, 1); compare(line.erase, 0);
        verify(pinch.erase > 0 && pinch.erase < 1);
        compare(dot.erase, 1); verify(dot.afterglow > 0 && dot.afterglow < 1);
    }
}
