import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
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
        columnSpacing: 8
        rowSpacing: 4
        Item {
            Layout.preferredWidth: root.expandedSize ? 36 : 28
            Layout.preferredHeight: root.expandedSize ? 38 : 28
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: iconMouse.containsMouse
                    ? (EasyEffects.processing ? root.categoryAccent : Appearance.colors.colLayer2Hover)
                    : (EasyEffects.processing
                        ? ColorUtils.transparentize(root.colText, 0.86)
                        : ColorUtils.transparentize(root.categoryAccent, 0.84))
                border.width: 1
                border.color: EasyEffects.processing
                    ? ColorUtils.transparentize(root.colText, 0.70)
                    : ColorUtils.transparentize(root.categoryAccent, 0.70)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "graphic_eq"
                    iconSize: root.expandedSize ? 22 : 20
                    fill: EasyEffects.processing ? 1 : 0
                    color: iconMouse.containsMouse && EasyEffects.processing
                        ? Appearance.m3colors.m3onPrimary
                        : (EasyEffects.processing ? root.colText : root.categoryAccent)
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
                // Only show the hint after the pointer really moves over the icon, so it
                // doesn't pop up when the sidebar opens under a resting cursor.
                property bool pointerMoved: false
                onContainsMouseChanged: if (!containsMouse) pointerMoved = false
                onPositionChanged: pointerMoved = true
                StyledToolTip {
                    extraVisibleCondition: iconMouse.containsMouse && iconMouse.pointerMoved
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
