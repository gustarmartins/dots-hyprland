import QtQuick
import QtQuick.Controls
import qs.modules.common
TextField {
    id: control
    implicitHeight: 40
    padding: 10
    color: Appearance.m3colors.m3onSurface
    placeholderTextColor: Appearance.m3colors.m3onSurfaceVariant
    selectionColor: Appearance.m3colors.m3primary
    selectedTextColor: Appearance.m3colors.m3onPrimary
    background: Rectangle {
        radius: 10
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
    }
}
