import QtQuick
import QtQuick.Effects
import "SwitchboardModel.js" as Model

FocusScope {
    id: surface
    required property bool previewMode
    required property string displayName
    required property string passwordStatus
    required property string faceStatus
    required property string fingerprintStatus
    required property var availableMethods
    required property bool busy
    required property CredentialState credentials
    property bool awaitingResponse: false
    property bool responseSecret: true
    property bool queued: false
    property bool faceWorking: false
    property bool fingerprintWorking: false
    property bool ownsKeyboard: true
    property bool reducedMotion: false
    property string userLabel: "OPERATOR"
    property Component footerContent: null
    property bool menuOpen: false
    signal closeMenuRequested()
    signal focusRequested()
    signal interacted()
    property bool authenticationMode: false
    property bool demoUnlock: false
    property bool demoDanger: false

    signal submitted(string secret)
    signal biometricRetryRequested()
    signal faceAuthenticationRequested()

    required property SwitchboardFlow flow
    readonly property bool portrait: width < height
    readonly property real designWidth: portrait ? 1000 : 1600
    readonly property real designHeight: portrait ? 1460 : 1000
    property real ambientTime: 0
    readonly property real sceneTime: flow.sceneTime
    readonly property bool recovering: flow.recovering
    readonly property string terminalPhase: flow.terminalPhase
    readonly property bool animate: !reducedMotion && ownsKeyboard
    readonly property bool inputReady: flow.inputReady
    readonly property var frame: flow.frame
    readonly property color accent: frame.accepted && frame.t >= 6.55 ? '#73b7c2' : '#ef4650'

    function interact() {
        focusRequested();
        flow.interact();
        interacted();
    }
    function wake() { interact(); access.focusPassword(); }
    function focusInput() {
        if (sceneTime === 2.8 && ownsKeyboard && !menuOpen) access.focusPassword();
    }
    function submitPassword(secret) {
        if (!inputReady || busy || queued || !secret.length) return;
        if (flow.preview) flow.resolve(secret === 'demo');
        else submitted(secret);
        access.clear();
    }
    function inject() { flow.inject(); }
    onSceneTimeChanged: {
        if (sceneTime === 2.8) focusInput();
    }
    // Popup restores its old focus on close; restore credential focus afterward.
    onMenuOpenChanged: { if (!menuOpen) Qt.callLater(focusInput); }
    Connections {
        target: surface.flow
        function onRecovered() { access.clear(); surface.focusInput(); }
        function onEnteredDormancy() { access.clear(); }
        function onSleepPendingChanged() { if (surface.flow.sleepPending) access.clear(); }
    }
    Component.onCompleted: {
        forceActiveFocus();
        if (demoUnlock || demoDanger) wake();
    }
    TapHandler { onPressedChanged: { if (pressed) surface.interact(); } }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            credentials.clear();
            closeMenuRequested();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_F5 && flow.preview) {
            flow.resolve(true); event.accepted = true; return;
        }
        if (event.key === Qt.Key_F6 && flow.preview) {
            flow.resolve(false); event.accepted = true; return;
        }
        if (sceneTime === 8.8 && flow.outcome === 'failure'
                && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) {
            inject(); event.accepted = true; return;
        }
        if (sceneTime < 2.8) {
            interact();
            if (availableMethods.includes(0)) {
                credentials.method = 0;
                if (event.key === Qt.Key_Backspace)
                    credentials.text = credentials.text.slice(0, -1);
                else if (event.text && !/[\u0000-\u001f\u007f]/.test(event.text)
                        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
                    credentials.text = (credentials.text + event.text).slice(0, 512);
            }
            event.accepted = true;
            return;
        }
        interact();
    }
    FrameAnimation {
        running: surface.visible && surface.sceneTime > 0 && surface.animate && !surface.flow.paused && !surface.flow.sleepPending
        onTriggered: surface.ambientTime += Math.min(frameTime, 0.1)
    }

    Timer {
        interval: 3300; running: surface.previewMode && !surface.authenticationMode && (surface.demoUnlock || surface.demoDanger)
        onTriggered: surface.flow.resolve(surface.demoUnlock)
    }
    Rectangle { anchors.fill: parent; color: '#090c10' }
    Item {
        id: stage
        width: surface.designWidth; height: surface.designHeight
        scale: Math.min(surface.width/width, surface.height/height)
        anchors.centerIn: parent
        SwitchboardPath {
            path: 'M63 21H'+(stage.width-202)+'L'+(stage.width-187)+' 30H'+(stage.width-101)+'L'+(stage.width-33)+' 69V'+(stage.height-59)+'L'+(stage.width-82)+' '+(stage.height-21)+'H210L181 '+(stage.height-12)+'H61L32 '+(stage.height-53)+'V61Z'
            stroke: '#57414a'; thickness: 3; fill: '#160f18'
        }
        Item {
            id: artwork
            anchors.fill: parent
            opacity: Model.span(surface.sceneTime,0.22,0.8)
            SwitchboardText { x: 110; y: 50; text: '/// MILITECH'; color: surface.accent; font.pixelSize: surface.portrait ? 27 : 37; font.bold: true; font.family: 'sans-serif' }
            SwitchboardText { x: 110; y: 101; text: surface.portrait ? 'AUTHORITY REQUIRED' : 'INTERNAL SYSTEMS / AUTHORITY REQUIRED'; font.pixelSize: 12; font.letterSpacing: 3 }
            Rectangle {
                x: stage.width/2-111; y: 52; width: 225; height: 59; color: 'transparent'; border.color: '#843943'
                SwitchboardText { anchors.horizontalCenter: parent.horizontalCenter; y: 12; text: 'LOCAL ACCESS TERMINAL'; font.pixelSize: 11 }
                SwitchboardText { anchors.horizontalCenter: parent.horizontalCenter; y: 33; text: 'RESTRICTED / CLASS 04'; font.pixelSize: 13; color: surface.accent; font.bold: true }
            }
            SwitchboardText { x: stage.width-200; y: 53; text: Qt.formatTime(surface.flow.localTime, 'HH:mm'); font.pixelSize: 30 }
            SwitchboardText { x: stage.width-223; y: 94; text: Qt.formatDate(surface.flow.localTime,'dd MMM yyyy').toUpperCase()+' / LOCAL'; color: '#a69d94'; font.pixelSize: 10 }
            Rectangle {
                x: 85; y: 130; width: stage.width-170; height: 31; color: surface.accent
                SwitchboardText { x: 15; y: 9; visible: !surface.portrait; text: 'SESSION CONTROL / AUTHORIZATION GATE'; color: '#180c12'; font.pixelSize: 10; font.letterSpacing: 1 }
                SwitchboardText { anchors.centerIn: parent; text: surface.frame.battle; color: '#180c12'; font.pixelSize: 10; font.letterSpacing: 1 }
                Row { visible: !surface.portrait; x: 1235; y: 5; spacing: 5
                    Repeater { model: [14,3,7,2,2,12,4,8,3,17,2,6,3,9,4]
                        Rectangle { required property int modelData; width: modelData; height: modelData%3 === 0 ? 16 : 11; color: '#180c12' }
                    }
                }
            }
            Rectangle {
                id: boardFrame
                x: 85; y: 190; width: stage.width-170; height: 375
                color: '#0c1016'; border.color: surface.accent
                SwitchboardText { x: 16; y: 9; text: 'LOCAL SWITCHBOARD / TRUST DESCENT'; color: surface.accent; font.pixelSize: 10; font.letterSpacing: 2 }
                SwitchboardText { anchors.right: parent.right; anchors.rightMargin: 20; y: 9; text: 'HOST / CONTESTED / RESIDENT'; color: '#d7b8a1'; font.pixelSize: 8; font.letterSpacing: 2 }
                Item {
                    id: boardViewport
                    x: 1; y: 30; width: parent.width-2; height: parent.height-31; clip: true
                    SwitchboardBoard {
                        id: board
                        anchors.centerIn: parent
                        scale: Math.min(boardViewport.width/1200,boardViewport.height/380)
                        frame: surface.frame; clock: surface.ambientTime
                        onInjected: surface.inject()
                    }
                }
            }
            Grid {
                x: surface.portrait ? 85 : 104
                y: surface.portrait ? 790 : 780
                columns: surface.portrait ? 1 : 3
                spacing: 14
                SwitchboardMonitor { width: surface.portrait ? 830 : 482; height: 140; heading: surface.frame.console.title; status: surface.frame.fighting ? 'HOSTILE' : 'LOCAL'; lines: surface.flow.hostLines; prompt: 'node03:~$ '+surface.frame.console.prompt; ink: '#c57999' }
                SwitchboardMonitor { width: surface.portrait ? 830 : 452; height: 140; heading: 'NETRUNNER / DECK FEED'; status: surface.recovering ? 'REBUILD' : 'LOW PROFILE'; lines: surface.flow.runnerLines; prompt: 'runner@deck:~$ hold --mask' }
                Rectangle {
                    width: surface.portrait ? 830 : 430; height: 140; color: '#110f18'; border.color: '#99526b'
                    SwitchboardText { x: 10; y: 9; text: 'NETRUNNER / DEFENSIVE PROGRAMS'; color: '#d98fa8'; font.pixelSize: 9; font.bold: true }
                    Grid {
                        x: 12; y: 34; columns: 3; rowSpacing: 5; columnSpacing: 4
                        Repeater {
                            model: 5
                            Item {
                                required property int index
                                readonly property var program: surface.frame.overview.programs[index]
                                width: 133; height: 29
                                SwitchboardText { text: parent.program.name; font.pixelSize: 9 }
                                SwitchboardText { y: 16; text: parent.program.status; font.pixelSize: 7; color: '#c4cf9a' }
                            }
                        }
                    }
                    SwitchboardText { x: 12; y: 106; text: surface.frame.overview.action; font.pixelSize: 8; color: '#bfb0bc' }
                    SwitchboardText { x: 12; y: 122; text: surface.frame.overview.detail; font.pixelSize: 7; color: '#a88e9c' }
                }
            }
        }
        // Distortion copies the board, never the credential input.
        ShaderEffectSource { id: boardTexture; sourceItem: boardFrame; hideSource: false; live: surface.animate; visible: false }
        MultiEffect {
            x: boardFrame.x+3; y: boardFrame.y; width: boardFrame.width; height: boardFrame.height; source: boardTexture
            colorization: 1; colorizationColor: '#00c9ef'; opacity: surface.frame.fighting ? 0.07 : 0.025
            visible: surface.animate && surface.sceneTime > 0
        }
        Repeater {
            model: 3
            ShaderEffectSource {
                required property int index
                readonly property real pulse: Math.sin(surface.ambientTime*(13+index*3))
                x: 85 + (pulse > 0.96 ? (index-1)*12 : 0)
                y: 250 + index*95
                width: boardFrame.width; height: 7+index*2
                sourceItem: boardFrame
                sourceRect: Qt.rect(0,60+index*95,width,height)
                live: visible; hideSource: false
                visible: surface.animate && surface.sceneTime > 0 && pulse > (surface.frame.fighting ? 0.93 : 0.996)
            }
        }
        SwitchboardAccess {
            id: access
            x: (stage.width-width)/2; y: 584
            frame: surface.frame; accent: surface.accent
            credentials: surface.credentials
            awaitingResponse: surface.awaitingResponse
            responseSecret: surface.responseSecret
            queued: surface.queued
            faceWorking: surface.faceWorking
            fingerprintWorking: surface.fingerprintWorking
            onInteracted: surface.interact()
            inputReady: surface.inputReady; busy: surface.busy
            methods: surface.availableMethods
            passwordStatus: surface.passwordStatus
            faceStatus: surface.faceStatus
            fingerprintStatus: surface.fingerprintStatus
            opacity: surface.sceneTime >= 0.18 ? 1 : 0
            onSubmitted: secret => surface.submitPassword(secret)
            onFaceRequested: surface.faceAuthenticationRequested()
            onFingerprintRequested: surface.biometricRetryRequested()
        }
        Rectangle {
            id: footer
            x: 85; y: stage.height-72; width: stage.width-170; height: 30; color: surface.accent
            visible: surface.sceneTime > 0
            z: 5
            Loader { anchors.fill: parent; sourceComponent: surface.footerContent }
            SwitchboardText { visible: !surface.footerContent; x: surface.portrait ? 18 : 490; y: 9; text: 'SYSTEM / '+surface.displayName.toUpperCase(); color: '#180c12'; font.pixelSize: 10 }
            SwitchboardText { visible: !surface.footerContent; x: surface.portrait ? 470 : 900; y: 9; text: 'USER / '+surface.userLabel.toUpperCase(); color: '#180c12'; font.pixelSize: 10 }
            SwitchboardText { visible: !surface.footerContent && !surface.portrait; anchors.right: parent.right; anchors.rightMargin: 20; y: 9; text: 'LOCAL ACCESS / NODE 03'; color: '#180c12'; font.pixelSize: 10 }
        }
        Rectangle {
            anchors.fill: parent; color: '#090c10'; visible: surface.sceneTime === 0
            SwitchboardText { anchors.centerIn: parent; text: 'MILITECH / LOCAL ACCESS\n\nTERMINAL DORMANT\n\n[ PRESS A KEY TO JACK IN ]'; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 22; color: '#d85b69' }
            MouseArea { anchors.fill: parent; onClicked: surface.wake() }
        }
    }
}
