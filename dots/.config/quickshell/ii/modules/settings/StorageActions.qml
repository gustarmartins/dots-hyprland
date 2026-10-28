import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    objectName: "storageActions"
    spacing: 10
    property var state: ({enabled:false, config:{}, disks:[]})
    property string error: ""
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/disk-reclaim"
    function refresh() { if (!read.running && !operation.running) read.running = true; }
    function run(args) { if (!operation.running) { operation.command = [helper].concat(args); operation.running = true; } }
    Component.onCompleted: refresh()
    Timer { interval: 30000; repeat: true; running: root.visible && root.state.enabled; onTriggered: root.refresh() }
    Process {
        id: read
        command: [root.helper, "status", "--json"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            try { if (code !== 0) throw new Error(); root.state = JSON.parse(result.text); }
            catch (_) { root.error = "Disk cleanup helper is unavailable."; }
        }
    }
    Process {
        id: operation
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error = code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
    StyledText { text: "Disk space & cleanup"; font.pixelSize: 22; font.weight: Font.Medium }
    SettingsButton {
        objectName: "storageMaster"
        text: root.state.enabled ? "Disk space alerts: On — turn off" : "Disk space alerts: Off — turn on"
        enabled: !operation.running
        onClicked: root.run([root.state.enabled ? "disable" : "enable"])
    }
    ColumnLayout {
        objectName: "storageFeatures"
        visible: root.state.enabled
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: !root.state.timer_active ? "Space checks are stopped. Turn alerts off and on to resume."
                : !root.state.last_check ? "Waiting for the first space check."
                : Date.now() / 1000 - root.state.last_check > 120 ? "A space check has not completed recently. Turn alerts off and on to retry."
                : "Checking available space every 30 seconds."
        }
        Repeater {
            model: root.state.disks || []
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: modelData.name.toUpperCase() + (modelData.mounted ? ": " + (modelData.free / 1073741824).toFixed(1) + " GiB available · " + modelData.level : ": not mounted")
                }
                SettingsButton {
                    text: modelData.name.toUpperCase() + " alerts: " + (root.state.config[modelData.name] ? "On" : "Off")
                    enabled: !operation.running
                    onClicked: root.run(["set", modelData.name, root.state.config[modelData.name] ? "off" : "on"])
                }
            }
        }
        SettingsButton {
            text: "Desktop notifications: " + (root.state.config.desktop ? "On" : "Off")
            enabled: !operation.running
            onClicked: root.run(["set", "desktop", root.state.config.desktop ? "off" : "on"])
        }
        SettingsButton {
            text: "Warn about rapid space consumption: " + (root.state.config.forecast ? "On" : "Off")
            enabled: !operation.running
            onClicked: root.run(["set", "forecast", root.state.config.forecast ? "off" : "on"])
        }
        RowLayout {
            SettingsButton { text: "Preview build caches"; enabled: !operation.running; onClicked: root.run(["open", "preview"]) }
            SettingsButton { text: "Review caches & trash"; enabled: !operation.running; onClicked: root.run(["open", "clean"]) }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Cleanup opens a preview and asks before removing files. Busy builds, source, final releases and browser data stay protected. Turning alerts off stops these checks; manual cleanup remains available in a terminal."
            color: Appearance.m3colors.m3onSurfaceVariant
            font.pixelSize: 12
        }
    }
    StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; visible: text.length > 0; text: root.error; color: Appearance.m3colors.m3error }
}
