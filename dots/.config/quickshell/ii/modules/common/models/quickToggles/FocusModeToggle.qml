import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

QuickToggleModel {
    id: root
    name: Translation.tr("Focus Mode")

    readonly property bool active: FocusMode.enabled

    icon: root.active ? "center_focus_strong" : "center_focus_weak"
    toggled: root.active
    statusText: FocusMode.statusText

    mainAction: () => {
        FocusMode.setEnabled(!FocusMode.enabled)
    }

    tooltipText: FocusMode.error || Translation.tr("Prioritizes an isolated focused app through CryoD. GPU and latency boost are separate controls in CryoD settings.")
}
