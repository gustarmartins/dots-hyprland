import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Material 3 Expressive section:
// - Top-level (nested: false): clean primary eyebrow heading above a borderless tonal card.
// - Nested (nested: true): flat inline disclosure row with hairline separator — zero nested boxes!
ColumnLayout {
    id: root
    property string title: ""
    property string subtitle: ""
    property string icon: "tune"
    property string sectionKey: ""
    property string detailsLabel: "More options"
    property string detailsSummary: ""
    property bool expanded: false
    property bool accented: false
    property bool nested: false
    default property alias contentData: core.data
    property alias detailsData: details.data

    readonly property bool isLight: Appearance.m3colors.darkmode === false
    readonly property color cardColor: isLight
        ? (Appearance.m3colors.m3surfaceContainerLowest ?? Appearance.m3colors.m3surfaceContainerLow)
        : Appearance.m3colors.m3surfaceContainerLow

    Layout.fillWidth: true
    spacing: nested ? 0 : 8

    // Top-level Material 3 Expressive category header (outside the card)
    RowLayout {
        visible: !root.nested && root.title.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        spacing: 8
        MaterialSymbol {
            text: root.icon
            iconSize: 18
            color: Appearance.m3colors.m3primary
        }
        StyledText {
            text: root.title
            textFormat: Text.PlainText
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Appearance.m3colors.m3primary
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: "·  " + root.subtitle
            textFormat: Text.PlainText
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
            elide: Text.ElideRight
        }
    }

    // Top-level borderless tonal card OR transparent flat container when nested.
    // Exposes `expanded` directly so `expandTrigger.parent.parent.expanded` stays valid.
    Rectangle {
        id: surface
        readonly property bool expanded: root.expanded
        Layout.fillWidth: true
        implicitHeight: surfaceCol.implicitHeight + (root.nested ? 0 : 12)
        radius: root.nested ? 0 : 20
        color: root.nested ? "transparent" : root.cardColor
        border.width: 0

        ColumnLayout {
            id: surfaceCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: root.nested ? 0 : 8
                rightMargin: root.nested ? 0 : 8
                topMargin: root.nested ? 0 : 6
            }
            spacing: 2

            Rectangle {
                visible: root.nested
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.45)
            }

            ColumnLayout {
                id: core
                visible: children.length > 0
                Layout.fillWidth: true
                spacing: 2
            }

            Rectangle {
                visible: !root.nested && core.children.length > 0 && details.children.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.topMargin: 4
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.4)
            }

            AbstractButton {
                id: expandTrigger
                objectName: "designExpand:" + root.sectionKey
                Layout.fillWidth: true
                visible: details.children.length > 0
                implicitHeight: Math.max(46, triggerRow.implicitHeight + 16)
                Accessible.name: root.nested ? root.title : root.detailsLabel
                Accessible.description: root.expanded ? "Expanded" : "Collapsed"
                onClicked: root.expanded = !root.expanded

                background: Rectangle {
                    radius: 12
                    color: expandTrigger.down
                        ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.10)
                        : expandTrigger.hovered
                            ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.05)
                            : "transparent"
                    border.width: expandTrigger.visualFocus ? 2 : 0
                    border.color: Appearance.m3colors.m3primary
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                contentItem: RowLayout {
                    id: triggerRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                    spacing: 12
                    Rectangle {
                        visible: root.nested
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: 10
                        color: root.expanded ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: 140 } }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.icon
                            iconSize: 18
                            color: root.expanded ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: root.nested ? root.title : root.detailsLabel
                            textFormat: Text.PlainText
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.nested ? (root.detailsSummary || root.subtitle) : root.detailsSummary
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            color: Appearance.m3colors.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                    MaterialSymbol {
                        text: "expand_more"
                        iconSize: 22
                        color: root.expanded ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurfaceVariant
                        rotation: root.expanded ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                }
            }

            ColumnLayout {
                id: details
                Layout.fillWidth: true
                Layout.leftMargin: root.nested ? 10 : 0
                Layout.rightMargin: 0
                Layout.topMargin: 2
                Layout.bottomMargin: 4
                spacing: 2
                visible: root.expanded && details.children.length > 0
            }
        }
    }
}
