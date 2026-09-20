// Normalise a PAM conversation to the plain values used by the testable
// authentication controller.
import QtQuick
import Quickshell.Services.Pam

Item {
    id: channel

    required property string config
    required property string configDirectory

    readonly property bool active: pam.active

    signal prompt(string text, bool responseRequired, bool responseVisible)
    signal completed(bool success)
    signal failed(string reason)

    visible: false
    width: 0
    height: 0

    function start() {
        return pam.start();
    }

    function abort() {
        pam.abort();
    }

    function respond(secret) {
        pam.respond(secret);
    }

    PamContext {
        id: pam
        config: channel.config
        configDirectory: channel.configDirectory

        onPamMessage: channel.prompt(pam.message, pam.responseRequired, pam.responseVisible)
        onCompleted: result => channel.completed(result === PamResult.Success)
        onError: error => channel.failed(PamError.toString(error))
    }
}
