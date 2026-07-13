import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        readonly property bool forceMonitorEnabled: Config?.options?.notifications?.forceMonitor?.enable === true
        readonly property string targetScreenName: forceMonitorEnabled
            ? (Config?.options?.notifications?.forceMonitor?.name ?? "")
            : HyprlandData.preferredNotificationMonitorName(Hyprland.focusedMonitor?.name ?? "")
        screen: Quickshell.screens.find(s => s.name === targetScreenName) ?? null
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
            && !HyprlandData.monitorHasFullscreen(targetScreenName)

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        anchors {
            top: true
            right: true
            bottom: true
        }

        mask: Region {
            item: listview.contentItem
        }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth

        NotificationListView {
            id: listview
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
                rightMargin: 4
                topMargin: 4
            }
            implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
            popup: true
        }
    }
}
