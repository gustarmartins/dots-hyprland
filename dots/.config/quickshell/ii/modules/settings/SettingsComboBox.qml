import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ComboBox {
    id: control
    implicitHeight: 40
    leftPadding: 12
    rightPadding: 34
    opacity: enabled ? 1 : 0.45

    readonly property color colSurface: Appearance.m3colors.m3surfaceContainer ?? Appearance.m3colors.m3surfaceContainerLow
    readonly property color colSurfaceHigh: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colSurfaceHighest: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colOnSurface: Appearance.m3colors.m3onSurface
    readonly property color colOnSurfaceVariant: Appearance.m3colors.m3onSurfaceVariant ?? Appearance.m3colors.m3onSurface
    readonly property color colPrimary: Appearance.m3colors.m3primary
    readonly property color colOutline: Appearance.m3colors.m3outline ?? Appearance.m3colors.m3outlineVariant
    readonly property color colOutlineVariant: Appearance.m3colors.m3outlineVariant
    readonly property color colSelectedBg: Appearance.m3colors.m3secondaryContainer
    readonly property color colSelectedFg: Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onSurface
    readonly property color colShadow: Appearance.m3colors.m3shadow ?? "#000000"

    background: Rectangle {
        radius: 10
        color: control.down ? control.colSurfaceHighest : control.hovered ? control.colSurfaceHighest : control.colSurfaceHigh
        border.width: (control.activeFocus || control.popup.visible) ? 2 : 1
        border.color: (control.activeFocus || control.popup.visible) ? control.colPrimary
            : control.hovered ? control.colOutline : control.colOutlineVariant
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    contentItem: StyledText {
        leftPadding: 0
        rightPadding: 0
        text: control.displayText
        textFormat: Text.PlainText
        font: control.font
        color: control.colOnSurface
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: MaterialSymbol {
        x: control.width - width - 8
        y: (control.height - height) / 2
        text: "expand_more"
        iconSize: 20
        color: (control.activeFocus || control.popup.visible) ? control.colPrimary : control.colOnSurfaceVariant
        rotation: control.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    delegate: ItemDelegate {
        id: itemDelegate
        required property var model
        required property int index

        readonly property bool isCurrent: control.currentIndex === index
        readonly property bool isActive: highlighted || hovered
        readonly property string itemLabel: {
            const raw = control.textRole ? model[control.textRole] : model.modelData;
            if (raw !== undefined && raw !== null) return String(raw);
            const fallback = model[control.textRole];
            return fallback !== undefined && fallback !== null ? String(fallback) : "";
        }

        width: ListView.view ? ListView.view.width : Math.max(0, control.width - 12)
        implicitHeight: Math.max(38, itemRow.implicitHeight + 14)
        leftPadding: 10
        rightPadding: 10
        topPadding: 7
        bottomPadding: 7
        text: itemLabel
        highlighted: control.highlightedIndex === index
        hoverEnabled: control.hoverEnabled

        background: Rectangle {
            radius: 8
            color: {
                if (itemDelegate.isCurrent) {
                    if (itemDelegate.down) return Qt.tint(control.colSelectedBg, Qt.alpha(control.colSelectedFg, 0.14));
                    if (itemDelegate.isActive) return Qt.tint(control.colSelectedBg, Qt.alpha(control.colSelectedFg, 0.08));
                    return control.colSelectedBg;
                }
                if (itemDelegate.down) return Qt.tint(control.colSurfaceHighest, Qt.alpha(control.colOnSurface, 0.12));
                if (itemDelegate.isActive) return control.colSurfaceHighest;
                return "transparent";
            }
            border.width: itemDelegate.isActive && !itemDelegate.isCurrent ? 1 : 0
            border.color: Qt.alpha(control.colOutlineVariant, 0.8)
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        contentItem: RowLayout {
            id: itemRow
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: itemDelegate.itemLabel
                textFormat: Text.PlainText
                font.family: control.font.family
                font.pixelSize: control.font.pixelSize
                font.weight: itemDelegate.isCurrent ? Font.DemiBold : Font.Normal
                color: itemDelegate.isCurrent ? control.colSelectedFg : control.colOnSurface
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            MaterialSymbol {
                visible: itemDelegate.isCurrent
                text: "check"
                iconSize: 18
                color: control.colSelectedFg
            }
        }
    }

    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(popupList.contentHeight + topPadding + bottomPadding, 320)
        padding: 6
        topMargin: 6
        bottomMargin: 6
        font: control.font

        contentItem: ListView {
            id: popupList
            clip: true
            implicitHeight: contentHeight
            spacing: 2
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Item {
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                anchors.topMargin: 0
                anchors.bottomMargin: -4
                radius: 16
                color: Qt.alpha(control.colShadow, 0.12)
            }
            Rectangle {
                anchors.fill: parent
                radius: 14
                color: control.colSurface
                border.width: 1
                border.color: control.colOutlineVariant
            }
        }
    }
}
