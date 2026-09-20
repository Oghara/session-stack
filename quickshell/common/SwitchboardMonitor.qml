import QtQuick

Rectangle {
    id: monitor
    required property string heading
    required property string status
    required property var lines
    required property string prompt
    property color ink: '#b3a1c9'
    color: '#110f18'; border.color: ink
    Rectangle { x: 1; y: 1; width: parent.width-2; height: 26; color: '#302034' }
    SwitchboardText { x: 10; y: 8; text: monitor.heading; color: monitor.ink; font.pixelSize: 9; font.bold: true }
    SwitchboardText { anchors.right: parent.right; anchors.rightMargin: 9; y: 9; text: monitor.status; color: monitor.ink; font.pixelSize: 8 }
    Column {
        x: 10; y: 35; spacing: 1
        Repeater {
            model: 7
            SwitchboardText {
                required property int index
                text: monitor.lines[index] || ''
                font.pixelSize: 9; color: monitor.ink
                opacity: 0.4 + index/10
            }
        }
    }
    Rectangle { x: 1; y: parent.height-22; width: parent.width-2; height: 21; color: '#211a25' }
    SwitchboardText { x: 10; y: parent.height-16; text: monitor.prompt; color: monitor.ink; font.pixelSize: 8 }
}
