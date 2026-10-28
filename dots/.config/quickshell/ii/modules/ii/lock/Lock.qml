pragma ComponentBehavior: Bound
import "root:/modules/common/functions/WorkspaceIdentity.js" as WorkspaceIdentity
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root

    // Monitor name -> addressable workspace selector to restore on unlock.
    property var savedWorkspaces: ({})

    Timer {
        id: restoreTimer
        interval: 150
        repeat: false
        onTriggered: {
            var batch = ""
            for (var j = 0; j < Quickshell.screens.length; ++j) {
                var monName = Quickshell.screens[j].name
                var wsId = root.savedWorkspaces[monName]
                if (wsId !== undefined) {
                    batch += `hl.dispatch(hl.dsp.focus({monitor=${JSON.stringify(monName)}})); hl.dispatch(hl.dsp.focus({workspace=${JSON.stringify(wsId)}}));`
                }
            }
            if (batch.length > 0) {
                Quickshell.execDetached(["hyprctl", "eval", batch])
            }
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    // Single batch for lock and unlock so we don't race multiple hyprctl calls
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                var next = {}
                var batch = ""
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    if (mData?.activeWorkspace == undefined) {
                        return;
                    }
                    var ws = WorkspaceIdentity.address(mData.activeWorkspace) || "1"
                    next[mon] = ws
                    batch += `hl.dispatch(hl.dsp.focus({monitor=${JSON.stringify(mon)}})); hl.dispatch(hl.dsp.focus({workspace=${2147483647 - i}}));`
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["hyprctl", "eval", batch])
            } else {
                restoreTimer.start()
            }
        }
    }

    // Push everything down (visual only; workspace switch is in Connections above)
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2
        }
    }
}
