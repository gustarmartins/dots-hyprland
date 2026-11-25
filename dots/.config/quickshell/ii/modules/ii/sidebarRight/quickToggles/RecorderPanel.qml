import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    objectName: "recorderPanel"
    implicitWidth: 460
    implicitHeight: contentCol.implicitHeight
    property bool watching: false
    readonly property bool pollingVisible: visible && (Window.window?.visible ?? false)

    function watch() {
        if (watching === pollingVisible) return;
        watching = pollingVisible;
        ScreenRecorder.watchers += watching ? 1 : -1;
    }

    onPollingVisibleChanged: watch()
    Component.onCompleted: watch()
    Component.onDestruction: if (watching) ScreenRecorder.watchers--

    ColumnLayout {
        id: contentCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: ScreenRecorder.recording ? "radio_button_checked" : "screen_record"
                iconSize: 23
                color: ScreenRecorder.recording ? Appearance.m3colors.m3error : Appearance.m3colors.m3primary
            }
            StyledText {
                text: "Screen recorder"
                font.pixelSize: 17
                font.weight: Font.Medium
                Layout.fillWidth: true
            }
            StyledText {
                text: ScreenRecorder.busy ? "Applying…"
                    : ScreenRecorder.recording ? ("REC · " + ScreenRecorder.formatElapsed(ScreenRecorder.elapsedSeconds))
                    : (ScreenRecorder.hasGsr ? "KMS Zero-copy" : "wf-recorder")
                color: ScreenRecorder.recording ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: 11
                font.weight: ScreenRecorder.recording ? Font.DemiBold : Font.Normal
            }
            RippleButton {
                objectName: "recorderPanelToggleBtn"
                implicitHeight: 30
                implicitWidth: btnLabel.implicitWidth + 20
                buttonRadius: 12
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                colBackground: ScreenRecorder.recording ? Appearance.m3colors.m3errorContainer : Appearance.m3colors.m3primaryContainer
                onClicked: ScreenRecorder.recording ? ScreenRecorder.stop() : ScreenRecorder.toggleFullscreen()
                contentItem: StyledText {
                    id: btnLabel
                    anchors.centerIn: parent
                    text: ScreenRecorder.recording ? "Stop" : "Record"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: ScreenRecorder.recording ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onPrimaryContainer
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText { text: "Preset"; Layout.preferredWidth: 74; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "recorderPresetPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.presetModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.presetModes.findIndex(m => m.value === ScreenRecorder.preset))
                onActivated: index => ScreenRecorder.applyPreset(ScreenRecorder.presetModes[index].value)
                Accessible.name: "Recording preset"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText { text: "Engine"; Layout.preferredWidth: 74; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "recorderBackendPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.backendModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.backendModes.findIndex(m => m.value === ScreenRecorder.backend))
                onActivated: index => ScreenRecorder.setFlag("--backend", ScreenRecorder.backendModes[index].value)
                Accessible.name: "Recorder engine"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText { text: "Video"; Layout.preferredWidth: 74; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "recorderCodecPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.codecModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.codecModes.findIndex(m => m.value === ScreenRecorder.codec))
                onActivated: index => ScreenRecorder.setFlag("--codec", ScreenRecorder.codecModes[index].value)
                Accessible.name: "Video codec"
            }
            StyledComboBox {
                objectName: "recorderQualityPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.qualityModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.qualityModes.findIndex(m => m.value === ScreenRecorder.quality))
                onActivated: index => ScreenRecorder.setFlag("--quality", ScreenRecorder.qualityModes[index].value)
                Accessible.name: "Video quality"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText { text: "Timing"; Layout.preferredWidth: 74; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "recorderFpsPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.fpsModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.fpsModes.findIndex(m => m.value === ScreenRecorder.fps))
                onActivated: index => ScreenRecorder.setFlag("--fps", ScreenRecorder.fpsModes[index].value)
                Accessible.name: "Frame rate"
            }
            StyledComboBox {
                objectName: "recorderFrameModePicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.frameRateModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.frameRateModes.findIndex(m => m.value === ScreenRecorder.frameRateMode))
                onActivated: index => ScreenRecorder.setFlag("--frame-mode", ScreenRecorder.frameRateModes[index].value)
                Accessible.name: "Frame rate mode"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText { text: "Encoder"; Layout.preferredWidth: 74; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "recorderTunePicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.tuneModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.tuneModes.findIndex(m => m.value === ScreenRecorder.tune))
                onActivated: index => ScreenRecorder.setFlag("--tune", ScreenRecorder.tuneModes[index].value)
                Accessible.name: "Encoder performance tune"
            }
            StyledComboBox {
                objectName: "recorderBitrateModePicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.bitrateModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.bitrateModes.findIndex(m => m.value === ScreenRecorder.bitrateMode))
                onActivated: index => ScreenRecorder.setFlag("--bitrate-mode", ScreenRecorder.bitrateModes[index].value)
                Accessible.name: "Bitrate control mode"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText { text: "Audio"; Layout.preferredWidth: 74; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "recorderAudioModePicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.audioModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.audioModes.findIndex(m => m.value === ScreenRecorder.audioMode))
                onActivated: index => ScreenRecorder.setFlag("--audio", ScreenRecorder.audioModes[index].value)
                Accessible.name: "Audio capture mode"
            }
            StyledComboBox {
                objectName: "recorderAudioCodecPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy && ScreenRecorder.audioMode !== "none"
                model: ScreenRecorder.audioCodecModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.audioCodecModes.findIndex(m => m.value === ScreenRecorder.audioCodec))
                onActivated: index => ScreenRecorder.setFlag("--audio-codec", ScreenRecorder.audioCodecModes[index].value)
                Accessible.name: "Audio codec"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText { text: "Format"; Layout.preferredWidth: 74; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "recorderContainerPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.containerModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.containerModes.findIndex(m => m.value === ScreenRecorder.container))
                onActivated: index => ScreenRecorder.setFlag("--container", ScreenRecorder.containerModes[index].value)
                Accessible.name: "Container format"
            }
            StyledComboBox {
                objectName: "recorderPixfmtPicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.pixfmtModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.pixfmtModes.findIndex(m => m.value === ScreenRecorder.pixfmt))
                onActivated: index => ScreenRecorder.setFlag("--pixfmt", ScreenRecorder.pixfmtModes[index].value)
                Accessible.name: "Pixel format"
            }
            StyledComboBox {
                objectName: "recorderColorRangePicker"
                Layout.fillWidth: true
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                model: ScreenRecorder.colorRangeModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, ScreenRecorder.colorRangeModes.findIndex(m => m.value === ScreenRecorder.colorRange))
                onActivated: index => ScreenRecorder.setFlag("--color-range", ScreenRecorder.colorRangeModes[index].value)
                Accessible.name: "Color range"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            StyledText { text: "Low-power VCN"; font.pixelSize: 12 }
            StyledSwitch {
                objectName: "recorderLowPowerSwitch"
                checked: ScreenRecorder.lowPower
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy && ScreenRecorder.backend === "gsr"
                onToggled: ScreenRecorder.setFlag("--low-power", checked ? "on" : "off")
                Accessible.name: "Low-power hardware encoder"
            }
            Item { Layout.fillWidth: true }
            StyledText { text: "Show cursor"; font.pixelSize: 12 }
            StyledSwitch {
                objectName: "recorderCursorSwitch"
                checked: ScreenRecorder.showCursor
                enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                onToggled: ScreenRecorder.setFlag("--cursor", checked ? "on" : "off")
                Accessible.name: "Capture mouse cursor"
            }
        }

        StyledText {
            objectName: "recorderActualState"
            Layout.fillWidth: true
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: ScreenRecorder.error ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
            text: ScreenRecorder.error || (!ScreenRecorder.ready ? "Detecting hardware encoders…"
                : ScreenRecorder.recording
                    ? ("Recording (" + ScreenRecorder.formatElapsed(ScreenRecorder.elapsedSeconds) + ") · "
                        + (ScreenRecorder.activeOutput ? ScreenRecorder.activeOutput.split("/").pop() : ScreenRecorder.activeBackend))
                    : ((ScreenRecorder.hasGsr && ScreenRecorder.hasKms ? "KMS zero-copy ready" : "Wayland capture")
                        + (ScreenRecorder.vaapiCodecs.length > 0 ? (" · VAAPI: " + ScreenRecorder.vaapiCodecs.join(", ").toUpperCase()) : "")))
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: 10
            color: Appearance.m3colors.m3onSurfaceVariant
            text: "Super+Alt+Shift+R toggles fullscreen + audio with these settings. KMS capture preserves direct scanout and minimizes game FPS impact."
        }
    }
}
