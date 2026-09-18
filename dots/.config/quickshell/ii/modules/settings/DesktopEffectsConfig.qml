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
    property string operation: ""
    property var pendingDelete: null
    readonly property bool profileMotion: draft.motion_source === "profile"
    function motionKey(key) { return root.profileMotion ? "profile_" + key : key; }
    function requestDelete(value) {
        if (apply.running || !String(value).startsWith("saved:")) return;
        const entry = DesktopEffects.savedPresets.find(item => "saved:" + item.id === value);
        if (!entry) return;
        root.pendingDelete = {id: entry.id, name: entry.name};
        deleteDialog.open();
    }
    Dialog {
        id: deleteDialog
        objectName: "deletePresetDialog"
        parent: Overlay.overlay
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(440, parent.width - 32)
        modal: true
        focus: true
        title: "Delete saved preset?"
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 20; color: Appearance.m3colors.m3surfaceContainerHigh }
        header: StyledText { text: deleteDialog.title; padding: 20; font.pixelSize: Appearance.font.pixelSize.larger }
        contentItem: StyledText {
            text: "Delete “" + (root.pendingDelete?.name ?? "") + "” from your saved presets? Your current desktop will stay as it is."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
        }
        footer: RowLayout {
            spacing: 12
            Item { Layout.fillWidth: true }
            DialogButton { buttonText: "Cancel"; onClicked: deleteDialog.reject() }
            DialogButton { buttonText: "Delete"; colText: Appearance.m3colors.m3error; onClicked: deleteDialog.accept() }
        }
        onAccepted: if (root.pendingDelete) root.run("delete", root.pendingDelete.id)
        onRejected: root.pendingDelete = null
    }
    readonly property string activePreset: {
        if (root.dirty) return "";
        if (root.draft.preset !== "custom") return root.draft.preset ?? "";
        const match = DesktopEffects.savedPresets.find(entry =>
            Object.keys(root.draft).every(key => key === "preset" || root.draft[key] === entry.settings[key]));
        return match ? "saved:" + match.id : "custom";
    }
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
        operation = action;
        status = action === "save" ? "Saving…" : action === "delete" ? "Deleting…" : "Applying…";
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
                if (root.operation === "delete") {
                    const removed = JSON.parse(output.text);
                    DesktopEffects.reloadPresets();
                    root.pendingDelete = null;
                    root.status = "Deleted: " + removed.name;
                    return;
                }
                if (root.operation === "save") {
                    const saved = JSON.parse(output.text);
                    DesktopEffects.reloadPresets();
                    presetName.text = "";
                    root.status = "Saved: " + saved.name;
                    return;
                }
                root.ready = false;
                root.draft = JSON.parse(output.text);
                root.dirty = false;
                root.ready = true;
                const saved = DesktopEffects.savedPresets.find(entry => "saved:" + entry.id === apply.command[2]);
                root.status = "Applied: " + (saved ? saved.name : root.draft.preset);
            } else root.status = (root.operation === "save" ? "Could not save: " : root.operation === "delete" ? "Could not delete: " : "Could not apply: ") + errors.text.trim();
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
            currentValue: root.activePreset
            options: [
                {displayName: "Light", icon: "eco", value: "light"},
                {displayName: "Balanced", icon: "balance", value: "balanced"},
                {displayName: "Cinematic", icon: "movie", value: "cinematic"},
                {displayName: "Aurora", icon: "auto_awesome", value: "aurora"}
            ].concat(DesktopEffects.savedPresets.map(entry => ({displayName: entry.name, icon: "bookmark", value: "saved:" + entry.id})))
            onSelected: value => root.run("preset", value)
            onAlternateSelected: value => root.requestDelete(value)
        }
        RowLayout {
            Layout.fillWidth: true
            MaterialTextField {
                id: presetName
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                placeholderText: "Preset name"
                maximumLength: 32
                enabled: root.ready && !apply.running
                onAccepted: if (savePreset.enabled) savePreset.clicked()
            }
            RippleButton {
                id: savePreset
                implicitWidth: 170
                implicitHeight: 48
                enabled: root.ready && !root.dirty && !apply.running && presetName.text.trim().length > 0
                contentItem: StyledText {
                    text: "Save current preset"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.run("save", presetName.text.trim())
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.dirty
            wrapMode: Text.WordWrap
            text: "Apply your changes before saving this look as a preset."
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: "Light removes blur and glow. Balanced keeps soft glass. Cinematic adds motion blur. Aurora adds animated light and stars. Your animation profile stays selected. Right-click a saved look to delete it."
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
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.profileMotion ? "Motion: " + (root.draft.animation_profile ?? "").replace(/\.lua$/, "").replace(/_/g, " ") + ". Fine-tune below, or keep the preset values."
                : "Motion: custom desktop effects. Choose an animation profile here or with Super+Alt+A to use its movement and curves."
        }
        ConfigSelectionArray {
            currentValue: root.draft.motion_source ?? "custom"
            options: [{displayName: "Animation profile", value: "profile"}, {displayName: "Custom motion", value: "custom"}]
            onSelected: value => root.edit("motion_source", value)
        }
        StyledComboBox {
            objectName: "animationProfilePicker"
            model: DesktopEffects.animationProfiles
            textRole: "displayName"
            valueRole: "value"
            currentIndex: DesktopEffects.animationProfiles.findIndex(entry => entry.value === root.draft.animation_profile)
            onActivated: {
                root.edit("animation_profile", currentValue);
                root.edit("motion_source", "profile");
            }
        }
        RippleButton {
            visible: root.profileMotion
            buttonText: "Reset motion adjustments to preset"
            implicitHeight: 40
            Layout.fillWidth: true
            onClicked: {
                root.edit("profile_tempo", 100);
                root.edit("profile_travel", -1);
                root.edit("profile_bounce", 0);
                root.edit("profile_workspace_style", "preset");
                root.edit("profile_window_style", "preset");
            }
        }
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
                value: root.draft[root.motionKey("tempo")] ?? 100
                onValueModified: root.edit(root.motionKey("tempo"), value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Workspace travel (%)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: root.profileMotion ? -1 : 0; to: 100
                value: root.draft[root.motionKey("travel")] ?? -1
                textFromValue: value => value < 0 ? "Preset" : String(value)
                valueFromText: text => text.toLowerCase() === "preset" ? -1 : Number(text)
                onValueModified: root.edit(root.motionKey("travel"), value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Spring damping (lower = more bounce)"; wrapMode: Text.WordWrap }
            EffectsSpinBox {
                from: root.profileMotion ? 0 : 16; to: 32
                value: root.draft[root.motionKey("bounce")] ?? 0
                textFromValue: value => value === 0 ? "Preset" : String(value)
                valueFromText: text => text.toLowerCase() === "preset" ? 0 : Number(text)
                onValueModified: root.edit(root.motionKey("bounce"), value)
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
            currentValue: root.draft[root.motionKey("workspace_style")] ?? "preset"
            options: (root.profileMotion ? [{displayName: "Use preset", value: "preset"}] : []).concat([{displayName: "Horizontal glide", value: "slidefade"}, {displayName: "Vertical glide", value: "slidefadevert"}, {displayName: "Full slide", value: "slide"}, {displayName: "Crossfade", value: "fade"}])
            onSelected: value => root.edit(root.motionKey("workspace_style"), value)
        }
    }
    ContentSection {
        icon: "palette"
        title: "Window entrance"
        ConfigSelectionArray {
            currentValue: root.draft[root.motionKey("window_style")] ?? "preset"
            options: (root.profileMotion ? [{displayName: "Use preset", value: "preset"}] : []).concat([{displayName: "Scale reveal", value: "popin"}, {displayName: "Full slide", value: "slide"}, {displayName: "GNOME zoom", value: "gnomed"}])
            onSelected: value => root.edit(root.motionKey("window_style"), value)
        }
    }
}
