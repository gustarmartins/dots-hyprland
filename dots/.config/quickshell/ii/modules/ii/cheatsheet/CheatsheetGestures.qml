pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    implicitWidth: QsWindow?.window?.screen.width * 0.7 ?? 960
    implicitHeight: QsWindow?.window?.screen.height * 0.7 ?? 640

    readonly property var sections: [
        {
            title: Translation.tr("Basic Everyday (3 Fingers)"),
            subtitle: Translation.tr("No keyboard needed — navigation & safe exit"),
            items: [
                { keys: ["3F", "← / →"], desc: Translation.tr("Switch workspaces (1:1 continuous glide)") },
                { keys: ["3F", "↑"], desc: Translation.tr("Open Overview & workspace switcher") },
                { keys: ["3F", "↓"], desc: Translation.tr("Back / Close Overview, panels, scratchpad, or exit Fullscreen") },
            ]
        },
        {
            title: Translation.tr("Shell Panels & Modes (4 Fingers)"),
            subtitle: Translation.tr("No keyboard needed — Quickshell & window size states"),
            items: [
                { keys: ["4F", "←"], desc: Translation.tr("Open Right Sidebar (Quick Toggles / Audio) · or close Left") },
                { keys: ["4F", "→"], desc: Translation.tr("Open Left Sidebar (AI / Translator) · or close Right") },
                { keys: ["4F", "↓"], desc: Translation.tr("Slide Scratchpad in/out (1:1 live tracking)") },
                { keys: ["4F", "↑"], desc: Translation.tr("Hide Scratchpad · or toggle Media Controls") },
                { keys: ["4F", "Spread ‹ ›"], desc: Translation.tr("Maximize (keeps bar) → spread again for True Fullscreen") },
                { keys: ["4F", "Pinch › ‹"], desc: Translation.tr("Unfullscreen / Unmaximize · or toggle Float / Tile") },
            ]
        },
        {
            title: Translation.tr("Window Control (Super + 3 Fingers)"),
            subtitle: Translation.tr("Full desktop Super+Mouse parity on touchpad"),
            items: [
                { keys: ["Super", "3F Swipe"], desc: Translation.tr("Move window (1:1 float drag / tiled swap)") },
                { keys: ["Super", "Alt", "3F Swipe"], desc: Translation.tr("Resize window live (1:1 float & tiled)") },
                { keys: ["Super", "3F › ‹"], desc: Translation.tr("Float window (1:1 animated)") },
                { keys: ["Super", "3F ‹ ›"], desc: Translation.tr("Tile window (1:1 animated)") },
                { keys: ["Super", "Shift", "3F ←/→"], desc: Translation.tr("Carry window to previous / next workspace") },
                { keys: ["Super", "Shift", "3F ↑"], desc: Translation.tr("Center floating window (or float & fit if tiled)") },
                { keys: ["Super", "Shift", "3F ↓"], desc: Translation.tr("Send window to Scratchpad") },
            ]
        },
        {
            title: Translation.tr("Advanced Power Gestures"),
            subtitle: Translation.tr("Float presets, live zoom, Alt+Tab, drag-to-close & media"),
            items: [
                { keys: ["Super", "Ctrl", "3F ←/→"], desc: Translation.tr("Snap float Left / Right half · or adjust tiled split") },
                { keys: ["Super", "Ctrl", "3F ↑"], desc: Translation.tr("Fit float to comfortable size (78% × 82%, centered)") },
                { keys: ["Super", "Ctrl", "3F ↓"], desc: Translation.tr("Compact mini / PiP float card (48% × 54%, centered)") },
                { keys: ["Super", "Ctrl", "3F Pinch"], desc: Translation.tr("Live screen magnifier zoom around cursor (1:1)") },
                { keys: ["Alt", "3F ←/→"], desc: Translation.tr("Cycle windows (touchpad Alt+Tab)") },
                { keys: ["Alt", "3F ↑"], desc: Translation.tr("Pin / unpin floating window across workspaces") },
                { keys: ["Alt", "3F ↓"], desc: Translation.tr("Drag-to-close window (1:1 preview — pull back to cancel)") },
                { keys: ["Super", "4F ↑"], desc: Translation.tr("Toggle this Gestures cheatsheet") },
                { keys: ["Super", "4F ↓ / ← / →"], desc: Translation.tr("Media Play/Pause · Previous · Next track") },
            ]
        }
    ]

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
        contentWidth: width
        contentHeight: grid.implicitHeight + 16
        clip: true

        GridLayout {
            id: grid
            width: flickable.width
            columns: width >= 880 ? 2 : 1
            columnSpacing: 28
            rowSpacing: 20

            Repeater {
                model: root.sections
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 6

                    StyledText {
                        text: modelData.title
                        font.pixelSize: Appearance.font.pixelSize.title
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        text: modelData.subtitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        Layout.bottomMargin: 4
                    }

                    Repeater {
                        model: modelData.items
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12

                            Row {
                                Layout.preferredWidth: 215
                                spacing: 4
                                Repeater {
                                    model: modelData.keys
                                    delegate: KeyboardKey {
                                        required property string modelData
                                        key: modelData
                                        pixelSize: Config.options.cheatsheet.fontSize.key
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: modelData.desc
                                font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }
            }
        }
    }
}
