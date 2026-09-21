pragma ComponentBehavior: Bound

import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false
    property Region viewportRegion: Region {
        item: root
        intersection: Intersection.Intersect
    }
    // ListView keeps only delegates near the viewport. Each delegate owns its
    // moving card region, so gaps and rounded corners stay click-through.
    property Region surfaceRegion: Region {
        regions: [...root.contentItem.children
            .filter(item => item.surfaceRegion !== undefined && item.surfaceRegion !== null)
            .map(item => item.surfaceRegion), root.viewportRegion]
    }
    Connections {
        target: root
        function onContentYChanged() { root.surfaceRegion.changed(); }
        function onXChanged() { root.surfaceRegion.changed(); }
        function onYChanged() { root.surfaceRegion.changed(); }
    }

    spacing: 12
    cacheBuffer: 160

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: popup ? 
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]
    }
}
