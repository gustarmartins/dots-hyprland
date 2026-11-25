import QtQuick
import "SettingsCatalog.js" as Catalog
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    spacing: 10
    Component.onCompleted: MusicLoudness.refresh()
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "Music loudness"; font.pixelSize: 20; font.weight: Font.Medium }
        SettingsSwitch {
            objectName: "musicLoudnessMaster"
            checked: MusicLoudness.enabled
            Accessible.name: "Music loudness controls"
            onToggled: MusicLoudness.setEnabled(checked)
        }
    }
    StyledText { Layout.fillWidth: true; text: "Pick one app, then use − / + below Eden boost. Extra gain applies only to that app before your existing effects. EQ, mid/side and limiter settings stay intact. Switching apps or turning this off removes the extra gain."; wrapMode: Text.WordWrap }
    ColumnLayout {
        objectName: "musicLoudnessSettings"
        visible: MusicLoudness.enabled
        Layout.fillWidth: true
        SettingsCheckBox {
            objectName: "musicLoudnessEdenDefault"
            text: "Start Eden and Eglantine unmuted at +10 dB"
            checked: MusicLoudness.edenDefault
            enabled: !MusicLoudness.busy
            onToggled: MusicLoudness.setEdenDefault(checked)
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { text: "App to adjust" }
            SettingsComboBox {
                objectName: "musicLoudnessSettingsApp"
                palette.text: Appearance.m3colors.m3onSurface
                palette.buttonText: Appearance.m3colors.m3onSurface
                Layout.fillWidth: true
                model: MusicLoudness.apps
                textRole: "name"
                valueRole: "id"
                currentIndex: MusicLoudness.apps.findIndex(app => app.id === MusicLoudness.selectedApp)
                displayText: currentIndex < 0 ? "Start playback to list an app" : currentText
                enabled: !MusicLoudness.busy
                onActivated: index => MusicLoudness.selectApp(MusicLoudness.apps[index].id)
                Accessible.name: "App to adjust"
            }
            SettingsButton { text: "Refresh"; palette.buttonText: Appearance.m3colors.m3onSurface; onClicked: MusicLoudness.refresh() }
        }
        StyledText { Layout.fillWidth: true; text: "Firefox, browsers and other apps appear after opening an audio stream. The selection covers that app’s audio streams, including browser tabs. Without song metadata, Reset or switching apps ends the adjustment; it also ends when those streams close."; wrapMode: Text.WordWrap; font.pixelSize: 12 }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Keep boost when changing presets for this song"; wrapMode: Text.WordWrap }
            SettingsSwitch { checked: MusicLoudness.followPresets; enabled: !MusicLoudness.busy; onToggled: MusicLoudness.setFollowPresets(checked) }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Button step" }
            SettingsComboBox {
                objectName: "musicLoudnessStep"
                Layout.preferredWidth: 110
                palette.text: Appearance.m3colors.m3onSurface
                palette.buttonText: Appearance.m3colors.m3onSurface
                model: ["0.5 dB", "1 dB", "2 dB"]
                currentIndex: [0.5, 1, 2].indexOf(MusicLoudness.stepDb)
                enabled: !MusicLoudness.busy
                onActivated: index => MusicLoudness.setStep([0.5, 1, 2][index])
                Accessible.name: "Loudness button step"
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Match target (LUFS)" }
            TextField {
                id: target
                objectName: "musicLoudnessTarget"
                Layout.preferredWidth: 86
                text: String(MusicLoudness.targetLufs)
                validator: DoubleValidator {}
                color: Appearance.m3colors.m3onSurface
                background: Rectangle { radius: 8; color: Appearance.m3colors.m3surfaceContainerHigh; border.color: target.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant }
                Accessible.name: "Loudness matching target in LUFS"
            }
            SettingsButton { text: "Save"; palette.buttonText: Appearance.m3colors.m3onSurface; enabled: target.acceptableInput && !MusicLoudness.busy; onClicked: MusicLoudness.setTarget(Number.fromLocaleString(Qt.locale(), target.text)) }
        }
        StyledText { Layout.fillWidth: true; text: "Match loudness measures 8 seconds through the current effects, using available peak headroom. Pause other audio first so it measures only your selected app. Manual − / + still works with other apps playing. Known song changes, closed streams or a disconnected effects pipeline reset the gain."; wrapMode: Text.WordWrap; font.pixelSize: 12 }
        SettingsCheckBox {
            objectName: "musicLoudnessSettingsAutoMatch"
            text: "Auto match loudness"
            checked: MusicLoudness.autoMatch
            enabled: !MusicLoudness.busy || MusicLoudness.autoMatch
            Accessible.name: "Auto match loudness"
            onToggled: MusicLoudness.setAutoMatch(checked)
        }
        TimingSettingRow {
            visible: MusicLoudness.autoMatch
            Layout.fillWidth: true
            setting: Catalog.loudnessInterval
        }
        StyledText { Layout.fillWidth: true; visible: MusicLoudness.autoMatch; text: "Adjusts up or down by at most 1 dB per check, from −12 to +6 dB. Quiet passages and mixed audio are skipped. Manual − / + or Reset turns automatic matching off."; wrapMode: Text.WordWrap; font.pixelSize: 12 }
        SettingsButton { text: "Reset music loudness"; palette.buttonText: Appearance.m3colors.m3onSurface; onClicked: MusicLoudness.reset() }
    }
    StyledText { Layout.fillWidth: true; visible: MusicLoudness.error.length > 0; text: MusicLoudness.error; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
}
