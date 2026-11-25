import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

Switch {
    id: control
    implicitWidth: 52
    implicitHeight: 36
    padding: 0
    opacity: enabled ? 1 : 0.45

    readonly property color colPrimary: Appearance.m3colors.m3primary
    readonly property color colOnPrimary: Appearance.m3colors.m3onPrimary
    readonly property color colTrackOff: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colOutline: Appearance.m3colors.m3outline ?? Appearance.m3colors.m3outlineVariant

    indicator: Rectangle {
        x: control.width - width
        y: (control.height - height) / 2
        width: 52
        height: 32
        radius: 16
        color: control.checked ? control.colPrimary : control.colTrackOff
        border.width: control.visualFocus ? 2 : (control.checked ? 0 : 2)
        border.color: control.visualFocus ? control.colPrimary : (control.checked ? control.colPrimary : control.colOutline)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

        Rectangle {
            readonly property real thumbSize: control.down ? 26 : (control.checked ? 24 : 16)
            width: thumbSize
            height: thumbSize
            radius: thumbSize / 2
            x: control.checked ? (parent.width - width - 4) : (control.down ? 3 : 8)
            y: (parent.height - height) / 2
            color: control.checked ? control.colOnPrimary : control.colOutline
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: control.checked
                text: "check"
                iconSize: 15
                color: control.colPrimary
            }
        }
    }
}
