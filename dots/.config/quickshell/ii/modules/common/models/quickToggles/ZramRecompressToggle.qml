import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Recompress")
    property string mode: "tier1"

    icon: "compress"
    statusText: mode
    toggled: false
    altActionOnRightClick: true

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh recompress-run"])
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh recompress-cycle"])
        refreshDelay.restart()
    }

    Process {
        id: fetchMode
        running: true
        command: ["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh recompress-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                if (s.length > 0) root.mode = s
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 500
        repeat: false
        onTriggered: fetchMode.running = true
    }

    tooltipText: Translation.tr("Left: recompress eligible idle pages at the selected tier. Right: choose ZSTD 3 → 9 → 15.")
}
