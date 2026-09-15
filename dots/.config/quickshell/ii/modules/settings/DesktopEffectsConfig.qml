import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    component EffectsSpinBox: SpinBox {
        id: numberControl
        editable: true
        leftPadding: 40
        rightPadding: 40
        background: Rectangle { color: Appearance.m3colors.m3surfaceContainerHigh; radius: 12 }
        down.indicator: Rectangle {
            x: 0; width: 36; height: parent.height; radius: 12
            color: numberControl.down.pressed ? Appearance.m3colors.m3secondaryContainer : "transparent"
            StyledText { anchors.centerIn: parent; text: "−"; font.pixelSize: 20 }
        }
        up.indicator: Rectangle {
            x: parent.width - width; width: 36; height: parent.height; radius: 12
            color: numberControl.up.pressed ? Appearance.m3colors.m3secondaryContainer : "transparent"
            StyledText { anchors.centerIn: parent; text: "+"; font.pixelSize: 20 }
        }
        implicitWidth: 144
        implicitHeight: 48
        font.pixelSize: 14
        palette.text: Appearance.m3colors.m3onSurface
        palette.buttonText: Appearance.m3colors.m3onSurface
        palette.base: Appearance.m3colors.m3surfaceContainerHigh
        palette.button: Appearance.m3colors.m3surfaceContainerHigh
        palette.highlight: Appearance.m3colors.m3primary
    }
    property var draft: ({})
    property bool ready: false
    property bool dirty: false
    property string status: "Loading effects…"
    function sync() {
        if (Object.keys(DesktopEffects.settings).length === 0) return;
        ready = false;
        draft = JSON.parse(JSON.stringify(DesktopEffects.settings));
        dirty = false;
        ready = true;
        status = "Active: " + draft.preset;
    }
    function edit(key, value) {
        if (!ready || draft[key] === value) return;
        let next = Object.assign({}, draft);
        next[key] = value;
        draft = next;
        dirty = true;
    }
    function run(action, value) {
        if (apply.running) return;
        status = "Applying…";
        apply.command = [Quickshell.env("HOME") + "/.local/bin/desktop-effects", action, value];
        apply.running = true;
    }
    Component.onCompleted: sync()
    Connections {
        target: DesktopEffects
        function onSettingsChanged() { if (!root.dirty) root.sync(); }
    }
    Process {
        id: apply
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: (code, exitStatus) => {
            if (code === 0) {
                root.ready = false;
                root.draft = JSON.parse(output.text);
                root.dirty = false;
                root.ready = true;
                root.status = "Applied: " + root.draft.preset;
            } else root.status = "Could not apply: " + errors.text;
        }
    }
    ContentSection {
        icon: "auto_awesome"
        title: "Make room for a little atmosphere"
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Choose a complete look, or tune individual effects below. Presets apply immediately. Custom changes apply together when you press Apply."
        }
        ConfigSelectionArray {
            enabled: !apply.running
            currentValue: root.draft.preset
            options: [
                {displayName: "Light", icon: "eco", value: "light"},
                {displayName: "Balanced", icon: "balance", value: "balanced"},
                {displayName: "Cinematic", icon: "movie", value: "cinematic"},
                {displayName: "Aurora", icon: "auto_awesome", value: "aurora"}
            ]
            onSelected: value => root.run("preset", value)
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: "Light removes blur, glow and continuous animation. Balanced keeps soft glass. Cinematic adds motion blur. Aurora adds animated light, stars and vertical workspace travel."
        }
        RowLayout {
            Layout.fillWidth: true
            RippleButton {
                text: "Apply custom changes"
                colBackground: Appearance.m3colors.m3primaryContainer
                contentItem: StyledText { text: "Apply custom changes"; color: Appearance.m3colors.m3onPrimaryContainer; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                implicitHeight: 48
                Layout.fillWidth: true
                enabled: root.ready && root.dirty && !apply.running
                onClicked: root.run("apply", JSON.stringify(root.draft))
            }
            RippleButton {
                text: "Reset edits"
                implicitWidth: 120
                contentItem: StyledText { text: "Reset edits"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                implicitHeight: 48
                enabled: root.dirty && !apply.running
                onClicked: root.sync()
            }
        }
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.status }
    }
    ContentSection {
        icon: "wallpaper"
        title: "Atmosphere"
        enabled: root.ready && !apply.running
        ConfigSwitch {
            text: "Drifting aurora light"
            buttonIcon: "check"
            checked: root.draft.aurora === true
            onCheckedChanged: root.edit("aurora", checked)
        }
        ConfigSwitch {
            text: "Twinkling stars"
            buttonIcon: "check"
            checked: root.draft.stars === true
            onCheckedChanged: root.edit("stars", checked)
        }
        ConfigSwitch {
            text: "Wallpaper follows workspace"
            buttonIcon: "check"
            checked: root.draft.parallax === true
            onCheckedChanged: root.edit("parallax", checked)
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Ambient light intensity"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 0; to: 80
                value: root.draft.ambient_strength ?? 0
                onValueModified: root.edit("ambient_strength", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Ambient animation speed (%)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 40; to: 200
                value: root.draft.ambient_speed ?? 40
                onValueModified: root.edit("ambient_speed", value)
            }
        }
    }
    ContentSection {
        icon: "blur_on"
        title: "Glass and light"
        enabled: root.ready && !apply.running
        ConfigSwitch {
            text: "Background blur"
            buttonIcon: "check"
            checked: root.draft.blur === true
            onCheckedChanged: root.edit("blur", checked)
        }
        ConfigSwitch {
            text: "Blur windows behind glass"
            buttonIcon: "check"
            checked: root.draft.live_blur === true
            onCheckedChanged: root.edit("live_blur", checked)
        }
        ConfigSwitch {
            text: "Inner glow"
            buttonIcon: "check"
            checked: root.draft.glow === true
            onCheckedChanged: root.edit("glow", checked)
        }
        ConfigSwitch {
            text: "Soft shadows"
            buttonIcon: "check"
            checked: root.draft.shadow === true
            onCheckedChanged: root.edit("shadow", checked)
        }
        ConfigSwitch {
            text: "Rotating borders"
            buttonIcon: "check"
            checked: root.draft.rotate === true
            onCheckedChanged: root.edit("rotate", checked)
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Blur passes"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 1; to: 5
                value: root.draft.passes ?? 1
                onValueModified: root.edit("passes", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Blur radius"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 2; to: 16
                value: root.draft.blur_size ?? 2
                onValueModified: root.edit("blur_size", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Glow intensity (%)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 0; to: 60
                value: root.draft.glow_strength ?? 0
                onValueModified: root.edit("glow_strength", value)
            }
        }
    }
    ContentSection {
        icon: "animation"
        title: "Motion"
        enabled: root.ready && !apply.running
        ConfigSwitch {
            text: "Motion blur"
            buttonIcon: "check"
            checked: root.draft.motion === true
            onCheckedChanged: root.edit("motion", checked)
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Motion blur samples"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 3; to: 24
                value: root.draft.samples ?? 3
                onValueModified: root.edit("samples", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Animation duration (%)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 50; to: 160
                value: root.draft.tempo ?? 50
                onValueModified: root.edit("tempo", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Workspace travel (%)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 0; to: 100
                value: root.draft.travel ?? 0
                onValueModified: root.edit("travel", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Spring damping (lower = more bounce)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 16; to: 32
                value: root.draft.bounce ?? 16
                onValueModified: root.edit("bounce", value)
            }
        }
    }
    ContentSection {
        icon: "rounded_corner"
        title: "Shape and spacing"
        enabled: root.ready && !apply.running
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Outer gaps (px)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 0; to: 30
                value: root.draft.gaps ?? 0
                onValueModified: root.edit("gaps", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Corner radius (px)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 0; to: 20
                value: root.draft.rounding ?? 0
                onValueModified: root.edit("rounding", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Border width (px)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: 1; to: 5
                value: root.draft.border ?? 1
                onValueModified: root.edit("border", value)
            }
        }
    }
    ContentSection {
        icon: "notifications"
        title: "Shell glass"
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Notification opacity (%)" }
            EffectsSpinBox {
                from: 65; to: 100; value: root.draft.popup_opacity ?? 82
                onValueModified: root.edit("popup_opacity", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Side panel opacity (%)" }
            EffectsSpinBox {
                from: 80; to: 100; value: root.draft.panel_opacity ?? 94
                onValueModified: root.edit("panel_opacity", value)
            }
        }
    }
    ContentSection {
        icon: "palette"
        title: "Color palette"
        ConfigSelectionArray {
            currentValue: root.draft.palette
            options: [{displayName: "Aurora", value: "aurora"}, {displayName: "Sunset", value: "sunset"}, {displayName: "Ocean", value: "ocean"}, {displayName: "Emerald", value: "emerald"}]
            onSelected: value => root.edit("palette", value)
        }
    }
    ContentSection {
        icon: "palette"
        title: "Workspace movement"
        ConfigSelectionArray {
            currentValue: root.draft.workspace_style
            options: [{displayName: "Horizontal glide", value: "slidefade"}, {displayName: "Vertical glide", value: "slidefadevert"}, {displayName: "Full slide", value: "slide"}, {displayName: "Crossfade", value: "fade"}]
            onSelected: value => root.edit("workspace_style", value)
        }
    }
    ContentSection {
        icon: "palette"
        title: "Window entrance"
        ConfigSelectionArray {
            currentValue: root.draft.window_style
            options: [{displayName: "Scale reveal", value: "popin"}, {displayName: "Full slide", value: "slide"}, {displayName: "GNOME zoom", value: "gnomed"}]
            onSelected: value => root.edit("window_style", value)
        }
    }
}
