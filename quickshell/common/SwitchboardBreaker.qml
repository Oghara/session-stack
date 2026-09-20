import QtQuick
import "SwitchboardModel.js" as Model

Item {
    id: breaker
    required property var frame
    required property real clock
    signal injected()
    readonly property bool injectionReady: visible && frame.t === 8.8 && !frame.recovering
    activeFocusOnTab: injectionReady
    Keys.onReturnPressed: { if (injectionReady) injected(); }
    Keys.onSpacePressed: { if (injectionReady) injected(); }
    readonly property var departure: frame.departure
    readonly property real load: Model.span(frame.t, 7.3, 8.8)
    readonly property real unfold: Model.span(frame.t, 7.3, 7.55) * (1-Model.span(frame.t, 8.4, 8.8))
    x: 944; y: 255 - unfold*36; width: 244; height: 115 + unfold*36
    visible: !frame.accepted && frame.t >= 7.3 && !frame.restored
    Item {
        id: panel
        anchors.fill: parent
        opacity: 1-Model.span(breaker.departure.collapse, 0.85, 1)
        transform: Scale { origin.x: 122; origin.y: 57.5; yScale: Math.pow(1-breaker.departure.collapse, 2) }
        Rectangle { anchors.fill: parent; color: '#11111b'; border.color: breaker.activeFocus ? '#fff3c9' : '#b7aecf' }
        SwitchboardPath { path: 'M0 '+(breaker.height-50)+'H7V32H23'; stroke: '#8ac7d5'; thickness: 2 }
        SwitchboardText { x: 4; y: 5; text: 'SYS-LINK'; font.pixelSize: 4; color: '#83b8c7' }
        Item {
            x: 21; y: 8; width: 57; height: 61
            scale: 0.86
            rotation: Math.sin(breaker.clock*3.6)*1.8
            SwitchboardPath { path: 'M21 10L25 2M29 9L34 1M38 10L44 3'; stroke: '#c1a5d2'; thickness: 2 }
            SwitchboardPath { path: 'M14 17L25 10H40L51 19L54 34L46 45L42 50H23L15 42L10 29Z M14 19L19 24L16 36L23 42M47 20L43 24L47 37L41 43'; stroke: '#c1a5d2'; thickness: 2; fill: '#252136' }
            SwitchboardPath { path: 'M11 26H5V38H12M53 24H59V38H52M7 40V46H17M51 44H59V50M22 14H39'; stroke: '#d6c79b'; thickness: 2 }
            SwitchboardPath { path: 'M42 14L36 22L41 28L35 36'; stroke: '#e591b5' }
            SwitchboardPath { path: breaker.departure.active ? 'M17 30L28 31L27 32L18 31Z' : 'M17 26L29 28L26 35L19 34Z'; stroke: '#e0cf93'; fill: '#e0cf93' }
            SwitchboardPath { path: 'M37 27L48 24L46 34L38 35Z'; stroke: '#91dbe8'; fill: '#91dbe8' }
            SwitchboardPath { path: 'M32 33L28 41L33 39L36 42'; stroke: '#c1a5d2' }
            Item {
                y: (1+Math.sin(breaker.clock*6))*1.8
                SwitchboardPath { path: 'M20 44L27 46H38L46 41L44 55L38 61H27L21 56Z'; stroke: '#c1a5d2'; fill: '#252136' }
                SwitchboardPath { path: 'M22 49L29 51H38L44 47M24 46V53M29 47V56M34 47V56M39 46V54M43 44V51'; stroke: '#d6c79b' }
            }
        }
        SwitchboardText { x: 81; y: 17; text: 'ICEBREAKER'; color: '#e6cf83'; font.pixelSize: 14; font.bold: true }
        SwitchboardText {
            x: 81; y: 38; font.pixelSize: 8; color: '#bda2c9'
            text: breaker.departure.active ? 'STAY GHOST.' : breaker.frame.recovering ? 'FRESH IMAGES / EXEC' : breaker.load < 1 ? 'UNSIGNED / LOADING' : 'VEC 7A / ARMED'
        }
        SwitchboardText {
            x: 13; y: breaker.height-49; font.pixelSize: 9; color: '#dfbc92'
            text: breaker.departure.active ? '> patch.detach() => CLEAN' : breaker.frame.recovering ? '> backdoor.exec(leech)' : '> target: EJECTION BUS'
        }
        Rectangle { x: 13; y: parent.height-25; width: 218; height: 3; color: '#302c38' }
        Rectangle { x: 13; y: parent.height-25; width: 218*(breaker.frame.recovering ? Model.span(breaker.frame.t,8.8,13.2) : breaker.load); height: 3; color: '#c9d7a0' }
        SwitchboardText {
            x: 13; y: breaker.height-16; font.pixelSize: 7; color: '#a6b4bb'
            text: breaker.departure.active ? 'RESIDENTS LIVE / AUTH LOCKED' : breaker.frame.recovering ? 'BACKDOOR → BROKER / NEW PID' : 'INJECT / CLICK OR TAB + ENTER'
        }
    }
    Rectangle {
        x: (parent.width-width)/2; y: 57; height: 2
        width: parent.width*(1-Math.pow(breaker.departure.erase,2))
        color: '#fff3c9'
        opacity: Model.span(breaker.departure.collapse,0.5,1)
        visible: breaker.departure.collapse > 0 && breaker.departure.erase < 1
        Rectangle { anchors.centerIn: parent; width: parent.width; height: 6; color: '#fff3c9'; opacity: 0.25 }
    }
    Rectangle {
        x: 120; y: 55; width: 5; height: 5; radius: 2.5
        color: '#fff3c9'; opacity: Math.pow(1-breaker.departure.afterglow,2)
        visible: breaker.departure.erase >= 1
    }
    MouseArea {
        anchors.fill: parent
        enabled: breaker.injectionReady
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: breaker.injected()
    }
}
