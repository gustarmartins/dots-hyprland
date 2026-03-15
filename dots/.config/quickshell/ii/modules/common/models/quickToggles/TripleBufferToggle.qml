import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Triple buffer")
    toggled: toggled
    icon: "filter_3"

    mainAction: () => {
        root.toggled = !root.toggled
        if (root.toggled) {
            Quickshell.execDetached(["bash", "-c", `hyprctl keyword render:new_render_scheduling 1`])
        } else {
            Quickshell.execDetached(["bash", "-c", `hyprctl keyword render:new_render_scheduling 0`])
        }
    }
    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption render:new_render_scheduling -j | jq ".int")" -eq 1`]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode === 0
        }
    }
    tooltipText: Translation.tr("Triple buffering for smoother frames")
}
