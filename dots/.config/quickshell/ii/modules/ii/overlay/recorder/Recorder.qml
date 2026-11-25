pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay
import qs.modules.ii.sidebarRight.quickToggles

StyledOverlayWidget {
    id: root
    property bool showConfig: false
    minimumWidth: showConfig ? 480 : 340
    minimumHeight: showConfig ? 490 : 210

    Component.onCompleted: ScreenRecorder.watchers++
    Component.onDestruction: ScreenRecorder.watchers--

    contentItem: OverlayBackground {
        id: contentItem
        radius: root.contentRadius
        property real padding: 12

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: contentItem.padding
            }
            spacing: 10

            Row {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 10

                BigRecorderButton {
                    materialSymbol: "screenshot_region"
                    name: "Screenshot region"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "photo_camera"
                    name: "Screenshot"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["bash", "-c", "grim - | wl-copy"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "screen_record"
                    name: "Record region"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "recordWithSound"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: ScreenRecorder.recording ? "stop_circle" : "capture"
                    name: ScreenRecorder.recording
                        ? ("Stop recording (" + ScreenRecorder.formatElapsed(ScreenRecorder.elapsedSeconds) + ")")
                        : "Record screen"
                    colBackground: ScreenRecorder.recording ? Appearance.m3colors.m3errorContainer : Appearance.colors.colLayer3
                    onClicked: {
                        if (ScreenRecorder.recording) {
                            ScreenRecorder.stop();
                        } else {
                            GlobalStates.overlayOpen = false;
                            Quickshell.execDetached([Directories.recordScriptPath, "--fullscreen", "--sound"]);
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledComboBox {
                    Layout.fillWidth: true
                    enabled: ScreenRecorder.ready && !ScreenRecorder.busy
                    model: ScreenRecorder.presetModes
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: Math.max(0, ScreenRecorder.presetModes.findIndex(m => m.value === ScreenRecorder.preset))
                    onActivated: index => ScreenRecorder.applyPreset(ScreenRecorder.presetModes[index].value)
                    Accessible.name: "Quick recording preset"
                }
                RippleButton {
                    implicitHeight: 34
                    implicitWidth: tuneRow.implicitWidth + 18
                    buttonRadius: 12
                    colBackground: root.showConfig ? Appearance.m3colors.m3primaryContainer : Appearance.colors.colLayer3
                    onClicked: root.showConfig = !root.showConfig
                    contentItem: Row {
                        id: tuneRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "tune"
                            iconSize: 16
                            color: root.showConfig ? Appearance.m3colors.m3onPrimaryContainer : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.showConfig ? "Hide" : "Tune"
                            font.pixelSize: 12
                            color: root.showConfig ? Appearance.m3colors.m3onPrimaryContainer : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 11
                color: ScreenRecorder.recording ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
                text: ScreenRecorder.recording
                    ? ("REC " + ScreenRecorder.formatElapsed(ScreenRecorder.elapsedSeconds) + " · " + ScreenRecorder.codec.toUpperCase() + " · " + (ScreenRecorder.fps === 0 ? "Native" : ScreenRecorder.fps + " fps"))
                    : ((ScreenRecorder.backend === "gsr" ? "KMS" : ScreenRecorder.backend)
                        + " · " + ScreenRecorder.codec.toUpperCase()
                        + " · " + (ScreenRecorder.fps === 0 ? "Native" : ScreenRecorder.fps + " fps")
                        + " · " + ScreenRecorder.quality.replace("_", " "))
            }

            Loader {
                active: root.showConfig
                visible: active
                Layout.fillWidth: true
                sourceComponent: RecorderPanel {}
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 8
                RippleButton {
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Qt.openUrlExternally(`file://${Config.options.screenRecord.savePath}`);
                    }
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "animated_images"
                            iconSize: 18
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Recordings")
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    component BigRecorderButton: RippleButton {
        id: bigButton
        required property string materialSymbol
        required property string name
        implicitHeight: 62
        implicitWidth: 62
        buttonRadius: height / 2

        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: bigButton.materialSymbol
            iconSize: 26
        }

        StyledToolTip {
            text: bigButton.name
        }
    }
}
