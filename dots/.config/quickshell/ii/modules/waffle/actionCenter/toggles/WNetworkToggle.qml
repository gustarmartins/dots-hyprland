import QtQuick
import qs.modules.common.models.quickToggles
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter.wifi

ActionCenterToggleButton {
    toggleModel: NetworkToggle {}
    name: toggleModel.statusText
    icon: WIcons.internetIcon
    menu: Component {
        WifiControl {}
    }
}
