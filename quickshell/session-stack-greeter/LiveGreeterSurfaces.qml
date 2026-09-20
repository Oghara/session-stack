import QtQuick
import "common" as Common
import Quickshell
import Quickshell.Wayland

Item {
    id: liveSurfaces

    property Component greeterSurfaceComponent: null
    Common.DisplayState {
        id: displays
        screens: Quickshell.screens
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            readonly property string outputName:
                modelData && modelData.name ? String(modelData.name) : ""
            readonly property bool ownsKeyboard:
                outputName !== ""
                    && outputName === displays.keyboardScreen

            screen: modelData
            visible: true
            color: "#07090c"
            exclusiveZone: 0
            focusable: ownsKeyboard
            WlrLayershell.namespace: "session-stack-greeter"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: ownsKeyboard
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            onOwnsKeyboardChanged: {
                if (ownsKeyboard && surfaceLoader.item) {
                    Qt.callLater(function() {
                        surfaceLoader.item.forceActiveFocus(
                            Qt.ActiveWindowFocusReason);
                    });
                }
            }

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            Loader {
                id: surfaceLoader
                anchors.fill: parent
                sourceComponent: liveSurfaces.greeterSurfaceComponent
                onLoaded: item.ownsKeyboard = Qt.binding(function() {
                    return panelWindow.ownsKeyboard;
                })
            }

            Connections {
                target: surfaceLoader.item
                ignoreUnknownSignals: true

                function onFocusRequested() {
                    displays.request(panelWindow.outputName);
                }
            }
        }
    }
}
