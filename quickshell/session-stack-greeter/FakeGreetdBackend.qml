import QtQuick

QtObject {
    id: backend

    readonly property bool available: true
    property string user: ""
    property var launchCommand: []
    property int cancelCount: 0

    signal authMessage(string message, bool error, bool responseRequired,
        bool echoResponse)
    signal authFailure(string message)
    signal readyToLaunch()
    signal launched()
    signal error(string message)

    function createSession(username) {
        user = username;
        Qt.callLater(function() {
            backend.authMessage("Password:", false, true, false);
        });
    }

    function cancelSession() {
        cancelCount += 1;
    }

    function respond(response) {
        Qt.callLater(function() {
            if (response === "demo")
                backend.readyToLaunch();
            else
                backend.authFailure("AUTHENTICATION REJECTED // USE DEMO");
        });
    }

    function launch(command) {
        launchCommand = Array.from(command);
        Qt.callLater(function() { backend.launched(); });
    }
}
