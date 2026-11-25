pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/display-app-status"
    readonly property bool enabled: Config.options.sidebar.displayStatus.enable
    readonly property string preferredMonitor: Config.options.sidebar.displayStatus.monitor
    readonly property bool showProcessDetails: Config.options.sidebar.displayStatus.showProcessDetails
    readonly property bool expandedByDefault: Config.options.sidebar.displayStatus.expandedByDefault

    property int watchers: 0
    readonly property bool activePolling: enabled && watchers > 0

    property bool ready: false
    property bool available: false
    property bool busy: false
    property string error: ""
    property var data: null

    function buildCommand() {
        const cmd = [
            "/bin/sh",
            "-c",
            "if [ -x \"$1\" ]; then exec \"$@\"; elif command -v display-app-status >/dev/null 2>&1; then shift; exec display-app-status \"$@\"; fi",
            "sh",
            root.helper
        ];
        if (root.preferredMonitor && root.preferredMonitor.trim().length > 0) {
            cmd.push("--monitor", root.preferredMonitor.trim());
        }
        if (!root.showProcessDetails) {
            cmd.push("--no-proc");
        }
        return cmd;
    }

    function refresh() {
        if (!root.enabled || read.running) return;
        root.busy = true;
        read.command = root.buildCommand();
        read.running = true;
    }

    function accept(text) {
        const trimmed = (text || "").trim();
        if (!trimmed) {
            root.available = false;
            root.ready = true;
            return;
        }
        try {
            const parsed = JSON.parse(trimmed);
            root.available = !!parsed.available;
            root.error = parsed.error ?? "";
            if (parsed.available) {
                root.data = parsed;
            }
            root.ready = true;
        } catch (e) {
            root.available = false;
            root.error = "Could not read display status";
            root.ready = true;
        }
    }

    Process {
        id: read
        stdout: StdioCollector {
            onStreamFinished: root.accept(text)
        }
        onExited: (code, status) => {
            root.busy = false;
            if (code !== 0) {
                root.available = false;
                root.ready = true;
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 1500
        repeat: true
        running: root.activePolling
        onTriggered: root.refresh()
    }

    onActivePollingChanged: {
        if (activePolling) {
            refresh();
        } else if (read.running) {
            read.running = false;
            root.busy = false;
        }
    }
    onPreferredMonitorChanged: if (activePolling) refresh()
    onShowProcessDetailsChanged: if (activePolling) refresh()
}
