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

    // Live profile name, read from actual system state (desync-proof, never a
    // stored counter). One of: ultra | blazing | optimized | heavy | anti-freeze | custom
    property string profile: "optimized"

    icon: switch(profile) {
        case "ultra":       return "local_fire_department" // ultra zram-only, max speed
        case "blazing":     return "rocket_launch"   // zram-only, fast speed
        case "optimized":   return "developer_board" // proven daily
        case "heavy":       return "stacks"           // VM / Waydroid footprint
        case "anti-freeze": return "ac_unit"          // widest reclaim buffer
        default:            return "help"             // custom / manual tinkering
    }
    statusText: switch(profile) {
        case "ultra":       return "Ultra Max"
        case "blazing":     return "Blazing"
        case "optimized":   return "Optimized"
        case "heavy":       return "Heavy / VM"
        case "anti-freeze": return "Anti-freeze"
        default:            return "Custom"
    }
    // Light the button up for any non-default mode (incl. custom) so the daily
    // "optimized" baseline reads as the neutral resting state.
    toggled: profile !== "optimized"

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "/home/gus/.local/bin/memory-mode.sh next"])
        refreshDelay.restart() // re-read state shortly after the apply lands
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", "/home/gus/.local/bin/memory-mode.sh get_state"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                if (s.length > 0) root.profile = s
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

    tooltipText: Translation.tr("Cycle: Ultra → Blazing → Optimized → Heavy → Anti-freeze")
}
