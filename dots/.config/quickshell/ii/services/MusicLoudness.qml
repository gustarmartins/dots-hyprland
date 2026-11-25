pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/music-loudness"
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/music-loudness/config.json"
    property bool enabled: false
    property var apps: []
    property string selectedApp: ""
    property bool matchReady: false
    property string matchMessage: ""
    property bool ready: false
    property bool active: false
    property bool measuring: false
    property bool followPresets: true
    property bool edenDefault: false
    property bool autoMatch: false
    property real autoInterval: 30
    property string autoMessage: ""
    property real db: 0
    property real stepDb: 1
    property real targetLufs: -16
    property string title: "Music loudness"
    property string preset: ""
    property string message: "Checking music…"
    property string error: ""
    readonly property bool busy: action.running || cancelAction.running
    function refresh() { if (!read.running) read.running = true; }
    function run(args) {
        if (busy) return;
        error = "";
        action.command = [helper].concat(args);
        action.running = true;
    }
    function adjust(direction) { run(["adjust", String(direction * stepDb)]); }
    function selectApp(value) { run(["select-app", value]); }
    function match() { run(["match"]); }
    function cancel(args) {
        if (cancelAction.running) return;
        error = "";
        cancelAction.command = [helper].concat(args);
        cancelAction.running = true;
    }
    function reset() { cancel(["reset"]); }
    function setEnabled(value) { if (value) run(["enable"]); else cancel(["disable"]); }
    function setTarget(value) { run(["target", String(value)]); }
    function setFollowPresets(value) { run(["follow-presets", String(value)]); }
    function setStep(value) { run(["step", String(value)]); }
    function setEdenDefault(value) { run(["eden-default", String(value)]); }
    function setAutoMatch(value) { if (value) run(["auto-match", "true"]); else cancel(["auto-match", "false"]); }
    function setAutoInterval(value) { run(["auto-interval", String(value)]); }
    FileView { path: root.configPath; watchChanges: true; onFileChanged: root.refresh() }
    Process {
        id: read
        running: true
        command: [root.helper, "status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            if (code !== 0) { root.ready = false; root.message = "Loudness status is unavailable"; return; }
            try {
                const s = JSON.parse(result.text);
                root.apps = s.apps || []; root.selectedApp = s.selected_app || "";
                root.matchReady = s.match_ready === true; root.matchMessage = s.match_message || "";
                root.enabled = s.enabled; root.ready = s.ready; root.active = s.active;
                root.measuring = s.measuring; root.db = s.db; root.title = s.title;
                root.preset = s.preset; root.message = s.message; root.stepDb = s.step_db;
                root.targetLufs = s.target_lufs; root.followPresets = s.follow_presets;
                root.edenDefault = s.eden_default === true;
                root.autoMatch = s.auto_match === true; root.autoInterval = s.auto_interval || 30;
                root.autoMessage = s.auto_message || "";
            } catch (e) { root.ready = false; root.message = "Could not read loudness status"; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => {
            const detail = errors.text.trim().replace(/^music-loudness: /, "");
            root.error = code === 0 || detail.toLowerCase().includes("cancelled") ? "" : detail;
            root.refresh();
        }
    }
    Process {
        id: cancelAction
        stderr: StdioCollector { id: cancelErrors }
        onExited: (code, status) => {
            root.error = code === 0 ? "" : cancelErrors.text.trim().replace(/^music-loudness: /, "");
            root.refresh();
        }
    }
    Connections { target: GlobalStates; function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.refresh(); } }
    Timer {
        interval: root.busy || root.measuring ? 500 : root.autoMatch ? 5000 : 2000
        repeat: true
        running: root.enabled && (root.active || root.measuring || root.busy || GlobalStates.sidebarRightOpen)
        onTriggered: root.refresh()
    }
}
