pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.waffle.startMenu
import Quickshell
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick

RowLayout {
    id: root

    property int maxResultsPerCategory: 4
    property int resultLimit: 20
    property StartMenuContext context
    property int currentIndex: context.currentIndex
    onCurrentIndexChanged: {
        forceCurrentIndex(currentIndex);
    }
    function focusFirstItem() {
        forceCurrentIndex(0);
    }
    function forceCurrentIndex(index) {
        context.currentIndex = index;
        // Somehow this hack is needed
        if (index === 0) {
            resultList.incrementCurrentIndex();
            resultList.decrementCurrentIndex();
        } else {
            resultList.decrementCurrentIndex();
            resultList.incrementCurrentIndex();
        }
    }

    Connections {
        target: context
        function onAccepted() {
            resultList.currentItem?.execute();
        }
    }

    ResultList {
        id: resultList
        Layout.fillHeight: true
        Layout.fillWidth: true
    }
    LauncherSearchResult { id: emptyEntry }
    ResultPreview {
        Layout.preferredWidth: 386
        Layout.leftMargin: 1
        Layout.rightMargin: 1
        entry: resultList.rows[resultList.currentIndex]?.entry ?? emptyEntry
    }

    component ResultList: WListView {
        id: resultListView
        clip: true
        spacing: 4
        currentIndex: root.currentIndex

        readonly property var rows: {
            const allResults = LauncherSearch.results;
            const groups = new Map();
            for (const entry of allResults) {
                let group = groups.get(entry.type);
                if (!group) {
                    if (groups.size >= root.resultLimit) continue;
                    group = [];
                    groups.set(entry.type, group);
                }
                if (group.length < root.maxResultsPerCategory) group.push(entry);
            }
            const categorizedResults = [];
            for (const group of groups.values()) {
                for (const entry of group) {
                    const category = categorizedResults.length ? entry.type : Translation.tr("Best match");
                    categorizedResults.push({ entry, category });
                    if (categorizedResults.length >= root.resultLimit) return categorizedResults;
                }
            }
            return categorizedResults;
        }
        model: rows.length
        onRowsChanged: if (resultList) root.focusFirstItem()
        delegate: Column {
            id: row
            required property int index
            readonly property var result: resultListView.rows[index]
            width: resultListView.width
            spacing: resultListView.spacing
            function execute() { button.execute(); }

            WChoiceButton {
                width: parent.width
                visible: row.result !== undefined && (row.index === 0
                    || resultListView.rows[row.index-1]?.category !== row.result.category)
                implicitHeight: 38
                contentItem: WText {
                    text: row.result?.category ?? ""
                    font.pixelSize: Looks.font.pixelSize.large
                    font.weight: Looks.font.weight.strong
                }
                onClicked: root.context.selectCategory(row.result.category)
            }
            SearchResultButton {
                id: button
                width: parent.width
                entry: row.result?.entry ?? emptyEntry
                firstEntry: row.index === 0
                checked: resultListView.currentIndex === row.index
                onRequestFocus: root.forceCurrentIndex(row.index)
            }
        }
    }

    component ResultPreview: Rectangle {
        id: resultPreview

        property var entry: emptyEntry

        Layout.fillHeight: true
        color: Looks.colors.bg1
        radius: Looks.radius.large

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 13

            ColumnLayout {
                id: mainInfoColumn
                Layout.alignment: Qt.AlignHCenter
                SearchEntryIcon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                    Layout.bottomMargin: 12
                    entry: resultPreview.entry
                    iconSize: 64
                }
                WText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    text: resultPreview.entry?.name || ""
                    font.pixelSize: Looks.font.pixelSize.xlarger
                }
                WText {
                    Layout.alignment: Qt.AlignHCenter
                    text: resultPreview.entry?.type || ""
                    color: Looks.colors.accentUnfocused
                    font.pixelSize: Looks.font.pixelSize.normal
                }
            }
            Rectangle {
                id: resultSeparator
                implicitHeight: 2
                Layout.topMargin: 16
                Layout.fillWidth: true
                color: Looks.colors.bg2Hover
            }
            WListView {
                id: actionsColumn
                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                spacing: 2
                model: {
                    const isAppEntry = resultPreview.entry.type === Translation.tr("App");
                    const appId = isAppEntry ? resultPreview.entry.id : "";
                    const pinned = isAppEntry ? (Config.options.dock.pinnedApps.includes(appId)) : false;
                    const startPinned = isAppEntry ? (Config.options.launcher.pinnedApps.includes(appId)) : false;
                    var result = [
                        ({
                            name: resultPreview.entry.verb,
                            iconName: isAppEntry ? "open_in_new" : "keyboard_return",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                resultPreview.entry.execute();
                            }
                        }),
                        ...(isAppEntry ? [
                            ({
                                name: startPinned ? Translation.tr("Unpin from Start") : Translation.tr("Pin to Start"),
                                iconName: startPinned ? "keep_off" : "keep",
                                iconType: LauncherSearchResult.IconType.Material,
                                execute: () => {
                                    LauncherApps.togglePin(appId);
                                }
                            })
                        ] : []),
                        ...(isAppEntry ? [
                            ({
                                name: pinned ? Translation.tr("Unpin from taskbar") : Translation.tr("Pin to taskbar"),
                                iconName: pinned ? "keep_off" : "keep",
                                iconType: LauncherSearchResult.IconType.Material,
                                execute: () => {
                                    TaskbarApps.togglePin(appId);
                                }
                            })
                        ] : []),
                    ];
                    result = result.concat(resultPreview.entry.actions ?? []);
                    return result;
                }
                delegate: WButton {
                    id: actionButton
                    required property var modelData
                    width: ListView.view?.width
                    icon.name: modelData.iconName
                    text: modelData.name
                    onClicked: modelData.execute();

                    contentItem: RowLayout {
                        spacing: 11
                        SearchEntryIcon {
                            entry: actionButton.modelData
                            iconSize: 16
                        }
                        WText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            text: actionButton.text
                        }
                    }
                }
            }
        }
    }

}
