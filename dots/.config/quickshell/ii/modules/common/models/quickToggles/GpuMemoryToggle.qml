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

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/memory-tools.sh\" gpu-report"])
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/memory-tools.sh\" gpu-evict"])
    }

    Process {
        id: fetchGpu
        running: true
        command: ["bash", "-c", "exec \"$HOME/.local/bin/memory-tools.sh\" gpu-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                if (s.length > 0) root.gpuState = s
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: fetchGpu.running = true
    }

    tooltipText: Translation.tr("Left: AMDGPU VRAM status. Right: evict VRAM only while GPU busy is ≤5%.")
}
