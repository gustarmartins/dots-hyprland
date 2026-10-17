import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    objectName: "pcReconnectWatch"
    spacing: 10
    property var state: ({enabled:false, desktop:true, repeat:false, wakeCodex:false})
    property string error: ""
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/pc-reconnect-watch"
    function refresh() { if (!read.running && !action.running) read.running=true; }
    function run(args) { if (!action.running) { action.command=[helper].concat(args); action.running=true; } }
    Component.onCompleted: refresh()
    Timer { interval: 15000; repeat: true; running: root.visible; onTriggered: root.refresh() }
    Process {
        id: read
        command: [root.helper,"status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            try { if (code !== 0) throw new Error(); root.state=JSON.parse(result.text); }
            catch (_) { root.error="Install pc-reconnect-watch and configure a pinned SSH alias."; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error=code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
    StyledText { text: "PC reconnection alerts"; font.pixelSize: 22; font.weight: Font.Medium }
    SettingsButton {
        objectName: "pcReconnectMaster"
        text: root.state.enabled ? "Reconnection alert: Armed — stop" : "Reconnection alert: Off — arm"
        enabled: !action.running
        onClicked: root.run([root.state.enabled ? "off" : "on"])
    }
    ColumnLayout {
        objectName: "pcReconnectFeatures"
        visible: root.state.enabled
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: (root.state.displayName || "Remote PC") + ": " + (root.state.reason || "Waiting for first check") + ". Last checked: " + (root.state.lastCheck ? new Date(root.state.lastCheck).toLocaleString() : "Not yet")
        }
        SettingsButton { objectName: "pcReconnectDesktop"; text: "Desktop notification: " + (root.state.desktop ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","desktop",root.state.desktop ? "off" : "on"]) }
        SettingsButton { objectName: "pcReconnectRepeat"; text: "Keep watching future reconnects: " + (root.state.repeat ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","repeat",root.state.repeat ? "off" : "on"]) }
        SettingsButton { objectName: "pcReconnectWake"; text: "Resume the linked Codex task: " + (root.state.wakeCodex ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","wakeCodex",root.state.wakeCodex ? "off" : "on"]) }
        SettingsButton { text: "Send a labelled test notification"; enabled: !action.running; onClicked: root.run(["test"]) }
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Checks pinned SSH access once a minute, without opening a remote desktop. By default, polling stops after the alert and any configured Codex wake are accepted. No watcher process runs between checks. Account and task settings stay in the private helper configuration." }
    }
    StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; visible: text.length>0; text: root.error; color: Appearance.m3colors.m3error }
}
