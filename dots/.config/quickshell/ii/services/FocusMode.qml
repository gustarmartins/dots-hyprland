pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var state: ({})
    property var profile: ({})
    property bool hardwareLeased: false
    readonly property bool hardwareEnabled: typeof profile.hardware === "boolean" ? profile.hardware : hardwareLeased
    property string error: ""
    property string request: ""
    property string executable: Quickshell.env("HOME") + "/.local/bin/focus-mode.sh"
    property string runtimePath: "/run/cryod"
    property string performancePath: "/run/focus-mode"
    property string preferencesPath: "/var/lib/cryod-desktop"
    property double now: Date.now()
    property double timestamp: 0
    readonly property bool fresh: now >= timestamp && now - timestamp < 15000
    readonly property bool enabled: state.enabled === true
    readonly property bool active: fresh && state.active === true
    readonly property bool available: fresh && state.available === true
    readonly property bool busy: control.running
    readonly property string statusText: busy ? "Applying…" : !fresh ? "Waiting for CryoD"
        : !enabled ? (hardwareLeased ? "Restore pending" : "Off")
        : active ? "CPU priority active" : state.reason === "external-setting-preserved" ? "Custom CPU settings"
        : state.reason === "no-isolated-focused-workload" ? "On · app not eligible"
        : state.reason === "native-policy-paused" ? "On · effects paused"
        : state.reason === "restore-pending" ? "Restore pending" : "On · waiting for focus"

    function setEnabled(value) { submit(value ? "on" : "off"); }
    function setHardwareEnabled(value) { submit(value ? "hardware-on" : "hardware-off"); }
    function submit(value) {
        if (busy) return;
        error = "";
        request = value;
        control.running = true;
    }
    IpcHandler {
        target: "cryodPerformance"
        function status(): string {
            return JSON.stringify({schema: 1, enabled: root.enabled, cpuActive: root.active,
                fresh: root.fresh, status: root.statusText, hardwareRequested: root.hardwareEnabled,
                hardwareLeased: root.hardwareLeased, busy: root.busy, error: root.error});
        }
    }
    Process {
        id: control
        command: [root.executable, root.request]
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
        onExited: (code, status) => {
            if (code !== 0 && !root.error) root.error = "Performance could not apply the change.";
            stateFile.reload(); hardwareFile.reload(); profileFile.reload();
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
        path: root.state.uid == null ? "" : root.performancePath + "/hardware-" + root.state.uid + ".json"
        // This opt-in marker normally does not exist while hardware tuning is off.
        printErrors: false
        watchChanges: true
        onPathChanged: root.hardwareLeased = false
        onFileChanged: reload()
        onLoaded: {
            try { root.hardwareLeased = JSON.parse(text()).schema === 1; }
            catch (_) { root.hardwareLeased = false; }
        }
        onLoadFailed: error => {
            root.hardwareLeased = false;
            if (error !== FileViewError.FileNotFound)
                console.warn("Performance hardware state:", FileViewError.toString(error));
        }
    }
    FileView {
        id: profileFile
        path: root.state.uid == null ? "" : root.preferencesPath + "/performance-" + root.state.uid + ".json"
        printErrors: false
        watchChanges: true
        onPathChanged: root.profile = ({})
        onFileChanged: reload()
        onLoaded: {
            try {
                const value = JSON.parse(text());
                root.profile = value.schema === 1 && value.uid === root.state.uid ? value : {};
            } catch (_) { root.profile = ({}); }
        }
        onLoadFailed: root.profile = ({})
    }
    Timer { interval: 2000; running: root.enabled; repeat: true; onTriggered: root.now = Date.now() }
}
