pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var monitors: []
    property int globalPolicy: 2
    property bool ready: false
    property bool busy: false
    property string error: ""
    property string actionError: ""
    property int watchers: 0
    readonly property var modes: [
        {value: 0, label: "0 · Off"},
        {value: 1, label: "1 · Always"},
        {value: 2, label: "2 · Fullscreen only"},
        {value: 3, label: "3 · Fullscreen games & video"}
    ]
    function refresh() {
        if (!read.running && !root.busy) read.running = true;
    }
    function accept(text, action) {
        try {
            const value = JSON.parse(text);
            if (value.monitors) {
                root.monitors = value.monitors;
                root.globalPolicy = value.globalPolicy;
                root.ready = true;
            }
            if (action) root.actionError = value.error ?? "";
            root.error = value.error ?? root.actionError;
        } catch (e) { root.error = "Could not read VRR state"; }
    }
    function setPolicy(output, policy) {
        if (root.busy) return;
        root.busy = true;
        root.error = "";
        root.actionError = "";
        write.command = [Quickshell.env("HOME") + "/.local/bin/vrrctl", "set", output, String(policy)];
        write.running = true;
    }
    Process {
        id: read
        command: [Quickshell.env("HOME") + "/.local/bin/vrrctl", "status"]
        stdout: StdioCollector { onStreamFinished: root.accept(text, false) }
    }
    Process {
        id: write
        stdout: StdioCollector { onStreamFinished: root.accept(text, true) }
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }
    Timer { interval: 2000; repeat: true; running: root.watchers > 0; onTriggered: root.refresh() }
    onWatchersChanged: if (watchers > 0) refresh()
}
