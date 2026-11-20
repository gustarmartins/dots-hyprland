import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.services
import qs.modules.common.widgets

ColumnLayout {
    id: root
    objectName: "memoryLocks"
    spacing: 10
    readonly property var state: MemoryLockDraft.snapshot
    readonly property bool ready: MemoryLockDraft.ready
    readonly property string error: MemoryLockDraft.error
    readonly property string readError: MemoryLockDraft.readError
    // The process browser is the first thing you see, including when there are no locks.
    // 0 = suggested, 1 = all, 2 = locked, 3 = saved names, 4 = review.
    property int tab: 0
    property int sortIndex: 0
    property string query: ""
    property int shown: 25
    property bool optionsOpen: false
    property bool explanationOpen: false
    property bool resultsOpen: false
    readonly property string helper: MemoryLockDraft.helper
    readonly property color warningColor: Appearance.m3colors.darkmode ? "#edc274" : "#805000"
    readonly property var protectedProcesses: state.processes.filter(p => p.protected === true)
    readonly property var rows: visibleRows()
    readonly property var selectableRows: selectionCandidates()
    readonly property bool reviewTabVisible: MemoryLockDraft.operations.length > 0 || MemoryLockDraft.results.length > 0 || MemoryLockDraft.needsReview || tab === 4
    function bytes(n) { return n === null || n === undefined ? "Unknown" : n >= 1073741824 ? (n / 1073741824).toFixed(2) + " GiB" : (n / 1048576).toFixed(0) + " MiB"; }
    function visibleRows() {
        let items = state.processes.slice();
        if (tab === 0) items = items.filter(p => p.can_lock && !p.protected && p.rss > 0);
        if (tab === 2) items = items.filter(p => p.protected === true);
        if (tab === 1 && query.trim()) {
            const term = query.trim().toLowerCase();
            items = items.filter(p => String(p.pid).includes(term) || p.name.toLowerCase().includes(term));
        }
        items.sort((a, b) => sortIndex === 2 ? a.name.localeCompare(b.name) || a.pid - b.pid : sortIndex === 3 ? a.pid - b.pid : (b[sortIndex === 1 ? "swap" : "rss"] ?? -1) - (a[sortIndex === 1 ? "swap" : "rss"] ?? -1) || a.pid - b.pid);
        if (tab === 0) {
            // Running build jobs dominate RAM but are transient. They remain in All.
            const nonBuild = items.filter(p => !/(?:^|[\/._-])(?:buildquota|build|gradle)(?:[\/._-]|$)/i.test(p.group || "") && !/^(?:clang(?:\+\+)?|gcc|g\+\+|cc1plus|ld|ninja)$/i.test(p.name));
            if (nonBuild.length) items = nonBuild;
            const groups = new Set();
            const names = new Set();
            items = items.filter(p => {
                if (groups.has(p.group) || names.has(p.name)) return false;
                groups.add(p.group); names.add(p.name); return true;
            }).slice(0, 6);
        }
        return items;
    }
    function selectionCandidates() {
        const groups = new Set();
        return rows.slice(0, shown).filter(p => {
            if (MemoryLockDraft.operationFor(p)) return false;
            if (tab === 2 ? !p.lock_id : (!p.can_lock || p.protected)) return false;
            const key = p.lock_id || p.group;
            if (groups.has(key)) return false;
            groups.add(key);
            return true;
        });
    }
    function refresh() { MemoryLockDraft.refresh(); }
    function addName() { MemoryLockDraft.addNames(nameInput.text, sharedName.checked); }
    function requestLock(p) { MemoryLockDraft.selectLock(p); }
    function requestRelease(p) { MemoryLockDraft.selectRelease(p); }
    function selectShown() {
        for (const p of selectableRows) {
            if (tab === 2) requestRelease(p);
            else requestLock(p);
        }
    }
    function showReview() { tab = 4; }
    onTabChanged: {
        shown = 25;
        if (tab !== 1 && searchInput.text) searchInput.text = "";
    }
    onQueryChanged: shown = 25
    onSortIndexChanged: shown = 25
    Component.onCompleted: MemoryLockDraft.attach()
    Component.onDestruction: MemoryLockDraft.detach()

    // One compact status bar, instead of an explanation above the process list.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: statusRow.implicitHeight + 16
        radius: 12
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.m3colors.m3outlineVariant
        RowLayout {
            id: statusRow
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 10
            MaterialSymbol { text: "memory"; iconSize: 24; color: Appearance.m3colors.m3primary }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 40
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.state.enabled ? (MemoryLockDraft.draft.enabled ? "Protection on" : "Protection on · off pending") : (MemoryLockDraft.draft.enabled ? "Protection off · on pending" : "Protection off")
                    font.weight: Font.DemiBold
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.ready ? root.protectedProcesses.length + " protected  ·  " + root.bytes(root.state.memory.available) + " available" : "Loading process information…"
                    font.pixelSize: 12
                    color: root.state.memory.low ? root.warningColor : Appearance.m3colors.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }
            MemoryActionButton {
                objectName: "memoryRefresh"
                text: MemoryLockDraft.reading ? "Refreshing…" : "Refresh"
                enabled: !MemoryLockDraft.reading && !MemoryLockDraft.applying
                onClicked: root.refresh()
            }
            SettingsSwitch {
                objectName: "memoryMaster"
                checked: MemoryLockDraft.draft.enabled
                enabled: MemoryLockDraft.initialized
                Accessible.name: "Enable memory locks"
                onClicked: MemoryLockDraft.setSwitch("enabled", checked)
            }
        }
    }
    StyledText { Layout.fillWidth: true; visible: !!root.error; text: root.error; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
    StyledText { Layout.fillWidth: true; visible: !!root.readError; text: root.readError; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
    MemoryActionButton { visible: !root.ready && !!root.readError; text: "Retry"; enabled: !MemoryLockDraft.reading; onClicked: root.refresh() }
    StyledText {
        Layout.fillWidth: true
        visible: root.ready && MemoryLockDraft.draft.enabled && (root.state.memory.low || root.state.memory.swap_total === 0)
        text: root.state.memory.low ? "RAM is running low. Review large locks before adding more." : "Swap is off; locks affect future swap use if it is enabled."
        color: root.warningColor
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        visible: MemoryLockDraft.draft.enabled && MemoryLockDraft.initialized
        Layout.fillWidth: true
        spacing: 8
        TabBar {
            id: views
            objectName: "memoryViews"
            Layout.fillWidth: true
            implicitWidth: 0
            spacing: 0
            currentIndex: root.tab
            onCurrentIndexChanged: root.tab = currentIndex
            background: Rectangle { radius: 10; color: Appearance.m3colors.m3surfaceContainerLow }
            MemoryTab { objectName: "memoryTabSuggested"; text: "Suggested" }
            MemoryTab { objectName: "memoryTabSearch"; text: "All" }
            MemoryTab { objectName: "memoryTabLocked"; text: "Locked (" + root.protectedProcesses.length + ")" }
            MemoryTab { objectName: "memoryTabSaved"; text: "Saved (" + MemoryLockDraft.draft.rules.length + ")"; Accessible.name: "Saved process names" }
            MemoryTab {
                objectName: "memoryTabReview"
                visible: root.reviewTabVisible
                text: "Review (" + MemoryLockDraft.operations.length + ")"
                Accessible.name: "Review selected groups"
            }
        }
        ColumnLayout {
            objectName: "memoryProcessBrowser"
            visible: root.tab <= 2
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SettingsField {
                    id: searchInput
                    objectName: "memorySearch"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 100
                    placeholderText: "Search all processes by name or PID…"
                    Accessible.name: "Search all processes by PID or name"
                    selectByMouse: true
                    onTextChanged: {
                        root.query = text;
                        if (text.trim() && root.tab !== 1) root.tab = 1;
                    }
                }
                SettingsComboBox {
                    objectName: "memorySort"
                    Layout.preferredWidth: root.width < 560 ? 145 : 185
                    model: ["RAM · largest", "Swap · largest", "Name · A–Z", "PID · ascending"]
                    currentIndex: root.sortIndex
                    onActivated: root.sortIndex = currentIndex
                    Accessible.name: "Sort processes"
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 40
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.tab === 0 ? "Suggested processes" : root.tab === 1 ? "All processes (" + root.rows.length + ")" : "Protected processes (" + root.rows.length + ")"
                        font.weight: Font.DemiBold
                        font.pixelSize: 15
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.tab === 0 ? "One per name and group · build jobs deprioritized" : root.tab === 1 ? "Your processes, sorted by " + (root.sortIndex === 1 ? "swap" : root.sortIndex === 2 ? "name" : root.sortIndex === 3 ? "PID" : "RAM") : "Release restores the group's previous swap limit"
                        font.pixelSize: 12
                        color: Appearance.m3colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
                MemoryActionButton {
                    objectName: "memorySelectShown"
                    text: "Select " + root.selectableRows.length
                    enabled: root.ready && root.selectableRows.length > 0
                    Accessible.name: "Select " + root.selectableRows.length + (root.tab === 2 ? " loaded groups to release" : " loaded groups to protect")
                    ToolTip.visible: hovered
                    ToolTip.text: Accessible.name
                    onClicked: root.selectShown()
                }
            }
            Repeater {
                model: root.rows.slice(0, root.shown)
                delegate: MemoryProcessRow {
                    required property var modelData
                    processData: modelData
                    totalRam: root.state.memory.total || 0
                    busy: !root.ready || MemoryLockDraft.inFlight(modelData)
                    selected: !!MemoryLockDraft.operationFor(modelData)
                    onLockRequested: p => root.requestLock(p)
                    onReleaseRequested: p => root.requestRelease(p)
                }
            }
            Rectangle {
                Layout.fillWidth: true
                visible: root.ready && root.rows.length === 0
                implicitHeight: emptyText.implicitHeight + 24
                radius: 10
                color: Appearance.m3colors.m3surfaceContainer
                StyledText {
                    id: emptyText
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    text: root.tab === 0 ? "No eligible groups right now. Open All to browse every process."
                        : root.tab === 2 ? "Nothing is protected yet. Choose a process in Suggested or All."
                        : "No processes match. Try a different name or PID."
                    color: Appearance.m3colors.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
            MemoryActionButton { visible: root.rows.length > root.shown; text: "Show next 25 · " + (root.rows.length - root.shown) + " remaining"; onClicked: root.shown += 25 }
        }
        ColumnLayout {
            visible: root.tab === 3
            Layout.fillWidth: true
            spacing: 8
            StyledText { text: "Saved process names"; font.weight: Font.DemiBold; font.pixelSize: 16 }
            StyledText { Layout.fillWidth: true; text: "Protect future launches by exact, case-sensitive name. Separate multiple names with commas."; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
            RowLayout {
                Layout.fillWidth: true
                SettingsField {
                    id: nameInput
                    objectName: "memoryName"
                    Layout.fillWidth: true
                    placeholderText: "Process name, e.g. mpv"
                    Accessible.name: "Save a process name for future launches"
                    selectByMouse: true
                    enabled: MemoryLockDraft.initialized
                    text: MemoryLockDraft.nameText
                    onTextEdited: MemoryLockDraft.nameText = text
                    onAccepted: root.addName()
                }
                MemoryActionButton { objectName: "memorySaveName"; text: "Add"; prominent: true; enabled: MemoryLockDraft.initialized && nameInput.text.trim().length > 0; onClicked: root.addName() }
            }
            MemoryCheckBox {
                id: sharedName
                objectName: "memoryNameShared"
                Layout.fillWidth: true
                text: "Allow other processes in the same group for these names"
                checked: MemoryLockDraft.nameShared
                enabled: MemoryLockDraft.initialized
                onClicked: MemoryLockDraft.nameShared = checked
            }
            Repeater {
                model: MemoryLockDraft.draft.rules
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            StyledText { Layout.fillWidth: true; text: modelData.name; textFormat: Text.PlainText; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            StyledText { Layout.fillWidth: true; text: MemoryLockDraft.nameStatus(modelData.name); textFormat: Text.PlainText; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
                        }
                        MemoryActionButton { objectName: "memoryRemoveName:" + modelData.name; text: "Remove"; enabled: MemoryLockDraft.initialized; onClicked: MemoryLockDraft.removeName(modelData.name) }
                    }
                    MemoryCheckBox {
                        Layout.fillWidth: true
                        text: "Allow shared group for " + modelData.name
                        checked: modelData.shared
                        enabled: MemoryLockDraft.initialized
                        onClicked: MemoryLockDraft.setShared(modelData.name, checked)
                    }
                }
            }
            StyledText { Layout.fillWidth: true; text: "Shared groups wait unless allowed. Removing a saved name can release locks owned by that rule."; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
        }
    }

    // Review is also available with master staged off, where existing groups can need review.
    ColumnLayout {
        visible: root.tab === 4 && MemoryLockDraft.initialized
        Layout.fillWidth: true
        spacing: 8
        StyledText { text: "Review changes"; font.weight: Font.DemiBold; font.pixelSize: 17 }
        StyledText {
            Layout.fillWidth: true
            text: MemoryLockDraft.operations.length ? "Changes apply to each whole process group. Review members and warnings before applying." : "No process groups selected. Other staged settings are included when you apply."
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        Repeater {
            model: MemoryLockDraft.operations
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: reviewBody.implicitHeight + 20
                color: Appearance.m3colors.m3surfaceContainer
                border.color: modelData.risky ? root.warningColor : Appearance.m3colors.m3outlineVariant
                border.width: 1
                radius: 10
                ColumnLayout {
                    id: reviewBody
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { Layout.fillWidth: true; text: modelData.label; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; font.weight: Font.DemiBold }
                        MemoryActionButton { objectName: "memoryUnselect:" + modelData.id; text: "Undo"; enabled: !MemoryLockDraft.applying || !(MemoryLockDraft.submitted.operations || []).some(o => o.id === modelData.id); onClicked: MemoryLockDraft.removeOperation(modelData.id) }
                    }
                    StyledText { Layout.fillWidth: true; visible: !!modelData.members && modelData.members.length > 0; text: "Group: " + (modelData.members || []).map(p => p.name + " (" + p.pid + ")").join(", "); textFormat: Text.PlainText; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
                    StyledText { Layout.fillWidth: true; visible: (modelData.warnings || []).length > 0; text: (modelData.warnings || []).join("\n"); textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.warningColor }
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: !MemoryLockDraft.draft.enabled && MemoryLockDraft.needsReview
            text: "Turning protection off will restore limits for groups changed outside Memory locks. Check the restore entries below before applying."
            wrapMode: Text.WordWrap
            color: root.warningColor
        }
        MemoryCheckBox {
            objectName: "memoryRiskAccepted"
            Layout.fillWidth: true
            visible: MemoryLockDraft.needsReview
            checked: MemoryLockDraft.acknowledged
            onClicked: MemoryLockDraft.acknowledged = checked
            text: "I reviewed the affected groups and warnings"
        }
        MemoryActionButton { visible: MemoryLockDraft.results.length > 0; text: root.resultsOpen ? "Hide last results" : "Show last results"; onClicked: root.resultsOpen = !root.resultsOpen }
        Repeater {
            model: root.resultsOpen ? MemoryLockDraft.results : []
            delegate: StyledText {
                required property var modelData
                Layout.fillWidth: true
                text: (modelData.ok ? "Applied · " : "Retry needed · ") + modelData.label + (modelData.message ? " — " + modelData.message : "")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: modelData.ok ? Appearance.m3colors.m3success : root.warningColor
            }
        }
    }

    // Failed restores remain actionable even if master off already stopped the timer.
    Repeater {
        model: root.ready ? root.state.locks.filter(r => r.status !== "locked" || !root.state.enabled || r.members.length === 0) : []
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: modelData.unit + " · " + modelData.status; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.warningColor }
            MemoryActionButton { text: "Restore limit"; enabled: root.ready; onClicked: MemoryLockDraft.selectRelease({lock_id:modelData.id, group:modelData.cgroup}) }
        }
    }
    MemoryActionButton { objectName: "memoryOptions"; text: root.optionsOpen ? "Hide options and OOM alerts" : "Options, help and OOM alerts"; onClicked: root.optionsOpen = !root.optionsOpen }
    ColumnLayout {
        visible: root.optionsOpen
        Layout.fillWidth: true
        spacing: 10
        RowLayout {
            visible: MemoryLockDraft.draft.enabled
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Follow saved process names"; font.weight: Font.Medium; wrapMode: Text.WordWrap }
            SettingsSwitch { objectName: "memoryAutomatic"; checked: MemoryLockDraft.draft.automatic; enabled: MemoryLockDraft.initialized; Accessible.name: "Follow saved process names"; onClicked: MemoryLockDraft.setSwitch("automatic", checked) }
        }
        RowLayout {
            visible: MemoryLockDraft.draft.enabled
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Remind me to review old locks · after " + (root.state.remind_days ?? 2) + " days"; font.weight: Font.Medium; wrapMode: Text.WordWrap }
            SettingsSwitch { objectName: "memoryReminders"; checked: MemoryLockDraft.draft.reminders; enabled: MemoryLockDraft.initialized; Accessible.name: "Remind about old locks"; onClicked: MemoryLockDraft.setSwitch("reminders", checked) }
        }
        MemoryActionButton { text: root.explanationOpen ? "Hide how locks work" : "How memory locks work"; onClicked: root.explanationOpen = !root.explanationOpen }
        StyledText {
            Layout.fillWidth: true
            visible: root.explanationOpen
            text: "A lock prevents new swap use for the entire process group, including children. Existing swap is not read back immediately, and file-backed memory can still be reclaimed. Locking too much leaves less RAM for other apps; it cannot guarantee speed or prevent apps being closed when RAM runs out.\n\nRAM is resident memory (RSS); shared pages can appear in multiple PIDs. Release restores the previous group limit without closing the app or forcing it into swap. Readings refresh every 10 seconds while this page is open."
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        MemoryActionButton { text: "Open terminal process list"; onClicked: Quickshell.execDetached(["kitty", "--hold", root.helper, "list"]) }
        OomNotifications { Layout.fillWidth: true }
    }

    component MemoryTab: TabButton {
        id: tabButton
        width: visible ? views.width / (root.reviewTabVisible ? 5 : 4) : 0
        implicitHeight: 40
        padding: 4
        background: Rectangle {
            radius: 9
            color: tabButton.checked ? Appearance.m3colors.m3primary : tabButton.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
            border.width: tabButton.activeFocus ? 2 : 1
            border.color: tabButton.checked || tabButton.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outline
        }
        contentItem: StyledText {
            text: tabButton.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 12
            font.weight: tabButton.checked ? Font.DemiBold : Font.Medium
            color: tabButton.checked ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
            elide: Text.ElideRight
        }
    }
    component MemoryCheckBox: CheckBox {
        id: check
        implicitHeight: Math.max(36, contentItem.implicitHeight + 8)
        indicator: Rectangle {
            x: 0
            y: (check.height - height) / 2
            width: 22; height: 22; radius: 5
            color: check.checked ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHigh
            border.width: check.activeFocus ? 2 : 1
            border.color: check.checked || check.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outline
            StyledText { anchors.centerIn: parent; visible: check.checked; text: "✓"; font.weight: Font.Bold; color: Appearance.m3colors.m3onPrimary }
        }
        contentItem: StyledText {
            text: check.text
            leftPadding: check.indicator.width + 10
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3onSurface
        }
    }
}
