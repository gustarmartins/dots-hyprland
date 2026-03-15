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
    name: Translation.tr("Tearing")
    toggled: toggled
    icon: "bolt"

    mainAction: () => {
        root.toggled = !root.toggled
        if (root.toggled) {
            Quickshell.execDetached(["bash", "-c", `hyprctl keyword general:allow_tearing 1`])
        } else {
            Quickshell.execDetached(["bash", "-c", `hyprctl keyword general:allow_tearing 0`])
        }
    }
    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption general:allow_tearing -j | jq ".int")" -eq 1`]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode === 0
        }
    }
    tooltipText: Translation.tr("Allow tearing for lower latency")
}
