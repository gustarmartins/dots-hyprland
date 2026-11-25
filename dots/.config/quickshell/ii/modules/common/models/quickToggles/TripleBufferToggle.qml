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
    toggled: false
    icon: "filter_3"
    statusText: root.toggled ? Translation.tr("Enabled") : Translation.tr("Off")

    // Enabling experimental render scheduling requires press-and-hold;
    // disabling stays an immediate single-click escape hatch.
    mainActionRequiresHold: !root.toggled
    mainHoldDurationMs: 1100
    mainHoldLabel: Translation.tr("Enable 3× buffer")

    mainAction: () => {
        const next = !root.toggled
        root.toggled = next
        HyprlandConfig.set("render:new_render_scheduling", next ? 1 : 0)
        refreshDelay.restart()
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption render:new_render_scheduling -j | jq -r ".bool")" = true`]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode === 0
        }
    }

    Timer {
        id: refreshDelay
        interval: 800
        repeat: false
        onTriggered: {
            if (!fetchActiveState.running)
                fetchActiveState.running = true
        }
    }

    Connections {
        target: HyprlandConfig

        function onReloaded() {
            if (!fetchActiveState.running)
                fetchActiveState.running = true
        }
    }

    tooltipText: root.toggled
        ? Translation.tr("Click to disable render scheduling immediately")
        : Translation.tr("Hold left-click to enable experimental render scheduling")
}
