import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    readonly property bool hasBrightness: Config.options.sidebar.quickSliders.showBrightness && brightnessMonitor !== null
    readonly property bool hasVolume: Config.options.sidebar.quickSliders.showVolume
    readonly property bool hasMic: Config.options.sidebar.quickSliders.showMic
    implicitHeight: controls.implicitHeight + 16
    radius: 18
    color: Appearance.colors.colLayer1
    GridLayout {
        id: controls
        anchors.fill: parent
        anchors.margins: 8
        columns: 2
        columnSpacing: 16
        rowSpacing: 2
        LevelControl {
            visible: root.hasBrightness
            Layout.columnSpan: 2
            icon: "light_mode"
            sliderValue: Hyprsunset.gamma === 100 ? 0.3 + (root.brightnessMonitor?.brightness ?? 1) * 0.7 : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * 0.3
            readout: Hyprsunset.gamma === 100 ? Math.round((root.brightnessMonitor?.brightness ?? 1) * 100) + "%" : "γ " + Hyprsunset.gamma
            accessibleLabel: "Brightness"
            onAdjusted: value => {
                if (!root.brightnessMonitor) return;
                if (value >= 0.3) {
                    root.brightnessMonitor.setBrightness((value - 0.3) / 0.7);
                    if (Hyprsunset.gamma !== 100) Hyprsunset.setGamma(100);
                } else {
                    if (root.brightnessMonitor.brightness !== 0) root.brightnessMonitor.setBrightness(0);
                    Hyprsunset.setGamma(value / 0.3 * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit);
                }
            }
        }
        LevelControl {
            visible: root.hasVolume
            Layout.columnSpan: root.hasMic ? 1 : 2
            icon: "volume_up"
            sliderValue: Audio.sink?.audio?.volume ?? 0
            enabled: !!Audio.sink?.audio
            readout: Math.round(sliderValue * 100) + "%"
            accessibleLabel: "Output volume"
            onAdjusted: value => { if (Audio.sink?.audio) Audio.sink.audio.volume = value; }
        }
        LevelControl {
            visible: root.hasMic
            Layout.columnSpan: root.hasVolume ? 1 : 2
            icon: "mic"
            sliderValue: Audio.source?.audio?.volume ?? 0
            enabled: !!Audio.source?.audio
            readout: Math.round(sliderValue * 100) + "%"
            accessibleLabel: "Microphone level"
            onAdjusted: value => { if (Audio.source?.audio) Audio.source.audio.volume = value; }
        }
    }
    component LevelControl: RowLayout {
        id: level
        required property string icon
        required property real sliderValue
        required property string readout
        required property string accessibleLabel
        signal adjusted(real value)
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 8
        MaterialSymbol { text: level.icon; iconSize: 18; color: Appearance.m3colors.m3onSurfaceVariant }
        StyledSlider {
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.XS
            implicitHeight: 30
            handleHeight: 24
            stopIndicatorValues: []
            value: level.sliderValue
            onMoved: level.adjusted(value)
            Accessible.name: level.accessibleLabel
        }
        StyledText {
            Layout.preferredWidth: 38
            text: level.readout
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            color: Appearance.m3colors.m3onSurfaceVariant
        }
    }
}
