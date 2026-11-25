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
    readonly property int sliderCount: (hasBrightness ? 1 : 0) + (hasVolume ? 1 : 0) + (hasMic ? 1 : 0)
    readonly property bool singleRow: width >= 480
    implicitHeight: controls.implicitHeight + 12
    radius: 14
    color: Appearance.colors.colLayer1
    GridLayout {
        id: controls
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 10
            topMargin: 6
            bottomMargin: 6
        }
        columns: root.singleRow ? Math.max(1, root.sliderCount) : 2
        columnSpacing: 12
        rowSpacing: 2
        LevelControl {
            visible: root.hasBrightness
            Layout.columnSpan: root.singleRow ? 1 : 2
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
            Layout.columnSpan: root.singleRow ? 1 : (root.hasMic ? 1 : 2)
            icon: "volume_up"
            sliderValue: Audio.sink?.audio?.volume ?? 0
            enabled: !!Audio.sink?.audio
            readout: Math.round(sliderValue * 100) + "%"
            accessibleLabel: "Output volume"
            onAdjusted: value => { if (Audio.sink?.audio) Audio.sink.audio.volume = value; }
        }
        LevelControl {
            visible: root.hasMic
            Layout.columnSpan: root.singleRow ? 1 : (root.hasVolume ? 1 : 2)
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
        spacing: 6
        MaterialSymbol { text: level.icon; iconSize: 16; color: Appearance.m3colors.m3onSurfaceVariant }
        StyledSlider {
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.XS
            implicitHeight: 24
            handleHeight: 20
            stopIndicatorValues: []
            value: level.sliderValue
            onMoved: level.adjusted(value)
            Accessible.name: level.accessibleLabel
        }
        StyledText {
            Layout.preferredWidth: 34
            text: level.readout
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            color: Appearance.m3colors.m3onSurfaceVariant
        }
    }
}
