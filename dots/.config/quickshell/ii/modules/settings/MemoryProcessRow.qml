import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    required property var processData
    property bool busy: false
    property bool selected: false
    property real totalRam: 0
    property color warningColor: Appearance.m3colors.darkmode ? "#edc274" : "#805000"
    signal lockRequested(var process)
    signal releaseRequested(var process)
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 16
    radius: 10
    color: selected ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainer
    border.color: selected ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
    border.width: selected ? 2 : 1
    readonly property color primaryTextColor: selected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
    readonly property color secondaryTextColor: selected ? Qt.alpha(Appearance.m3colors.m3onSecondaryContainer, 0.8) : Appearance.m3colors.m3onSurfaceVariant
    function bytes(n) {
        if (n === null || n === undefined) return "Unknown";
        return n >= 1073741824 ? (n / 1073741824).toFixed(2) + " GiB" : (n / 1048576).toFixed(0) + " MiB";
    }
    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.processData.name
                    textFormat: Text.PlainText
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: root.primaryTextColor
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "PID " + root.processData.pid
                          + (root.processData.group_count > 1 ? "  ·  " + root.processData.group_count + " in group" : "")
                          + (root.processData.protected ? "  ·  Protected" : "")
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    color: root.secondaryTextColor
                    elide: Text.ElideRight
                    ToolTip.visible: detailsHover.hovered
                    ToolTip.text: (root.processData.unit || root.processData.group || "")
                                  + (root.processData.age_days != null ? " · Locked " + root.processData.age_days.toFixed(1) + " days" : "")
                    HoverHandler { id: detailsHover }
                }
            }
            ColumnLayout {
                Layout.preferredWidth: root.width < 500 ? 112 : 156
                Layout.minimumWidth: 105
                Layout.maximumWidth: root.width < 500 ? 112 : 156
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.bytes(root.processData.rss) + " RAM"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: root.processData.large_rss ? root.warningColor : root.primaryTextColor
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.bytes(root.processData.swap) + " swap"
                    font.pixelSize: 12
                    color: root.processData.swap > 0 ? root.warningColor : root.secondaryTextColor
                    elide: Text.ElideRight
                }
            }
            MemoryActionButton {
                objectName: "memoryAction:" + root.processData.pid
                text: root.selected ? "Undo" : root.processData.lock_id ? "Release" : root.processData.protected ? "Protected" : "Protect"
                prominent: !root.selected && !root.processData.lock_id && !root.processData.protected && root.processData.can_lock === true
                implicitHeight: 36
                enabled: !root.busy && (root.selected || !!root.processData.lock_id || (!root.processData.protected && root.processData.can_lock === true))
                Accessible.name: (root.selected ? "Undo selection for " : root.processData.lock_id ? "Select release for " : "Select protection for ") + root.processData.name + ", PID " + root.processData.pid
                onClicked: root.processData.lock_id ? root.releaseRequested(root.processData) : root.lockRequested(root.processData)
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: !!root.processData.reason
            text: root.processData.reason || ""
            textFormat: Text.PlainText
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3onSurfaceVariant
        }
    }
}
