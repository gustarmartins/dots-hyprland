import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

QuickToggleModel {
    id: root
    name: Translation.tr("Performance")

    readonly property bool active: FocusMode.enabled

    icon: "speed"
    available: !FocusMode.busy
    toggled: root.active
    statusText: FocusMode.statusText

    mainAction: () => {
        FocusMode.setEnabled(!FocusMode.enabled)
    }

    tooltipText: FocusMode.error || Translation.tr("CryoD CPU priority and your optional hardware boost. Configure in Settings → CryoD. Turning off restores both.")
}
