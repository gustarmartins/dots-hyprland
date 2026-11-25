import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 10

    property bool watching: false
    readonly property bool pollingVisible: visible && (Window.window?.visible ?? false)
    readonly property var info: PipeWireAudio.data
    readonly property bool hasData: PipeWireAudio.available && info !== null

    function watch() {
        if (watching === pollingVisible) return;
        watching = pollingVisible;
        PipeWireAudio.watchers += watching ? 1 : -1;
    }

    onPollingVisibleChanged: watch()
    Component.onCompleted: watch()
    Component.onDestruction: if (watching) PipeWireAudio.watchers--

    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "PipeWire & kernel audio"; font.pixelSize: 20; font.weight: Font.Medium }
        SettingsSwitch {
            objectName: "pipewireAudioMaster"
            checked: Config.options.sidebar.audioStatus.enable
            Accessible.name: "Show PipeWire audio strip in Control center"
            onToggled: Config.options.sidebar.audioStatus.enable = checked
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Appearance.m3colors.m3onSurfaceVariant
        text: !Config.options.sidebar.audioStatus.enable
            ? "Hidden in Control center and background polling stopped."
            : !root.hasData
            ? (PipeWireAudio.ready ? "PipeWire audio telemetry helper not available." : "Reading live PipeWire clock and kernel scheduling…")
            : ("Clock: " + (root.info.clock?.rateLabel ?? "") + " · Quantum " + (root.info.clock?.quantum ?? 0)
                + " (" + Number(root.info.clock?.latencyMs || 0).toFixed(2) + " ms, " + (root.info.clock?.mode ?? "Adaptive") + ")"
                + " · DAC: " + (root.info.hardware?.codec ?? "") + " (" + (root.info.hardware?.format ?? "Standby") + ")"
                + " · Kernel: " + (root.info.kernel?.shortRelease ?? "") + " " + (root.info.kernel?.preempt ?? "")
                + " (PW " + (root.info.kernel?.pipewire?.label ?? "") + ", EE " + (root.info.kernel?.easyeffects?.label ?? "") + ")")
    }

    ColumnLayout {
        visible: Config.options.sidebar.audioStatus.enable && root.hasData
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
            text: {
                const chain = root.info?.chain ?? [];
                if (!chain.length) return "";
                return "Signal chain: " + chain.map(s => s.label).join("  →  ");
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText { text: "Live quantum:"; color: Appearance.m3colors.m3onSurfaceVariant }
            Repeater {
                model: [
                    { q: 0, label: "Adaptive" },
                    { q: 64, label: "64" },
                    { q: 128, label: "128" },
                    { q: 256, label: "256" },
                    { q: 512, label: "512" },
                    { q: 1024, label: "1024" }
                ]
                delegate: SettingsButton {
                    required property var modelData
                    text: ((root.info?.clock?.forceQuantum ?? 0) === modelData.q ? "✓ " : "") + modelData.label
                    enabled: !PipeWireAudio.acting
                    onClicked: PipeWireAudio.setQuantum(modelData.q)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText { text: "Sample rate:"; color: Appearance.m3colors.m3onSurfaceVariant }
            Repeater {
                model: [
                    { r: 0, label: "Auto (native)" },
                    { r: 44100, label: "44.1 kHz" },
                    { r: 48000, label: "48 kHz" },
                    { r: 96000, label: "96 kHz" },
                    { r: 192000, label: "192 kHz" }
                ]
                delegate: SettingsButton {
                    required property var modelData
                    text: ((root.info?.clock?.forceRate ?? 0) === modelData.r ? "✓ " : "") + modelData.label
                    enabled: !PipeWireAudio.acting
                    onClicked: PipeWireAudio.setRate(modelData.r)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            SettingsButton { text: "Reset to adaptive clock"; enabled: !PipeWireAudio.acting; onClicked: PipeWireAudio.resetClock() }
            SettingsButton { text: "Refresh PipeWire status"; enabled: !PipeWireAudio.busy && !PipeWireAudio.acting; onClicked: PipeWireAudio.refresh() }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: PipeWireAudio.error
        visible: text.length > 0
        wrapMode: Text.WordWrap
        color: Appearance.m3colors.m3error
    }
}
