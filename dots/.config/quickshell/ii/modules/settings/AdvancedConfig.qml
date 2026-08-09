import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property bool controlsReady: false

    function queueColorApply() {
        if (controlsReady && Config.ready)
            colorApplyTimer.restart();
    }

    function setTerminalTuning(harmony, threshold, contrast) {
        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = harmony;
        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = threshold;
        Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = contrast;
        queueColorApply();
    }

    Component.onCompleted: controlsReady = true

    Timer {
        id: colorApplyTimer
        interval: 400
        repeat: false
        onTriggered: Quickshell.execDetached([
            Directories.wallpaperSwitchScriptPath,
            "--noswitch"
        ])
    }

    ContentSection {
        icon: "colors"
        title: Translation.tr("Color generation")

        ConfigSwitch {
            buttonIcon: "hardware"
            text: Translation.tr("Shell & utilities")
            checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked;
                root.queueColorApply();
            }
        }
        ConfigSwitch {
            buttonIcon: "tv_options_input_settings"
            text: Translation.tr("Qt apps")
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            checked: Config.options.appearance.wallpaperTheming.enableQtApps
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableQtApps = checked;
                root.queueColorApply();
            }
            StyledToolTip {
                text: Translation.tr("Shell & utilities theming must also be enabled")
            }
        }
        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Terminal")
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            checked: Config.options.appearance.wallpaperTheming.enableTerminal
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableTerminal = checked;
                root.queueColorApply();
            }
            StyledToolTip {
                text: Translation.tr("Shell & utilities theming must also be enabled")
            }
        }
        ConfigSwitch {
            buttonIcon: "dark_mode"
            text: Translation.tr("Force dark terminal palette")
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                && Config.options.appearance.wallpaperTheming.enableTerminal
            checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked;
                root.queueColorApply();
            }
            StyledToolTip {
                text: Translation.tr("Keep terminal colors dark even while the desktop uses light mode")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: Translation.tr("ANSI red, green, yellow, blue, magenta, and cyan stay separate. Wallpaper tint only rotates those hues; contrast changes tone without washing colors to white. Changes apply automatically.")
        }

        ConfigSpinBox {
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                && Config.options.appearance.wallpaperTheming.enableTerminal
            icon: "invert_colors"
            text: Translation.tr("Terminal: Wallpaper tint (%)")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100;
                root.queueColorApply();
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 44
            Layout.rightMargin: 8
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: Translation.tr("0% keeps canonical ANSI hues. Higher values pull them toward the wallpaper accent.")
        }

        ConfigSpinBox {
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                && Config.options.appearance.wallpaperTheming.enableTerminal
            icon: "gradient"
            text: Translation.tr("Terminal: Maximum hue shift (°)")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
            from: 0
            to: 45
            stepSize: 5
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value;
                root.queueColorApply();
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 44
            Layout.rightMargin: 8
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: Translation.tr("A hard safety cap in degrees. 10–20° keeps color families easy to identify.")
        }

        ConfigSpinBox {
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                && Config.options.appearance.wallpaperTheming.enableTerminal
            icon: "format_color_text"
            text: Translation.tr("Terminal: ANSI contrast (%)")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100;
                root.queueColorApply();
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 44
            Layout.rightMargin: 8
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: Translation.tr("Moves hard-to-read ANSI tones away from the background. It is bounded, so even 100% cannot turn the palette white.")
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    && Config.options.appearance.wallpaperTheming.enableTerminal
                materialIcon: "palette"
                mainText: Translation.tr("Full spectrum")
                onClicked: root.setTerminalTuning(0, 0, 0.50)
                StyledToolTip {
                    text: Translation.tr("Exact ANSI hue families with strong readable contrast")
                }
            }
            RippleButtonWithIcon {
                enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    && Config.options.appearance.wallpaperTheming.enableTerminal
                materialIcon: "tune"
                mainText: Translation.tr("Balanced tint")
                onClicked: root.setTerminalTuning(0.15, 15, 0.50)
                StyledToolTip {
                    text: Translation.tr("Recommended: subtle wallpaper tint without collapsing colors")
                }
            }
        }
    }
}
