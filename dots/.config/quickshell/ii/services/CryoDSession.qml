pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

Singleton {
    id: root
    property bool owner: false
    property bool offAttempted: false
    property string lastPayload: ""
    property var receipt: ({})
    property string error: ""
    property string runtimePath: "/run/cryod"
    property string bridgeExecutable: "/usr/local/libexec/cryod-desktop/cryod-session-bridge"
    property string serviceExecutable: "/usr/bin/systemctl"
    property bool manageFallback: true
    property var fallbackApplied: null
    property bool fallbackRequested: false
    property string fallbackError: ""
    property double wallNow: Date.now()
    readonly property bool enabled: Config.ready && Config.options.cryod.enabled
    readonly property bool wanted: enabled && (Config.options.cryod.protectForeground || Config.options.cryod.protectVisible)
    readonly property bool fresh: receipt.enabled === true && receipt.fresh === true
        && wallNow >= (receipt.published_unix_ms ?? 0)
        && wallNow - (receipt.published_unix_ms ?? 0) < 15000

    function start() { owner = true; sync(); }
    function sync() {
        if (!owner || !Config.ready) return;
        if (manageFallback && fallbackApplied !== wanted) fallbackControlTimer.restart();
        if (wanted) {
            offAttempted = false;
            if (!bridge.running) bridge.running = true;
            else publish();
        } else if (bridge.running) {
            bridge.write(JSON.stringify({enabled:false}) + "\n");
            offTimeout.restart();
        } else if (!offAttempted) {
            // One bounded Off transaction reconciles an enabled lease retained
            // by the daemon from an earlier shell. No watcher remains while Off.
            offAttempted = true;
            bridge.running = true;
            offTimeout.restart();
        }
    }
    function snapshot() {
        const active = Hyprland.activeToplevel?.address ?? "";
        const normalize = address => address.startsWith("0x") ? address : "0x" + address;
        const windows = HyprlandData.windowList.map(win => {
            const monitor = HyprlandData.monitors.find(mon => mon.id === win.monitor);
            const workspace = win.workspace?.id ?? 0;
            return {pid: win.pid ?? 0, address: win.address, app_id: win.class ?? "",
                monitor: win.monitor, workspace: workspace,
                focused: active.length > 0 && normalize(active) === normalize(win.address),
                visible: win.mapped !== false && win.hidden !== true &&
                    (win.pinned === true || monitor?.activeWorkspace?.id === workspace || monitor?.specialWorkspace?.id === workspace),
                fullscreen: (win.fullscreen ?? 0) > 0 || (win.fullscreenClient ?? 0) > 0};
        });
        return {enabled:true, session:Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"),
            protect_foreground:Config.options.cryod.protectForeground,
            protect_visible:Config.options.cryod.protectVisible, windows:windows};
    }
    function publish(force = false) {
        if (!owner || !bridge.running) return;
        const frame = wanted ? snapshot() : {enabled:false};
        const encoded = JSON.stringify(frame);
        if (force || encoded !== lastPayload) {
            lastPayload = encoded;
            bridge.write(encoded + "\n");
        }
    }
    onWantedChanged: sync()
    Connections {
        target: Config
        function onReadyChanged() { root.sync(); }
        function onReloaded() { root.sync(); }
    }
    Connections {
        target: Config.options.cryod
        function onProtectForegroundChanged() { root.publish(true); }
        function onProtectVisibleChanged() { root.publish(true); }
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root.publish(); }
    }
    Connections {
        target: HyprlandData
        function onWindowListChanged() { root.publish(); }
        function onMonitorsChanged() { root.publish(); }
        function onWorkspacesChanged() { root.publish(); }
    }
    Process {
        id: fallbackControl
        command: [root.serviceExecutable, "--user", root.fallbackRequested ? "start" : "stop", "cryod-session-fallback.service"]
        onExited: (code, status) => {
            root.fallbackError = code === 0 ? "" : "Standalone fallback is unavailable.";
            if (code === 0) root.fallbackApplied = root.fallbackRequested;
            if (code === 0 && root.fallbackApplied !== root.wanted) fallbackControlTimer.restart();
        }
    }
    Timer {
        id: fallbackControlTimer
        interval: 150
        onTriggered: {
            if (!root.owner || !root.manageFallback || !Config.ready) return;
            if (fallbackControl.running) { restart(); return; }
            root.fallbackRequested = root.wanted;
            fallbackControl.running = true;
        }
    }
    Process {
        id: bridge
        command: [root.bridgeExecutable, "--socket", root.runtimePath + "/session.sock"]
        stdinEnabled: true
        onStarted: { root.lastPayload = ""; root.publish(true); }
        stdout: SplitParser {
            onRead: data => {
                try {
                    const reply = JSON.parse(data);
                    if (reply.resync === true) { root.publish(true); return; }
                    root.receipt = reply;
                    root.wallNow = Date.now();
                    root.error = reply.accepted ? "" : "Waiting for verified window information.";
                    if (reply.accepted && !reply.enabled) offTimeout.stop();
                } catch (_) { root.error = "Session status is unavailable."; }
            }
        }
        onExited: (code, status) => {
            if (root.owner && root.wanted) reconnect.restart();
            else root.offAttempted = true;
        }
    }
    Timer { id: reconnect; interval: 2000; onTriggered: root.sync() }
    Timer {
        id: offTimeout
        interval: 2000
        onTriggered: {
            if (bridge.running && !root.wanted) {
                bridge.running = false;
                root.error = "The session bridge stopped; daemon acknowledgement is unavailable.";
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: root.owner && root.wanted; onTriggered: root.publish(true) }
    Timer { interval: 1000; repeat: true; running: root.enabled; onTriggered: root.wallNow = Date.now() }
    FileView {
        path: root.runtimePath + "/focus.json"
        preload: root.enabled
        watchChanges: root.enabled
        onFileChanged: reload()
        onLoaded: {
            try { root.receipt = JSON.parse(text()); root.wallNow = Date.now(); }
            catch (_) { root.error = "Session status is unavailable."; }
        }
    }
    IpcHandler {
        target: "cryodSession"
        function status(): string {
            return JSON.stringify({enabled:root.enabled, wanted:root.wanted,
                groupLaunches:root.enabled && Config.options.cryod.groupLaunches,
                bridgeRunning:bridge.running, fresh:root.fresh, receipt:root.receipt, error:root.error,
                fallbackError:root.fallbackError});
        }
    }
}
