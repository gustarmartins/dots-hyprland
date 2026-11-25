//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import "modules/settings/SettingsCatalog.js" as Catalog

ApplicationWindow {
    id: root
    property string currentPage: "design"
    property string designSection: ""
    property string query: ""
    property string feedback: "Changes save automatically. Text lists use a Save button."
    readonly property bool searching: query.trim().length > 0
    readonly property var page: Catalog.page(currentPage)
    readonly property bool wide: width >= 900
    readonly property bool isLight: Appearance.m3colors.darkmode === false
    readonly property color canvasColor: isLight ? Appearance.m3colors.m3surfaceContainerLow : Appearance.m3colors.m3background
    readonly property color railColor: isLight ? Appearance.m3colors.m3surfaceContainer : Appearance.m3colors.m3surfaceContainerLowest
    property bool aboutVisited: false

    visible: true
    title: "illogical-impulse Settings"
    width: 1180
    height: 800
    minimumWidth: 680
    minimumHeight: 480
    font.family: Appearance.font.family.main
    font.pixelSize: 13
    palette {
        window: canvasColor
        windowText: Appearance.m3colors.m3onSurface
        base: Appearance.m3colors.m3surfaceContainerHigh
        alternateBase: Appearance.m3colors.m3surfaceContainerLow
        text: Appearance.m3colors.m3onSurface
        placeholderText: Appearance.m3colors.m3onSurfaceVariant
        button: Appearance.m3colors.m3surfaceContainerHigh
        buttonText: Appearance.m3colors.m3onSurface
        brightText: Appearance.m3colors.m3onPrimary
        light: Appearance.m3colors.m3surfaceContainerHighest
        midlight: Appearance.m3colors.m3surfaceContainerHigh
        mid: Appearance.m3colors.m3outlineVariant
        dark: Appearance.m3colors.m3outline
        shadow: Appearance.m3colors.m3shadow
        highlight: Appearance.m3colors.m3primary
        highlightedText: Appearance.m3colors.m3onPrimary
        toolTipBase: Appearance.m3colors.m3inverseSurface
        toolTipText: Appearance.m3colors.m3inverseOnSurface
        link: Appearance.m3colors.m3primary
        linkVisited: Appearance.m3colors.m3tertiary
    }
    color: canvasColor
    onClosing: event => { if (Config.writesPaused) event.accepted = false; else Qt.quit(); }
    Component.onCompleted: MaterialThemeLoader.reapplyTheme()

    function navigate(id) {
        if (Config.writesPaused) return;
        designSection = id === "fonts" ? "fonts" : id === "effects" ? "effects" : "";
        if (id === "about") aboutVisited = true;
        currentPage = Catalog.canonicalPage(id);
        query = ""; searchField.text = "";
        if (designSection) Qt.callLater(() => designPage.revealSection());
    }

    Shortcut { sequence: "Ctrl+F"; enabled: !Config.writesPaused; onActivated: { searchField.forceActiveFocus(); searchField.selectAll(); } }
    Shortcut { sequence: "Ctrl+PageDown"; enabled: !Config.writesPaused; onActivated: root.navigate(Catalog.pages[(Catalog.pages.findIndex(p => p.id === root.currentPage) + 1) % Catalog.pages.length].id) }
    Shortcut { sequence: "Ctrl+PageUp"; enabled: !Config.writesPaused; onActivated: root.navigate(Catalog.pages[(Catalog.pages.findIndex(p => p.id === root.currentPage) + Catalog.pages.length - 1) % Catalog.pages.length].id) }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Material 3 Expressive Navigation Drawer Pane
        Rectangle {
            Layout.preferredWidth: root.wide ? 232 : 178
            Layout.fillHeight: true
            color: root.railColor

            ColumnLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 16; bottomMargin: 14 }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 4
                    spacing: 10
                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 11
                        color: Appearance.m3colors.m3primaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "tune"
                            iconSize: 20
                            color: Appearance.m3colors.m3onPrimaryContainer
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Settings"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }

                ListView {
                    id: navigation
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: Catalog.pages
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: StyledScrollBar {}
                    delegate: AbstractButton {
                        id: navButton
                        required property var modelData
                        readonly property bool selected: !root.searching && root.currentPage === modelData.id
                        width: navigation.width
                        height: root.wide ? 42 : 46
                        padding: 0
                        enabled: !Config.writesPaused
                        Accessible.name: modelData.title
                        ToolTip.visible: hovered && !root.wide
                        ToolTip.text: modelData.title
                        onClicked: root.navigate(modelData.id)
                        background: Rectangle {
                            radius: height / 2
                            color: navButton.selected
                                ? Appearance.m3colors.m3secondaryContainer
                                : navButton.down
                                    ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.10)
                                    : navButton.hovered
                                        ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.06)
                                        : "transparent"
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        contentItem: RowLayout {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 12 }
                            spacing: 11
                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 20
                                fill: navButton.selected ? 1 : 0
                                color: navButton.selected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.title
                                textFormat: Text.PlainText
                                font.pixelSize: root.wide ? 13 : 12
                                font.weight: navButton.selected ? Font.DemiBold : Font.Normal
                                color: navButton.selected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                                elide: Text.ElideRight
                                wrapMode: root.wide ? Text.NoWrap : Text.WordWrap
                            }
                        }
                    }
                }

                SettingsButton {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    text: root.wide ? "Open config file" : "{ }"
                    Accessible.name: "Open configuration file"
                    enabled: !Config.writesPaused
                    onClicked: Qt.openUrlExternally(Directories.shellConfigPath)
                }
            }
        }

        // Right Content Pane
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Top bar: page title + pill search + close
            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(102, headerRow.implicitHeight + 44)

                RowLayout {
                    id: headerRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 24
                        rightMargin: 20
                    }
                    spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: root.searching ? "Search results" : root.page.title
                            textFormat: Text.PlainText
                            font.family: Appearance.font.family.title
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.searching
                                ? "Matches across every desktop page · edit directly below."
                                : root.page.description
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            color: Appearance.m3colors.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    // Material 3 Pill Search Bar
                    Rectangle {
                        Layout.preferredWidth: Math.min(340, Math.max(200, root.width * 0.28))
                        implicitHeight: 40
                        radius: 20
                        color: root.isLight ? Appearance.m3colors.m3surfaceContainerLowest : Appearance.m3colors.m3surfaceContainerHigh
                        border.width: searchField.activeFocus ? 2 : 1
                        border.color: searchField.activeFocus ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                            spacing: 6
                            MaterialSymbol {
                                text: "search"
                                iconSize: 18
                                color: searchField.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurfaceVariant
                            }
                            TextField {
                                id: searchField
                                objectName: "settingsSearch"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: TextInput.AlignVCenter
                                color: Appearance.m3colors.m3onSurface
                                placeholderTextColor: Appearance.m3colors.m3onSurfaceVariant
                                selectionColor: Appearance.m3colors.m3primary
                                selectedTextColor: Appearance.m3colors.m3onPrimary
                                background: Item {}
                                placeholderText: root.wide ? "Search settings…  Ctrl+F" : "Search…"
                                Accessible.name: "Search all settings"
                                selectByMouse: true
                                enabled: !Config.writesPaused
                                onTextEdited: root.query = text
                                Keys.onEscapePressed: { text = ""; root.query = ""; }
                            }
                            AbstractButton {
                                visible: searchField.text.length > 0
                                implicitWidth: 26
                                implicitHeight: 26
                                Accessible.name: "Clear search"
                                onClicked: { searchField.text = ""; root.query = ""; }
                                background: Rectangle {
                                    radius: 13
                                    color: parent.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.08) : "transparent"
                                }
                                contentItem: MaterialSymbol {
                                    text: "close"
                                    iconSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    color: Appearance.m3colors.m3onSurfaceVariant
                                }
                            }
                        }
                    }

                    ToolButton {
                        id: closeButton
                        implicitWidth: 38
                        implicitHeight: 38
                        Accessible.name: "Close settings"
                        enabled: !Config.writesPaused
                        onClicked: root.close()
                        background: Rectangle {
                            radius: 19
                            color: closeButton.down ? Appearance.m3colors.m3secondaryContainer
                                : closeButton.hovered ? Appearance.m3colors.m3surfaceContainerHighest
                                : root.isLight ? Appearance.m3colors.m3surfaceContainerLowest : Appearance.m3colors.m3surfaceContainerHigh
                            border.width: closeButton.visualFocus ? 2 : 1
                            border.color: closeButton.visualFocus ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: MaterialSymbol {
                            text: "close"
                            iconSize: 19
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: closeButton.down ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                        }
                    }
                }
            }

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: !Config.ready ? 4 : root.searching ? 2 : root.currentPage === "home" ? 0 : root.currentPage === "design" ? 1 : root.currentPage === "about" ? 3 : 2
                SettingsHome { onNavigate: id => root.navigate(id) }
                DesignPage {
                    id: designPage
                    requestedSection: root.designSection
                    onEdited: path => { root.feedback = "Saved · " + (Catalog.entries.find(e => e.path === path)?.title ?? "Setting"); }
                }
                CatalogPage {
                    id: catalogPage
                    effectsEditor: designPage.effectsEditor
                    pageId: root.currentPage
                    query: root.query
                    writable: !Config.writesPaused
                    onNavigate: id => root.navigate(id)
                    onEdited: path => { root.feedback = "Saved · " + (Catalog.entries.find(e => e.path === path)?.title ?? "Setting"); }
                }
                Loader { id: about; active: root.aboutVisited; source: "modules/settings/About.qml" }
                BusyIndicator { running: !Config.ready }
            }

            // Pinned bottom bar (Memory draft OR Design staged Apply/Reset OR subtle status bar)
            Rectangle {
                id: footerBar
                Layout.fillWidth: true
                readonly property bool showMemoryBar: MemoryLockDraft.initialized && (root.currentPage === "memory" || MemoryLockDraft.dirty || MemoryLockDraft.applying)
                readonly property bool showDesignApply: (root.currentPage === "design" || root.searching) && designPage.effectsDirty
                readonly property bool showStatusBar: root.currentPage !== "memory" || root.searching || !!Config.writeError || Config.writesPaused
                visible: showMemoryBar || showStatusBar
                implicitHeight: footerCol.implicitHeight + 18
                color: showDesignApply ? Appearance.m3colors.m3secondaryContainer : root.railColor
                Behavior on color { ColorAnimation { duration: 160 } }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1
                    color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.45)
                }

                ColumnLayout {
                    id: footerCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 24; rightMargin: 20 }
                    spacing: 8

                    RowLayout {
                        visible: footerBar.showMemoryBar
                        Layout.fillWidth: true
                        spacing: 10
                        BusyIndicator { running: MemoryLockDraft.applying || MemoryLockDraft.checking; visible: running; implicitWidth: 22; implicitHeight: 22 }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 30
                            text: MemoryLockDraft.applying ? "Applying… New edits stay in the next draft."
                                : MemoryLockDraft.checking ? "Checking selected groups…"
                                : MemoryLockDraft.needsReview && !MemoryLockDraft.acknowledged ? "Review group warnings to apply"
                                : MemoryLockDraft.dirty ? "Changes not applied" : "No pending changes"
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                        }
                        MemoryActionButton {
                            objectName: "memoryReview"
                            visible: MemoryLockDraft.operations.length > 0 || MemoryLockDraft.needsReview
                            text: "Review (" + MemoryLockDraft.operations.length + ")"
                            onClicked: {
                                if (root.currentPage !== "memory" || root.searching) root.navigate("memory");
                                Qt.callLater(() => catalogPage.showMemoryReview());
                            }
                        }
                        MemoryActionButton { objectName: "memoryDiscard"; text: "Discard"; enabled: !MemoryLockDraft.applying && MemoryLockDraft.dirty; onClicked: MemoryLockDraft.discard() }
                        MemoryActionButton { objectName: "memoryApplyAll"; text: MemoryLockDraft.applying ? "Applying…" : "Apply all"; prominent: true; enabled: MemoryLockDraft.canApply; onClicked: MemoryLockDraft.applyAll() }
                    }

                    RowLayout {
                        visible: footerBar.showStatusBar
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            visible: footerBar.showDesignApply
                            text: "pending_actions"
                            iconSize: 18
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.searching && designPage.effectsDirty ? "Unapplied GPU / animation edits"
                                : root.currentPage === "memory" ? "Memory-lock edits apply together with Apply all. Browsing never changes locks."
                                : Config.writeError ? Config.writeError
                                : Config.writesPaused ? "Applying desktop fonts…"
                                : root.currentPage === "design" && !root.searching
                                    ? (designPage.effectsDirty ? "You have unapplied GPU or animation edits" : designPage.effectsStatus + " · Color and shell changes save immediately.")
                                : root.feedback
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                            font.weight: footerBar.showDesignApply ? Font.Medium : Font.Normal
                            color: Config.writeError ? Appearance.m3colors.m3error
                                : footerBar.showDesignApply ? Appearance.m3colors.m3onSecondaryContainer
                                : Appearance.m3colors.m3onSurfaceVariant
                        }
                        SettingsButton {
                            objectName: "designReset"
                            visible: footerBar.showDesignApply
                            enabled: !designPage.effectsBusy && !Config.writesPaused
                            implicitHeight: 36
                            text: "Reset edits"
                            onClicked: designPage.resetEffects()
                        }
                        SettingsButton {
                            objectName: "designApply"
                            prominent: true
                            visible: footerBar.showDesignApply
                            enabled: !designPage.effectsBusy && !Config.writesPaused
                            implicitHeight: 36
                            text: "Apply custom changes"
                            onClicked: designPage.applyEffects()
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "settings"
        function open(page: string): void { if (Catalog.pages.some(p => p.id === Catalog.canonicalPage(page))) root.navigate(page); }
        function search(text: string): void { if (!Config.writesPaused) { searchField.text = text; root.query = text; } }
        function status(): string { return JSON.stringify({page:root.currentPage,search:root.query,ready:Config.ready,loading:Config.writesPaused,pages:Catalog.pages.map(p=>p.id),settings:Catalog.entries.length}); }
    }
}
