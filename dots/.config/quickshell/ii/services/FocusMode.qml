pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var state: ({})
    property bool hardwareEnabled: false
    property string error: ""
    property string request: ""
    property string executable: Quickshell.env("HOME") + "/.local/bin/focus-mode.sh"
    property string runtimePath: "/run/cryod"
    property double now: Date.now()
    property double timestamp: 0
    readonly property bool fresh: now >= timestamp && now - timestamp < 15000
    readonly property bool enabled: state.enabled === true
    readonly property bool active: fresh && state.active === true
    readonly property bool available: fresh && state.available === true
    readonly property bool busy: control.running
    readonly property string statusText: !enabled ? "Off" : !fresh ? "Waiting for CryoD"
        : active ? "Focused" : state.reason === "external-setting-preserved" ? "Custom CPU settings"
        : state.reason === "no-isolated-focused-workload" ? "Waiting for an app"
        : state.reason === "native-policy-paused" ? "CryoD effects paused" : "Waiting for focus"

    function setEnabled(value) { submit(value ? "on" : "off"); }
    function setHardwareEnabled(value) { submit(value ? "hardware-on" : "hardware-off"); }
    function submit(value) {
        if (busy) return;
        error = "";
        request = value;
        control.running = true;
    }
    Process {
        id: control
        command: [root.executable, root.request]
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
        onExited: (code, status) => {
            if (code !== 0 && !root.error) root.error = "Focus Mode could not apply the change.";
            stateFile.reload(); hardwareFile.reload();
        }
    }
    FileView {
        id: stateFile
        path: root.runtimePath + "/status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const value = JSON.parse(text());
                root.state = value.native?.focus_performance ?? {};
                root.timestamp = (value.timestamp ?? 0) * 1000;
                root.now = Date.now();
            } catch (_) { root.state = {}; }
        }
        onLoadFailed: root.state = ({})
    }
    FileView {
        id: hardwareFile
        path: "/run/focus-mode/hardware-" + (root.state.uid ?? "") + ".json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.hardwareEnabled = JSON.parse(text()).schema === 1; }
            catch (_) { root.hardwareEnabled = false; }
        }
        onLoadFailed: root.hardwareEnabled = false
    }
    Timer { interval: 2000; running: root.enabled; repeat: true; onTriggered: root.now = Date.now() }
}
