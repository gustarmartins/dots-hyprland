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
    name: Translation.tr("ZRAM Algo")

    property string algoState: "zstd"
    readonly property string liveAlgo: algoState.indexOf("->") >= 0 ? algoState.split("->")[0] : algoState

    icon: switch(liveAlgo) {
        case "zstd":  return "compress"
        case "lz4":   return "speed"
        case "lz4hc": return "data_saver_on"
        default:      return "help"
    }
    statusText: algoState
    toggled: algoState.indexOf("->") >= 0 || liveAlgo !== "zstd"

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/zram-algo-mode.sh\" next"])
        refreshDelay.restart()
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/zram-algo-mode.sh\" live"])
        refreshDelay.restart()
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", "exec \"$HOME/.local/bin/zram-algo-mode.sh\" status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                if (s.length > 0) root.algoState = s
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 900
        repeat: false
        onTriggered: fetchActiveState.running = true
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: fetchActiveState.running = true
    }

    tooltipText: Translation.tr("Left: stage next boot zstd/lz4/lz4hc. Right or hold: guarded live apply.")
}
