import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton { // Expand button
    id: root
    required property int count
    required property bool expanded
    property bool more: false
    property real fontSize: Appearance?.font.pixelSize.small ?? 12
    property real iconSize: Appearance?.font.pixelSize.normal ?? 16
    implicitHeight: root.more ? 28 : fontSize + 4 * 2
    implicitWidth: Math.max(contentItem.implicitWidth + 5 * 2, root.more ? 36 : 30)
    Layout.alignment: Qt.AlignVCenter
    Layout.fillHeight: false

    buttonRadius: Appearance.rounding.full
    colBackground: root.more && !root.expanded ? Appearance.colors.colPrimaryContainer : ColorUtils.mix(Appearance?.colors.colLayer2, Appearance?.colors.colLayer2Hover, 0.5)
    colBackgroundHover: root.more ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.25) : Appearance?.colors.colLayer2Hover ?? "#E5DFED"
    colRipple: Appearance?.colors.colLayer2Active ?? "#D6CEE2"
    scale: root.more && hovered ? 1.1 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: contentRow.implicitWidth
        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 3
            StyledText {
                Layout.leftMargin: 4
                visible: root.count > 1
                text: root.count
                font.pixelSize: root.fontSize
            }
            MaterialSymbol {
                text: root.more && !root.expanded ? "more_horiz" : "keyboard_arrow_down"
                iconSize: root.more ? Math.max(root.iconSize, 20) : root.iconSize
                color: root.more && !root.expanded ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                rotation: expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
