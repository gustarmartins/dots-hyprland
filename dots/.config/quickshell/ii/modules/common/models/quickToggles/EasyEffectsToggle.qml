import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("EasyEffects")

    available: EasyEffects.available
    toggled: EasyEffects.processing
    statusText: EasyEffects.error || (EasyEffects.busy ? Translation.tr("Updating…")
        : EasyEffects.processing ? Translation.tr("On") : Translation.tr("Off"))
    icon: "graphic_eq"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    mainAction: () => {
        EasyEffects.toggle()
    }

    altAction: () => {
        EasyEffects.show()
        GlobalStates.sidebarRightOpen = false
    }

    tooltipText: EasyEffects.error || Translation.tr("EasyEffects processing on/off | Right-click to configure")
}
