import QtQuick
import Quickshell.Hyprland
import qs.modules.common
import qs.services

QtObject {
    id: root
    property HyprlandMonitor monitor
    readonly property int activeWorkspace: monitor?.activeWorkspace?.id ?? 1
    readonly property int shownCount: Math.max(1, Config.options.bar.workspaces.shown)
    readonly property int group: Math.floor((activeWorkspace - 1) / shownCount)
    readonly property var occupied: Array.from({length: shownCount}, (_, index) =>
        Hyprland.workspaces.values.some(ws => ws && ws.id === root.getWorkspaceIdAt(index)))
    readonly property var biggestWindow: Array.from({length: shownCount}, (_, index) =>
        HyprlandData.biggestWindowForWorkspace(root.getWorkspaceIdAt(index)))
    // Each bar must judge its own active workspace, independent of keyboard focus.
    readonly property bool currentWorkspaceNotFake: !!biggestWindow[(activeWorkspace - 1) % shownCount]
    readonly property int fakeWorkspace: currentWorkspaceNotFake ? -9999 : activeWorkspace
    readonly property var specialWorkspace: HyprlandData.monitors.find(mon => mon.id === root.monitor?.id)?.specialWorkspace
    readonly property string specialWorkspaceName: specialWorkspace?.name?.replace(/^special:/, "") ?? ""
    readonly property bool specialWorkspaceActive: !!specialWorkspace?.id && specialWorkspaceName !== ""

    function getWorkspaceId(group, index) {
        return group * shownCount + index + 1;
    }
    function getWorkspaceIdAt(index) {
        return getWorkspaceId(group, index);
    }
}
