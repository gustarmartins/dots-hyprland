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
    altActionRequiresHold: true
    altHoldDurationMs: 1100
    altHoldLabel: Translation.tr("Writeback all")

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
        running: false
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
        running: root.pollingEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchBudget.running = true
    }

    tooltipText: Translation.tr("Left: guarded writeback using the configured idle age and budget. Hold right-click: emergency writeback all.")
}
