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
    name: Translation.tr("Memory Mode")
    toggled: false
    icon: toggled ? "memory" : "developer_board"
    statusText: toggled ? "Aggressive" : "Optimized"

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "/home/gus/.local/bin/memory-mode.sh toggle"])
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", "/home/gus/.local/bin/memory-mode.sh get_state"]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode === 0
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            fetchActiveState.running = true
        }
    }

    tooltipText: Translation.tr("Toggle between Optimized and Aggressive memory management")
}
