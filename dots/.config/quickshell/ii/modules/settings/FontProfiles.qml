import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property var profiles: []
    property string message: "Reading installed font profiles…"
    property bool awaitingReload: false
    readonly property bool busy: apply.running || awaitingReload
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/fontctl"
    readonly property string selectedName: profiles[picker.currentIndex]?.id ?? ""
    readonly property string presetName: selectedName + (compact.checked ? "-10pt" : "")
    property bool previewReady: false
    onPresetNameChanged: previewReady = false
    Component.onDestruction: if (Config.writesPaused && root.awaitingReload) Config.writesPaused = false
    function cleaned(text) { return text.replace(/\x1b\[[0-9;]*m/g, "").trim(); }
    function args(preview) {
        let result = [helper, "preset", presetName, "--user-only"];
        if (grayscale.checked) result.push("--subpixel", "none");
        if (preview) result.push("--preview");
        return result;
    }
    Process {
        command: [root.helper, "preset", "catalog"]
        running: true
        stdout: StdioCollector { id: catalogOutput }
        stderr: StdioCollector { id: catalogError }
        onExited: code => {
            if (code !== 0) { root.message = "fontctl is unavailable. Install the fork's current fontctl helper."; return; }
            try { root.profiles = JSON.parse(catalogOutput.text); root.message = "Choose a profile, preview the font matches, then apply."; }
            catch (error) { root.message = "Could not read the font catalog. Update fontctl and reopen Settings."; }
        }
    }
    Process {
        id: preview
        stdout: StdioCollector { id: previewOutput }
        stderr: StdioCollector { id: previewError }
        onExited: code => {
            root.message = root.cleaned(previewOutput.text + "\n" + previewError.text);
            root.previewReady = code === 0;
        }
    }
    Process {
        id: apply
        stdout: StdioCollector { id: applyOutput }
        stderr: StdioCollector { id: applyError }
        onExited: code => {
            root.message = code === 0 ? "Applied " + root.presetName + ". Running applications may need reopening." : "Font apply failed: " + root.cleaned(applyError.text + "\n" + applyOutput.text);
            root.awaitingReload = true;
            Config.reloadFromDisk();
            releaseTimer.restart();
        }
    }
    Connections {
        target: Config
        function onReloaded() {
            if (root.awaitingReload) { root.awaitingReload = false; Config.writesPaused = false; releaseTimer.stop(); }
        }
    }
    Timer {
        id: releaseTimer
        interval: 3000
        onTriggered: {
            root.awaitingReload = false; Config.writesPaused = false;
            root.message += " Check the shell font values below after the file reload.";
        }
    }
    StyledText { text: "Desktop font profiles"; font.pixelSize: 22; font.weight: Font.Medium }
    StyledText {
        Layout.fillWidth: true
        text: "Preview checks installed fonts without changing anything. Apply updates your user Fontconfig, GTK, Qt, Kitty and shell settings, and restarts the running shell. System-wide font files are left to fontctl in a terminal."
        wrapMode: Text.WordWrap
        color: Appearance.m3colors.m3onSurfaceVariant
        font.pixelSize: 13
    }
    SettingsComboBox {
        id: picker
        objectName: "fontProfilePicker"
        Layout.fillWidth: true
        model: root.profiles.map(p => ({label:p.id + " — " + p.description, value:p.id}))
        textRole: "label"
        enabled: !root.busy && !preview.running
        Accessible.name: "Font profile"
    }
    RowLayout {
        CheckBox { id: compact; text: "Uniform 10 pt"; enabled: !root.busy && !preview.running }
        CheckBox { id: grayscale; text: "Grayscale rendering"; enabled: !root.busy && !preview.running; onToggled: root.previewReady = false }
    }
    RowLayout {
        SettingsButton {
            objectName: "fontPreview"
            text: preview.running ? "Checking fonts…" : "Preview profile"
            enabled: root.selectedName.length > 0 && !root.busy && !preview.running
            onClicked: { root.previewReady = false; preview.command = root.args(true); preview.running = true; }
        }
        SettingsButton {
            objectName: "fontApply"
            text: root.busy ? "Applying…" : "Apply to desktop"
            enabled: root.previewReady && !root.busy && !preview.running
            onClicked: {
                Config.flushPendingWrites();
                if (Config.writeError) { root.message = Config.writeError; return; }
                Config.writesPaused = true;
                apply.command = root.args(false); apply.running = true;
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: root.message
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.pixelSize: 12
        color: Appearance.m3colors.m3onSurfaceVariant
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.m3colors.m3outlineVariant }
}
