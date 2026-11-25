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
    readonly property bool isLight: Appearance.m3colors.darkmode === false
    readonly property color cardBg: isLight ? Appearance.m3colors.m3surfaceContainerLowest : Appearance.m3colors.m3surfaceContainerLow
    readonly property color cardHoverBg: Appearance.m3colors.m3surfaceContainerHigh
    contentWidth: availableWidth
    topPadding: 14
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    ColumnLayout {
        width: Math.min(root.availableWidth - 40, 840)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: summary.implicitHeight + 40
            radius: 24
            color: Appearance.m3colors.m3primaryContainer
            ColumnLayout {
                id: summary
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                spacing: 6
                StyledText {
                    text: "Make it yours"
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onPrimaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Appearance, effects, widgets and workstation tools in one place. Press Ctrl+F anytime to jump straight to a setting."
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                    color: Appearance.m3colors.m3onPrimaryContainer
                    opacity: 0.9
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: (Appearance.m3colors.darkmode ? "Dark mode" : "Light mode")
                        + "  ·  " + (Config.options.appearance.fonts.main || "Default font")
                        + "  ·  " + Quickshell.screens.map(s => s.name).join(" + ")
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onPrimaryContainer
                    opacity: 0.8
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.width > 680 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10
            Repeater {
                model: Catalog.pages.filter(p => !["home", "about"].includes(p.id))
                delegate: AbstractButton {
                    id: destCard
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    padding: 16
                    Accessible.name: modelData.title
                    onClicked: root.navigate(modelData.id)
                    background: Rectangle {
                        radius: 20
                        color: destCard.down ? Appearance.m3colors.m3secondaryContainer
                            : destCard.hovered ? root.cardHoverBg : root.cardBg
                        border.width: destCard.visualFocus ? 2 : 0
                        border.color: Appearance.m3colors.m3primary
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }
                    contentItem: RowLayout {
                        spacing: 14
                        Rectangle {
                            implicitWidth: 42
                            implicitHeight: 42
                            radius: 14
                            color: destCard.hovered ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3secondaryContainer
                            Behavior on color { ColorAnimation { duration: 130 } }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData.icon
                                iconSize: 22
                                color: destCard.hovered ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSecondaryContainer
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.title
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: Appearance.m3colors.m3onSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.description
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Appearance.m3colors.m3onSurfaceVariant
                            }
                        }
                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: 20
                            color: Appearance.m3colors.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
        Item { Layout.preferredHeight: 20 }
    }
}
