pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/eden-audio-boost"
    property bool enabled: false
    property bool active: false
    property int streams: 0
    property real db: 12
    property string targetKey: ""
    property string targetName: ""
    property string targetReason: ""
    property string activeApp: ""
    property string activeKey: ""
    property string message: ""
    property string error: ""
    readonly property bool busy: action.running
    function refresh() { if (!read.running && !action.running) read.running = true; }
    function run(args) { if (busy) return; root.error = ""; action.command = [helper].concat(args); action.running = true; }
    function boost(explicitTargetKey) {
        const key = explicitTargetKey !== undefined ? explicitTargetKey : root.targetKey;
        if (key && key.length > 0) run(["boost", "--confirmed", "--target", key]);
        else run(["boost", "--confirmed"]);
    }
    function reset() { run(["reset"]); }
    function setEnabled(value) { run([value ? "enable" : "disable"]); }
    Process {
        id: read
        running: true
        command: [root.helper, "status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            if (code !== 0) { root.enabled = false; return; }
            try {
                const s = JSON.parse(result.text);
                root.enabled = !!s.enabled;
                root.active = !!s.active;
                root.streams = s.streams || 0;
                root.db = s.db !== undefined ? s.db : 12;
                root.targetKey = s.target_key || "";
                root.targetName = s.target_name || "";
                root.targetReason = s.target_reason || "";
                root.activeApp = s.active_app || "";
                root.activeKey = s.active_key || "";
                root.message = s.message || "";
            }
            catch (error) { root.error = "Could not read app boost status"; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error = code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
    Connections { target: GlobalStates; function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.refresh(); } }
    Timer { interval: 1800; repeat: true; running: root.enabled && (root.active || GlobalStates.sidebarRightOpen); onTriggered: root.refresh() }
}
