import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 10
    property var state: ({enabled:false, active:false, kernel:true, oomd:true, recent:[]})
    property string error: ""
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/oom-notify"
    function refresh() { if (!read.running && !action.running) read.running=true; }
    function run(args) { if (action.running) return; action.command=[helper].concat(args); action.running=true; }
    Component.onCompleted: refresh()
    Timer { interval: 10000; repeat: true; running: root.visible; onTriggered: root.refresh() }
    Process {
        id: read
        command: [root.helper,"status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => { try { if (code !== 0) throw new Error(); root.state=JSON.parse(result.text); } catch (e) { root.error="Install oom-notify from Linux Memory Toolkit."; } }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error=code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
    StyledText { text: "OOM notifications"; font.pixelSize: 22; font.weight: Font.Medium }
    SettingsButton {
        text: root.state.enabled ? "Memory kill notifications: On — disable" : "Memory kill notifications: Off — enable"
        enabled: !action.running
        onClicked: root.run([root.state.enabled ? "off" : "on"])
    }
    ColumnLayout {
        visible: root.state.enabled
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.state.active ? "Watching for memory kills. Bursts are combined; command lines stay out of popups." : "Monitor is stopped. Check oom-notify status." }
        SettingsButton { text: "Kernel OOM kills: " + (root.state.kernel ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","kernel",root.state.kernel ? "off" : "on"]) }
        SettingsButton { text: "systemd-oomd kills: " + (root.state.oomd ? "On" : "Off"); enabled: !action.running; onClicked: root.run(["set","oomd",root.state.oomd ? "off" : "on"]) }
        SettingsButton { text: "Send a labelled test notification"; enabled: !action.running; onClicked: root.run(["test"]) }
        SettingsButton { text: "Open recent memory kills"; onClicked: Quickshell.execDetached(["kitty","--hold",root.helper,"history"]) }
    }
    StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; visible: text.length>0; text: root.error; color: Appearance.m3colors.m3error }
}
