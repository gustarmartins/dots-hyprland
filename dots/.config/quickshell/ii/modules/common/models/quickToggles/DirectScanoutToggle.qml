import QtQuick
import qs.services
import qs.modules.common.models.hyprland

QuickToggleModel {
    id: root
    name: Translation.tr("Direct scanout")
    icon: "desktop_windows"
    available: policy.value !== undefined
    toggled: policy.value === 1 || policy.value === 2
    mainAction: () => policy.setValue(root.toggled ? 0 : 1)
    tooltipText: Translation.tr("Allow eligible fullscreen windows to scan out directly")

    HyprlandConfigOption {
        id: policy
        key: "render:direct_scanout"
    }
}
