import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ScrollView {
    id: root
    signal edited(string path)
    property string requestedSection: ""
    readonly property bool effectsDirty: desktopEffects.dirty
    readonly property alias effectsEditor: desktopEffects
    readonly property bool effectsBusy: desktopEffects.busy || !desktopEffects.ready
    readonly property string effectsStatus: desktopEffects.status
    function applyEffects() { desktopEffects.run("apply", JSON.stringify(desktopEffects.draft)); }
    function resetEffects() { desktopEffects.sync(); }
    contentWidth: availableWidth
    topPadding: 14
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    component ModeCard: AbstractButton {
        id: modeBtn
        property bool selected: false
        property string modeIcon: "light_mode"
        property string modeTitle: "Light"
        property string modeSubtitle: ""
        enabled: !Config.writesPaused
        implicitHeight: 62
        background: Rectangle {
            radius: 16
            color: modeBtn.selected
                ? Appearance.m3colors.m3primaryContainer
                : modeBtn.down
                    ? Appearance.m3colors.m3surfaceContainerHighest
                    : modeBtn.hovered
                        ? Appearance.m3colors.m3surfaceContainerHighest
                        : Appearance.m3colors.m3surfaceContainerHigh
            border.width: modeBtn.selected || modeBtn.visualFocus ? 2 : 0
            border.color: Appearance.m3colors.m3primary
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        contentItem: RowLayout {
            anchors { fill: parent; leftMargin: 16; rightMargin: 14 }
            spacing: 12
            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: 12
                color: modeBtn.selected ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHighest
                Behavior on color { ColorAnimation { duration: 150 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: modeBtn.modeIcon
                    iconSize: 20
                    fill: modeBtn.selected ? 1 : 0
                    color: modeBtn.selected ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurfaceVariant
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    text: modeBtn.modeTitle
                    textFormat: Text.PlainText
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: modeBtn.selected ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface
                }
                StyledText {
                    visible: modeBtn.modeSubtitle.length > 0
                    text: modeBtn.modeSubtitle
                    textFormat: Text.PlainText
                    font.pixelSize: 11
                    color: modeBtn.selected ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                    opacity: modeBtn.selected ? 0.85 : 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            MaterialSymbol {
                visible: modeBtn.selected
                text: "check_circle"
                iconSize: 20
                fill: 1
                color: Appearance.m3colors.m3primary
            }
        }
    }

    component SubGroupLabel: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.topMargin: 10
        Layout.bottomMargin: 2
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: Appearance.m3colors.m3primary
        textFormat: Text.PlainText
    }

    function revealSection() {
        if (!requestedSection) return;
        const node = requestedSection === "fonts" ? typography : desktopEffects;
        if (requestedSection === "fonts") typography.expanded = true;
        Qt.callLater(() => {
            const at = node.mapToItem(contentItem, 0, 0);
            contentItem.contentY = Math.max(0, contentItem.contentY + at.y);
        });
    }
    onRequestedSectionChanged: revealSection()
    Component.onCompleted: revealSection()
    function changed(path) {
        root.edited(path);
        if (path.startsWith("appearance.palette") || path.startsWith("appearance.wallpaperTheming")) colorTimer.restart();
    }
    function setMode(mode) {
        Config.flushPendingWrites();
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", mode, "--noswitch"]);
    }

    ColumnLayout {
        width: Math.min(root.availableWidth - 40, 840)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 22

        DesignSection {
            objectName: "designColors"
            sectionKey: "colors"
            title: "Color & theme"
            subtitle: "Material You palette from your wallpaper"
            icon: "palette"
            detailsLabel: "App targets & terminal palette tuning"
            detailsSummary: {
                const apps = Config.options.appearance.wallpaperTheming;
                const targets = [];
                if (apps.enableAppsAndShell) targets.push("Shell");
                if (apps.enableAppsAndShell && apps.enableQtApps) targets.push("Qt");
                if (apps.enableAppsAndShell && apps.enableTerminal) targets.push("Terminals");
                const tint = Math.round((apps.terminalGenerationProps.harmony ?? 0) * 100);
                return (targets.length ? targets.join(", ") : "Theming off") + "  ·  Terminal tint " + tint + "%";
            }

            // Hero theme switcher + live generated palette chips
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 10
                Layout.bottomMargin: 6
                spacing: 10
                ModeCard {
                    objectName: "designLightMode"
                    Layout.fillWidth: true
                    modeIcon: "light_mode"
                    modeTitle: "Light"
                    modeSubtitle: "Bright surfaces"
                    selected: !Appearance.m3colors.darkmode
                    onClicked: root.setMode("light")
                }
                ModeCard {
                    objectName: "designDarkMode"
                    Layout.fillWidth: true
                    modeIcon: "dark_mode"
                    modeTitle: "Dark"
                    modeSubtitle: "Low-glare surfaces"
                    selected: Appearance.m3colors.darkmode
                    onClicked: root.setMode("dark")
                }
                Rectangle {
                    visible: root.width > 740
                    implicitHeight: 62
                    implicitWidth: swatchRow.implicitWidth + 18
                    radius: 16
                    color: Appearance.m3colors.m3surfaceContainerHigh
                    Row {
                        id: swatchRow
                        anchors.centerIn: parent
                        spacing: 5
                        Repeater {
                            model: [
                                Appearance.m3colors.m3primary,
                                Appearance.m3colors.m3secondary,
                                Appearance.m3colors.m3tertiary,
                                Appearance.m3colors.m3primaryContainer,
                                Appearance.m3colors.m3secondaryContainer,
                                Appearance.m3colors.m3tertiaryContainer
                            ]
                            delegate: Rectangle {
                                required property color modelData
                                width: 18
                                height: 34
                                radius: 9
                                color: modelData
                                border.width: 1
                                border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.45)
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                        }
                    }
                }
            }

            // Most relevant controls visible immediately — no accordion needed!
            DesignRows {
                paths: [
                    "appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode",
                    "appearance.palette.type",
                    "appearance.palette.accentColor"
                ]
                onEdited: path => root.changed(path)
            }

            // Flat inline advanced controls — zero nested bordered cards!
            detailsData: [
                SubGroupLabel { text: "WHERE WALLPAPER COLORS APPLY" },
                DesignRows {
                    paths: [
                        "appearance.wallpaperTheming.enableAppsAndShell",
                        "appearance.wallpaperTheming.enableQtApps",
                        "appearance.wallpaperTheming.enableTerminal"
                    ]
                    onEdited: path => root.changed(path)
                },
                SubGroupLabel { text: "TERMINAL COLOR TUNING" },
                DesignRows {
                    paths: [
                        "appearance.wallpaperTheming.terminalGenerationProps.harmony",
                        "appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold",
                        "appearance.wallpaperTheming.terminalGenerationProps.termFgBoost"
                    ]
                    onEdited: path => root.changed(path)
                }
            ]
        }

        DesktopEffectsConfig { id: desktopEffects; Layout.fillWidth: true }

        DesignSection {
            sectionKey: "surfaces"
            title: "Shell surfaces"
            subtitle: "Transparency, tint and screen corners"
            icon: "layers"
            detailsLabel: "Manual transparency, tint & screen corners"
            detailsSummary: {
                const t = Config.options.appearance.transparency;
                const mode = !t.enable ? "Opaque" : t.automatic ? "Automatic transparency"
                    : "BG " + Math.round(t.backgroundTransparency * 100) + "% · Content " + Math.round(t.contentTransparency * 100) + "%";
                const corner = ["Corners off", "Always rounded", "Rounded except fullscreen"][Config.options.appearance.fakeScreenRounding] ?? "";
                return mode + (corner ? "  ·  " + corner : "");
            }
            DesignRows {
                paths: ["appearance.transparency.enable", "appearance.transparency.automatic"]
                onEdited: path => root.changed(path)
            }
            detailsData: [
                DesignRows {
                    paths: [
                        "appearance.transparency.backgroundTransparency",
                        "appearance.transparency.contentTransparency",
                        "appearance.extraBackgroundTint",
                        "appearance.fakeScreenRounding"
                    ]
                    onEdited: path => root.changed(path)
                }
            ]
        }

        DesignSection {
            id: typography
            sectionKey: "fonts"
            title: "Typography"
            subtitle: (Config.options.appearance.fonts.main || "Default font")
                + " · " + (Config.options.appearance.fontSizes.ui > 0 ? Config.options.appearance.fontSizes.ui + " pt" : "default size")
                + " · " + (Config.options.appearance.fonts.monospace || "Monospace")
            icon: "text_fields"
            detailsLabel: "Typography studio, clarity & monitor terminal sizing"
            detailsSummary: "Live specimen previews, 26 font presets, text clarity & per-monitor Kitty sizes"

            // Always-visible glanceable typography hero card (zero subprocess work until expanded).
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 10
                Layout.bottomMargin: 6
                spacing: 14

                Rectangle {
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: 16
                    color: Appearance.m3colors.m3primaryContainer
                    Text {
                        anchors.centerIn: parent
                        text: "Aa"
                        font.family: Appearance.font.family.title || Appearance.font.family.main
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: (Config.options.appearance.fonts.title || Config.options.appearance.fonts.main || "Default")
                            + "  ·  " + (Config.options.appearance.fonts.main || "Interface")
                        textFormat: Text.PlainText
                        font.family: Appearance.font.family.title || Appearance.font.family.main
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [
                                {
                                    role: "UI",
                                    fam: Config.options.appearance.fonts.main || "Default",
                                    pt: Config.options.appearance.fontSizes.ui > 0 ? (Config.options.appearance.fontSizes.ui + " pt") : "auto",
                                    useMono: false
                                },
                                {
                                    role: "Headings",
                                    fam: Config.options.appearance.fonts.title || Config.options.appearance.fonts.main || "Default",
                                    pt: Config.options.appearance.fontSizes.title > 0 ? (Config.options.appearance.fontSizes.title + " pt") : "auto",
                                    useMono: false
                                },
                                {
                                    role: "Code",
                                    fam: Config.options.appearance.fonts.monospace || "Monospace",
                                    pt: Config.options.appearance.fontSizes.mono > 0 ? (Config.options.appearance.fontSizes.mono + " pt") : "auto",
                                    useMono: true
                                }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                implicitHeight: 24
                                implicitWidth: chipText.implicitWidth + 16
                                radius: 12
                                color: Appearance.m3colors.m3surfaceContainerHigh
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: modelData.role + ": " + modelData.fam + " · " + modelData.pt
                                    textFormat: Text.PlainText
                                    font.family: modelData.useMono ? (Appearance.font.family.monospace || Appearance.font.family.main) : Appearance.font.family.main
                                    font.pixelSize: 11
                                    color: Appearance.m3colors.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }

            detailsData: [
                Item {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    implicitHeight: fontProfilesLoader.implicitHeight
                    Loader {
                        id: fontProfilesLoader
                        anchors { left: parent.left; right: parent.right }
                        active: typography.expanded
                        sourceComponent: Component { FontProfiles {} }
                    }
                },
                SubGroupLabel { text: "SHELL BASE SIZES (PT)" },
                DesignRows { groups: ["Shell base sizes (pt)"]; onEdited: path => root.changed(path) },
                SubGroupLabel { text: "SHELL FONT FAMILIES" },
                DesignRows { groups: ["Shell font families"]; onEdited: path => root.changed(path) }
            ]
        }

        DesignSection {
            sectionKey: "background"
            title: "Wallpaper & parallax"
            subtitle: "Fullscreen rendering and workspace motion"
            icon: "wallpaper"
            detailsLabel: "Parallax zoom & motion tuning"
            detailsSummary: "Zoom " + Math.round((Config.options.background.parallax.workspaceZoom ?? 1) * 100)
                + "%  ·  Widgets " + Math.round((Config.options.background.parallax.widgetsFactor ?? 1) * 100) + "%"
            DesignRows {
                paths: ["background.hideWhenFullscreen", "background.parallax.enableWorkspace"]
                onEdited: path => root.changed(path)
            }
            detailsData: [
                DesignRows {
                    paths: [
                        "background.parallax.workspaceZoom",
                        "background.parallax.widgetsFactor",
                        "background.parallax.enableSidebar",
                        "background.parallax.vertical",
                        "background.parallax.autoVertical"
                    ]
                    onEdited: path => root.changed(path)
                }
            ]
        }

        Item { Layout.preferredHeight: 24 }
    }

    Timer {
        id: colorTimer
        interval: 500
        onTriggered: { Config.flushPendingWrites(); Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"]); }
    }
}
