import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

CheckBox {
    id: control
    implicitHeight: Math.max(36, contentItem.implicitHeight + 8)
    spacing: 10
    opacity: enabled ? 1 : 0.45

    readonly property color colPrimary: Appearance.m3colors.m3primary
    readonly property color colOnPrimary: Appearance.m3colors.m3onPrimary
    readonly property color colSurfaceHigh: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colSurfaceHighest: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colOnSurface: Appearance.m3colors.m3onSurface
    readonly property color colOutline: Appearance.m3colors.m3outline ?? Appearance.m3colors.m3outlineVariant

    indicator: Rectangle {
        x: control.leftPadding
        y: (control.height - height) / 2
        width: 20
        height: 20
        radius: 5
        color: control.checked ? control.colPrimary
            : control.hovered ? control.colSurfaceHighest : control.colSurfaceHigh
        border.width: control.activeFocus ? 2 : (control.checked ? 0 : 1.5)
        border.color: control.checked || control.activeFocus ? control.colPrimary : control.colOutline
        Behavior on color { ColorAnimation { duration: 120 } }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: control.checked
            text: "check"
            iconSize: 16
            color: control.colOnPrimary
        }
    }

    contentItem: StyledText {
        text: control.text
        font: control.font
        color: control.colOnSurface
        leftPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
}
