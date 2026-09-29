import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
ComboBox {
    id: control
    implicitHeight: 40
    leftPadding: 12
    rightPadding: 32
    opacity: enabled ? 1 : 0.4
    background: Rectangle {
        radius: 10
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
    }
    indicator: MaterialSymbol {
        x: control.width - width - 8
        y: (control.height - height) / 2
        text: "expand_more"
        iconSize: 20
        color: Appearance.m3colors.m3onSurface
    }
}
