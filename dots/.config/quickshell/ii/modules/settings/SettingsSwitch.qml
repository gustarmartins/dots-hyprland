import QtQuick
import QtQuick.Controls
import qs.modules.common
Switch {
    id: control
    implicitWidth: 52
    implicitHeight: 40
    padding: 0
    indicator: Rectangle {
        x: control.width - width
        y: (control.height - height) / 2
        width: 52
        height: 30
        radius: 15
        color: control.checked ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHighest
        border.width: control.checked ? 0 : 2
        border.color: Appearance.m3colors.m3outline
        Rectangle {
            x: control.checked ? 26 : 4
            y: 4
            width: 22
            height: 22
            radius: 11
            color: control.checked ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3outline
            Behavior on x { NumberAnimation { duration: 100 } }
        }
    }
}
