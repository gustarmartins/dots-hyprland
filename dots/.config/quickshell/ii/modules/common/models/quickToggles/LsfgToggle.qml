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
    name: Translation.tr("LSFG 120Hz")
    toggled: false
    icon: "auto_awesome"

    statusText: root.toggled ? Translation.tr("120Hz (VRR Off)") : Translation.tr("144Hz (VRR On)")

    mainAction: () => {
        root.toggled = !root.toggled
        if (root.toggled) {
            applyMode.command = ["bash", "-c", "hyprctl eval 'local monitors = require(\"monitors\"); local m = {}; for k,v in pairs(monitors.aoc) do m[k]=v end; m.mode = \"1920x1080@120.0\"; m.vrr = 0; hl.monitor(m); hl.config({misc={vrr=0}})'"]
        } else {
            applyMode.command = ["bash", "-c", "hyprctl eval 'local monitors = require(\"monitors\"); hl.monitor(monitors.aoc); hl.config({misc={vrr=1}})'"]
        }
        applyMode.running = true
        fetchTimer.restart()
    }

    Process {
        id: applyMode
        running: false
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", "hyprctl monitors -j | jq -e '.[] | select(.name == \"DP-1\" and .refreshRate < 130)' >/dev/null"]
        onExited: (exitCode, exitStatus) => {
            root.toggled = (exitCode === 0)
        }
    }

    Timer {
        id: fetchTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!fetchActiveState.running)
                fetchActiveState.running = true
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            if (!fetchActiveState.running)
                fetchActiveState.running = true
        }
    }

    tooltipText: Translation.tr("Toggle between 120Hz (VRR off for LSFG) and 144Hz (VRR on for desktop)")
}
