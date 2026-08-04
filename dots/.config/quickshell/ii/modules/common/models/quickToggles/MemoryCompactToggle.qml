import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.services

QuickToggleModel {
    name: Translation.tr("Compact RAM")
    icon: "vertical_align_center"
    hasStatusText: false
    toggled: false
    altActionOnRightClick: true
    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/memory-tools.sh\" compact-memory"])
    }
    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/memory-tools.sh\" compact-zram"])
    }
    tooltipText: Translation.tr("Left: global physical compaction. Right: compact zram's allocator.")
}
