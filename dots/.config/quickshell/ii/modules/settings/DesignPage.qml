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
    readonly property bool effectsBusy: desktopEffects.busy || !desktopEffects.ready
    readonly property string effectsStatus: desktopEffects.status
    function applyEffects() { desktopEffects.run("apply", JSON.stringify(desktopEffects.draft)); }
    function resetEffects() { desktopEffects.sync(); }
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    component ModeButton: SettingsButton {
        enabled: !Config.writesPaused
        implicitHeight: 48
        background: Rectangle {
            radius: 14
            color: parent.highlighted ? Appearance.m3colors.m3primaryContainer : parent.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
            border.width: parent.highlighted ? 2 : 1
            border.color: parent.highlighted ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
            Behavior on color { ColorAnimation { duration: 180 } }
        }
        contentItem: StyledText { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: parent.highlighted ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface; font.pixelSize: 16 }
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
        width: root.availableWidth
        spacing: 14
        DesignSection {
            objectName: "designColors"
            sectionKey: "colors"
            title: "Color & theme"
            subtitle: "Material colors from your wallpaper · Matugen / Monet"
            icon: "palette"
            accented: true
            detailsLabel: "Accent, application colors & terminal palette"
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ModeButton {
                    objectName: "designLightMode"
                    Layout.fillWidth: true
                    text: "☀  Light"
                    highlighted: !Appearance.m3colors.darkmode
                    onClicked: root.setMode("light")
                }
                ModeButton {
                    objectName: "designDarkMode"
                    Layout.fillWidth: true
                    text: "☾  Dark"
                    highlighted: Appearance.m3colors.darkmode
                    onClicked: root.setMode("dark")
                }
                Row {
                    spacing: 4
                    visible: root.width > 600
                    Repeater {
                        model: [Appearance.m3colors.m3primary, Appearance.m3colors.m3secondary, Appearance.m3colors.m3tertiary, Appearance.m3colors.m3primaryContainer, Appearance.m3colors.m3secondaryContainer, Appearance.m3colors.m3tertiaryContainer]
                        delegate: Rectangle {
                            required property color modelData
                            width: 24; height: 32; radius: 9; color: modelData
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }
                    }
                }
            }
            DesignRows { paths: ["appearance.palette.type"]; onEdited: path => root.changed(path) }
            detailsData: [
                DesignRows { paths: ["appearance.palette.accentColor"]; onEdited: path => root.changed(path) },
                DesignSection {
                    title: "Application colors"; icon: "apps"; sectionKey: "applications"
                    subtitle: "Choose where the wallpaper palette is applied."
                    DesignRows { groups: ["Apply colors to applications"]; onEdited: path => root.changed(path) }
                },
                DesignSection {
                    title: "Terminal palette"; icon: "terminal"; sectionKey: "terminal"
                    detailsLabel: "Tint, hue shift & contrast"
                    DesignRows { paths: ["appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode"]; onEdited: path => root.changed(path) }
                    detailsData: DesignRows {
                        paths: ["appearance.wallpaperTheming.terminalGenerationProps.harmony", "appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold", "appearance.wallpaperTheming.terminalGenerationProps.termFgBoost"]
                        onEdited: path => root.changed(path)
                    }
                }
            ]
        }
        DesktopEffectsConfig { id: desktopEffects; Layout.fillWidth: true }
        DesignSection {
            sectionKey: "surfaces"
            title: "Shell surfaces"
            subtitle: "Transparency, tint and screen corners"
            icon: "layers"
            detailsLabel: "Transparency amounts, tint & rounding"
            DesignRows { paths: ["appearance.transparency.enable"]; onEdited: path => root.changed(path) }
            detailsData: [
                DesignRows { paths: ["appearance.transparency.automatic", "appearance.transparency.backgroundTransparency", "appearance.transparency.contentTransparency"]; onEdited: path => root.changed(path) },
                DesignRows { groups: ["Surface appearance"]; onEdited: path => root.changed(path) }
            ]
        }
        DesignSection {
            id: typography
            sectionKey: "fonts"
            title: "Typography"
            subtitle: (Config.options.appearance.fonts.main || "Default font") + " · desktop profiles and shell text"
            icon: "text_fields"
            detailsLabel: "Font profiles, sizes & families"
            detailsData: [
                Loader { Layout.fillWidth: true; active: typography.expanded; sourceComponent: Component { FontProfiles {} } },
                DesignRows { groups: ["Shell base sizes (pt)", "Shell font families"]; onEdited: path => root.changed(path) }
            ]
        }
        DesignSection {
            sectionKey: "background"
            title: "Background rendering"
            subtitle: "Fullscreen behavior and wallpaper movement"
            icon: "wallpaper"
            detailsLabel: "Workspace & sidebar parallax"
            DesignRows { groups: ["Wallpaper visibility"]; onEdited: path => root.changed(path) }
            detailsData: DesignRows { groups: ["Wallpaper motion"]; onEdited: path => root.changed(path) }
        }
        Item { Layout.preferredHeight: 20 }
    }
    Timer {
        id: colorTimer
        interval: 500
        onTriggered: { Config.flushPendingWrites(); Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"]); }
    }
}
