import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.quickToggles
import QtQuick
import QtQuick.Controls

AndroidQuickToggleButton {
    id: root
    toggleModel: IdleInhibitorToggle {}
    mainAction: () => controls.open()
    altAction: () => Idle.toggleInhibit()
    tooltipText: "Configure auto-sleep (plugged in & battery) · Right-click to toggle Keep awake"
    readonly property bool panelSize: width >= 280 && height >= 218
    mouseArea.enabled: !panelSize || editMode
    contentItem: Loader {
        sourceComponent: root.panelSize ? fullPanel : compactPanel
    }
    Component {
        id: fullPanel
        SleepPanel { enabled: !root.editMode }
    }
    Component {
        id: compactPanel
        Column {
            spacing: 4
            anchors.centerIn: parent
            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "coffee"
                iconSize: 24
                color: root.colText
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.expandedSize ? "Keep awake" : (Idle.inhibit ? "Awake" : "Sleep")
                color: root.colText
                font.pixelSize: 12
            }
            Text {
                visible: root.expandedSize
                anchors.horizontalCenter: parent.horizontalCenter
                text: Idle.inhibit ? "Always awake" : ((Idle.onAc ? "AC · " : "Bat · ") + Idle.formatMinutes(Idle.effectiveSleepMinutes))
                color: root.colText
                opacity: 0.8
                font.pixelSize: 10
            }
        }
    }
    Popup {
        id: controls
        parent: Overlay.overlay
        width: Math.min(480, parent ? parent.width - 24 : 480)
        height: Idle.hasBattery ? 330 : 276
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? Math.max(12, (parent.height - height) / 2) : 0
        padding: 18
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 22
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.m3colors.m3outlineVariant
        }
        contentItem: SleepPanel { visible: controls.visible }
    }
}
