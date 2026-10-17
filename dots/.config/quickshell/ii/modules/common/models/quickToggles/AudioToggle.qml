import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Audio output")
    available: Audio.ready
    statusText: !available ? Translation.tr("Unavailable") : toggled ? Translation.tr("Unmuted") : Translation.tr("Muted")
    tooltipText: Translation.tr("Audio output | Right-click for volume mixer & device selector")
    toggled: available && !Audio.sink?.audio?.muted
    icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
    mainAction: () => {
        Audio.toggleMute()
    }
    hasMenu: true
}
