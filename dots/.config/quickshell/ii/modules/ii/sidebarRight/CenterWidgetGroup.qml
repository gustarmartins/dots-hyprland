import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarRight.notifications
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    signal openQuickSettings()
    radius: 24
    color: Appearance.m3colors.m3surfaceContainerLow

    NotificationList {
        anchors.fill: parent
        anchors.margins: 8
        onOpenQuickSettings: root.openQuickSettings()
    }
}
