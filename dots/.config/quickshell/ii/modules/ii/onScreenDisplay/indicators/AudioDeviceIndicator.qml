import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property alias glassSurface: card

    implicitWidth: Math.max(240, Math.min(380, row.implicitWidth + 32)) + 2 * Appearance.sizes.elevationMargin
    implicitHeight: card.implicitHeight + 2 * Appearance.sizes.elevationMargin

    StyledRectangularShadow {
        target: card
    }

    GlassSurface {
        id: card
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        radius: 24
        topLeftRadius: !Config.options.bar.bottom ? 12 : 24
        topRightRadius: !Config.options.bar.bottom ? 12 : 24
        bottomLeftRadius: Config.options.bar.bottom ? 12 : 24
        bottomRightRadius: Config.options.bar.bottom ? 12 : 24

        implicitWidth: row.implicitWidth + 28
        implicitHeight: row.implicitHeight + 18

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 12

            MaterialSymbol {
                text: Audio.lastDeviceIcon || "headphones"
                iconSize: 22
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                spacing: 1
                StyledText {
                    text: Audio.lastDeviceTitle || Translation.tr("Audio device")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    visible: text !== ""
                    text: Audio.lastDeviceSubtitle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
            }
        }
    }
}
