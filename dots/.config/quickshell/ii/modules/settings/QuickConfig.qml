import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    forceWidth: true

    Process {
        id: randomWallProc
        property string status: ""
        property string scriptPath: `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`
        command: ["bash", "-c", FileUtils.trimFileProtocol(randomWallProc.scriptPath)]
        stdout: SplitParser {
            onRead: data => {
                randomWallProc.status = data.trim();
            }
        }
    }

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        padding: 5
        Layout.fillWidth: true
        Layout.minimumHeight: implicitHeight
        toggled: Appearance.m3colors.darkmode === dark
        colBackground: Appearance.colors.colLayer2
        onClicked: {
            Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
        }
        contentItem: ColumnLayout {
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
        }
    }

    // Wallpaper selection
    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Wallpaper & Colors")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true

            Item {
                Layout.preferredWidth: 320
                Layout.minimumWidth: 220
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                implicitHeight: 200
                
                StyledImage {
                    id: wallpaperPreview
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: Config.options.background.wallpaperPath
                    cache: false
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: 360
                            height: 200
                            radius: Appearance.rounding.normal
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 220
                Layout.alignment: Qt.AlignTop
                RippleButtonWithIcon {
                    enabled: !WallpaperDiscovery.busy && !randomWallProc.running
                    Layout.fillWidth: true
                    implicitHeight: 44
                    materialIcon: "explore"
                    mainText: WallpaperDiscovery.busy ? Translation.tr("Finding your next wallpaper…") : Translation.tr("Discover: Games & Art")
                    onClicked: WallpaperDiscovery.fetch()
                    StyledToolTip {
                        text: Translation.tr("Fresh game art and illustrated landscapes from Wallhaven. SFW, wide images, 1080p minimum; 1440p and 4K preferred.")
                    }
                }
                RippleButtonWithIcon {
                    enabled: !randomWallProc.running && !WallpaperDiscovery.busy
                    visible: Config.options.background.discovery.includeKonachan
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.small
                    materialIcon: "ifl"
                    objectName: "konachanWallpaperButton"
                    mainText: Translation.tr("Konachan · anime option")
                    onClicked: {
                        WallpaperDiscovery.fetch("konachan");
                    }
                    StyledToolTip {
                        text: Translation.tr("Random SFW Anime wallpaper from Konachan\nImage is saved to ~/Pictures/Wallpapers")
                    }
                }
                RippleButtonWithIcon {
                    enabled: !randomWallProc.running && !WallpaperDiscovery.busy
                    visible: Config.options.policies.weeb === 1
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.small
                    materialIcon: "ifl"
                    mainText: randomWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: osu! seasonal")
                    onClicked: {
                        randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/random_osu_wall.sh`;
                        randomWallProc.running = true;
                    }
                    StyledToolTip {
                        text: Translation.tr("Random osu! seasonal background\nImage is saved to ~/Pictures/Wallpapers")
                    }
                }
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "wallpaper"
                    StyledToolTip {
                        text: Translation.tr("Pick wallpaper image on your system")
                    }
                    onClicked: {
                        Quickshell.execDetached(`${Directories.wallpaperSwitchScriptPath}`);
                    }
                    mainContentComponent: Component {
                        RowLayout {
                            spacing: 10
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                text: Translation.tr("Choose file")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            RowLayout {
                                spacing: 3
                                KeyboardKey {
                                    key: "Ctrl"
                                }
                                KeyboardKey {
                                    key: Config.options.cheatsheet.superKey ?? "󰖳"
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "+"
                                }
                                KeyboardKey {
                                    key: "T"
                                }
                            }
                        }
                    }
                }
            }
        }

        // Independent row: optional source buttons cannot compress theme controls.
        RowLayout {
            Layout.fillWidth: true
            uniformCellSizes: true
            SmallLightDarkPreferenceButton { objectName: "wallpaperLightButton"; dark: false }
            SmallLightDarkPreferenceButton { objectName: "wallpaperDarkButton"; dark: true }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Pick a mood, or let the mix alternate between your games and painted worlds.")
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
        }
        ConfigSelectionArray {
            currentValue: Config.options.background.discovery.theme
            onSelected: value => Config.options.background.discovery.theme = value
            options: [
                {value: "mix", displayName: "Your mix", icon: "shuffle"},
                {value: "mario", displayName: "Mario"},
                {value: "lis", displayName: "Life is Strange 1"},
                {value: "tomb", displayName: "Tomb Raider"},
                {value: "painted", displayName: "Painted landscapes"},
                {value: "worlds", displayName: "Other game worlds"}
            ]
        }
        ConfigSwitch {
            buttonIcon: "add_photo_alternate"
            text: Translation.tr("Include Konachan anime in the mix")
            checked: Config.options.background.discovery.includeKonachan
            onCheckedChanged: Config.options.background.discovery.includeKonachan = checked
        }
        ConfigSwitch {
            buttonIcon: "autorenew"
            text: Translation.tr("Rotate automatically")
            checked: Config.options.background.discovery.rotate
            onCheckedChanged: Config.options.background.discovery.rotate = checked
        }
        ConfigSelectionArray {
            visible: Config.options.background.discovery.rotate
            currentValue: Config.options.background.discovery.intervalMinutes
            onSelected: value => Config.options.background.discovery.intervalMinutes = value
            options: [
                {value: 30, displayName: "Every 30 minutes"},
                {value: 60, displayName: "Every hour"},
                {value: 180, displayName: "Every 3 hours"}
            ]
        }
        StyledText {
            Layout.fillWidth: true
            visible: Config.options.background.discovery.rotate
            wrapMode: Text.WordWrap
            text: WallpaperDiscovery.busy ? Translation.tr("Rotation: fetching a wallpaper…")
                : Translation.tr("Next automatic wallpaper: ") + Qt.formatDateTime(new Date(WallpaperDiscovery.nextRotationAt), "hh:mm")
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: WallpaperDiscovery.status || (WallpaperDiscovery.current.label
                ? WallpaperDiscovery.current.label + " · " + WallpaperDiscovery.current.width + " × " + WallpaperDiscovery.current.height
                : Translation.tr("Click Discover to fetch. Downloads are kept in Pictures/Wallpapers/Discovery."))
            color: Appearance.colors.colSubtext
        }
        RowLayout {
            visible: !!WallpaperDiscovery.current.url
            RippleButtonWithIcon {
                materialIcon: "open_in_new"
                mainText: Translation.tr("Wallpaper & source")
                onClicked: Qt.openUrlExternally(WallpaperDiscovery.current.url)
            }
            StyledText {
                text: WallpaperDiscovery.current.provider || ""
                color: Appearance.colors.colSubtext
            }
        }

        ConfigSelectionArray {
            currentValue: Config.options.appearance.palette.type
            onSelected: newValue => {
                Config.options.appearance.palette.type = newValue;
                Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`]);
            }
            options: [
                {
                    "value": "auto",
                    "displayName": Translation.tr("Auto")
                },
                {
                    "value": "scheme-content",
                    "displayName": Translation.tr("Content")
                },
                {
                    "value": "scheme-expressive",
                    "displayName": Translation.tr("Expressive")
                },
                {
                    "value": "scheme-fidelity",
                    "displayName": Translation.tr("Fidelity")
                },
                {
                    "value": "scheme-fruit-salad",
                    "displayName": Translation.tr("Fruit Salad")
                },
                {
                    "value": "scheme-vibrant",
                    "displayName": Translation.tr("Vibrant")
                },
                {
                    "value": "scheme-monochrome",
                    "displayName": Translation.tr("Monochrome")
                },
                {
                    "value": "scheme-neutral",
                    "displayName": Translation.tr("Neutral")
                },
                {
                    "value": "scheme-rainbow",
                    "displayName": Translation.tr("Rainbow")
                },
                {
                    "value": "scheme-tonal-spot",
                    "displayName": Translation.tr("Tonal Spot")
                }
            ]
        }

        ConfigSwitch {
            buttonIcon: "ev_shadow"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: {
                Config.options.appearance.transparency.enable = checked;
            }
        }
    }

    ContentSection {
        icon: "screenshot_monitor"
        title: Translation.tr("Bar & screen")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Bar style")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        }
                    ]
                }
            }
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Screen round corner")

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: newValue => {
                        Config.options.appearance.fakeScreenRounding = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("When not fullscreen"),
                            icon: "fullscreen_exit",
                            value: 2
                        }
                    ]
                }
            }
            
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        text: Translation.tr('Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening %1 manually.').arg(Directories.shellConfigPath)

        Item {
            Layout.fillWidth: true
        }
        RippleButtonWithIcon {
            id: copyPathButton
            property bool justCopied: false
            Layout.fillWidth: false
            buttonRadius: Appearance.rounding.small
            materialIcon: justCopied ? "check" : "content_copy"
            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
            onClicked: {
                copyPathButton.justCopied = true
                Quickshell.clipboardText = FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                revertTextTimer.restart();
            }
            colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive

            Timer {
                id: revertTextTimer
                interval: 1500
                onTriggered: {
                    copyPathButton.justCopied = false
                }
            }
        }
    }
}
