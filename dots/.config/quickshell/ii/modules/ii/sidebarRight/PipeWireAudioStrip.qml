import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    objectName: "pipewireAudioStrip"

    property bool expanded: PipeWireAudio.expandedByDefault
    property bool watching: false
    readonly property bool pollingVisible: visible && (Window.window?.visible ?? false)
    readonly property var info: PipeWireAudio.data
    readonly property bool hasData: PipeWireAudio.available && info !== null

    function watch() {
        if (watching === pollingVisible) return;
        watching = pollingVisible;
        PipeWireAudio.watchers += watching ? 1 : -1;
    }

    function pillBg(tone) {
        if (tone === "good") return Appearance.m3colors.m3primaryContainer;
        if (tone === "info") return Appearance.m3colors.m3secondaryContainer;
        if (tone === "warn") return Appearance.m3colors.m3tertiaryContainer;
        if (tone === "bad") return Appearance.m3colors.m3errorContainer;
        return Appearance.m3colors.m3surfaceContainerHighest;
    }

    function pillFg(tone) {
        if (tone === "good") return Appearance.m3colors.m3onPrimaryContainer;
        if (tone === "info") return Appearance.m3colors.m3onSecondaryContainer;
        if (tone === "warn") return Appearance.m3colors.m3onTertiaryContainer;
        if (tone === "bad") return Appearance.m3colors.m3onErrorContainer;
        return Appearance.m3colors.m3onSurfaceVariant;
    }

    function dotColor(tone) {
        if (tone === "good") return Appearance.m3colors.m3primary;
        if (tone === "info") return Appearance.m3colors.m3secondary;
        if (tone === "warn") return Appearance.m3colors.m3tertiary;
        if (tone === "bad") return Appearance.m3colors.m3error;
        return Appearance.m3colors.m3outline;
    }

    function latencyText() {
        if (!hasData || !info.clock) return "";
        const c = info.clock;
        const ms = Number(c.latencyMs || 0).toFixed(1) + "ms";
        return c.forceQuantum > 0 ? (c.forceQuantum + " · " + ms) : ("Auto · " + ms);
    }

    onPollingVisibleChanged: watch()
    Component.onCompleted: watch()
    Component.onDestruction: if (watching) PipeWireAudio.watchers--

    Connections {
        target: PipeWireAudio
        function onExpandedByDefaultChanged() {
            root.expanded = PipeWireAudio.expandedByDefault;
        }
    }

    implicitHeight: contentCol.implicitHeight + 10
    radius: 12
    color: headerMouse.containsMouse
        ? Appearance.m3colors.m3surfaceContainerHighest
        : Appearance.m3colors.m3surfaceContainerHigh
    border.width: 1
    border.color: root.expanded
        ? Appearance.m3colors.m3outline
        : Appearance.m3colors.m3outlineVariant

    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

    component MiniBadge: Rectangle {
        id: badge
        property string label: ""
        property string tone: "neutral"

        height: 19
        implicitWidth: badgeText.implicitWidth + 10
        radius: 9.5
        color: root.pillBg(tone)
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: badge.label
            textFormat: Text.PlainText
            font.pixelSize: 10
            font.weight: Font.Medium
            color: root.pillFg(badge.tone)
        }
    }

    component ClockChip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal activated()

        height: 22
        implicitWidth: chipLabel.implicitWidth + 14
        radius: 11
        color: chip.selected
            ? Appearance.m3colors.m3primary
            : (chipMouse.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainer)
        border.width: chip.selected ? 0 : 1
        border.color: Appearance.m3colors.m3outlineVariant
        opacity: PipeWireAudio.acting ? 0.6 : 1.0

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            textFormat: Text.PlainText
            font.pixelSize: 10
            font.weight: chip.selected ? Font.DemiBold : Font.Medium
            color: chip.selected ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !PipeWireAudio.acting
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
        }
    }

    component InfoRow: RowLayout {
        id: irow
        property string label: ""
        property string value: ""
        property color valueColor: Appearance.m3colors.m3onSurface

        Layout.fillWidth: true
        spacing: 8

        StyledText {
            text: irow.label
            textFormat: Text.PlainText
            font.pixelSize: 11
            color: Appearance.m3colors.m3onSurfaceVariant
            Layout.preferredWidth: 56
        }
        StyledText {
            text: irow.value
            textFormat: Text.PlainText
            font.pixelSize: 11
            color: irow.valueColor
            Layout.fillWidth: true
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    ColumnLayout {
        id: contentCol
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 10
            rightMargin: 10
            topMargin: 5
        }
        spacing: 5

        Item {
            id: headerArea
            objectName: "pipewireAudioHeader"
            Layout.fillWidth: true
            implicitHeight: 20

            RowLayout {
                anchors.fill: parent
                spacing: 6

                MaterialSymbol {
                    text: "graphic_eq"
                    iconSize: 15
                    color: root.hasData ? root.dotColor(root.info.overall) : Appearance.m3colors.m3onSurfaceVariant
                }

                StyledText {
                    text: "PipeWire"
                    textFormat: Text.PlainText
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onSurface
                }

                StyledText {
                    visible: !root.hasData
                    Layout.fillWidth: true
                    text: PipeWireAudio.ready ? "Audio telemetry unavailable" : "Reading PipeWire…"
                    textFormat: Text.PlainText
                    font.pixelSize: 11
                    color: Appearance.m3colors.m3onSurfaceVariant
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: root.hasData
                    text: (root.info?.clock?.rateShort ?? "44.1k") + " · " + root.latencyText()
                    textFormat: Text.PlainText
                    font.pixelSize: 11
                    color: Appearance.m3colors.m3onSurfaceVariant
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                MiniBadge {
                    objectName: "pipewireSpatialBadge"
                    visible: root.hasData && (root.info?.spatial?.state === "active" || root.info?.spatial?.state === "dolby-ready")
                    label: root.info?.spatial?.badge ?? ""
                    tone: root.info?.spatial?.tone ?? "good"
                }

                MiniBadge {
                    objectName: "pipewireRtBadge"
                    visible: root.hasData
                    label: root.info?.kernel?.pipewire?.label ?? "RT"
                    tone: root.info?.kernel?.pipewire?.tone ?? "neutral"
                }

                MaterialSymbol {
                    visible: root.hasData
                    text: "expand_more"
                    iconSize: 17
                    color: Appearance.m3colors.m3onSurfaceVariant
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }

            MouseArea {
                id: headerMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.hasData
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        Item {
            id: drawer
            objectName: "pipewireAudioDrawer"
            Layout.fillWidth: true
            visible: root.hasData && (implicitHeight > 0 || root.expanded)
            clip: true
            implicitHeight: (root.hasData && root.expanded) ? drawerCol.implicitHeight : 0
            opacity: (root.hasData && root.expanded) ? 1 : 0

            Behavior on implicitHeight { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: drawerCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 1
                    color: Appearance.m3colors.m3outlineVariant
                    opacity: 0.6
                }

                Flow {
                    objectName: "pipewireChainFlow"
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: root.info?.chain ?? []
                        delegate: Row {
                            required property var modelData
                            required property int index
                            spacing: 4

                            MaterialSymbol {
                                visible: index > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "chevron_right"
                                iconSize: 13
                                color: Appearance.m3colors.m3outline
                            }

                            MiniBadge {
                                label: {
                                    if (modelData.id === "easyeffects" && typeof EasyEffects !== "undefined" && EasyEffects.preset) {
                                        return "EE · " + EasyEffects.preset;
                                    }
                                    return modelData.label;
                                }
                                tone: modelData.tone ?? "neutral"
                            }
                        }
                    }
                }

                InfoRow {
                    label: "DAC"
                    value: {
                        const hw = root.info?.hardware;
                        if (!hw) return "";
                        const parts = [hw.codec || "ALSA DAC"];
                        if (hw.active && hw.format) parts.push(hw.format);
                        if (hw.maxBits) parts.push(hw.maxBits + "-bit");
                        if (hw.rateRange) parts.push(hw.rateRange);
                        return parts.join(" · ");
                    }
                }

                InfoRow {
                    label: "Kernel"
                    value: {
                        const k = root.info?.kernel;
                        if (!k) return "";
                        const parts = [k.shortRelease, k.preempt];
                        parts.push("PW " + (k.pipewire?.label ?? ""));
                        if (k.easyeffects?.label && k.easyeffects.label !== "Offline") parts.push("EE " + k.easyeffects.label);
                        if (k.cstatePinned) parts.push("C1");
                        return parts.join(" · ");
                    }
                }

                InfoRow {
                    label: "Spatial"
                    value: {
                        const sp = root.info?.spatial;
                        const hw = root.info?.hardware;
                        if (!sp) return "";
                        const head = sp.enabled ? (sp.badge + (sp.passthrough ? " + Dolby HDMI" : "")) : "Off (Stereo)";
                        return hw?.hdmiSummary ? (head + " · " + hw.hdmiSummary) : head;
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: "Quantum"
                        font.pixelSize: 10
                        color: Appearance.m3colors.m3onSurfaceVariant
                        Layout.preferredWidth: 50
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [
                                { q: 0, label: "Auto" },
                                { q: 64, label: "64" },
                                { q: 128, label: "128" },
                                { q: 256, label: "256" },
                                { q: 512, label: "512" },
                                { q: 1024, label: "1024" }
                            ]
                            delegate: ClockChip {
                                required property var modelData
                                objectName: "pipewireQuantum-" + modelData.q
                                label: modelData.label
                                selected: (root.info?.clock?.forceQuantum ?? 0) === modelData.q
                                onActivated: PipeWireAudio.setQuantum(modelData.q)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: "Rate"
                        font.pixelSize: 10
                        color: Appearance.m3colors.m3onSurfaceVariant
                        Layout.preferredWidth: 50
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [
                                { r: 0, label: "Auto" },
                                { r: 44100, label: "44.1k" },
                                { r: 48000, label: "48k" },
                                { r: 96000, label: "96k" },
                                { r: 192000, label: "192k" }
                            ]
                            delegate: ClockChip {
                                required property var modelData
                                objectName: "pipewireRate-" + modelData.r
                                label: modelData.label
                                selected: (root.info?.clock?.forceRate ?? 0) === modelData.r
                                onActivated: PipeWireAudio.setRate(modelData.r)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: PipeWireAudio.error.length > 0
                            ? PipeWireAudio.error
                            : (PipeWireAudio.acting ? "Applying live clock…" : "Zero-restart PipeWire clock · live while open")
                        textFormat: Text.PlainText
                        font.pixelSize: 10
                        color: PipeWireAudio.error.length > 0 ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }

                    ClockChip {
                        objectName: "pipewireClockReset"
                        visible: (root.info?.clock?.forceQuantum ?? 0) > 0 || (root.info?.clock?.forceRate ?? 0) > 0
                        label: "Reset"
                        selected: false
                        onActivated: PipeWireAudio.resetClock()
                    }

                    ClockChip {
                        objectName: "pipewireAudioRefresh"
                        label: "Refresh"
                        selected: false
                        onActivated: PipeWireAudio.refresh()
                    }
                }
            }
        }
    }
}
