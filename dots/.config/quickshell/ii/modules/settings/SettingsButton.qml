import QtQuick
import QtQuick.Controls
import qs.modules.common
Button {
    id: control
    implicitHeight: 40
    padding: 10
    opacity: enabled ? 1 : 0.4
    background: Rectangle {
        radius: 10
        color: control.down ? Appearance.m3colors.m3secondaryContainer : control.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
    }
}
