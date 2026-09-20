import QtQml

QtObject {
    id: state
    required property var screens
    property string requestedScreen: ""
    readonly property string preferredScreen: {
        const outputs = screens || [];
        for (const output of outputs) {
            if (output.name && !/^(eDP|LVDS|DSI)(-|$)/i.test(output.name))
                return output.name;
        }
        return outputs.length ? outputs[0].name : "";
    }
    readonly property string keyboardScreen: available(requestedScreen)
        ? requestedScreen : preferredScreen

    function available(name) {
        return name !== "" && (screens || []).some(output => output.name === name);
    }
    function request(name) {
        if (available(name)) requestedScreen = name;
    }
}
