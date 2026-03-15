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
    name: Translation.tr("Direct scanout")
    toggled: toggled
    icon: "desktop_windows"

    mainAction: () => {
        root.toggled = !root.toggled
        if (root.toggled) {
            Quickshell.execDetached(["bash", "-c", `hyprctl keyword render:direct_scanout 1`])
        } else {
            Quickshell.execDetached(["bash", "-c", `hyprctl keyword render:direct_scanout 0`])
        }
    }
    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption render:direct_scanout -j | jq ".int")" -eq 1`]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode === 0
        }
    }
    tooltipText: Translation.tr("Bypass compositor for fullscreen apps")
}
