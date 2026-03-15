import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property string iconName
    required property double percentage
    property int warningThreshold: 100
    implicitHeight: resourceColumn.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    property bool warning: percentage * 100 >= warningThreshold

    ColumnLayout {
        id: resourceColumn
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 1

        ClippedFilledCircularProgress {
            id: resourceProgress
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 22
            lineWidth: 3
            value: percentage
            enableAnimation: false
            colPrimary: root.warning ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
            accountForLightBleeding: !root.warning

            MaterialSymbol {
                font.weight: Font.Medium
                fill: 1
                text: root.iconName
                iconSize: 15
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Math.round(root.percentage * 100).toString()
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.warning ? Appearance.colors.colError : Appearance.colors.colOnLayer1
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        enabled: root.visible
    }
}
