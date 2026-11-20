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

    statusText: root.toggled ? Translation.tr("120 Hz · VRR off") : Translation.tr("Desktop profile")

    mainAction: () => {
        root.toggled = !root.toggled
        if (root.toggled) {
            applyMode.command = ["bash", "-c", "hyprctl eval 'local monitors = assert(package.loaded[\"monitors\"], \"Monitor profiles are not loaded\"); local m = {}; for k,v in pairs(monitors.aoc) do m[k]=v end; m.mode = \"1920x1080@120.0\"; m.vrr = 0; hl.monitor(m)'"]
        } else {
            applyMode.command = ["bash", "-c", "hyprctl eval 'local monitors = assert(package.loaded[\"monitors\"], \"Monitor profiles are not loaded\"); hl.monitor(monitors.aoc)'"]
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
        running: false
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
        running: root.pollingEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!fetchActiveState.running)
                fetchActiveState.running = true
        }
    }

    tooltipText: Translation.tr("Use 120 Hz with VRR off on the AOC, or restore its saved desktop profile. The global VRR policy stays unchanged.")
}
