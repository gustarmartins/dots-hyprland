import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.services

QuickToggleModel {
    name: Translation.tr("Drop Caches")
    icon: "delete_sweep"
    hasStatusText: false
    toggled: false
    mainAction: () => {
        Quickshell.execDetached(["bash", "-c", "exec \"$HOME/.local/bin/memory-tools.sh\" drop-caches"])
    }
    tooltipText: Translation.tr("Drop clean page cache, dentries, and inodes (vm.drop_caches=3).")
}
