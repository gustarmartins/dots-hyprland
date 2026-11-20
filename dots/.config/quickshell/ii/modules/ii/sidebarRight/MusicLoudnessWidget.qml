import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    visible: MusicLoudness.enabled
    implicitHeight: content.implicitHeight + 20
    radius: 14
    color: MusicLoudness.active ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
    component LoudnessButton: Button {
        id: control
        implicitHeight: 36
        padding: 10
        opacity: enabled ? 1 : 0.4
        background: Rectangle {
            radius: 10
            color: control.down || control.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
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
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 6
        ComboBox {
            id: appPicker
            objectName: "musicLoudnessApp"
            Layout.fillWidth: true
            model: MusicLoudness.apps
            textRole: "name"
            valueRole: "id"
            currentIndex: MusicLoudness.apps.findIndex(app => app.id === MusicLoudness.selectedApp)
            displayText: currentIndex < 0 ? "Pick an app · start its audio to list it" : currentText
            enabled: !MusicLoudness.busy
            Accessible.name: "App to adjust"
            onActivated: index => MusicLoudness.selectApp(MusicLoudness.apps[index].id)
            onPressedChanged: if (pressed) MusicLoudness.refresh()
            palette.text: Appearance.m3colors.m3onSurface
            palette.buttonText: Appearance.m3colors.m3onSurface
            palette.base: Appearance.m3colors.m3surfaceContainerHigh
            palette.button: Appearance.m3colors.m3surfaceContainerHigh
            palette.highlight: Appearance.m3colors.m3primary
            contentItem: StyledText {
                text: appPicker.displayText
                textFormat: Text.PlainText
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                leftPadding: 10
                rightPadding: appPicker.indicator.width + 12
            }
            background: Rectangle { radius: 8; color: Appearance.m3colors.m3surfaceContainerHigh; border.color: Appearance.m3colors.m3outlineVariant }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            LoudnessButton {
                objectName: "musicLoudnessMinus"
                text: "−"
                font.pixelSize: 25
                Layout.preferredWidth: 44
                Layout.preferredHeight: 54
                enabled: MusicLoudness.ready && !MusicLoudness.busy && !MusicLoudness.measuring
                Accessible.name: "Make music quieter by " + MusicLoudness.stepDb + " dB"
                onClicked: MusicLoudness.adjust(-1)
                ToolTip.visible: hovered
                ToolTip.text: "−" + MusicLoudness.stepDb + " dB for the selected app"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "Music loudness"; font.pixelSize: 11; color: Appearance.m3colors.m3onSurfaceVariant }
                StyledText {
                    objectName: "musicLoudnessValue"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: (MusicLoudness.db > 0 ? "+" : "") + MusicLoudness.db.toFixed(1) + " dB"
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }
                StyledText {
                    objectName: "musicLoudnessTrack"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: MusicLoudness.title
                    textFormat: Text.PlainText
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            LoudnessButton {
                objectName: "musicLoudnessPlus"
                text: "+"
                font.pixelSize: 25
                Layout.preferredWidth: 44
                Layout.preferredHeight: 54
                enabled: MusicLoudness.ready && !MusicLoudness.busy && !MusicLoudness.measuring
                Accessible.name: "Make music louder by " + MusicLoudness.stepDb + " dB"
                onClicked: MusicLoudness.adjust(1)
                ToolTip.visible: hovered
                ToolTip.text: "+" + MusicLoudness.stepDb + " dB for the selected app"
            }
        }
        StyledText {
            objectName: "musicLoudnessStatus"
            Layout.fillWidth: true
            text: MusicLoudness.error || (MusicLoudness.measuring ? "Measuring 8 seconds of playback…" : (MusicLoudness.autoMatch ? (MusicLoudness.autoMessage || "Auto match ready") : MusicLoudness.message))
            textFormat: Text.PlainText
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: MusicLoudness.error ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            visible: MusicLoudness.ready && !MusicLoudness.matchReady && !MusicLoudness.autoMatch
            text: MusicLoudness.matchMessage
            textFormat: Text.PlainText
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            LoudnessButton {
                objectName: "musicLoudnessMatch"
                text: "Match loudness"
                enabled: MusicLoudness.matchReady && !MusicLoudness.busy && !MusicLoudness.measuring
                Accessible.name: "Measure this song and match its loudness"
                onClicked: MusicLoudness.match()
                ToolTip.visible: hovered
                ToolTip.text: MusicLoudness.matchMessage + ". Target: " + MusicLoudness.targetLufs + " LUFS."
            }
            LoudnessButton {
                objectName: "musicLoudnessReset"
                text: MusicLoudness.measuring ? "Cancel / reset" : "Reset"
                enabled: MusicLoudness.active || MusicLoudness.measuring || MusicLoudness.db !== 0 || MusicLoudness.autoMatch
                onClicked: MusicLoudness.reset()
            }
        }
        CheckBox {
            objectName: "musicLoudnessAutoMatch"
            Layout.alignment: Qt.AlignHCenter
            text: "Auto match loudness"
            checked: MusicLoudness.autoMatch
            enabled: !MusicLoudness.busy || MusicLoudness.autoMatch
            palette.windowText: Appearance.m3colors.m3onSurface
            palette.text: Appearance.m3colors.m3onSurface
            Accessible.name: "Auto match loudness"
            onToggled: MusicLoudness.setAutoMatch(checked)
            ToolTip.visible: hovered
            ToolTip.text: "Check every " + MusicLoudness.autoInterval + " seconds. Small corrections toward " + MusicLoudness.targetLufs + " LUFS. Manual − / + or Reset turns this off."
        }
    }
}
