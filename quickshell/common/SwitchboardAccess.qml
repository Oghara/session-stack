import QtQuick
import "SwitchboardModel.js" as Model

Rectangle {
    id: access
    required property var frame
    required property bool inputReady
    required property bool busy
    required property var methods
    required property string passwordStatus
    required property string faceStatus
    required property string fingerprintStatus
    required property color accent
    required property CredentialState credentials
    property bool responseSecret: true
    property bool awaitingResponse: false
    property bool queued: false
    property bool faceWorking: false
    property bool fingerprintWorking: false
    readonly property int method: credentials.method
    readonly property bool canSubmit: inputReady && !busy && !queued
        && method === 0 && methods.includes(0)
    readonly property string placeholder: {
        if (queued) return 'WAITING FOR AUTHENTICATION';
        if (awaitingResponse) return passwordStatus;
        if (method === 0) return 'ENTER CREDENTIAL';
        return method === 1 ? 'FACE VECTOR / READY' : 'PRINT VECTOR / READY';
    }
    signal interacted()
    onMethodsChanged: {
        if (methods.length && !methods.includes(credentials.method))
            credentials.method = methods[0];
    }
    readonly property var copy: Model.overlay(frame)
    readonly property bool takeover: frame.fighting && !frame.restored
    signal submitted(string secret)
    signal faceRequested()
    signal fingerprintRequested()
    function focusPassword() {
        if (methods.includes(0)) credentials.method = 0;
        password.forceActiveFocus();
    }
    function clear() { credentials.clear(); }
    width: 832; height: 186
    color: '#101419'; border.color: '#62353a'
    Rectangle { width: 16; height: parent.height; color: access.accent }
    Rectangle { width: parent.width; height: 2; color: access.accent }
    SwitchboardText {
        x: 36; y: 12; width: parent.width-64
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 17; font.bold: true; font.letterSpacing: 1.4
        text: access.copy.title; color: '#e5b2c1'
        fontSizeMode: Text.Fit; minimumPixelSize: 11
    }
    Rectangle {
        x: 42; y: 44; width: parent.width-84; height: 60
        visible: access.frame.t >= 2.8 && !access.takeover
        color: '#090c10'; border.color: access.accent
        TextInput {
            id: password
            anchors.left: parent.left; anchors.right: submitButton.left
            anchors.leftMargin: 15; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: '#ddd8c4'; font.family: 'DejaVu Sans Mono'; font.pixelSize: 19
            echoMode: access.responseSecret ? TextInput.Password : TextInput.Normal
            passwordCharacter: '●'
            selectByMouse: false
            maximumLength: 512
            readOnly: !access.canSubmit
            inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            text: access.credentials.text
            onTextEdited: {
                access.credentials.text = text;
                access.interacted();
            }
            onAccepted: { if (!readOnly) access.submitted(text); }
            SwitchboardText {
                anchors.verticalCenter: parent.verticalCenter
                text: access.placeholder
                font.pixelSize: 15; color: '#958790'
                visible: password.text.length === 0
            }
        }
        Rectangle {
            id: submitButton
            width: 60; height: parent.height
            anchors.right: parent.right
            color: '#20131c'; border.color: access.accent
            SwitchboardText { anchors.centerIn: parent; text: '→'; font.pixelSize: 25; color: access.accent }
            MouseArea { anchors.fill: parent; enabled: access.canSubmit; onClicked: access.submitted(password.text) }
        }
    }
    SwitchboardText {
        x: 35; y: 112; width: parent.width-60
        horizontalAlignment: Text.AlignHCenter; font.pixelSize: 9; color: '#b6a99e'
        elide: Text.ElideRight
        text: access.method === 0 ? access.passwordStatus : access.method === 1 ? access.faceStatus : access.fingerprintStatus
        visible: !access.takeover && access.frame.t >= 2.8
    }
    Rectangle {
        x: 42; y: 44; width: parent.width-84; height: 86
        visible: access.takeover || access.frame.t < 2.8
        color: '#110b14'; border.color: access.frame.recovering ? '#a78a62' : '#572635'
        SwitchboardText { x: 5; y: 13; width: parent.width-10; horizontalAlignment: Text.AlignHCenter; text: access.copy.vector; font.pixelSize: 10; font.bold: true; color: '#f1c591' }
        SwitchboardText { x: 5; y: 34; width: parent.width-10; horizontalAlignment: Text.AlignHCenter; text: access.copy.command; font.pixelSize: 12; color: '#dfbbc6' }
        Rectangle { x: parent.width*0.14; y: 55; width: parent.width*0.72; height: 3; color: '#30222c'
            Rectangle { width: parent.width*access.copy.progress; height: 3; color: '#f1c591' }
        }
        SwitchboardText { x: 5; y: 66; width: parent.width-10; horizontalAlignment: Text.AlignHCenter; text: access.copy.note; font.pixelSize: 8; color: '#bba194' }
    }
    Row {
        x: 24; y: 138; width: parent.width-48; height: 48
        Repeater {
            model: access.methods
            Rectangle {
                id: methodButton
                required property int modelData
                width: (access.width-48)/access.methods.length; height: 48
                enabled: access.inputReady && !access.busy
                activeFocusOnTab: enabled
                function activate() {
                    access.credentials.method = modelData;
                    access.interacted();
                    if (modelData === 0) access.focusPassword();
                    else if (modelData === 1) access.faceRequested();
                    else access.fingerprintRequested();
                }
                Keys.onReturnPressed: activate()
                Keys.onSpacePressed: activate()
                color: '#11151a'; border.color: activeFocus ? access.accent : '#352b30'
                SwitchboardText { anchors.horizontalCenter: parent.horizontalCenter; y: 9; text: ['01  PASSWORD','02  FACE','03  FINGERPRINT'][methodButton.modelData]; font.pixelSize: 12 }
                SwitchboardText {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 30; font.pixelSize: 8; color: '#aaa095'
                    text: {
                        if (access.frame.recovering && !access.frame.restored) return 'RESTORING';
                        if (access.takeover) return 'SEALED';
                        if (access.busy || (modelData === 1 && access.faceWorking)
                                || (modelData === 2 && access.fingerprintWorking)) return 'CHECKING';
                        return 'READY';
                    }
                }
                Rectangle { x: 10; y: 46; width: parent.width-20; height: 2; color: access.accent; visible: access.method === methodButton.modelData }
                MouseArea {
                    anchors.fill: parent
                    enabled: access.inputReady && !access.busy
                    onClicked: methodButton.activate()
                }
            }
        }
    }
}
