import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 18

    property var profiles: []
    property string activeCategory: "all"
    property string selectedId: ""
    property bool compactScale: false
    property bool grayscaleSmoothing: false
    property int previewMonitorIndex: 0
    property string statusTone: "info" // "info", "ok", "warn", "error"
    property string statusTitle: "Reading installed font presets…"
    property string rawOutput: ""
    property bool showDetails: false
    property bool awaitingReload: false
    property bool previewReady: false

    property var kittyState: null
    property string kittyMessage: ""
    property bool kittyEnabled: false

    readonly property bool isLight: Appearance.m3colors.darkmode === false
    readonly property bool wide: width >= 580
    readonly property bool busy: apply.running || awaitingReload
    readonly property bool kittyBusy: kittyRefresh.running || kittyAction.running
    readonly property bool kittyAvailable: kittyState !== null
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/fontctl"
    readonly property string kittyHelper: Quickshell.env("HOME") + "/.local/bin/kitty-font-monitor"

    readonly property var selectedProfile: {
        const found = profiles.find(p => p.id === selectedId);
        return found || (profiles.length > 0 ? profiles[0] : null);
    }
    readonly property string selectedName: selectedProfile?.id ?? ""
    readonly property string presetName: selectedName + (compactScale ? "-10pt" : "")
    readonly property var filteredProfiles: {
        if (activeCategory === "all") return profiles;
        return profiles.filter(p => (p.group || "modern") === activeCategory);
    }

    readonly property real effectiveUiPt: compactScale ? 10 : (selectedProfile?.uiSize ?? 11)
    readonly property real effectiveMonoPt: compactScale ? 10 : (selectedProfile?.monoSize ?? 12)
    readonly property real effectiveTitlePt: compactScale ? 10 : (selectedProfile?.titleSize ?? 13)
    readonly property real effectiveKittyPt: {
        if (kittyEnabled && kittyState) {
            const mons = kittyState.monitors || [];
            if (mons.length > 0) {
                const idx = Math.max(0, Math.min(previewMonitorIndex, mons.length - 1));
                if (mons[idx]?.effective_size > 0) return mons[idx].effective_size;
            }
            if (kittyState.default_size > 0) return kittyState.default_size;
        }
        return compactScale ? 10 : (selectedProfile?.kittySize ?? 11);
    }
    readonly property string effectiveKittyTargetLabel: {
        if (kittyEnabled && kittyState && (kittyState.monitors || []).length > 0) {
            const mons = kittyState.monitors;
            const idx = Math.max(0, Math.min(previewMonitorIndex, mons.length - 1));
            return (mons[idx]?.name || "Monitor") + " · " + formatPt(effectiveKittyPt);
        }
        return "Kitty · " + formatPt(effectiveKittyPt);
    }

    readonly property color panelBg: isLight ? Appearance.m3colors.m3surfaceContainerLow : Appearance.m3colors.m3surfaceContainer
    readonly property color panelRaisedBg: isLight ? Appearance.m3colors.m3surfaceContainerLowest : Appearance.m3colors.m3surfaceContainerHigh
    readonly property color hairline: Qt.alpha(Appearance.m3colors.m3outlineVariant, isLight ? 0.55 : 0.32)

    function shortMonoName(family) {
        return (family || "Monospace")
            .replace(/\s*Nerd Font Mono$/i, "")
            .replace(/\s*Nerd Font$/i, "")
            .trim();
    }
    function shortMonitorName(mon) {
        if (!mon) return "Monitor";
        const lbl = mon.label || mon.name || "Monitor";
        if (/arzopa/i.test(lbl)) return "Arzopa";
        if (/aoc/i.test(lbl)) return "AOC";
        return mon.name || lbl.split(" ")[0];
    }

    onKittyStateChanged: kittyEnabled = kittyState?.enabled === true
    onPresetNameChanged: {
        previewReady = false;
        if (selectedProfile) {
            statusTone = "info";
            statusTitle = "Previewing " + displayLabel(selectedProfile) + " — verify installed families to unlock Apply.";
        }
    }
    Component.onDestruction: if (Config.writesPaused && root.awaitingReload) Config.writesPaused = false

    function cleaned(text) { return (text || "").replace(/\x1b\[[0-9;]*m/g, "").trim(); }
    function displayLabel(profile) {
        if (!profile) return "";
        return profile.label || (profile.id.charAt(0).toUpperCase() + profile.id.slice(1));
    }
    function formatPt(value) {
        const n = Math.round(Number(value || 0) * 100) / 100;
        if (n <= 0) return "Preset";
        return (Math.abs(n - Math.round(n)) < 0.001 ? String(Math.round(n)) : String(n)) + " pt";
    }
    function ptToPx(pt, minPx, maxPx) {
        return Math.max(minPx, Math.min(maxPx, Math.round(Number(pt || 11) * 96 / 72)));
    }
    function stepPt(current, fallback, delta) {
        const base = Number(current) > 0 ? Number(current) : (Number(fallback) > 0 ? Number(fallback) : 10);
        const next = Math.max(6, Math.min(36, Math.round((base + delta) * 2) / 2));
        return String(next);
    }
    function isDesktopCurrent(profile) {
        if (!profile) return false;
        const curUi = (Config.options.appearance.fonts.main || "").toLowerCase();
        const curMono = (Config.options.appearance.fonts.monospace || "").toLowerCase();
        const curTitle = (Config.options.appearance.fonts.title || "").toLowerCase();
        const pUi = (profile.ui || "").toLowerCase();
        const pMono = (profile.mono || "").toLowerCase();
        const pTitle = (profile.title || "").toLowerCase();
        return pUi.length > 0 && pUi === curUi && pMono === curMono && pTitle === curTitle;
    }
    function selectProfileById(id) {
        if (!id) return;
        selectedId = id;
        const idx = profiles.findIndex(p => p.id === id);
        if (idx >= 0 && picker.currentIndex !== idx) picker.currentIndex = idx;
    }
    function runKitty(commandArgs, note) {
        if (kittyAction.running) return;
        kittyAction.pendingNote = note || "";
        kittyAction.command = [kittyHelper, ...commandArgs];
        kittyAction.running = true;
    }
    function args(previewMode) {
        let result = [helper, "preset", presetName, "--user-only"];
        result.push("--hintstyle", ["hintfull", "hintslight", "hintmedium", "hintnone"][hinting.currentIndex]);
        if (grayscaleSmoothing) result.push("--subpixel", "none");
        if (previewMode) result.push("--preview");
        return result;
    }

    // Reusable segmented option tile (Apple / Material 3 Expressive style)
    component OptionCard: AbstractButton {
        id: opt
        property string titleText: ""
        property string subtitleText: ""
        property string badgeText: ""
        property string iconName: ""
        property bool selected: false
        implicitHeight: Math.max(66, optContent.implicitHeight + 22)
        padding: 0
        opacity: enabled ? 1 : 0.45
        background: Rectangle {
            radius: 14
            color: opt.selected
                ? Appearance.m3colors.m3secondaryContainer
                : opt.down
                    ? Appearance.m3colors.m3surfaceContainerHighest
                    : opt.hovered
                        ? Appearance.m3colors.m3surfaceContainerHighest
                        : root.panelRaisedBg
            border.width: opt.selected || opt.visualFocus ? 2 : 1
            border.color: opt.selected || opt.visualFocus ? Appearance.m3colors.m3primary : root.hairline
            Behavior on color { ColorAnimation { duration: 130 } }
            Behavior on border.color { ColorAnimation { duration: 130 } }
        }
        contentItem: RowLayout {
            id: optContent
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 13; rightMargin: 12 }
            spacing: 10
            MaterialSymbol {
                visible: opt.iconName.length > 0
                text: opt.iconName
                iconSize: 20
                fill: opt.selected ? 1 : 0
                color: opt.selected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: opt.titleText
                        textFormat: Text.PlainText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: opt.selected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        visible: opt.badgeText.length > 0
                        implicitHeight: 20
                        implicitWidth: optBadgeLabel.implicitWidth + 12
                        radius: 10
                        color: opt.selected
                            ? Qt.alpha(Appearance.m3colors.m3onSecondaryContainer, 0.14)
                            : Qt.alpha(Appearance.m3colors.m3onSurface, root.isLight ? 0.08 : 0.11)
                        StyledText {
                            id: optBadgeLabel
                            anchors.centerIn: parent
                            text: opt.badgeText
                            textFormat: Text.PlainText
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: opt.selected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: opt.subtitleText.length > 0
                    text: opt.subtitleText
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: opt.selected
                        ? Qt.alpha(Appearance.m3colors.m3onSecondaryContainer, 0.85)
                        : Appearance.m3colors.m3onSurfaceVariant
                }
            }
            MaterialSymbol {
                visible: opt.selected
                text: "check_circle"
                iconSize: 18
                fill: 1
                color: Appearance.m3colors.m3primary
            }
        }
    }

    component Eyebrow: StyledText {
        Layout.fillWidth: true
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: Appearance.m3colors.m3primary
        textFormat: Text.PlainText
    }

    // ── Subprocess Helpers ──────────────────────────────────────────────────────
    Process {
        command: [root.helper, "preset", "catalog"]
        running: true
        stdout: StdioCollector { id: catalogOutput }
        stderr: StdioCollector { id: catalogError }
        onExited: code => {
            if (code !== 0) {
                root.statusTone = "error";
                root.statusTitle = "fontctl is unavailable. Install the fork's fontctl helper.";
                return;
            }
            try {
                const list = JSON.parse(catalogOutput.text);
                root.profiles = list;
                const activeMatch = list.find(p => root.isDesktopCurrent(p));
                const initial = activeMatch || list[0];
                if (initial) {
                    root.selectProfileById(initial.id);
                    Qt.callLater(() => {
                        const idx = root.filteredProfiles.findIndex(p => p.id === initial.id);
                        if (idx >= 0) {
                            const cols = root.wide ? 2 : 1;
                            const row = Math.floor(idx / cols);
                            galleryFlick.contentY = Math.max(0, Math.min(galleryFlick.contentHeight - galleryFlick.height, row * 82 - 8));
                        }
                    });
                }
                root.statusTone = "info";
                root.statusTitle = initial
                    ? ("Previewing " + root.displayLabel(initial) + " — click Verify fonts to check matches before applying.")
                    : "Choose a preset below.";
            } catch (error) {
                root.statusTone = "error";
                root.statusTitle = "Could not read the font catalog. Update fontctl and reopen Settings.";
            }
        }
    }

    Process {
        id: preview
        stdout: StdioCollector { id: previewOutput }
        stderr: StdioCollector { id: previewError }
        onExited: code => {
            const combined = root.cleaned(previewOutput.text + "\n" + previewError.text);
            root.rawOutput = combined;
            const isPresetCheck = preview.command[1] === "preset";
            root.previewReady = code === 0 && isPresetCheck;
            if (code !== 0) {
                root.statusTone = "error";
                root.statusTitle = "Font check failed — expand Details below to inspect.";
                root.showDetails = true;
            } else if (!isPresetCheck) {
                root.statusTone = "info";
                root.statusTitle = "Active desktop font targets loaded below.";
                root.showDetails = true;
            } else if (combined.indexOf("Missing family") >= 0) {
                root.statusTone = "warn";
                root.statusTitle = "Ready to apply, with a Fontconfig fallback warning (see Details).";
                root.showDetails = true;
            } else {
                root.statusTone = "ok";
                root.statusTitle = "Verified " + root.displayLabel(root.selectedProfile)
                    + " (" + root.presetName + ") — all font families resolved cleanly.";
            }
        }
    }

    Process {
        id: apply
        stdout: StdioCollector { id: applyOutput }
        stderr: StdioCollector { id: applyError }
        onExited: code => {
            const combined = root.cleaned(applyError.text + "\n" + applyOutput.text);
            root.rawOutput = combined;
            if (code === 0) {
                root.statusTone = "ok";
                root.statusTitle = "Applied " + root.displayLabel(root.selectedProfile) + ". Running apps may need reopening.";
            } else {
                root.statusTone = "error";
                root.statusTitle = "Font apply reported an issue — expand Details to review.";
                root.showDetails = true;
            }
            root.awaitingReload = true;
            Config.reloadFromDisk();
            releaseTimer.restart();
            if (root.kittyAvailable) kittyRefresh.running = true;
        }
    }

    Process {
        id: kittyRefresh
        command: [root.kittyHelper, "status", "--json"]
        running: true
        stdout: StdioCollector { id: kittyStatusOut }
        stderr: StdioCollector { id: kittyStatusErr }
        onExited: code => {
            if (code !== 0) {
                root.kittyState = null;
                root.kittyMessage = "Install kitty-font-monitor to manage per-monitor Kitty sizes here.";
                return;
            }
            try {
                root.kittyState = JSON.parse(kittyStatusOut.text);
                root.kittyMessage = "";
            } catch (error) {
                root.kittyState = null;
                root.kittyMessage = "Could not read Kitty monitor font settings.";
            }
        }
    }

    Process {
        id: kittyAction
        property string pendingNote: ""
        stdout: StdioCollector { id: kittyActionOut }
        stderr: StdioCollector { id: kittyActionErr }
        onExited: code => {
            if (code !== 0) {
                root.kittyEnabled = root.kittyState?.enabled === true;
                root.kittyMessage = root.cleaned(kittyActionErr.text + "\n" + kittyActionOut.text) || "Kitty monitor font update failed.";
                return;
            }
            try {
                const parsed = JSON.parse(kittyActionOut.text);
                if (parsed && parsed.monitors !== undefined) {
                    root.kittyState = parsed;
                    if (parsed.action && parsed.action.applied !== undefined) {
                        root.kittyMessage = "Saved and updated " + parsed.action.applied + " open Kitty window(s).";
                    } else if (parsed.action && parsed.action.reset !== undefined) {
                        root.kittyMessage = "Disabled and reset " + parsed.action.reset + " open Kitty window(s) to kitty.conf default.";
                    } else {
                        root.kittyMessage = pendingNote || "Saved Kitty monitor font settings.";
                    }
                    return;
                }
                if (parsed && parsed.applied !== undefined) {
                    root.kittyMessage = "Updated " + parsed.applied + " open Kitty window(s).";
                } else if (parsed && parsed.reset !== undefined) {
                    root.kittyMessage = "Reset " + parsed.reset + " open Kitty window(s) to kitty.conf default.";
                } else {
                    root.kittyMessage = pendingNote || "Done.";
                }
            } catch (error) {
                root.kittyMessage = pendingNote || "Done.";
            }
            kittyRefresh.running = true;
        }
    }

    Connections {
        target: Config
        function onReloaded() {
            if (root.awaitingReload) { root.awaitingReload = false; Config.writesPaused = false; releaseTimer.stop(); }
        }
    }

    Timer {
        id: releaseTimer
        interval: 3000
        onTriggered: {
            root.awaitingReload = false; Config.writesPaused = false;
            root.statusTitle += " Check shell font values below after reload.";
        }
    }

    // ── 1. HERO LIVE TYPOGRAPHY SPECIMEN ────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: specimenCol.implicitHeight + 28
        radius: 18
        color: root.panelBg
        border.width: 1
        border.color: root.hairline

        ColumnLayout {
            id: specimenCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            // Specimen Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        spacing: 8
                        StyledText {
                            text: root.selectedProfile ? root.displayLabel(root.selectedProfile) : "Typography Studio"
                            textFormat: Text.PlainText
                            font.family: root.selectedProfile?.title || Appearance.font.family.title
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSurface
                        }
                        Rectangle {
                            visible: root.isDesktopCurrent(root.selectedProfile)
                            implicitHeight: 22
                            implicitWidth: currentBadgeText.implicitWidth + 14
                            radius: 11
                            color: Appearance.m3colors.m3primaryContainer
                            StyledText {
                                id: currentBadgeText
                                anchors.centerIn: parent
                                text: "Active on desktop"
                                textFormat: Text.PlainText
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Appearance.m3colors.m3onPrimaryContainer
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.selectedProfile?.description ?? ""
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        color: Appearance.m3colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    visible: root.selectedProfile !== null
                    implicitHeight: 24
                    implicitWidth: scalePillText.implicitWidth + 16
                    radius: 12
                    color: root.panelRaisedBg
                    border.width: 1
                    border.color: root.hairline
                    StyledText {
                        id: scalePillText
                        anchors.centerIn: parent
                        text: root.compactScale ? "Compact 10 pt" : ("UI " + root.formatPt(root.effectiveUiPt) + " · Title " + root.formatPt(root.effectiveTitlePt))
                        textFormat: Text.PlainText
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                }
            }

            // Two-Pane Live Preview: Desktop Surface + Mini Kitty Terminal
            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: 12
                rowSpacing: 10

                // Left: Desktop UI & Editorial Specimen
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: uiSampleCol.implicitHeight + 28
                    radius: 14
                    color: root.panelRaisedBg
                    border.width: 1
                    border.color: root.hairline

                    ColumnLayout {
                        id: uiSampleCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Quiet clarity, built for focus."
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            font.family: root.selectedProfile?.title || Appearance.font.family.title
                            font.pixelSize: root.ptToPx(root.effectiveTitlePt, 14, 24) + 5
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSurface
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Buttons, notifications, menus and long paragraphs follow your interface voice — 0123456789."
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            font.family: root.selectedProfile?.ui || Appearance.font.family.main
                            font.pixelSize: root.ptToPx(root.effectiveUiPt, 12, 18)
                            color: Appearance.m3colors.m3onSurfaceVariant
                            lineHeight: 1.3
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 8
                            Rectangle {
                                implicitHeight: 28
                                implicitWidth: samplePrimaryLabel.implicitWidth + 20
                                radius: 14
                                color: Appearance.m3colors.m3primary
                                Text {
                                    id: samplePrimaryLabel
                                    anchors.centerIn: parent
                                    text: "Continue"
                                    textFormat: Text.PlainText
                                    font.family: root.selectedProfile?.ui || Appearance.font.family.main
                                    font.pixelSize: Math.max(11, root.ptToPx(root.effectiveUiPt, 11, 15) - 1)
                                    font.weight: Font.DemiBold
                                    color: Appearance.m3colors.m3onPrimary
                                }
                            }
                            Rectangle {
                                implicitHeight: 28
                                implicitWidth: sampleClockLabel.implicitWidth + 16
                                radius: 14
                                color: Appearance.m3colors.m3surfaceContainerHigh
                                Text {
                                    id: sampleClockLabel
                                    anchors.centerIn: parent
                                    text: "18:42 · 144 Hz"
                                    textFormat: Text.PlainText
                                    font.family: root.selectedProfile?.numbers || root.selectedProfile?.ui || Appearance.font.family.numbers
                                    font.pixelSize: Math.max(11, root.ptToPx(root.effectiveUiPt, 11, 15) - 1)
                                    font.weight: Font.Medium
                                    color: Appearance.m3colors.m3onSurface
                                }
                            }
                        }
                    }
                }

                // Right: Live Dark Mini Kitty Terminal Specimen
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: termSampleCol.implicitHeight + 24
                    radius: 14
                    color: "#151820"
                    border.width: 1
                    border.color: "#2c3242"

                    ColumnLayout {
                        id: termSampleCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: ["#ff6b6b", "#ffd166", "#5ad290"]
                                delegate: Rectangle {
                                    required property color modelData
                                    width: 8; height: 8; radius: 4
                                    color: modelData
                                    opacity: 0.85
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.shortMonoName(root.selectedProfile?.mono)
                                textFormat: Text.PlainText
                                font.family: root.selectedProfile?.mono || Appearance.font.family.monospace
                                font.pixelSize: 11
                                color: "#9aa5be"
                                elide: Text.ElideRight
                            }
                            // Quick monitor size switcher inside the terminal preview
                            Row {
                                visible: root.kittyEnabled && (root.kittyState?.monitors?.length ?? 0) > 1
                                spacing: 4
                                Repeater {
                                    model: root.kittyState?.monitors ?? []
                                    delegate: AbstractButton {
                                        required property var modelData
                                        required property int index
                                        readonly property bool activeChip: root.previewMonitorIndex === index
                                        implicitHeight: 20
                                        implicitWidth: monChipText.implicitWidth + 12
                                        padding: 0
                                        onClicked: root.previewMonitorIndex = index
                                        background: Rectangle {
                                            radius: 10
                                            color: parent.activeChip ? "#3b4766" : "#222736"
                                        }
                                        contentItem: Text {
                                            id: monChipText
                                            text: root.shortMonitorName(modelData) + " " + root.formatPt(modelData.effective_size)
                                            textFormat: Text.PlainText
                                            font.family: root.selectedProfile?.mono || Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            font.weight: parent.activeChip ? Font.DemiBold : Font.Normal
                                            color: parent.activeChip ? "#f1f5ff" : "#9aa5be"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: !root.kittyEnabled || (root.kittyState?.monitors?.length ?? 0) <= 1
                                text: root.effectiveKittyTargetLabel
                                textFormat: Text.PlainText
                                font.family: root.selectedProfile?.mono || Appearance.font.family.monospace
                                font.pixelSize: 10
                                color: "#8be9fd"
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "$ git status -sb\n## main...origin/main\n✓ 0 warnings · 144Hz VRR\nfn size(dpi: f32) -> " + root.formatPt(root.effectiveKittyPt)
                            textFormat: Text.PlainText
                            font.family: root.selectedProfile?.mono || Appearance.font.family.monospace
                            font.pixelSize: root.ptToPx(root.effectiveKittyPt, 10, 22)
                            color: "#e6ecf8"
                            lineHeight: 1.32
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Role Summary Pills
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: root.selectedProfile !== null
                Repeater {
                    model: root.selectedProfile ? [
                        "UI · " + (root.selectedProfile.ui || "—") + " " + root.formatPt(root.effectiveUiPt),
                        "Titles · " + (root.selectedProfile.title || "—") + " " + root.formatPt(root.effectiveTitlePt),
                        "Terminal · " + (root.selectedProfile.mono || "—") + " " + root.formatPt(root.effectiveKittyPt),
                        "Reading · " + (root.selectedProfile.reading || "—")
                    ] : []
                    delegate: Rectangle {
                        required property string modelData
                        implicitHeight: 24
                        implicitWidth: roleLabel.implicitWidth + 16
                        radius: 12
                        color: root.panelRaisedBg
                        StyledText {
                            id: roleLabel
                            anchors.centerIn: parent
                            text: modelData
                            textFormat: Text.PlainText
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    // ── 2. VISUAL PRESET GALLERY & QUICK PICKER ─────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Eyebrow { text: "CHOOSE A TYPEFACE PRESET" }
                StyledText {
                    Layout.fillWidth: true
                    text: "Click any card to preview live above. All 26 curated presets remain available."
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
            SettingsComboBox {
                id: picker
                objectName: "fontProfilePicker"
                Layout.preferredWidth: root.wide ? 270 : Math.min(220, root.width * 0.48)
                model: root.profiles.map(p => ({label: root.displayLabel(p) + " — " + (p.ui || p.description), value: p.id}))
                textRole: "label"
                enabled: !root.busy && !preview.running && root.profiles.length > 0
                Accessible.name: "Font profile"
                onActivated: index => {
                    if (index >= 0 && index < root.profiles.length) {
                        root.selectedId = root.profiles[index].id;
                    }
                }
            }
        }

        // Category Filter Chips
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    {id: "all", label: "All (" + root.profiles.length + ")"},
                    {id: "charming", label: "Charming"},
                    {id: "editorial", label: "Editorial"},
                    {id: "modern", label: "Modern"},
                    {id: "dense", label: "Compact & Dense"},
                    {id: "classic", label: "Classic"}
                ]
                delegate: AbstractButton {
                    id: chip
                    required property var modelData
                    readonly property bool selected: root.activeCategory === modelData.id
                    implicitHeight: 30
                    implicitWidth: chipTxt.implicitWidth + 24
                    padding: 0
                    enabled: !root.busy
                    onClicked: root.activeCategory = modelData.id
                    background: Rectangle {
                        radius: 15
                        color: chip.selected
                            ? Appearance.m3colors.m3primaryContainer
                            : chip.hovered
                                ? Appearance.m3colors.m3surfaceContainerHighest
                                : root.panelRaisedBg
                        border.width: chip.selected ? 0 : 1
                        border.color: root.hairline
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    contentItem: StyledText {
                        id: chipTxt
                        text: chip.modelData.label
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        font.weight: chip.selected ? Font.DemiBold : Font.Medium
                        color: chip.selected ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        // Scrollable Visual Specimen Card Grid
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.min(266, Math.max(92, galleryGrid.implicitHeight + 16))
            radius: 16
            color: root.panelBg
            border.width: 1
            border.color: root.hairline
            clip: true

            Flickable {
                id: galleryFlick
                anchors.fill: parent
                anchors.margins: 8
                contentWidth: width
                contentHeight: galleryGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                GridLayout {
                    id: galleryGrid
                    width: galleryFlick.width - 6
                    columns: root.wide ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    Repeater {
                        model: root.filteredProfiles
                        delegate: AbstractButton {
                            id: card
                            required property var modelData
                            readonly property bool isSelected: root.selectedId === modelData.id
                            readonly property bool isActiveDesktop: root.isDesktopCurrent(modelData)
                            Layout.fillWidth: true
                            implicitHeight: 74
                            padding: 0
                            enabled: !root.busy && !preview.running
                            Accessible.name: root.displayLabel(modelData) + " font preset"
                            onClicked: root.selectProfileById(modelData.id)

                            background: Rectangle {
                                radius: 13
                                color: card.isSelected
                                    ? Appearance.m3colors.m3secondaryContainer
                                    : card.down
                                        ? Appearance.m3colors.m3surfaceContainerHighest
                                        : card.hovered
                                            ? Appearance.m3colors.m3surfaceContainerHighest
                                            : root.panelRaisedBg
                                border.width: card.isSelected || card.visualFocus ? 2 : 1
                                border.color: card.isSelected || card.visualFocus ? Appearance.m3colors.m3primary : root.hairline
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                            }

                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 8; bottomMargin: 8 }
                                spacing: 10

                                Rectangle {
                                    implicitWidth: 46
                                    implicitHeight: 46
                                    radius: 11
                                    color: card.isSelected
                                        ? Appearance.m3colors.m3primary
                                        : Appearance.m3colors.m3surfaceContainerHigh
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Aa"
                                        textFormat: Text.PlainText
                                        font.family: card.modelData.title || card.modelData.ui || Appearance.font.family.main
                                        font.pixelSize: 21
                                        font.weight: Font.DemiBold
                                        color: card.isSelected ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: root.displayLabel(card.modelData)
                                            textFormat: Text.PlainText
                                            font.family: card.modelData.ui || Appearance.font.family.main
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            color: card.isSelected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Rectangle {
                                            visible: card.isActiveDesktop
                                            implicitHeight: 18
                                            implicitWidth: activeDotTxt.implicitWidth + 10
                                            radius: 9
                                            color: Appearance.m3colors.m3primaryContainer
                                            StyledText {
                                                id: activeDotTxt
                                                anchors.centerIn: parent
                                                text: "Active"
                                                textFormat: Text.PlainText
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: Appearance.m3colors.m3onPrimaryContainer
                                            }
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.description || ""
                                        textFormat: Text.PlainText
                                        font.family: card.modelData.ui || Appearance.font.family.main
                                        font.pixelSize: 11
                                        color: card.isSelected
                                            ? Qt.alpha(Appearance.m3colors.m3onSecondaryContainer, 0.85)
                                            : Appearance.m3colors.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: (card.modelData.ui || "") + "  ·  " + (card.modelData.mono || "")
                                        textFormat: Text.PlainText
                                        font.family: card.modelData.mono || Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        color: card.isSelected
                                            ? Qt.alpha(Appearance.m3colors.m3onSecondaryContainer, 0.72)
                                            : Appearance.m3colors.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── 3. TEXT SIZE & EDGE CLARITY (PLAIN ENGLISH, NO JARGON) ──────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        Eyebrow { text: "SIZE SCALE & EDGE CLARITY" }

        // A. Text Scale (replaces cryptic "Uniform 10 pt")
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                text: "Desktop text scale"
                textFormat: Text.PlainText
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSurface
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                OptionCard {
                    objectName: "fontScalePreset"
                    Layout.fillWidth: true
                    iconName: "format_size"
                    titleText: "Natural hierarchy"
                    badgeText: root.selectedProfile
                        ? (root.selectedProfile.uiSize + " / " + root.selectedProfile.titleSize + " / " + root.selectedProfile.monoSize + " pt")
                        : "Balanced"
                    subtitleText: "Keeps each preset's intended contrast between headings, UI labels and code."
                    selected: !root.compactScale
                    enabled: !root.busy && !preview.running
                    onClicked: root.compactScale = false
                }
                OptionCard {
                    objectName: "fontScaleCompact"
                    Layout.fillWidth: true
                    iconName: "density_small"
                    titleText: "Compact 10 pt everywhere"
                    badgeText: "10 pt"
                    subtitleText: "Overrides UI, titles and code to a uniform 10 pt so more content fits on 1080p."
                    selected: root.compactScale
                    enabled: !root.busy && !preview.running
                    onClicked: root.compactScale = true
                }
            }
        }

        // B. Edge Smoothing (replaces cryptic "Grayscale rendering")
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                text: "Edge smoothing (Subpixel antialiasing)"
                textFormat: Text.PlainText
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSurface
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                OptionCard {
                    objectName: "fontSmoothRgb"
                    Layout.fillWidth: true
                    iconName: "desktop_windows"
                    titleText: "RGB subpixel"
                    badgeText: "Best for AOC"
                    subtitleText: "Uses red/green/blue subpixels for maximum sharpness on standard desktop LCDs."
                    selected: !root.grayscaleSmoothing
                    enabled: !root.busy && !preview.running
                    onClicked: {
                        if (root.grayscaleSmoothing) {
                            root.grayscaleSmoothing = false;
                            root.previewReady = false;
                        }
                    }
                }
                OptionCard {
                    objectName: "fontSmoothGrayscale"
                    Layout.fillWidth: true
                    iconName: "blur_linear"
                    titleText: "Grayscale smoothing"
                    badgeText: "No color fringe"
                    subtitleText: "Neutral monochrome edges — avoids colored fringes on portable or non-RGB panels."
                    selected: root.grayscaleSmoothing
                    enabled: !root.busy && !preview.running
                    onClicked: {
                        if (!root.grayscaleSmoothing) {
                            root.grayscaleSmoothing = true;
                            root.previewReady = false;
                        }
                    }
                }
            }
        }

        // C. Pixel-Grid Alignment (Hinting)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                text: "Pixel-grid alignment (Hinting)"
                textFormat: Text.PlainText
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: "Controls how strictly glyph stems snap to screen pixels. Stronger is crisper on 1080p; slight keeps macOS-like letter shapes."
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            SettingsComboBox {
                id: hinting
                objectName: "fontHinting"
                Layout.fillWidth: true
                Layout.topMargin: 2
                model: [
                    "Crisp grid (Full) — sharpest edges on 1080p screens",
                    "Natural shapes (Slight) — macOS-like smooth curves",
                    "Balanced (Medium) — middle ground between crisp and smooth",
                    "Unmodified (None) — pure outline geometry, zero snapping"
                ]
                enabled: !root.busy && !preview.running
                Accessible.name: "Font hinting"
                onCurrentIndexChanged: root.previewReady = false
            }
        }
    }

    // ── 4. VERIFY & APPLY BAR ───────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: applyBarCol.implicitHeight + 22
        radius: 16
        color: root.panelBg
        border.width: 1
        border.color: root.hairline

        ColumnLayout {
            id: applyBarCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: root.statusTone === "ok" ? "check_circle"
                        : root.statusTone === "error" ? "error"
                        : root.statusTone === "warn" ? "warning" : "info"
                    iconSize: 18
                    fill: root.statusTone === "ok" ? 1 : 0
                    color: root.statusTone === "ok" ? Appearance.m3colors.m3success
                        : root.statusTone === "error" ? Appearance.m3colors.m3error
                        : Appearance.m3colors.m3primary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusTitle
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onSurface
                }
                AbstractButton {
                    visible: root.rawOutput.length > 0
                    implicitHeight: 26
                    implicitWidth: detLabel.implicitWidth + 16
                    padding: 0
                    onClicked: root.showDetails = !root.showDetails
                    background: Rectangle {
                        radius: 13
                        color: parent.hovered ? Appearance.m3colors.m3surfaceContainerHighest : root.panelRaisedBg
                    }
                    contentItem: StyledText {
                        id: detLabel
                        text: root.showDetails ? "Hide details" : "Details"
                        textFormat: Text.PlainText
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3primary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8
                SettingsButton {
                    objectName: "fontPreview"
                    prominent: !root.previewReady
                    text: preview.running ? "Verifying fonts…" : "Verify fonts"
                    enabled: root.selectedName.length > 0 && !root.busy && !preview.running
                    onClicked: { root.previewReady = false; preview.command = root.args(true); preview.running = true; }
                }
                SettingsButton {
                    objectName: "fontApply"
                    prominent: root.previewReady
                    text: root.busy ? "Applying…" : "Apply to desktop"
                    enabled: root.previewReady && !root.busy && !preview.running
                    onClicked: {
                        Config.flushPendingWrites();
                        if (Config.writeError) { root.statusTone = "error"; root.statusTitle = Config.writeError; return; }
                        Config.writesPaused = true;
                        apply.command = root.args(false); apply.running = true;
                    }
                }
                SettingsButton {
                    text: "Inspect active"
                    enabled: !root.busy && !preview.running
                    onClicked: { root.previewReady = false; preview.command = [root.helper, "status"]; preview.running = true; }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: "Updates GTK, Qt, Quickshell, Kitty & browsers (website fonts & zoom stay intact; Quickshell restarts automatically)."
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                color: Appearance.m3colors.m3onSurfaceVariant
            }

            Rectangle {
                visible: root.showDetails && root.rawOutput.length > 0
                Layout.fillWidth: true
                implicitHeight: Math.min(200, detailsText.implicitHeight + 18)
                radius: 10
                color: root.panelRaisedBg
                border.width: 1
                border.color: root.hairline
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 9
                    contentWidth: width
                    contentHeight: detailsText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        id: detailsText
                        width: parent.width
                        text: root.rawOutput
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                }
            }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.hairline }

    // ── 5. PER-MONITOR TERMINAL SIZING (KITTY) ──────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                implicitWidth: 38
                implicitHeight: 38
                radius: 12
                color: root.kittyEnabled ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "terminal"
                    iconSize: 20
                    color: root.kittyEnabled ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    spacing: 8
                    StyledText {
                        text: "Terminal sizing by monitor (Kitty)"
                        textFormat: Text.PlainText
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSurface
                    }
                    Rectangle {
                        visible: root.kittyAvailable
                        implicitHeight: 20
                        implicitWidth: kmBadge.implicitWidth + 12
                        radius: 10
                        color: root.kittyEnabled ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                        StyledText {
                            id: kmBadge
                            anchors.centerIn: parent
                            text: root.kittyEnabled ? "Active" : "Off"
                            textFormat: Text.PlainText
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: root.kittyEnabled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Use a denser Kitty size on large desktop displays (AOC) and a larger size on compact portable panels (Arzopa), without changing Hyprland display scale. Off stops all monitor overrides."
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Appearance.m3colors.m3onSurfaceVariant
                    font.pixelSize: 12
                }
            }
            SettingsSwitch {
                objectName: "kittyMonitorFontsMaster"
                Accessible.name: "Enable per-monitor Kitty font sizing"
                checked: root.kittyEnabled
                enabled: root.kittyAvailable && !root.kittyBusy && !root.busy
                onToggled: {
                    root.kittyEnabled = checked;
                    if (checked) root.runKitty(["set", "--enabled", "true", "--apply", "--json"], "Enabled per-monitor Kitty sizing.");
                    else root.runKitty(["set", "--enabled", "false", "--reset-live", "--json"], "Disabled per-monitor Kitty sizing.");
                }
            }
        }

        ColumnLayout {
            visible: root.kittyAvailable && root.kittyEnabled
            Layout.fillWidth: true
            spacing: 12

            // Side-by-side Display Cards with Live Terminal Density Preview
            GridLayout {
                Layout.fillWidth: true
                visible: (root.kittyState?.monitors?.length ?? 0) > 0
                columns: root.wide ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: root.kittyState?.monitors ?? []
                    delegate: Rectangle {
                        id: monCard
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: monCardCol.implicitHeight + 24
                        radius: 16
                        color: root.panelBg
                        border.width: 1
                        border.color: root.hairline

                        ColumnLayout {
                            id: monCardCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle {
                                    implicitWidth: 34
                                    implicitHeight: 34
                                    radius: 10
                                    color: Appearance.m3colors.m3surfaceContainerHigh
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: (monCard.modelData.inches > 0 && monCard.modelData.inches < 20) ? "tablet_mac" : "desktop_windows"
                                        iconSize: 18
                                        color: Appearance.m3colors.m3primary
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    StyledText {
                                        text: monCard.modelData.label
                                        textFormat: Text.PlainText
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: Appearance.m3colors.m3onSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    StyledText {
                                        text: monCard.modelData.connected
                                            ? (monCard.modelData.width + "×" + monCard.modelData.height
                                                + (monCard.modelData.inches > 0 ? (" · " + monCard.modelData.inches + "″ · " + monCard.modelData.ppi + " PPI") : ""))
                                            : "Disconnected saved display"
                                        textFormat: Text.PlainText
                                        font.pixelSize: 11
                                        color: Appearance.m3colors.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // True-size mini terminal sample for this monitor
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Math.max(38, monSampleTxt.implicitHeight + 14)
                                radius: 10
                                color: "#151820"
                                border.width: 1
                                border.color: "#2c3242"
                                Text {
                                    id: monSampleTxt
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                                    text: "[TMUX] " + root.shortMonitorName(monCard.modelData) + " · 0123456789"
                                    textFormat: Text.PlainText
                                    font.family: root.selectedProfile?.mono || Appearance.font.family.monospace
                                    font.pixelSize: root.ptToPx(monCard.modelData.effective_size, 10, 22)
                                    color: "#e6ecf8"
                                    elide: Text.ElideRight
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                StyledText {
                                    Layout.fillWidth: true
                                    text: monCard.modelData.configured_size > 0 ? "Custom monitor size" : "Inherits default"
                                    textFormat: Text.PlainText
                                    font.pixelSize: 11
                                    color: Appearance.m3colors.m3onSurfaceVariant
                                }
                                SettingsButton {
                                    text: "−"
                                    implicitHeight: 32
                                    leftPadding: 11
                                    rightPadding: 11
                                    enabled: !root.kittyBusy
                                    onClicked: root.runKitty(["set", "--monitor", monCard.modelData.selector + "=" + root.stepPt(monCard.modelData.effective_size, root.kittyState.default_size, -0.5), "--apply", "--json"])
                                }
                                StyledText {
                                    text: root.formatPt(monCard.modelData.effective_size)
                                    textFormat: Text.PlainText
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: Appearance.m3colors.m3onSurface
                                    Layout.minimumWidth: 54
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                SettingsButton {
                                    text: "+"
                                    implicitHeight: 32
                                    leftPadding: 11
                                    rightPadding: 11
                                    enabled: !root.kittyBusy
                                    onClicked: root.runKitty(["set", "--monitor", monCard.modelData.selector + "=" + root.stepPt(monCard.modelData.effective_size, root.kittyState.default_size, 0.5), "--apply", "--json"])
                                }
                            }
                        }
                    }
                }
            }

            // Sticky default + Behavior switches inside one tonal card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: kittyPrefsCol.implicitHeight + 24
                radius: 16
                color: root.panelBg
                border.width: 1
                border.color: root.hairline

                ColumnLayout {
                    id: kittyPrefsCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                text: "Default Kitty size across presets"
                                textFormat: Text.PlainText
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Appearance.m3colors.m3onSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Saved to kitty.conf and preserved whenever you switch fontctl presets."
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                font.pixelSize: 11
                                color: Appearance.m3colors.m3onSurfaceVariant
                            }
                        }
                        SettingsButton {
                            objectName: "kittyDefaultMinus"
                            text: "−"
                            implicitHeight: 32
                            leftPadding: 11
                            rightPadding: 11
                            enabled: !root.kittyBusy
                            onClicked: root.runKitty(["set", "--default", root.stepPt(root.kittyState.default_size, root.kittyState.kitty_conf_size, -0.5), "--apply", "--json"])
                        }
                        StyledText {
                            objectName: "kittyDefaultValue"
                            text: root.formatPt(root.kittyState?.default_size ?? 0)
                            textFormat: Text.PlainText
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSurface
                            Layout.minimumWidth: 54
                            horizontalAlignment: Text.AlignHCenter
                        }
                        SettingsButton {
                            objectName: "kittyDefaultPlus"
                            text: "+"
                            implicitHeight: 32
                            leftPadding: 11
                            rightPadding: 11
                            enabled: !root.kittyBusy
                            onClicked: root.runKitty(["set", "--default", root.stepPt(root.kittyState.default_size, root.kittyState.kitty_conf_size, 0.5), "--apply", "--json"])
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.hairline }

                    SettingsCheckBox {
                        objectName: "kittyAutoOnMove"
                        Layout.fillWidth: true
                        text: "Auto-adjust when opening or moving Kitty between monitors (preserves manual Ctrl+Shift+± zoom on the same screen)"
                        checked: root.kittyState?.auto_on_move === true
                        enabled: !root.kittyBusy
                        onToggled: root.runKitty(["set", "--auto-on-move", checked ? "true" : "false", "--json"])
                    }
                    SettingsCheckBox {
                        objectName: "kittyReloadOnFontctl"
                        Layout.fillWidth: true
                        text: "Live-reload open Kitty windows when applying a font preset"
                        checked: root.kittyState?.reload_on_fontctl === true
                        enabled: !root.kittyBusy
                        onToggled: root.runKitty(["set", "--reload-on-fontctl", checked ? "true" : "false", "--json"])
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        SettingsButton {
                            objectName: "kittyApplyOpen"
                            text: "Apply to open Kitty (" + (root.kittyState?.live_kitty_count ?? 0) + ")"
                            enabled: !root.kittyBusy
                            onClicked: root.runKitty(["apply", "--json"])
                        }
                        SettingsButton {
                            objectName: "kittyResetOpen"
                            text: "Reset open windows"
                            enabled: !root.kittyBusy
                            onClicked: root.runKitty(["reset", "--json"])
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.kittyMessage.length > 0
            Layout.fillWidth: true
            text: root.kittyMessage
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.hairline }
}
