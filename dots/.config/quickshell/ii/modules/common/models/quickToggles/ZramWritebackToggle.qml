import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Guarded Writeback")
    property string budget: "Checking"

    icon: "save"
    statusText: budget
    toggled: budget.startsWith("Cap reached")
    altActionOnRightClick: true

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh writeback-cold"])
        refreshDelay.restart()
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh writeback-all"])
        refreshDelay.restart()
    }

    Process {
        id: fetchBudget
        running: true
        command: ["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh writeback-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                if (s.length > 0) root.budget = s
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 1500
        repeat: false
        onTriggered: fetchBudget.running = true
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: fetchBudget.running = true
    }

    tooltipText: Translation.tr("Left: guarded writeback using the configured idle age and budget. Right: emergency writeback; warning is shown, action proceeds.")
}
