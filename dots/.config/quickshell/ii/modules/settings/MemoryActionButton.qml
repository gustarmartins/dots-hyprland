import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

// A distinct primary action and a legible outlined secondary action for Memory locks.
Button {
    id: control
    property bool prominent: false
    implicitHeight: 38
    implicitWidth: Math.max(76, label.implicitWidth + leftPadding + rightPadding)
    leftPadding: 14
    rightPadding: 14
    opacity: enabled ? 1 : 0.48
    background: Rectangle {
        radius: 9
        color: control.prominent ? Appearance.m3colors.m3primary
             : control.down ? Appearance.m3colors.m3surfaceContainerHighest
             : control.hovered ? Appearance.m3colors.m3surfaceContainerHighest
             : Appearance.m3colors.m3surfaceContainerHigh
        border.width: control.activeFocus ? 2 : 1
        border.color: control.prominent || control.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outline
    }
    contentItem: StyledText {
        id: label
        text: control.text
        color: control.prominent ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
        font.weight: control.prominent ? Font.DemiBold : Font.Medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
