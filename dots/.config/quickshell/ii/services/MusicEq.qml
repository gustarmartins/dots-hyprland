pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/music-eq"
    property bool enabled: false
    property bool active: false
    property var config: ({})
    property string message: ""
    property string error: ""
    readonly property bool busy: action.running
    function refresh() { if (!read.running && !action.running) read.running = true; }
    function run(args) { if (busy) return; error = ""; action.command = [helper].concat(args); action.running = true; }
    function setEnabled(value) { run([value ? "enable" : "disable"]); }
    function setFeature(key, value) { run(["set", key, value ? "true" : "false"]); }
    Process {
        id: read
        running: true
        command: [root.helper, "status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            if (code !== 0) { root.error = "Music EQ helper is unavailable"; return; }
            try {
                const s = JSON.parse(result.text);
                root.enabled = s.enabled; root.active = s.running; root.config = s.config;
                root.message = s.message || "Waiting for playback";
            } catch (e) { root.error = "Could not read Music EQ status"; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error = code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
}
