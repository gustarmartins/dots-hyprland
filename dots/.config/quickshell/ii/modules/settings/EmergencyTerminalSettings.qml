import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property bool writable
    property bool shortcutEnabled: true
    property bool ready: false
    property string errorMessage: ""
    FileView {
        id: preference
        path: FileUtils.trimFileProtocol(Directories.config) + "/hypr/emergency-terminal.state"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.shortcutEnabled = text().trim() !== "off";
            root.ready = true;
        }
        onLoadFailed: error => {
            root.ready = error === FileViewError.FileNotFound;
            if (root.ready) root.shortcutEnabled = true;
            else root.errorMessage = "Could not read the emergency shortcut preference.";
        }
        onSaved: { root.ready = true; root.errorMessage = ""; }
        onSaveFailed: {
            root.errorMessage = "Could not save the emergency shortcut preference.";
            reload();
        }
    }
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "Emergency terminal · Super+Ctrl+Enter"; wrapMode: Text.WordWrap }
        SettingsSwitch {
            objectName: "emergencyTerminalShortcut"
            Accessible.name: "Emergency terminal shortcut"
            checked: root.shortcutEnabled
            enabled: root.ready && root.writable
            onToggled: {
                root.ready = false;
                root.shortcutEnabled = checked;
                preference.setText(checked ? "on\n" : "off\n");
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: root.errorMessage || "Open foot with a clean Bash prompt, even when Quickshell or Kitty is busy."
        wrapMode: Text.WordWrap
    }
}
