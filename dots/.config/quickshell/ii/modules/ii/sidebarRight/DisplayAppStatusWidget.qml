import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    objectName: "displayAppStatusCard"

    property bool expanded: DisplayAppStatus.expandedByDefault
    property bool watching: false
    readonly property bool pollingVisible: visible && (Window.window?.visible ?? false)
    readonly property var info: DisplayAppStatus.data
    readonly property bool hasData: DisplayAppStatus.available && info !== null

    function watch() {
        if (watching === pollingVisible) return;
        watching = pollingVisible;
        DisplayAppStatus.watchers += watching ? 1 : -1;
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

    function headerIcon() {
        if (!hasData) return "monitor";
        const g = info.gamemode?.state ?? "off";
        if (g === "active" || g === "tag" || g === "content") return "sports_esports";
        const fs = info.fullscreen?.mode ?? "";
        if (fs === "native_fs" || fs === "forced_fs") return "fullscreen";
        return "monitor";
    }

    function monitorBadge() {
        if (!hasData || !info.monitor) return "Display";
        const m = info.monitor;
        const label = (m.make && m.make.toUpperCase() === "AOC") ? "AOC" : (m.shortName || m.name || "Display");
        return m.hz > 0 ? (label + " · " + m.hz + "Hz") : label;
    }

    function vulkanSummary() {
        const p = info?.process;
        if (!p || !p.readable) return "";
        const hasVk = p.vulkanLoaded || !!p.presentMode || p.unorderedSubmitsDisabled !== null || p.lsfgLoaded || p.lsfgDisabled;
        if (!hasVk) return "";
        const parts = [];
        if (p.presentMode) parts.push("Present: " + p.presentMode);
        else if (p.vulkanLoaded) parts.push("Present: app-default");
        if (p.unorderedSubmitsDisabled === true) parts.push("WSI sync: safe");
        else if (p.unorderedSubmitsDisabled === false) parts.push("WSI sync: unordered");
        if (p.lsfgLoaded) parts.push("lsfg-vk: loaded");
        else if (p.lsfgDisabled) parts.push("lsfg-vk: bypassed");
        if (p.sdlDriver) parts.push("SDL: " + p.sdlDriver);
        return parts.join(" · ");
    }

    onPollingVisibleChanged: watch()
    Component.onCompleted: watch()
    Component.onDestruction: if (watching) DisplayAppStatus.watchers--

    Connections {
        target: DisplayAppStatus
        function onExpandedByDefaultChanged() {
            root.expanded = DisplayAppStatus.expandedByDefault;
        }
    }

    implicitHeight: contentCol.implicitHeight + 14
    radius: 14
    color: headerMouse.containsMouse
        ? Appearance.m3colors.m3surfaceContainerHighest
        : Appearance.m3colors.m3surfaceContainerHigh
    border.width: 1
    border.color: root.expanded
        ? Appearance.m3colors.m3outline
        : Appearance.m3colors.m3outlineVariant

    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

    component StatusPill: Rectangle {
        id: pill
        property string icon: ""
        property string label: ""
        property string tone: "neutral"

        height: 21
        implicitWidth: pillRow.implicitWidth + 13
        radius: 10.5
        color: root.pillBg(tone)
        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                visible: pill.icon.length > 0
                text: pill.icon
                iconSize: 12
                color: root.pillFg(pill.tone)
            }
            StyledText {
                text: pill.label
                textFormat: Text.PlainText
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.pillFg(pill.tone)
            }
        }
    }

    component DetailRow: RowLayout {
        id: drow
        property string label: ""
        property string value: ""
        property color valueColor: Appearance.m3colors.m3onSurface

        Layout.fillWidth: true
        spacing: 8

        StyledText {
            text: drow.label
            textFormat: Text.PlainText
            font.pixelSize: 11
            color: Appearance.m3colors.m3onSurfaceVariant
            Layout.preferredWidth: 68
        }
        StyledText {
            text: drow.value
            textFormat: Text.PlainText
            font.pixelSize: 11
            color: drow.valueColor
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
            topMargin: 7
        }
        spacing: 5

        Item {
            id: summaryArea
            Layout.fillWidth: true
            implicitHeight: summaryCol.implicitHeight

            ColumnLayout {
                id: summaryCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                spacing: 5

                RowLayout {
                    id: headerBar
                    objectName: "displayAppStatusHeader"
                    Layout.fillWidth: true
                    implicitHeight: 20
                    spacing: 6

                    MaterialSymbol {
                        text: root.headerIcon()
                        iconSize: 16
                        color: root.hasData ? root.dotColor(root.info.overall) : Appearance.m3colors.m3onSurfaceVariant
                    }

                    StyledText {
                        objectName: "displayAppStatusMonitor"
                        text: root.monitorBadge()
                        textFormat: Text.PlainText
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }

                    StyledText {
                        visible: root.hasData
                        text: "·"
                        font.pixelSize: 11
                        color: Appearance.m3colors.m3outline
                    }

                    StyledText {
                        objectName: "displayAppStatusApp"
                        Layout.fillWidth: true
                        text: root.hasData
                            ? (root.info.app?.name || "No active app")
                            : (DisplayAppStatus.ready ? "Display status unavailable" : "Reading display…")
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: root.hasData ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Rectangle {
                        visible: root.hasData
                        width: 7
                        height: 7
                        radius: 4
                        color: root.dotColor(root.info?.overall ?? "neutral")
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }

                    MaterialSymbol {
                        visible: root.hasData
                        text: "expand_more"
                        iconSize: 18
                        color: Appearance.m3colors.m3onSurfaceVariant
                        rotation: root.expanded ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                }

                Flow {
                    id: pillFlow
                    objectName: "displayAppStatusPills"
                    Layout.fillWidth: true
                    visible: root.hasData
                    spacing: 5

                    StatusPill {
                        objectName: "displayPillFullscreen"
                        icon: root.info?.fullscreen?.mode === "native_fs" ? "fullscreen"
                            : root.info?.fullscreen?.tone === "warn" ? "warning"
                            : "web_asset"
                        label: root.info?.fullscreen?.label ?? "Windowed"
                        tone: root.info?.fullscreen?.tone ?? "neutral"
                    }

                    StatusPill {
                        objectName: "displayPillScanout"
                        icon: root.info?.scanout?.state === "active" ? "bolt"
                            : root.info?.scanout?.state === "paused_panel" ? "layers"
                            : root.info?.scanout?.state === "blocked" ? "block"
                            : "display_settings"
                        label: root.info?.scanout?.label ?? "Scanout"
                        tone: root.info?.scanout?.tone ?? "neutral"
                    }

                    StatusPill {
                        objectName: "displayPillVrr"
                        icon: root.info?.vrr?.active ? "sync" : "sync_disabled"
                        label: root.info?.vrr?.label ?? "VRR"
                        tone: root.info?.vrr?.tone ?? "neutral"
                    }

                    StatusPill {
                        objectName: "displayPillGame"
                        icon: "sports_esports"
                        label: root.info?.gamemode?.label ?? "Game"
                        tone: root.info?.gamemode?.tone ?? "neutral"
                    }

                    StatusPill {
                        objectName: "displayPillProtocol"
                        icon: root.info?.protocol?.xwayland ? "window" : "desktop_windows"
                        label: root.info?.protocol?.label ?? "Wayland"
                        tone: root.info?.protocol?.tone ?? "neutral"
                    }

                    StatusPill {
                        objectName: "displayPillTearing"
                        icon: root.info?.tearing?.state === "active" ? "speed"
                            : root.info?.tearing?.state === "blocked" ? "warning"
                            : "sync_lock"
                        label: root.info?.tearing?.label ?? "No tear"
                        tone: root.info?.tearing?.tone ?? "neutral"
                    }
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
            id: detailsDrawer
            objectName: "displayAppStatusDetails"
            Layout.fillWidth: true
            visible: root.hasData && (implicitHeight > 0 || root.expanded)
            clip: true
            implicitHeight: (root.hasData && root.expanded) ? detailsCol.implicitHeight : 0
            opacity: (root.hasData && root.expanded) ? 1 : 0

            Behavior on implicitHeight {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                id: detailsCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                spacing: 5

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    implicitHeight: 1
                    color: Appearance.m3colors.m3outlineVariant
                    opacity: 0.6
                }

                DetailRow {
                    label: "Display"
                    value: {
                        const m = root.info?.monitor;
                        if (!m) return "";
                        const parts = [m.shortName || m.name];
                        if (m.name && m.shortName !== m.name) parts.push(m.name);
                        if (m.width && m.height) parts.push(m.width + "×" + m.height + " @ " + m.hz + "Hz");
                        if (m.workspace) parts.push("WS " + m.workspace);
                        return parts.join(" · ");
                    }
                }

                DetailRow {
                    visible: !!(root.info?.app?.present && root.info?.app?.title)
                    label: "Window"
                    value: (root.info?.app?.title || "") + (root.info?.app?.pid ? ("  (PID " + root.info.app.pid + ")") : "")
                }

                DetailRow {
                    label: "Fullscreen"
                    value: (root.info?.fullscreen?.detail ?? "")
                        + (root.info?.scanout?.solitary ? " · Solitary" : "")
                    valueColor: root.info?.fullscreen?.tone === "warn"
                        ? Appearance.m3colors.m3tertiary
                        : Appearance.m3colors.m3onSurface
                }

                DetailRow {
                    label: "Scanout"
                    value: root.info?.scanout?.detail ?? ""
                    valueColor: root.info?.scanout?.tone === "bad"
                        ? Appearance.m3colors.m3error
                        : root.info?.scanout?.tone === "warn"
                        ? Appearance.m3colors.m3tertiary
                        : Appearance.m3colors.m3onSurface
                }

                DetailRow {
                    label: "Game"
                    value: root.info?.gamemode?.detail ?? ""
                }

                DetailRow {
                    label: "Sync"
                    value: {
                        const v = root.info?.vrr;
                        const t = root.info?.tearing;
                        if (!v || !t) return "";
                        return (v.active ? "VRR active" : "VRR off")
                            + " (" + (v.policyLabel || v.policy) + ") · "
                            + (t.detail || t.label);
                    }
                }

                DetailRow {
                    objectName: "displayAppStatusVulkan"
                    visible: DisplayAppStatus.showProcessDetails && root.vulkanSummary().length > 0
                    label: "Vulkan"
                    value: root.vulkanSummary()
                }

                Rectangle {
                    visible: !!(root.info?.tip && root.info.tip.length > 0)
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: tipRow.implicitHeight + 10
                    radius: 10
                    color: Appearance.m3colors.m3secondaryContainer

                    RowLayout {
                        id: tipRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 6
                        MaterialSymbol {
                            text: "info"
                            iconSize: 13
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.info?.tip ?? ""
                            textFormat: Text.PlainText
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: DisplayAppStatus.busy ? "Refreshing…" : "Live · updates while panel is open"
                        textFormat: Text.PlainText
                        font.pixelSize: 10
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    Rectangle {
                        objectName: "displayAppStatusRefresh"
                        implicitHeight: 22
                        implicitWidth: refreshRow.implicitWidth + 14
                        radius: 11
                        color: refreshMouse.containsMouse
                            ? Appearance.m3colors.m3surfaceContainerHighest
                            : Appearance.m3colors.m3surfaceContainer
                        border.width: 1
                        border.color: Appearance.m3colors.m3outlineVariant

                        RowLayout {
                            id: refreshRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: "refresh"
                                iconSize: 12
                                color: Appearance.m3colors.m3onSurfaceVariant
                            }
                            StyledText {
                                text: "Refresh"
                                font.pixelSize: 10
                                color: Appearance.m3colors.m3onSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DisplayAppStatus.refresh()
                        }
                    }
                }
            }
        }
    }
}
