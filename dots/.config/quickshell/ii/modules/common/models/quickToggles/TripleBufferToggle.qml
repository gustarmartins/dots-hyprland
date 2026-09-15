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
    name: root.enableArmed ? Translation.tr("Click again") : Translation.tr("Triple buffer")
    toggled: false
    icon: root.enableArmed ? "warning" : "filter_3"

    property bool enableArmed: false

    statusText: root.enableArmed ? Translation.tr("Confirm enable")
        : (root.toggled ? Translation.tr("Enabled") : Translation.tr("Off"))

    // Enabling new render scheduling previously caused a DP-1 KMS modeset
    // storm on this RX 6600 setup, so require a deliberate second click.
    // Disabling stays immediate so the risky path always has a quick escape.
    mainAction: () => {
        if (root.toggled) {
            root.enableArmed = false
            confirmEnableTimer.stop()
            root.toggled = false
            HyprlandConfig.set("render:new_render_scheduling", 0)
            refreshDelay.restart()
            return
        }

        if (!root.enableArmed) {
            root.enableArmed = true
            confirmEnableTimer.restart()
            return
        }

        root.enableArmed = false
        confirmEnableTimer.stop()
        root.toggled = true
        HyprlandConfig.set("render:new_render_scheduling", 1)
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
        id: confirmEnableTimer
        interval: 5000
        repeat: false
        onTriggered: root.enableArmed = false
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

    tooltipText: root.enableArmed
        ? Translation.tr("Warning: click again within 5 seconds to enable")
        : Translation.tr("Experimental on this GPU; enabling previously stalled both displays")
}
