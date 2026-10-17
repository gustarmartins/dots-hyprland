import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    required property var processData
    property bool busy: false
    property real totalRam: 0
    property color warningColor: Appearance.m3colors.darkmode ? "#edc274" : "#805000"
    signal lockRequested(var process)
    signal releaseRequested(var process)
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 24
    radius: 14
    color: Appearance.m3colors.m3surfaceContainerLow
    border.color: processData.large_rss ? warningColor : Appearance.m3colors.m3outlineVariant
    border.width: 1
    function bytes(n) {
        if (n === null || n === undefined) return "Unknown";
        return n >= 1073741824 ? (n / 1073741824).toFixed(2) + " GiB" : (n / 1048576).toFixed(1) + " MiB";
    }
    ColumnLayout {
        id: body
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            StyledText {
                Layout.fillWidth: true
                text: root.processData.name
                textFormat: Text.PlainText
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                text: "PID  " + root.processData.pid
                font.family: Appearance.font.family.monospace
                font.pixelSize: 12
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            SettingsButton {
                objectName: "memoryAction:" + root.processData.pid
                text: root.processData.lock_id ? "Release…" : root.processData.protected ? "Protected" : "Lock…"
                implicitHeight: 34
                enabled: !root.busy && (!!root.processData.lock_id || root.processData.can_lock === true)
                Accessible.name: (root.processData.lock_id ? "Release group for " : "Lock group for ") + root.processData.name + ", PID " + root.processData.pid
                onClicked: root.processData.lock_id ? root.releaseRequested(root.processData) : root.lockRequested(root.processData)
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 18
            StyledText {
                text: "RSS  " + root.bytes(root.processData.rss) + (root.totalRam > 0 && root.processData.rss != null ? "  ·  " + (100 * root.processData.rss / root.totalRam).toFixed(1) + "%" : "")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.processData.large_rss ? root.warningColor : Appearance.m3colors.m3primary
            }
            StyledText {
                text: "Swap  " + root.bytes(root.processData.swap)
                font.pixelSize: 13
                color: root.processData.swap > 0 ? root.warningColor : Appearance.m3colors.m3onSurfaceVariant
            }
            StyledText {
                text: root.processData.large_rss ? "Large RSS" : root.processData.protected ? "Protected" : root.processData.protected === false ? "Can swap" : "Status unknown"
                font.pixelSize: 12
                font.weight: Font.Medium
                color: root.processData.large_rss ? root.warningColor : root.processData.protected ? Appearance.m3colors.m3success : Appearance.m3colors.m3onSurfaceVariant
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: (root.processData.group_count ? "Group of " + root.processData.group_count + "  ·  " : "")
                  + (root.processData.age_days != null ? "Locked " + (root.processData.age_days < 1 ? "today" : root.processData.age_days.toFixed(1) + " days ago") + "  ·  " : "")
                  + (root.processData.unit || root.processData.group || "")
            textFormat: Text.PlainText
            font.pixelSize: 11
            color: Appearance.m3colors.m3onSurfaceVariant
            elide: Text.ElideMiddle
            ToolTip.visible: groupHover.hovered
            ToolTip.text: text
            HoverHandler { id: groupHover }
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
