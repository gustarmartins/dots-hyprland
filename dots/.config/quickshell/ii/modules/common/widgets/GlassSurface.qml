import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.services

// A static material tint; the compositor supplies blur through BackgroundEffect.
Rectangle {
    id: root
    property color baseColor: Appearance.m3colors.m3surfaceContainerLow
    property real surfaceOpacity: (DesktopEffects.settings.popup_opacity ?? 82) / 100
    readonly property bool glassEnabled: Config.options.appearance.transparency.enable
        && DesktopEffects.settings.blur !== false
    readonly property real materialOpacity: glassEnabled ? Math.max(0, Math.min(1, surfaceOpacity)) : 1

    radius: 24
    antialiasing: true
    gradient: Gradient {
        GradientStop {
            position: 0
            color: Qt.alpha(ColorUtils.mix(root.baseColor, Appearance.m3colors.m3primary, 0.94), root.materialOpacity)
        }
        GradientStop {
            position: 1
            color: Qt.alpha(root.baseColor, root.materialOpacity)
        }
    }
    border.width: 1
    border.color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.14)
}
