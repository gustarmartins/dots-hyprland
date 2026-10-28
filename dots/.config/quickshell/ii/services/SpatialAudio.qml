pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/mpv-spatial"
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/mpv/spatial.json"
    property bool enabled: false
    property bool automatic: true
    property bool running: false
    property string message: "Checking spatial audio…"
    property string error: ""
    readonly property bool busy: action.running
    function refresh() { if (!read.running && !action.running) read.running = true; }
    function run(args) { if (busy) return; error = ""; action.command = [helper].concat(args); action.running = true; }
    function setEnabled(value) { run([value ? "enable" : "disable"]); }
    function setAutomatic(value) { run(["automatic", value ? "true" : "false"]); }
    FileView { path: root.configPath; watchChanges: true; onFileChanged: root.refresh() }
    Process {
        id: read
        running: true
        command: [root.helper, "status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            if (code !== 0) { root.error = "Could not read spatial audio status"; return; }
            try {
                const s = JSON.parse(result.text);
                root.enabled = s.enabled; root.automatic = s.automatic;
                root.running = s.running; root.message = s.message;
            } catch (e) { root.error = "Invalid spatial audio status"; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error = code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
}
