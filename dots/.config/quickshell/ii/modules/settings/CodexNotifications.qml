import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 8
    property var configuration: ({enabled:false,focus:true,reopen:true})
    property string error: ""
    function run(args) {
        if (control.running) return;
        control.command = [Quickshell.env("HOME") + "/.local/bin/codex-notify"].concat(args);
        control.running = true;
    }
    Component.onCompleted: run(["status"])
    Process {
        id: control
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            try {
                const value = JSON.parse(output.text);
                if (code !== 0) root.error = value.error || "Could not update notifications.";
                else { root.configuration = value; root.error = ""; }
            } catch (_) { root.error = "Install codex-notify to use session notifications."; }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "Codex session notifications"; font.weight: Font.Medium }
        SettingsSwitch { objectName:"codexNotifyMaster"; checked:root.configuration.enabled; enabled:!control.running; onToggled:root.run([checked ? "on" : "off"]) }
    }
    ColumnLayout {
        visible: root.configuration.enabled
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth:true
            StyledText { Layout.fillWidth:true; text:"Focus the existing terminal" }
            SettingsSwitch { objectName:"codexNotifyFocus"; checked:root.configuration.focus; enabled:!control.running; onToggled:root.run(["set","focus",checked ? "on" : "off"]) }
        }
        RowLayout {
            Layout.fillWidth:true
            StyledText { Layout.fillWidth:true; text:"Open a window for detached or stopped sessions"; wrapMode:Text.WordWrap }
            SettingsSwitch { objectName:"codexNotifyReopen"; checked:root.configuration.reopen; enabled:!control.running; onToggled:root.run(["set","reopen",checked ? "on" : "off"]) }
        }
        StyledText { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:"New Codex clients send the full response. Click an alert to open its session; use ••• to read it here."; color:Appearance.m3colors.m3onSurfaceVariant }
    }
    StyledText { Layout.fillWidth:true; wrapMode:Text.WordWrap; visible:!!root.error; text:root.error; color:Appearance.m3colors.m3error }
}
