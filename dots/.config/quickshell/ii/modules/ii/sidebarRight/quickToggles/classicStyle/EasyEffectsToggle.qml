import qs.modules.common.widgets
import qs
import qs.services
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Hyprland

QuickToggleButton {
    id: root
    visible: EasyEffects.available
    enabled: !EasyEffects.busy
    toggled: EasyEffects.active && !EasyEffects.bypassed
    buttonIcon: "instant_mix"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    onClicked: {
        EasyEffects.toggle()
    }

    altAction: () => {
        EasyEffects.show()
        GlobalStates.sidebarRightOpen = false
    }

    StyledToolTip {
        text: Translation.tr("EasyEffects processing on/off | Right-click to configure")
    }
}
