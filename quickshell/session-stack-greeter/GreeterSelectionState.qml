import QtQuick

QtObject {
    id: state

    property var users: generatedData.users
    property var systems: generatedData.systems

    property int selectedUserIndex: users.length > 0 ? 0 : -1
    property int selectedSystemIndex: systems.length > 0 ? 0 : -1
    property string manualUsername: ""
    property int selectionGeneration: 0
    property bool selectionEnabled: true

    readonly property var selectedUser: selectedUserIndex >= 0
        && selectedUserIndex < users.length ? users[selectedUserIndex] : null
    readonly property var selectedSystem: selectedSystemIndex >= 0
        && selectedSystemIndex < systems.length ? systems[selectedSystemIndex] : null
    readonly property string selectedUsername: selectedUser
        ? selectedUser.username : manualUsername.trim()
    readonly property string selectedUserLabel: selectedUser
        ? (selectedUser.label || selectedUser.username) : selectedUsername === "" ? "OTHER USER"
        : selectedUsername.toUpperCase()
    readonly property bool ready: selectedUsername !== "" && selectedSystem !== null

    readonly property var authenticationUser: users.find(user =>
        user.username === selectedUsername) || null
    readonly property bool passwordAuthenticationEnabled:
        generatedData.passwordAuthenticationEnabled
    readonly property bool faceAuthenticationEnabled: authenticationUser !== null
        && authenticationUser.faceAuthenticationEnabled === true
    readonly property bool fingerprintAuthenticationEnabled: authenticationUser !== null
        && authenticationUser.fingerprintAuthenticationEnabled === true

    property GeneratedSystemData generatedData: GeneratedSystemData {}

    function selectUser(index) {
        if (!selectionEnabled || index < 0 || index >= users.length)
            return false;
        if (selectedUserIndex === index && manualUsername === "")
            return true;
        selectedUserIndex = index;
        manualUsername = "";
        selectionGeneration += 1;
        return true;
    }

    function selectManualUser(username) {
        if (!selectionEnabled)
            return false;
        const normalized = String(username || "").trim();
        if (selectedUserIndex < 0 && manualUsername === normalized)
            return true;
        selectedUserIndex = -1;
        manualUsername = normalized;
        selectionGeneration += 1;
        return true;
    }

    function selectSystem(index) {
        if (!selectionEnabled || index < 0 || index >= systems.length)
            return false;
        if (selectedSystemIndex === index)
            return true;
        selectedSystemIndex = index;
        selectionGeneration += 1;
        return true;
    }
}
