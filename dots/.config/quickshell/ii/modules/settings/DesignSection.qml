import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    property string title: ""
    property string subtitle: ""
    property string icon: "tune"
    property string sectionKey: ""
    property string detailsLabel: "Fine-tune"
    property bool expanded: false
    property bool accented: false
    default property alias contentData: core.data
    property alias detailsData: details.data
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 28
    radius: 22
    color: accented ? Appearance.m3colors.m3surfaceContainer : Appearance.m3colors.m3surfaceContainerLow
    border.width: 1
    border.color: accented ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
    Behavior on color { ColorAnimation { duration: 180 } }
    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: 13
                color: Appearance.m3colors.m3secondaryContainer
                MaterialSymbol { anchors.centerIn: parent; text: root.icon; iconSize: 22; color: Appearance.m3colors.m3onSecondaryContainer }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText { Layout.fillWidth: true; text: root.title; font.pixelSize: 18; font.weight: Font.Medium; wrapMode: Text.WordWrap }
                StyledText { Layout.fillWidth: true; visible: text.length > 0; text: root.subtitle; font.pixelSize: 12; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
            }
        }
        ColumnLayout { id: core; Layout.fillWidth: true; spacing: 8 }
        SettingsButton {
            objectName: "designExpand:" + root.sectionKey
            Layout.fillWidth: true
            visible: details.children.length > 0
            text: (root.expanded ? "▾  " : "▸  ") + root.detailsLabel
            Accessible.name: root.detailsLabel
            Accessible.description: root.expanded ? "Expanded" : "Collapsed"
            onClicked: root.expanded = !root.expanded
        }
        ColumnLayout { id: details; Layout.fillWidth: true; spacing: 10; visible: root.expanded }
    }
}
