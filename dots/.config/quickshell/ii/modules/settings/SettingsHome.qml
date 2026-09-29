import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "SettingsCatalog.js" as Catalog

ScrollView {
    id: root
    signal navigate(string page)
    contentWidth: availableWidth
    clip: true
    ColumnLayout {
        width: root.availableWidth
        spacing: 18
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            implicitHeight: summary.implicitHeight + 40
            radius: 22
            color: Appearance.m3colors.m3secondaryContainer
            ColumnLayout {
                id: summary
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 8
                StyledText { text: "Make it yours."; font.pixelSize: 30; font.weight: Font.Medium; color: Appearance.m3colors.m3onSecondaryContainer }
                StyledText { Layout.fillWidth: true; text: "Your fork’s settings, organized around what you use. Search across every page or start with a part of your desktop."; wrapMode: Text.WordWrap; font.pixelSize: 14; color: Appearance.m3colors.m3onSecondaryContainer }
                StyledText {
                    Layout.fillWidth: true
                    text: (Config.options.appearance.fonts.main || "Default font") + "  ·  " + Quickshell.screens.map(s => s.name).join(" + ")
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            columns: root.width > 700 ? 2 : 1
            columnSpacing: 12
            rowSpacing: 12
            Repeater {
                model: Catalog.pages.filter(p => !["home", "about"].includes(p.id))
                delegate: Button {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    padding: 16
                    Accessible.name: modelData.title
                    onClicked: root.navigate(modelData.id)
                    background: Rectangle { radius: 18; color: parent.hovered ? Appearance.m3colors.m3surfaceContainerHigh : Appearance.m3colors.m3surfaceContainerLow; border.width: 1; border.color: Appearance.m3colors.m3outlineVariant }
                    contentItem: ColumnLayout {
                        spacing: 6
                        RowLayout {
                            MaterialSymbol { text: modelData.icon; iconSize: 22; color: Appearance.m3colors.m3primary }
                            StyledText { Layout.fillWidth: true; text: modelData.title; font.pixelSize: 16; font.weight: Font.Medium; wrapMode: Text.WordWrap }
                            StyledText { text: "›"; font.pixelSize: 22 }
                        }
                        StyledText { Layout.fillWidth: true; text: modelData.description; font.pixelSize: 12; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
                    }
                }
            }
        }
        Item { Layout.preferredHeight: 24 }
    }
}
