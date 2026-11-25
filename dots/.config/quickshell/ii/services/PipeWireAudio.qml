pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/pipewire-audio-status"
    readonly property bool enabled: Config.options.sidebar.audioStatus.enable
    readonly property bool expandedByDefault: Config.options.sidebar.audioStatus.expandedByDefault

    property int watchers: 0
    readonly property bool activePolling: enabled && watchers > 0

    property bool ready: false
    property bool available: false
    property bool busy: false
    property bool acting: false
    property string error: ""
    property var data: null

    function wrapCommand(args) {
        return [
            "/bin/sh",
            "-c",
            "if [ -x \"$1\" ]; then exec \"$@\"; elif command -v pipewire-audio-status >/dev/null 2>&1; then shift; exec pipewire-audio-status \"$@\"; fi",
            "sh",
            root.helper
        ].concat(args);
    }

    function refresh() {
        if (!root.enabled || read.running || action.running) return;
        root.busy = true;
        read.command = root.wrapCommand(["status"]);
        read.running = true;
    }

    function runAction(args) {
        if (action.running) return;
        root.acting = true;
        root.error = "";
        action.command = root.wrapCommand(args);
        action.running = true;
    }

    function setQuantum(q) {
        runAction(["set-quantum", String(q)]);
    }

    function setRate(r) {
        runAction(["set-rate", String(r)]);
    }

    function resetClock() {
        runAction(["reset"]);
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
            root.error = "Could not read PipeWire audio status";
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

    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: root.accept(text)
        }
        onExited: (code, status) => {
            root.acting = false;
            if (code !== 0 && !root.error) {
                root.error = "PipeWire clock update failed";
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
}
