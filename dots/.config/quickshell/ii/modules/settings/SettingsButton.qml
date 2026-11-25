import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

Button {
    id: control
    property bool prominent: false
    implicitHeight: 40
    leftPadding: 14
    rightPadding: 14
    topPadding: 8
    bottomPadding: 8
    opacity: enabled ? 1 : 0.45

    readonly property color colBgRest: prominent
        ? Appearance.m3colors.m3primary
        : Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colBgHover: prominent
        ? Qt.tint(Appearance.m3colors.m3primary, Qt.alpha(Appearance.m3colors.m3onPrimary, 0.08))
        : Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colBgDown: prominent
        ? Qt.tint(Appearance.m3colors.m3primary, Qt.alpha(Appearance.m3colors.m3onPrimary, 0.14))
        : Appearance.m3colors.m3secondaryContainer

    background: Rectangle {
        radius: 12
        color: control.down ? control.colBgDown : control.hovered ? control.colBgHover : control.colBgRest
        border.width: control.visualFocus ? 2 : (control.prominent ? 0 : 1)
        border.color: control.visualFocus ? Appearance.m3colors.m3primary
            : control.hovered ? (Appearance.m3colors.m3outline ?? Appearance.m3colors.m3outlineVariant)
            : Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    contentItem: StyledText {
        text: control.text
        textFormat: Text.PlainText
        font.pixelSize: 13
        font.weight: control.prominent ? Font.DemiBold : Font.Medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: control.prominent
            ? Appearance.m3colors.m3onPrimary
            : control.down
                ? (Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onSurface)
                : Appearance.m3colors.m3onSurface
    }
}
