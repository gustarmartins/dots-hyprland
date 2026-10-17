import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    objectName: "companyPasswordAlerts"
    spacing: 10
    property var state: ({enabled:false, desktop:true, resets:true, recovery:true})
    property string error: ""
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/imak-password-audit"
    function refresh() { if (!read.running && !action.running) read.running=true; }
    function run(args) { if (!action.running) { action.command=[helper].concat(args); action.running=true; } }
    Component.onCompleted: refresh()
    Timer { interval: 15000; repeat: true; running: root.visible; onTriggered: root.refresh() }
    Process {
        id: read
        command: [root.helper,"status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            try { if (code !== 0) throw new Error(); root.state=JSON.parse(result.text); root.error=""; }
            catch (_) { root.error="Install the company password audit helper and connect Microsoft 365."; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error=code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
    StyledText { text: "Company password alerts"; font.pixelSize: 22; font.weight: Font.Medium }
    SettingsButton {
        objectName: "companyAlertsMaster"
        text: root.state.enabled ? "Password audit: On — disable" : "Password audit: Off — enable"
        enabled: !action.running
        onClicked: root.run([root.state.enabled ? "off" : "on"])
    }
    ColumnLayout {
        objectName: "companyAlertsFeatures"
        visible: root.state.enabled
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Last checked: " + (root.state.lastSuccess ? new Date(root.state.lastSuccess).toLocaleString() : "Awaiting first check") + ". Archived events: " + (root.state.archivedEvents || 0) + "."
        }
        SettingsButton { objectName: "companyAlertsDesktop"; text: "Desktop notifications: " + (root.state.desktop ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","desktop",root.state.desktop ? "off" : "on"]) }
        SettingsButton { objectName: "companyAlertsResets"; text: "Password changes, resets and blocks: " + (root.state.resets ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","resets",root.state.resets ? "off" : "on"]) }
        SettingsButton { objectName: "companyAlertsRecovery"; text: "Recovery method registration and changes: " + (root.state.recovery ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","recovery",root.state.recovery ? "off" : "on"]) }
        SettingsButton { text: "Send a labelled test notification"; enabled: !action.running; onClicked: root.run(["test"]) }
        SettingsButton { text: "Open password audit history"; onClicked: Quickshell.execDetached(["kitty","--hold",root.helper,"show"]) }
        SettingsButton { text: "Open Microsoft Entra admin center"; onClicked: Qt.openUrlExternally("https://entra.microsoft.com/") }
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Checks every 15 minutes while this PC is online. Microsoft may publish audit events later. Account sign-in belongs in Microsoft 365 CLI. Turning this feature off stops collection and notifications; saved history remains private." }
    }
    StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; visible: text.length>0; text: root.error; color: Appearance.m3colors.m3error }
}
