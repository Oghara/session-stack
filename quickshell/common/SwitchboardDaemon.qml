import QtQuick

Item {
    id: terminal
    required property var worker
    x: worker.x
    y: worker.y
    width: worker.w
    height: 94
    opacity: worker.opacity * (worker.dead ? 0.55 : 1)
    clip: true
    transform: Scale { origin.y: 47; yScale: terminal.worker.reveal }
    SwitchboardPath {
        path: 'M0 7L9 0H' + terminal.width + 'V85L' + (terminal.width-11) + ' 94H0Z'
        fill: '#111019'
        stroke: '#b39bc8'
    }
    SwitchboardText {
        x: 10; y: 9
        font.pixelSize: 10; font.bold: true
        color: terminal.worker.dead ? '#978193' : '#e1dfa3'
        text: terminal.worker.id.toUpperCase() + ' / PID ' + terminal.worker.pid + (terminal.worker.replacement ? ' :: NEW IMAGE' : '')
    }
    Rectangle { x: 9; y: 25; width: parent.width-18; height: 1; color: '#51434e' }
    Column {
        x: 10; y: 33; spacing: 4
        Repeater {
            model: [terminal.worker.line1, terminal.worker.line2, terminal.worker.line3]
            SwitchboardText {
                required property string modelData
                font.pixelSize: 9
                color: '#c5b1d6'
                text: modelData
            }
        }
    }
    Rectangle { x: 10; y: 80; width: parent.width-20; height: 4; color: '#302936' }
    Rectangle { x: 10; y: 80; width: (parent.width-20)*terminal.worker.progress; height: 4; color: '#cddd99' }
    Item {
        anchors.fill: parent
        visible: terminal.worker.dead
        SwitchboardPath { path: 'M5 3L'+(terminal.width-5)+' 91M'+(terminal.width-5)+' 3L5 91'; stroke: '#a75d78' }
        Rectangle {
            x: 37; y: 32; width: parent.width-74; height: 28
            color: '#21101a'; border.color: '#da819b'
            SwitchboardText { anchors.centerIn: parent; text: 'PROCESS DESTROYED'; font.pixelSize: 9; color: '#f394aa' }
        }
    }
}
