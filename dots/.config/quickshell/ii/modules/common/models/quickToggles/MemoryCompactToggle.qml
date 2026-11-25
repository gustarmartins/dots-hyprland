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
    mainActionRequiresHold: true
    mainHoldDurationMs: 900
    mainHoldLabel: Translation.tr("Compact RAM")
    altActionRequiresHold: true
    altHoldDurationMs: 900
    altHoldLabel: Translation.tr("Compact ZRAM")
    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh compact-memory"])
    }
    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec memory-tools.sh compact-zram"])
    }
    tooltipText: Translation.tr("Hold left-click: global physical compaction. Hold right-click: compact zram's allocator.")
}
