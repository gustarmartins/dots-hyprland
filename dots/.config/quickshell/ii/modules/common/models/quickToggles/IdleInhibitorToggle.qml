import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Keep awake")

    toggled: Idle.inhibit
    icon: "coffee"
    statusText: Idle.error || (Idle.inhibit
        ? Translation.tr("Always awake")
        : (Idle.onAc ? "AC · " : "Bat · ") + Idle.formatMinutes(Idle.effectiveSleepMinutes))
    mainAction: () => {
        Idle.toggleInhibit()
    }
    tooltipText: Translation.tr("Configure auto-sleep (plugged in & battery) and Keep awake")
}
