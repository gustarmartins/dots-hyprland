import qs.modules.common.models.quickToggles
import QtQuick
import QtQuick.Controls
import qs.modules.ii.sidebarRight.quickToggles
import qs.services
import qs.modules.common
import qs.modules.common.widgets

AndroidQuickToggleButton {
    id: root
    toggleModel: VrrToggle {}
    mainAction: () => controls.open()
    altAction: () => controls.open()
    tooltipText: "Select a display and VRR mode"
    readonly property bool panelSize: width >= 280 && height >= 218
    mouseArea.enabled: !panelSize || editMode
    contentItem: Loader {
        sourceComponent: root.panelSize ? fullPanel : compactPanel
    }
    Component { id: fullPanel; VrrPanel { enabled: !root.editMode } }
    Component {
        id: compactPanel
        Column {
            spacing: 4
            anchors.centerIn: parent
            MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; text: "sync"; iconSize: 24; color: root.colText }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "VRR"; color: root.colText; font.pixelSize: 12 }
        }
    }
    Popup {
        id: controls
        parent: Overlay.overlay
        width: Math.min(480, parent ? parent.width - 24 : 480)
        height: 250
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? Math.max(12, (parent.height - height) / 2) : 0
        padding: 18
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 22; color: Appearance.m3colors.m3surfaceContainerHigh; border.width: 1; border.color: Appearance.m3colors.m3outlineVariant }
        contentItem: VrrPanel { visible: controls.visible }
    }
}
