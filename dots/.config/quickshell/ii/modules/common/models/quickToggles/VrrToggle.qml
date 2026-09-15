import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("VRR")
    toggled: false
    icon: "sync"

    property bool stateKnown: false
    property bool activeNow: false
    property int policy: 0

    statusText: !root.stateKnown ? Translation.tr("Unknown") : !root.toggled ? Translation.tr("Off")
        : (root.activeNow ? Translation.tr("Active") : Translation.tr("Enabled, inactive"))

    mainAction: () => {
        root.toggled = !root.toggled
        HyprlandConfig.set("misc:vrr", root.toggled ? 1 : 0)
        refreshDelay.restart()
    }

    Process {
        id: fetchState
        running: true
        command: ["bash", "-c", "printf '%s %s\\n' \"$(hyprctl getoption misc:vrr -j | jq -r '.int')\" \"$(hyprctl monitors -j | jq -r '[.[] | select(.vrr == true)] | length')\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(/\s+/)
                root.stateKnown = fields.length === 2
                    && /^[0-3]$/.test(fields[0]) && /^\d+$/.test(fields[1])
                if (!root.stateKnown)
                    return
                root.policy = Number(fields[0])
                root.activeNow = Number(fields[1]) > 0
                root.toggled = root.policy !== 0
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 700
        repeat: false
        onTriggered: {
            if (!fetchState.running)
                fetchState.running = true
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (!fetchState.running)
                fetchState.running = true
        }
    }

    Connections {
        target: HyprlandConfig

        function onReloaded() {
            refreshDelay.restart()
        }
    }

    tooltipText: Translation.tr("Variable refresh rate; Active means at least one display reports VRR active")
}
