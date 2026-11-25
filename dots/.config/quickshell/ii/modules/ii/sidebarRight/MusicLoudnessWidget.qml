import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    visible: MusicLoudness.enabled
    readonly property bool compact: width < 440
    implicitHeight: content.implicitHeight + 14
    radius: 14
    color: MusicLoudness.active ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colPrimaryText: MusicLoudness.active
        ? (Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onSurface)
        : Appearance.m3colors.m3onSurface
    readonly property color colSecondaryText: MusicLoudness.active
        ? Qt.alpha(Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onSurface, 0.8)
        : Appearance.m3colors.m3onSurfaceVariant
    readonly property color colMenuSurface: Appearance.m3colors.m3surfaceContainer ?? Appearance.m3colors.m3surfaceContainerLow
    readonly property color colSelectedFg: Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onSurface
    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

    component LoudnessButton: Button {
        id: control
        implicitHeight: 26
        topPadding: 3
        bottomPadding: 3
        leftPadding: 10
        rightPadding: 10
        opacity: enabled ? 1 : 0.4
        background: Rectangle {
            radius: 10
            color: control.down || control.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerLow
            border.width: control.activeFocus ? 2 : 1
            border.color: control.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
        }
        contentItem: StyledText {
            text: control.text
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Appearance.m3colors.m3onSurface
        }
    }

    GridLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 10
            rightMargin: 10
            topMargin: 7
        }
        columns: root.compact ? 1 : 2
        columnSpacing: 8
        rowSpacing: 5

        ComboBox {
            id: appPicker
            objectName: "musicLoudnessApp"
            Layout.fillWidth: root.compact
            Layout.preferredWidth: root.compact ? -1 : 136
            implicitHeight: 30
            model: MusicLoudness.apps
            textRole: "name"
            valueRole: "id"
            currentIndex: MusicLoudness.apps.findIndex(app => app.id === MusicLoudness.selectedApp)
            displayText: currentIndex < 0 ? "Pick app" : currentText
            enabled: !MusicLoudness.busy
            Accessible.name: "App to adjust"
            onActivated: index => MusicLoudness.selectApp(MusicLoudness.apps[index].id)
            onPressedChanged: if (pressed) MusicLoudness.refresh()
            palette.text: Appearance.m3colors.m3onSurface
            palette.buttonText: Appearance.m3colors.m3onSurface
            palette.base: Appearance.m3colors.m3surfaceContainerLow
            palette.button: Appearance.m3colors.m3surfaceContainerLow
            palette.highlight: Appearance.m3colors.m3primary
            indicator: MaterialSymbol {
                x: appPicker.width - width - 6
                y: (appPicker.height - height) / 2
                text: "expand_more"
                iconSize: 16
                color: (appPicker.activeFocus || appPicker.popup.visible) ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurfaceVariant
                rotation: appPicker.popup.visible ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
            contentItem: StyledText {
                text: appPicker.displayText
                textFormat: Text.PlainText
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                leftPadding: 10
                rightPadding: 24
                color: Appearance.m3colors.m3onSurface
            }
            background: Rectangle {
                radius: 10
                color: appPicker.hovered || appPicker.down ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerLow
                border.width: (appPicker.activeFocus || appPicker.popup.visible) ? 2 : 1
                border.color: (appPicker.activeFocus || appPicker.popup.visible) ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
            }
            delegate: ItemDelegate {
                id: appItem
                required property var model
                required property int index
                readonly property bool isCurrent: appPicker.currentIndex === index
                readonly property bool isActive: highlighted || hovered
                width: ListView.view ? ListView.view.width : Math.max(0, appPicker.width - 12)
                implicitHeight: 34
                leftPadding: 10
                rightPadding: 10
                text: String(model[appPicker.textRole] ?? model.modelData ?? "")
                highlighted: appPicker.highlightedIndex === index
                hoverEnabled: appPicker.hoverEnabled
                background: Rectangle {
                    radius: 8
                    color: appItem.isCurrent
                        ? (appItem.isActive ? Qt.tint(Appearance.m3colors.m3secondaryContainer, Qt.alpha(root.colSelectedFg, 0.08)) : Appearance.m3colors.m3secondaryContainer)
                        : appItem.isActive ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
                }
                contentItem: StyledText {
                    text: appItem.text
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.weight: appItem.isCurrent ? Font.DemiBold : Font.Normal
                    color: appItem.isCurrent ? root.colSelectedFg : Appearance.m3colors.m3onSurface
                }
            }
            popup: Popup {
                y: appPicker.height + 4
                width: Math.max(appPicker.width, 160)
                implicitHeight: Math.min(appPickerList.contentHeight + topPadding + bottomPadding, 240)
                padding: 6
                contentItem: ListView {
                    id: appPickerList
                    clip: true
                    implicitHeight: contentHeight
                    spacing: 2
                    model: appPicker.popup.visible ? appPicker.delegateModel : null
                    currentIndex: appPicker.highlightedIndex
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds
                }
                background: Rectangle {
                    radius: 12
                    color: root.colMenuSurface
                    border.width: 1
                    border.color: Appearance.m3colors.m3outlineVariant
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    objectName: "musicLoudnessTrack"
                    Layout.fillWidth: true
                    text: MusicLoudness.title
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: root.colPrimaryText
                }
                StyledText {
                    objectName: "musicLoudnessStatus"
                    Layout.fillWidth: true
                    text: MusicLoudness.error || (MusicLoudness.measuring ? "Measuring 8 seconds of playback…" : (MusicLoudness.autoMatch ? (MusicLoudness.autoMessage || "Auto match ready") : MusicLoudness.message))
                    textFormat: Text.PlainText
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: MusicLoudness.error ? Appearance.m3colors.m3error : root.colSecondaryText
                }
            }

            RowLayout {
                spacing: 4
                LoudnessButton {
                    objectName: "musicLoudnessMinus"
                    text: "−"
                    font.pixelSize: 18
                    leftPadding: 0
                    rightPadding: 0
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    enabled: MusicLoudness.ready && !MusicLoudness.busy && !MusicLoudness.measuring
                    Accessible.name: "Make music quieter by " + MusicLoudness.stepDb + " dB"
                    onClicked: MusicLoudness.adjust(-1)
                    ToolTip.visible: hovered
                    ToolTip.text: "−" + MusicLoudness.stepDb + " dB for the selected app"
                }
                StyledText {
                    objectName: "musicLoudnessValue"
                    Layout.preferredWidth: 54
                    horizontalAlignment: Text.AlignHCenter
                    text: (MusicLoudness.db > 0 ? "+" : "") + MusicLoudness.db.toFixed(1) + " dB"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: root.colPrimaryText
                }
                LoudnessButton {
                    objectName: "musicLoudnessPlus"
                    text: "+"
                    font.pixelSize: 18
                    leftPadding: 0
                    rightPadding: 0
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    enabled: MusicLoudness.ready && !MusicLoudness.busy && !MusicLoudness.measuring
                    Accessible.name: "Make music louder by " + MusicLoudness.stepDb + " dB"
                    onClicked: MusicLoudness.adjust(1)
                    ToolTip.visible: hovered
                    ToolTip.text: "+" + MusicLoudness.stepDb + " dB for the selected app"
                }
            }
        }

        GridLayout {
            Layout.columnSpan: root.compact ? 1 : 2
            Layout.fillWidth: true
            columns: root.compact ? 1 : 2
            columnSpacing: 8
            rowSpacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                CheckBox {
                    id: autoBox
                    objectName: "musicLoudnessAutoMatch"
                    text: "Auto match"
                    font.pixelSize: 11
                    implicitHeight: 26
                    padding: 0
                    spacing: 6
                    checked: MusicLoudness.autoMatch
                    enabled: !MusicLoudness.busy || MusicLoudness.autoMatch
                    Accessible.name: "Auto match loudness"
                    onToggled: MusicLoudness.setAutoMatch(checked)
                    ToolTip.visible: hovered
                    ToolTip.text: "Check every " + MusicLoudness.autoInterval + " seconds. Small corrections toward " + MusicLoudness.targetLufs + " LUFS. Manual − / + or Reset turns this off."
                    indicator: Rectangle {
                        implicitWidth: 16
                        implicitHeight: 16
                        x: autoBox.leftPadding
                        y: (autoBox.height - height) / 2
                        radius: 4
                        color: autoBox.checked ? Appearance.m3colors.m3primary : "transparent"
                        border.width: autoBox.checked ? 0 : 1.5
                        border.color: autoBox.hovered ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                        Behavior on color { ColorAnimation { duration: 140 } }
                        StyledText {
                            anchors.centerIn: parent
                            visible: autoBox.checked
                            text: "✓"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                    contentItem: StyledText {
                        text: autoBox.text
                        font: autoBox.font
                        color: root.colPrimaryText
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: autoBox.indicator.width + autoBox.spacing
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: MusicLoudness.ready && !MusicLoudness.matchReady && !MusicLoudness.autoMatch
                    text: MusicLoudness.matchMessage
                    textFormat: Text.PlainText
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: root.colSecondaryText
                }
            }

            RowLayout {
                Layout.fillWidth: !root.compact
                Layout.alignment: root.compact ? Qt.AlignLeft : Qt.AlignRight
                spacing: 6
                Item { Layout.fillWidth: true; visible: !root.compact }
                LoudnessButton {
                    objectName: "musicLoudnessMatch"
                    text: "Match loudness"
                    font.pixelSize: 11
                    enabled: MusicLoudness.matchReady && !MusicLoudness.busy && !MusicLoudness.measuring
                    Accessible.name: "Measure this song and match its loudness"
                    onClicked: MusicLoudness.match()
                    ToolTip.visible: hovered
                    ToolTip.text: MusicLoudness.matchMessage + ". Target: " + MusicLoudness.targetLufs + " LUFS."
                }
                LoudnessButton {
                    objectName: "musicLoudnessReset"
                    text: MusicLoudness.measuring ? "Cancel / reset" : "Reset"
                    font.pixelSize: 11
                    enabled: MusicLoudness.active || MusicLoudness.measuring || MusicLoudness.db !== 0 || MusicLoudness.autoMatch
                    onClicked: MusicLoudness.reset()
                }
            }
        }
    }
}
