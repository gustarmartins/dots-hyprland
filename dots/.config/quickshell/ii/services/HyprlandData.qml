pragma Singleton
pragma ComponentBehavior: Bound

import "root:/modules/common/functions/WorkspaceIdentity.js" as WorkspaceIdentity
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    // Keep the compatibility snapshots used by existing widgets, while the
    // native service owns discovery, object lifetimes and IPC connections.
    readonly property var nativeToplevels: Hyprland.toplevels.values
    property var windowList: []
    // Native refreshes publish each window separately. Re-reading every full
    // QVariantMap from a binding for each publication made one N-window reply
    // rebuild the entire compatibility model N times, including all consumers.
    // Observe changes without converting the maps; publish once after the batch.
    onNativeToplevelsChanged: windowSnapshotTimer.restart()
    Variants {
        model: root.nativeToplevels
        Scope {
            required property var modelData
            Connections {
                target: modelData
                function onLastIpcObjectChanged() { windowSnapshotTimer.restart(); }
            }
        }
    }
    function refreshWindowSnapshot() {
        root.windowList = root.nativeToplevels.map(toplevel => {
            const win = toplevel?.lastIpcObject;
            if (!win?.address || win.size?.length !== 2) return null;
            // Title events update the native title directly. They do not need
            // another full clients request just to copy a spinner into JSON.
            return Object.assign({}, win, {title: toplevel.title});
        }).filter(win => win !== null);
    }
    Timer {
        id: windowSnapshotTimer
        interval: 0
        onTriggered: root.refreshWindowSnapshot()
    }
    readonly property var addresses: windowList.map(win => win.address)
    readonly property var windowByAddress: windowList.reduce((map, win) => { map[win.address] = win; return map; }, {})
    readonly property var workspaces: Hyprland.workspaces.values
        .filter(ws => ws && ws.id >= 1 && ws.id <= 100 && ws.lastIpcObject.id !== undefined)
        .map(ws => Object.assign({}, ws.lastIpcObject, {
            id: ws.id, name: ws.name, hasfullscreen: ws.hasFullscreen,
            monitor: ws.monitor?.name ?? ws.lastIpcObject.monitor,
            monitorID: ws.monitor?.id ?? ws.lastIpcObject.monitorID,
        }));
    readonly property var workspaceIds: workspaces.map(ws => ws.id)
    readonly property var workspaceById: workspaces.reduce((map, ws) => { map[ws.id] = ws; return map; }, {})
    readonly property var activeWorkspace: {
        const ws = Hyprland.focusedWorkspace;
        return ws ? Object.assign({}, ws.lastIpcObject, {
            id: ws.id, name: ws.name, hasfullscreen: ws.hasFullscreen,
            monitor: ws.monitor?.name ?? "", monitorID: ws.monitor?.id ?? -1,
        }) : null;
    }
    readonly property var monitors: Hyprland.monitors.values
        .filter(mon => mon && mon.lastIpcObject.name && mon.lastIpcObject.width > 0)
        .map(mon => Object.assign({}, mon.lastIpcObject, {
            focused: mon.focused,
            activeWorkspace: Object.assign({}, mon.lastIpcObject.activeWorkspace, {
                id: mon.activeWorkspace?.id ?? -1, name: mon.activeWorkspace?.name ?? "",
            }),
        }));
    property var layers: ({})
    property bool trackLayerEvents: false
    property double lastEventAt: 0
    IpcHandler {
        target: "hyprlandDiagnostics"
        function status(): string {
            return JSON.stringify({
                eventAgeMs: root.lastEventAt ? Date.now() - root.lastEventAt : -1,
                snapshotWindowCount: root.windowList.length,
                focusedWorkspace: Hyprland.focusedWorkspace?.id ?? -1,
                monitors: Hyprland.monitors.values.map(mon => ({
                    name: mon.name, workspace: mon.activeWorkspace?.id ?? -1,
                })),
            });
        }
    }
    readonly property bool monitorsReady: monitors.length > 0 && monitors.length === Hyprland.monitors.values.length
    readonly property bool workspacesReady: Hyprland.workspaces.values.length > 0
        && Hyprland.workspaces.values.every(ws => ws && WorkspaceIdentity.address(ws.lastIpcObject) !== "")

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    function monitorHasFullscreen(screenName) {
        // A newly created workspace has no JSON snapshot yet. Its readiness must
        // not hide this monitor's background (or an unrelated monitor's panels).
        // The monitor's native active-workspace identity already updates on IPC.
        if (!screenName)
            return true;

        const monitor = root.monitors.find(mon => mon.name === screenName);
        if (!monitor)
            return true;

        const workspaceId = monitor.activeWorkspace?.id;
        const workspace = root.workspaceById[workspaceId];
        const workspaceFullscreen = workspace?.hasfullscreen === true;
        const clientFullscreen = root.windowList.some(win => {
            return win.monitor === monitor.id && win.workspace?.id === workspaceId && (win.fullscreen > 0 || win.fullscreenClient > 0);
        });

        return workspaceFullscreen || clientFullscreen;
    }

    function preferredNotificationMonitorName(preferredScreenName) {
        if (preferredScreenName && !root.monitorHasFullscreen(preferredScreenName))
            return preferredScreenName;

        const fallbackMonitor = root.monitors.find(mon => !root.monitorHasFullscreen(mon.name));
        if (fallbackMonitor)
            return fallbackMonitor.name;

        return preferredScreenName ?? "";
    }

    function isGameClient(win) {
        if (!win)
            return false;
        if (String(win.contentType ?? "").toLowerCase() === "game")
            return true;
        return Array.isArray(win.tags) && win.tags.some(tag => String(tag).replace(/\*$/, "") === "gamemode");
    }

    function monitorHasGame(screenName) {
        if (!screenName)
            return false;
        if (root.monitorHasFullscreen(screenName))
            return true;
        const monitor = root.monitors.find(mon => mon.name === screenName);
        if (!monitor)
            return false;
        return root.windowList.some(win => win.monitor === monitor.id && root.isGameClient(win));
    }

    function anyMonitorHasGame() {
        return root.anyMonitorHasFullscreen() || root.windowList.some(win => root.isGameClient(win));
    }

    function allMonitorsHaveFullscreen() {
        if (!root.monitorsReady || !root.workspacesReady || root.monitors.length === 0)
            return false;
        return root.monitors.every(mon => root.monitorHasFullscreen(mon.name));
    }

    function anyMonitorHasFullscreen() {
        if (!root.monitorsReady || !root.workspacesReady)
            return true;

        return root.monitors.some(mon => root.monitorHasFullscreen(mon.name));
    }

    // Internals

    function updateWindowList() { Hyprland.refreshToplevels(); }
    function updateMonitors() { Hyprland.refreshMonitors(); }
    function updateWorkspaces() { Hyprland.refreshWorkspaces(); }
    function updateLayers() {
        layersPending = true;
        if (!layerRefreshThrottle.running) layerRefreshThrottle.start();
    }

    function updateNativeSnapshots() {
        updateWindowList();
        updateMonitors();
        updateWorkspaces();
    }

    function updateAll() {
        updateNativeSnapshots();
        updateLayers();
    }

    Timer {
        id: eventRefreshThrottle
        interval: 25
        onTriggered: root.updateNativeSnapshots()
    }

    // Compatibility consumers still read titles from lastIpcObject. Limit
    // those client-only snapshots even when a title changes every frame.
    Timer {
        id: titleRefreshThrottle
        interval: 250
        onTriggered: root.refreshWindowSnapshot()
    }

    property bool layersPending: false
    Timer {
        id: layerRefreshThrottle
        interval: 50
        onTriggered: {
            if (getLayers.running) return;
            root.layersPending = false;
            getLayers.running = true;
        }
    }

    function biggestWindowForWorkspace(workspaceId) {
        return windowStatsByWorkspace[workspaceId]?.largest ?? null;
    }

    // Both bars and the overview use the same snapshot. Visit each window once
    // regardless of the number of outputs or workspace cells on screen.
    readonly property var windowStatsByWorkspace: {
        const stats = Object.create(null);
        for (const window of root.windowList) {
            const id = window.workspace?.id;
            if (id == null) continue;
            const group = stats[id] ?? (stats[id] = { count: 0, largest: null, area: 0 });
            ++group.count;
            const area = (window.size?.[0] ?? 0) * (window.size?.[1] ?? 0);
            if (area > group.area) {
                group.area = area;
                group.largest = window;
            }
        }
        return stats;
    }

    Component.onCompleted: {
        // The native connection performs its initial refresh with permission
        // to create monitors. An earlier manual refresh can race that request
        // and leave only empty monitor placeholders from workspace discovery.
        updateLayers();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            root.lastEventAt = Date.now();
            if (["openlayer", "closelayer"].includes(event.name)) {
                if (root.trackLayerEvents) root.updateLayers();
                return;
            }
            if (event.name === "screencast") return;
            if (root.trackLayerEvents && ["monitoradded", "monitoraddedv2", "monitorremoved", "configreloaded"].includes(event.name))
                root.updateLayers();
            if (["windowtitle", "windowtitlev2"].includes(event.name)) {
                if (!titleRefreshThrottle.running) titleRefreshThrottle.start();
                return;
            }
            // Focus is already applied to the native model; it does not change
            // any geometry. Do not refresh every monitor/client on focus churn.
            if (["activewindow", "activewindowv2"].includes(event.name)) return;
            // Properties such as window size, reserved monitor space and
            // special-workspace details still require fresh JSON snapshots.
            if (!eventRefreshThrottle.running) eventRefreshThrottle.start();
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (parsed && typeof parsed === "object") root.layers = parsed;
                } catch (error) {
                    console.warn("[HyprlandData] Could not read layers:", error);
                }
            }
        }
        onExited: {
            if (root.layersPending) layerRefreshThrottle.restart();
        }
    }
}
