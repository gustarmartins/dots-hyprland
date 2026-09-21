pragma Singleton
pragma ComponentBehavior: Bound

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
    readonly property var windowList: Hyprland.toplevels.values
        .map(toplevel => toplevel?.lastIpcObject)
        .filter(win => win?.address && win.size?.length === 2);
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
            activeWorkspace: {id: mon.activeWorkspace?.id ?? -1, name: mon.activeWorkspace?.name ?? ""},
        }));
    property var layers: ({})
    readonly property bool monitorsReady: monitors.length > 0 && monitors.length === Hyprland.monitors.values.length
    readonly property bool workspacesReady: Hyprland.workspaces.values.length > 0
        && Hyprland.workspaces.values.every(ws => ws && ws.lastIpcObject.id !== undefined)

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
        if (!screenName || !root.monitorsReady || !root.workspacesReady)
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

    // Eden publishes both title formats every frame. Refresh only client
    // snapshots, at most four times a second, preserving the existing limit.
    Timer {
        id: titleRefreshThrottle
        interval: 250
        onTriggered: root.updateWindowList()
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
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
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
            if (["openlayer", "closelayer"].includes(event.name)) {
                root.updateLayers();
                return;
            }
            if (event.name === "screencast") return;
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "configreloaded"].includes(event.name))
                root.updateLayers();
            if (["windowtitle", "windowtitlev2"].includes(event.name)) {
                if (!titleRefreshThrottle.running) titleRefreshThrottle.start();
                return;
            }
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
