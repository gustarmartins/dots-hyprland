import QtQuick
import "SettingsCatalog.js" as Catalog
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    objectName: "designEffects"
    Layout.fillWidth: true
    spacing: 22

    component EffectToggleRow: AbstractButton {
        id: toggle
        property string description: ""
        Layout.fillWidth: true
        checkable: false
        implicitHeight: rowBody.implicitHeight + 22
        background: Rectangle {
            radius: 10
            color: toggle.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.04) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        contentItem: RowLayout {
            id: rowBody
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
            spacing: 16
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: toggle.text
                    textFormat: Text.PlainText
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onSurface
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: toggle.description.length > 0
                    text: toggle.description
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
            SettingsSwitch {
                checked: toggle.checked
                checkable: false
                onClicked: toggle.clicked()
            }
        }
    }

    component EffectsSpinBox: SpinBox {
        id: numberControl
        editable: true
        implicitWidth: 156
        implicitHeight: 40
        leftPadding: 38
        rightPadding: 38
        font.pixelSize: 13
        palette.text: Appearance.m3colors.m3onSurface
        palette.buttonText: Appearance.m3colors.m3onSurface
        palette.base: Appearance.m3colors.m3surfaceContainerHigh
        palette.button: Appearance.m3colors.m3surfaceContainerHigh
        palette.highlight: Appearance.m3colors.m3primary
        palette.highlightedText: Appearance.m3colors.m3onPrimary
        background: Rectangle {
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: 12
            border.width: numberControl.activeFocus ? 2 : 1
            border.color: numberControl.activeFocus ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
        }
        down.indicator: Rectangle {
            x: 2
            y: 2
            width: 34
            height: parent.height - 4
            radius: 10
            color: numberControl.down.pressed ? Appearance.m3colors.m3secondaryContainer
                : numberControl.down.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
            StyledText {
                anchors.centerIn: parent
                text: "−"
                font.pixelSize: 17
                font.weight: Font.Medium
                color: numberControl.down.pressed ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
            }
        }
        up.indicator: Rectangle {
            x: parent.width - width - 2
            y: 2
            width: 34
            height: parent.height - 4
            radius: 10
            color: numberControl.up.pressed ? Appearance.m3colors.m3secondaryContainer
                : numberControl.up.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
            StyledText {
                anchors.centerIn: parent
                text: "+"
                font.pixelSize: 17
                font.weight: Font.Medium
                color: numberControl.up.pressed ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
            }
        }
    }

    component NumberRow: RowLayout {
        id: nrow
        property string label: ""
        property string description: ""
        default property alias controlData: slot.data
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: nrow.label
                textFormat: Text.PlainText
                font.pixelSize: 14
                font.weight: Font.Medium
                color: Appearance.m3colors.m3onSurface
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: nrow.description.length > 0
                text: nrow.description
                textFormat: Text.PlainText
                font.pixelSize: 12
                color: Appearance.m3colors.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
        RowLayout { id: slot; spacing: 8 }
    }

    property var draft: ({})
    property bool ready: false
    property bool dirty: false
    readonly property bool busy: apply.running
    property string status: "Loading effects…"
    property string operation: ""
    property var pendingDelete: null
    readonly property bool profileMotion: draft.motion_source === "profile"
    function motionKey(key) {
        return root.profileMotion ? "profile_" + key : key;
    }
    function requestDelete(value) {
        if (apply.running || !String(value).startsWith("saved:"))
            return;
        const entry = DesktopEffects.savedPresets.find(item => "saved:" + item.id === value);
        if (!entry)
            return;
        root.pendingDelete = { id: entry.id, name: entry.name };
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
        background: Rectangle {
            radius: 22
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.m3colors.m3outlineVariant
        }
        header: StyledText {
            text: deleteDialog.title
            padding: 20
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
        }
        contentItem: StyledText {
            text: "Delete “" + (root.pendingDelete?.name ?? "")
                  + "” from your saved presets? Your current desktop will stay as it is."
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
        const match = DesktopEffects.savedPresets.find(entry => Object.keys(root.draft).every(key => key === "preset" || root.draft[key] === entry.settings[key]));
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
            } else
                root.status = (root.operation === "save" ? "Could not save: " : root.operation === "delete"
                               ? "Could not delete: " : "Could not apply: ") + errors.text.trim();
        }
    }

    DesignSection {
        sectionKey: "gpu"
        title: "Desktop GPU effects"
        subtitle: "Presets apply immediately · custom edits use Apply"
        icon: "auto_awesome"
        detailsLabel: "Fine-tune glass, atmosphere, geometry & saved looks"
        detailsSummary: "Blur " + (root.draft.blur_size ?? 8) + "px (" + (root.draft.passes ?? 3) + " passes)  ·  Rounding "
            + (root.draft.rounding ?? 18) + "px  ·  Opacity " + (root.draft.popup_opacity ?? 82) + "% / " + (root.draft.panel_opacity ?? 94) + "%"
        enabled: root.ready && !apply.running && !Config.writesPaused

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            Layout.bottomMargin: 6
            spacing: 8
            StyledText {
                text: "Look preset"
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            ConfigSelectionArray {
                objectName: "designGpuPresets"
                enabled: !apply.running
                currentValue: root.activePreset
                options: [
                    { displayName: "Minimal", icon: "eco", value: "light" },
                    { displayName: "Soft glass", icon: "balance", value: "balanced" },
                    { displayName: "Cinema", icon: "movie", value: "cinematic" },
                    { displayName: "Aurora", icon: "auto_awesome", value: "aurora" },
                    { displayName: "Custom", icon: "tune", value: "custom" }
                ].concat(DesktopEffects.savedPresets.map(entry => ({
                    displayName: entry.name, icon: "bookmark", value: "saved:" + entry.id
                })))
                onSelected: value => root.run("preset", value)
                onAlternateSelected: value => root.requestDelete(value)
            }
        }

        EffectToggleRow {
            objectName: "designBlur"
            text: "Background blur"
            description: "Frosted glass blur behind translucent panels and popups."
            checked: root.draft.blur === true
            onClicked: root.edit("blur", !checked)
        }
        EffectToggleRow {
            objectName: "designGlow"
            text: "Inner glow"
            description: "Soft ambient edge lighting around floating surfaces."
            checked: root.draft.glow === true
            onClicked: root.edit("glow", !checked)
        }

        detailsData: [
            DesignSection {
                nested: true
                title: "Glass & shadows"
                icon: "blur_on"
                sectionKey: "glass"
                detailsSummary: (root.draft.passes ?? 1) + " passes  ·  radius " + (root.draft.blur_size ?? 2) + "  ·  glow " + (root.draft.glow_strength ?? 0) + "%"
                detailsData: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    EffectToggleRow {
                        text: "Blur windows behind glass"
                        checked: root.draft.live_blur === true
                        onClicked: root.edit("live_blur", !checked)
                    }
                    EffectToggleRow {
                        text: "Soft shadows"
                        checked: root.draft.shadow === true
                        onClicked: root.edit("shadow", !checked)
                    }
                    EffectToggleRow {
                        text: "Rotating borders"
                        checked: root.draft.rotate === true
                        onClicked: root.edit("rotate", !checked)
                    }
                    NumberRow {
                        label: "Blur passes"
                        EffectsSpinBox { from: 1; to: 5; value: root.draft.passes ?? 1; onValueModified: root.edit("passes", value) }
                    }
                    NumberRow {
                        label: "Blur radius"
                        EffectsSpinBox { from: 2; to: 16; value: root.draft.blur_size ?? 2; onValueModified: root.edit("blur_size", value) }
                    }
                    NumberRow {
                        label: "Glow intensity (%)"
                        EffectsSpinBox { from: 0; to: 60; value: root.draft.glow_strength ?? 0; onValueModified: root.edit("glow_strength", value) }
                    }
                }
            },
            DesignSection {
                nested: true
                title: "Atmosphere"
                icon: "auto_awesome"
                sectionKey: "atmosphere"
                detailsSummary: (root.draft.aurora ? "Aurora on" : "Aurora off")
                    + "  ·  " + (root.draft.stars ? "Stars on" : "Stars off")
                    + "  ·  Intensity " + (root.draft.ambient_strength ?? 0)
                detailsData: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    EffectToggleRow {
                        text: "Drifting aurora light"
                        checked: root.draft.aurora === true
                        onClicked: root.edit("aurora", !checked)
                    }
                    EffectToggleRow {
                        text: "Twinkling stars"
                        checked: root.draft.stars === true
                        onClicked: root.edit("stars", !checked)
                    }
                    EffectToggleRow {
                        text: "Wallpaper follows workspace"
                        checked: root.draft.parallax === true
                        onClicked: root.edit("parallax", !checked)
                    }
                    NumberRow {
                        label: "Ambient light intensity"
                        EffectsSpinBox { from: 0; to: 80; value: root.draft.ambient_strength ?? 0; onValueModified: root.edit("ambient_strength", value) }
                    }
                    TimingSettingRow {
                        Layout.fillWidth: true
                        flatRow: true
                        effectsEditor: root
                        setting: Catalog.ambientSpeed
                    }
                }
            },
            DesignSection {
                nested: true
                title: "Shape & spacing"
                icon: "rounded_corner"
                sectionKey: "geometry"
                detailsSummary: "Gaps " + (root.draft.gaps ?? 0) + "px  ·  Corners " + (root.draft.rounding ?? 0) + "px  ·  Border " + (root.draft.border ?? 1) + "px"
                detailsData: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    NumberRow {
                        label: "Outer gaps (px)"
                        EffectsSpinBox { from: 0; to: 30; value: root.draft.gaps ?? 0; onValueModified: root.edit("gaps", value) }
                    }
                    NumberRow {
                        label: "Corner radius (px)"
                        EffectsSpinBox { from: 0; to: 20; value: root.draft.rounding ?? 0; onValueModified: root.edit("rounding", value) }
                    }
                    NumberRow {
                        label: "Border width (px)"
                        EffectsSpinBox { from: 1; to: 5; value: root.draft.border ?? 1; onValueModified: root.edit("border", value) }
                    }
                }
            },
            DesignSection {
                nested: true
                title: "Window opacity"
                icon: "opacity"
                sectionKey: "opacity"
                detailsSummary: "Notifications " + (root.draft.popup_opacity ?? 82) + "%  ·  Sidebars " + (root.draft.panel_opacity ?? 94) + "%"
                detailsData: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    NumberRow {
                        label: "Notification opacity (%)"
                        EffectsSpinBox { from: 65; to: 100; value: root.draft.popup_opacity ?? 82; onValueModified: root.edit("popup_opacity", value) }
                    }
                    NumberRow {
                        label: "Side panel opacity (%)"
                        EffectsSpinBox { from: 80; to: 100; value: root.draft.panel_opacity ?? 94; onValueModified: root.edit("panel_opacity", value) }
                    }
                }
            },
            DesignSection {
                nested: true
                title: "Effect accent"
                icon: "palette"
                sectionKey: "effectAccent"
                detailsSummary: "Current accent: " + (root.draft.palette ?? "aurora")
                detailsData: ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8
                    ConfigSelectionArray {
                        currentValue: root.draft.palette
                        options: [
                            { displayName: "Aurora", value: "aurora" },
                            { displayName: "Sunset", value: "sunset" },
                            { displayName: "Ocean", value: "ocean" },
                            { displayName: "Emerald", value: "emerald" }
                        ]
                        onSelected: value => root.edit("palette", value)
                    }
                }
            },
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: 6
                Layout.bottomMargin: 4
                implicitHeight: 1
                color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.45)
            },
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.topMargin: 4
                Layout.bottomMargin: 6
                spacing: 6
                StyledText {
                    text: "Save as preset"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onSurface
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SettingsField {
                        id: presetName
                        Layout.fillWidth: true
                        Layout.minimumWidth: 100
                        placeholderText: "Name your current look…"
                        maximumLength: 32
                        enabled: root.ready && !apply.running
                        onAccepted: if (savePreset.enabled) savePreset.clicked()
                    }
                    SettingsButton {
                        id: savePreset
                        prominent: true
                        text: "Save preset"
                        enabled: root.ready && !root.dirty && !apply.running && presetName.text.trim().length > 0
                        onClicked: root.run("save", presetName.text.trim())
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Apply pending edits before saving. Right-click any saved preset chip above to delete it."
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
            }
        ]
    }

    DesignSection {
        sectionKey: "animation"
        title: "Motion & animations"
        subtitle: root.profileMotion
            ? "Profile: " + (root.draft.animation_profile ?? "").replace(/\.lua$/, "").replace(/_/g, " ")
            : "Custom motion"
        icon: "animation"
        detailsLabel: "Customize timing, springs, motion blur & transitions"
        detailsSummary: (root.draft.motion ? "Motion blur on" : "Motion blur off")
            + "  ·  Tempo " + (root.draft[root.motionKey("tempo")] ?? 100) + "%"
        enabled: root.ready && !apply.running && !Config.writesPaused

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            Layout.bottomMargin: 6
            spacing: 16
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: "Animation profile"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    text: "Curated Hyprland spring curves and workspace transitions."
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
            SettingsComboBox {
                objectName: "animationProfilePicker"
                Layout.preferredWidth: Math.min(244, root.width * 0.45)
                model: DesktopEffects.animationProfiles
                textRole: "displayName"
                valueRole: "value"
                currentIndex: DesktopEffects.animationProfiles.findIndex(entry => entry.value === root.draft.animation_profile)
                onActivated: {
                    root.edit("animation_profile", currentValue);
                    root.edit("motion_source", "profile");
                }
            }
        }

        detailsData: [
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 4
                    spacing: 10
                    ConfigSelectionArray {
                        Layout.fillWidth: true
                        currentValue: root.draft.motion_source ?? "custom"
                        options: [
                            { displayName: "Animation profile", value: "profile" },
                            { displayName: "Custom motion", value: "custom" }
                        ]
                        onSelected: value => root.edit("motion_source", value)
                    }
                    SettingsButton {
                        visible: root.profileMotion
                        text: "Reset tweaks"
                        onClicked: {
                            root.edit("profile_tempo", 100);
                            root.edit("profile_travel", -1);
                            root.edit("profile_bounce", 0);
                            root.edit("profile_workspace_style", "preset");
                            root.edit("profile_window_style", "preset");
                        }
                    }
                }
                EffectToggleRow {
                    text: "Motion blur"
                    description: "Subtle directional blur during rapid window movement."
                    checked: root.draft.motion === true
                    onClicked: root.edit("motion", !checked)
                }
                NumberRow {
                    label: "Motion blur samples"
                    EffectsSpinBox { from: 3; to: 24; value: root.draft.samples ?? 3; onValueModified: root.edit("samples", value) }
                }
                TimingSettingRow {
                    Layout.fillWidth: true
                    flatRow: true
                    effectsEditor: root
                    setting: Catalog.animationDuration
                }
                NumberRow {
                    label: "Glide travel (%)"
                    description: "Full slide always uses 100%."
                    EffectsSpinBox {
                        enabled: !["slide", "slidevert", "fade"].includes(root.draft[root.motionKey("workspace_style")])
                        from: root.profileMotion ? -1 : 0
                        to: 100
                        value: ["slide", "slidevert"].includes(root.draft[root.motionKey("workspace_style")])
                            ? 100 : root.draft[root.motionKey("travel")] ?? -1
                        textFromValue: value => value < 0 ? "Preset" : String(value)
                        valueFromText: text => text.toLowerCase() === "preset" ? -1 : Number(text)
                        onValueModified: root.edit(root.motionKey("travel"), value)
                    }
                }
                NumberRow {
                    label: "Spring damping"
                    description: "Lower values add more bounce."
                    EffectsSpinBox {
                        from: root.profileMotion ? 0 : 16
                        to: 32
                        value: root.draft[root.motionKey("bounce")] ?? 0
                        textFromValue: value => value === 0 ? "Preset" : String(value)
                        valueFromText: text => text.toLowerCase() === "preset" ? 0 : Number(text)
                        onValueModified: root.edit(root.motionKey("bounce"), value)
                    }
                }
            },
            DesignSection {
                nested: true
                title: "Workspace movement"
                icon: "view_carousel"
                sectionKey: "workspaceMotion"
                detailsSummary: "Style: " + (root.draft[root.motionKey("workspace_style")] ?? "preset")
                detailsData: ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8
                    ConfigSelectionArray {
                        currentValue: root.draft[root.motionKey("workspace_style")] ?? "preset"
                        options: (root.profileMotion ? [{ displayName: "Use preset", value: "preset" }] : []).concat([
                            { displayName: "Horizontal glide", value: "slidefade" },
                            { displayName: "Vertical glide", value: "slidefadevert" },
                            { displayName: "Full slide", value: "slide" },
                            { displayName: "Crossfade", value: "fade" }
                        ])
                        onSelected: value => root.edit(root.motionKey("workspace_style"), value)
                    }
                }
            },
            DesignSection {
                nested: true
                title: "Window entrance"
                icon: "open_in_new"
                sectionKey: "windowMotion"
                detailsSummary: "Style: " + (root.draft[root.motionKey("window_style")] ?? "preset")
                detailsData: ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8
                    ConfigSelectionArray {
                        currentValue: root.draft[root.motionKey("window_style")] ?? "preset"
                        options: (root.profileMotion ? [{ displayName: "Use preset", value: "preset" }] : []).concat([
                            { displayName: "Scale reveal", value: "popin" },
                            { displayName: "Full slide", value: "slide" },
                            { displayName: "GNOME zoom", value: "gnomed" }
                        ])
                        onSelected: value => root.edit(root.motionKey("window_style"), value)
                    }
                }
            }
        ]
    }
}
