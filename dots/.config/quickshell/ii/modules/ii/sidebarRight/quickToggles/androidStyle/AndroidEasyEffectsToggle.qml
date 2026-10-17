import qs
import qs.modules.common
import qs.services
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

AndroidQuickToggleButton {
    id: root
    enabled: (available && !EasyEffects.busy) || editMode
    toggleModel: EasyEffectsToggle {}
    // The icon owns processing; clicking the body opens the app at any tile size.
    mainAction: toggleModel.altAction
    tooltipText: Translation.tr("Open EasyEffects") + (EasyEffects.preset ? " · " + EasyEffects.preset : "")

    contentItem: GridLayout {
        columns: root.expandedSize ? 2 : 1
        columnSpacing: 10
        rowSpacing: 4
        Item {
            Layout.preferredWidth: root.expandedSize ? 40 : 28
            Layout.preferredHeight: root.expandedSize ? 40 : 28
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Rectangle {
                anchors.fill: parent
                radius: 14
                color: iconMouse.containsMouse
                    ? (EasyEffects.processing ? Appearance.m3colors.m3primary : Appearance.colors.colLayer2Hover)
                    : (EasyEffects.processing ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceContainerHighest)
                border.width: 1
                border.color: EasyEffects.processing ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "graphic_eq"
                    iconSize: root.expandedSize ? 24 : 20
                    fill: EasyEffects.processing ? 1 : 0
                    color: iconMouse.containsMouse && EasyEffects.processing
                        ? Appearance.m3colors.m3onPrimary : root.colText
                }
            }
            MouseArea {
                id: iconMouse
                objectName: "easyEffectsProcessingIcon"
                anchors.fill: parent
                enabled: !root.editMode && !EasyEffects.busy
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: EasyEffects.toggle()
                StyledToolTip {
                    text: EasyEffects.processing ? Translation.tr("Turn effects off") : Translation.tr("Turn effects on")
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3
            StyledText {
                Layout.fillWidth: true
                text: root.expandedSize ? root.name : root.statusText
                color: root.colText
                font.pixelSize: root.expandedSize ? 13 : 11
                font.weight: Font.Medium
                horizontalAlignment: root.expandedSize ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.expandedSize
                text: root.statusText
                color: EasyEffects.error ? Appearance.m3colors.m3error : root.colText
                font.pixelSize: 11
                opacity: 0.8
                horizontalAlignment: root.expandedSize ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.expandedSize && EasyEffects.preset.length > 0
                text: EasyEffects.preset
                color: root.colText
                font.pixelSize: 10
                opacity: 0.65
                elide: Text.ElideRight
            }
        }
    }
}
