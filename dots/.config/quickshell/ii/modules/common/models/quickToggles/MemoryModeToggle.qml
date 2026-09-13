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
    name: Translation.tr("Memory")

    property string memoryState: "off"

    icon: memoryState === "ram-plus" ? "add_to_drive" : "memory"
    statusText: memoryState === "ram-plus"
        ? "Max Speed · disk 4 GiB"
        : "Max Speed · disk off"
    toggled: memoryState === "ram-plus"
    altActionOnRightClick: true

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/memory-mode.sh\" report"])
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/memory-mode.sh\" toggle"])
        refreshDelay.restart()
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", "exec \"$HOME/.local/bin/memory-mode.sh\" get_state"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                if (s.length > 0) root.memoryState = s
            }
        }
    }

    // One-shot quick re-read after a tap (swapoff/swapon can take a beat).
    Timer {
        id: refreshDelay
        interval: 700
        repeat: false
        onTriggered: fetchActiveState.running = true
    }

    // Steady-state poll keeps the widget honest if state changes out-of-band.
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: fetchActiveState.running = true
    }

    tooltipText: Translation.tr("Turbo VM. L: show info. R: toggle 4G low-priority NVMe.")
}
