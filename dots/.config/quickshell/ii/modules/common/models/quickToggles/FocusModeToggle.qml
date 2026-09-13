import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

QuickToggleModel {
    id: root
    name: Translation.tr("Focus Mode")

    property bool active: false

    icon: root.active ? "center_focus_strong" : "center_focus_weak"
    toggled: root.active
    statusText: root.active ? "Focused" : "Off"

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/focus-mode.sh\" toggle"])
        refreshDelay.restart()
    }

    Process {
        id: fetchState
        running: true
        command: ["bash", "-c", "exec \"$HOME/.local/bin/focus-mode.sh\" get_state"]
        stdout: StdioCollector {
            onStreamFinished: root.active = (text.trim() === "on")
        }
    }

    Timer {
        id: refreshDelay
        interval: 700
        repeat: false
        onTriggered: fetchState.running = true
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: fetchState.running = true
    }

    tooltipText: Translation.tr("Keeps the focused app hot: CPU/GPU boost, RAM and OOM protection")
}
