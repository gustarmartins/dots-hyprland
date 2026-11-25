import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("GPU Memory")
    property string gpuState: "Checking"

    icon: "memory_alt"
    statusText: gpuState
    toggled: false
    altActionOnRightClick: true
    altActionRequiresHold: true
    altHoldDurationMs: 1200
    altHoldLabel: Translation.tr("Evict VRAM")

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh gpu-report"])
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh gpu-evict"])
    }

    Process {
        id: fetchGpu
        running: false
        command: ["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh gpu-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                if (s.length > 0) root.gpuState = s
            }
        }
    }

    Timer {
        interval: 5000
        running: root.pollingEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchGpu.running = true
    }

    tooltipText: Translation.tr("Left: AMDGPU VRAM status. Hold right-click: evict VRAM (only while GPU busy is ≤5%).")
}
