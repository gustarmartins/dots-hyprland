import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles

QuickToggleModel {
    id: root
    name: Translation.tr("Build Cache")

    property string cacheState: "off"

    icon: cacheState === "on" ? "memory_alt" : "database"
    statusText: cacheState === "on"
        ? "RAM · syncs to Btrfs"
        : cacheState === "off" ? "Btrfs · 1-click RAM" : cacheState
    toggled: cacheState === "on"
    altActionOnRightClick: true
    mainActionRequiresHold: true
    mainHoldDurationMs: 950
    mainHoldLabel: cacheState === "on" ? Translation.tr("Sync to Btrfs") : Translation.tr("Move to RAM")

    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/build-cache-mode\" toggle-gui"])
        refreshDelay.restart()
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/build-cache-mode\" report"])
    }

    Process {
        id: fetchState
        running: false
        command: ["bash", "-c", "exec \"$HOME/.local/bin/build-cache-mode\" get_state"]
        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim()
                if (state.length > 0) root.cacheState = state
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 1200
        repeat: false
        onTriggered: fetchState.running = true
    }

    Timer {
        interval: 3000
        running: root.pollingEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchState.running = true
    }

    tooltipText: Translation.tr("Hold left-click: copy Gradle caches to 6 GiB tmpfs or sync them back. Right-click: status. Active writers safely block switching.")
}
