import QtQuick
import QtQuick.Controls
import "common" as Common

Item {
    id: menus
    required property var selection
    required property string openMenu
    signal menuRequested(string name)
    signal interacted()
    function closeMenu() { menuRequested(""); }
    onOpenMenuChanged: {
        if (openMenu !== "") {
            chooser.open();
        } else chooser.close();
    }
    Connections {
        target: selection
        function onSelectionEnabledChanged() {
            if (!menus.selection.selectionEnabled) menus.closeMenu();
        }
    }
    Row {
        anchors.centerIn: parent
        height: parent.height
        spacing: 16
        Repeater {
            model: ["system", "user"]
            Button {
                required property string modelData
                width: (menus.width-40)/2
                height: menus.height
                enabled: menus.selection.selectionEnabled
                text: modelData === "system"
                    ? "SYSTEM / " + (menus.selection.selectedSystem ? menus.selection.selectedSystem.label : "SELECT")
                    : "USER / " + menus.selection.selectedUserLabel
                font.family: "DejaVu Sans Mono"; font.pixelSize: 12
                onClicked: {
                    menus.interacted();
                    menus.menuRequested(menus.openMenu === modelData ? "" : modelData);
                }
                contentItem: Text {
                    text: parent.text; font: parent.font; color: "#180c12"
                    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle { color: parent.activeFocus || parent.hovered ? "#efabb0" : "transparent" }
            }
        }
    }
    Popup {
        id: chooser
        x: (menus.width-width)/2; y: -height-10
        width: Math.min(600, menus.width)
        height: Math.min(430, 100 + options.count*48)
        focus: true
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: { if (menus.openMenu !== "") menus.closeMenu(); }
        TapHandler {
            parent: chooser.contentItem
            onPressedChanged: { if (pressed) menus.interacted(); }
        }
        background: Rectangle { color: "#11131b"; border.color: "#ef4650" }
        Common.SwitchboardText {
            text: menus.openMenu === "user" ? "SELECT ACCOUNT" : "SELECT DESKTOP SESSION"
            color: "#ef8d9b"; font.pixelSize: 16
        }
        ListView {
            id: options
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: manualUser.top; topMargin: 32; bottomMargin: 8 }
            clip: true
            model: menus.openMenu === "user" ? menus.selection.users : menus.selection.systems
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                required property int index
                required property var modelData
                width: options.width; height: 44
                text: modelData.label
                font.family: "DejaVu Sans Mono"; font.pixelSize: 14
                contentItem: Text { text: parent.text; font: parent.font; color: "#e0c7ce"; elide: Text.ElideRight }
                background: Rectangle { color: parent.hovered || parent.activeFocus ? "#422431" : "#19151c" }
                onClicked: {
                    if (menus.openMenu === "user") menus.selection.selectUser(index);
                    else menus.selection.selectSystem(index);
                    menus.closeMenu();
                }
            }
        }
        TextField {
            id: manualUser
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: visible ? 42 : 0
            visible: menus.openMenu === "user"
            placeholderText: "OTHER USER / ENTER USERNAME"
            text: menus.selection.manualUsername
            maximumLength: 256
            onAccepted: {
                if (text.trim() && menus.selection.selectManualUser(text)) menus.closeMenu();
            }
        }
    }
}
