import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    objectName: "memoryLocks"
    spacing: 14
    property var state: ({enabled:false, automatic:false, reminders:false, locks:[], rules:[], processes:[], memory:{}})
    property bool ready: false
    property string error: ""
    property string readError: ""
    property string notice: ""
    property int tab: 0
    property int sortIndex: 0
    property string query: ""
    property int shown: 25
    property bool preferencesOpen: false
    property bool explanationOpen: false
    property var pending: ({})
    property string pendingKind: ""
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/noswap"
    readonly property color warningColor: Appearance.m3colors.darkmode ? "#edc274" : "#805000"
    readonly property bool busy: action.running || inspect.running || read.running
    readonly property var protectedProcesses: state.processes.filter(p => p.protected === true)
    readonly property var rows: visibleRows()
    function bytes(n) { return n === null || n === undefined ? "Unknown" : n >= 1073741824 ? (n / 1073741824).toFixed(2) + " GiB" : (n / 1048576).toFixed(1) + " MiB"; }
    function visibleRows() {
        let items = state.processes.slice();
        if (tab === 0) items = items.filter(p => p.protected === true);
        if (tab === 1) items = items.filter(p => p.can_lock && p.rss > 0);
        if (tab === 2 && query.trim()) {
            const term = query.trim().toLowerCase();
            items = items.filter(p => String(p.pid).includes(term) || p.name.toLowerCase().includes(term));
        }
        items.sort((a, b) => sortIndex === 2 ? a.name.localeCompare(b.name) || a.pid - b.pid : sortIndex === 3 ? a.pid - b.pid : (b[sortIndex === 1 ? "swap" : "rss"] ?? -1) - (a[sortIndex === 1 ? "swap" : "rss"] ?? -1) || a.pid - b.pid);
        if (tab === 1) {
            const groups = new Set();
            items = items.filter(p => { if (groups.has(p.group)) return false; groups.add(p.group); return true; }).slice(0, 6);
        }
        return items;
    }
    function refresh() { if (!read.running && !busy && !confirm.visible) read.running = true; }
    function run(args) {
        if (busy) return;
        error = ""; notice = "";
        action.command = [helper].concat(args); action.running = true;
    }
    function requestLock(p) {
        if (busy) return;
        error = "";
        inspect.command = [helper, "inspect", String(p.pid), "--expect-start", String(p.start), "--expect-boot", state.boot, "--json"];
        inspect.running = true;
    }
    function requestRelease(p) {
        const group = state.locks.find(r => r.id === p.lock_id);
        if (!group) return;
        pending = group; pendingKind = "release"; confirm.open();
    }
    function acceptAction() {
        const kind = pendingKind, data = pending;
        confirm.close();
        if (kind === "lock") run(["lock", String(data.process.pid), "--expect-identity", JSON.stringify(data.identity), "--force"]);
        else if (kind === "release") run(["unlock", data.id].concat(data.status === "locked" ? [] : ["--force"]));
        else if (kind === "off") run(["off", "--force"]);
    }
    onTabChanged: shown = 25
    onQueryChanged: shown = 25
    onSortIndexChanged: shown = 25
    Component.onCompleted: refresh()
    Process {
        id: read
        command: [root.helper, "dashboard", "--json"]
        stdout: StdioCollector { id: result }
        stderr: StdioCollector { id: readErrors }
        onExited: (code, status) => {
            try {
                if (code !== 0) throw new Error(readErrors.text.trim() || "Could not read process memory.");
                const data = JSON.parse(result.text);
                if (data.schema !== 2 || !Array.isArray(data.processes)) throw new Error("Update noswap from Linux Memory Toolkit to use the process browser.");
                root.state = data; root.ready = true; root.readError = "";
            } catch (e) { root.ready = false; root.readError = "Memory data unavailable. " + e.message; }
        }
    }
    Process {
        id: inspect
        stdout: StdioCollector { id: preview }
        stderr: StdioCollector { id: previewErrors }
        onExited: (code, status) => {
            if (code !== 0) { root.error = previewErrors.text.trim() || "Process preview failed. Refresh and try again."; return; }
            try { root.pending = JSON.parse(preview.text); root.pendingKind = "lock"; confirm.open(); }
            catch (e) { root.error = "Could not read the process preview."; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => {
            if (code !== 0) root.error = errors.text.trim() || "The change failed. Refresh and try again.";
            else root.notice = "Memory settings updated.";
            Qt.callLater(root.refresh);
        }
    }
    Timer { interval: 10000; repeat: true; running: root.visible && root.state.enabled; onTriggered: root.refresh() }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: intro.implicitHeight + 28
        radius: 18
        color: Appearance.m3colors.m3surfaceContainer
        ColumnLayout {
            id: intro
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol { text: "memory"; iconSize: 26; color: Appearance.m3colors.m3primary }
                StyledText { Layout.fillWidth: true; text: "Keep your work responsive"; wrapMode: Text.WordWrap; font.pixelSize: 19; font.weight: Font.Medium }
                Switch {
                    objectName: "memoryMaster"
                    checked: root.state.enabled
                    enabled: root.ready && !root.busy
                    Accessible.name: "Enable memory locks"
                    onClicked: {
                        if (root.state.enabled) { root.pendingKind = "off"; confirm.open(); }
                        else root.run(["on"]);
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: "When background work fills RAM, your computer may move app memory into swap. Lock the apps you need to keep responsive to reduce delays when you return to them."
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                text: root.state.enabled ? "On · Choose what deserves to stay in RAM. Locking too much can leave less room for other apps." : "Off · Enable to browse processes and manage locks. Saved names and reminder preferences are kept."
                color: root.state.enabled ? Appearance.m3colors.m3success : Appearance.m3colors.m3onSurfaceVariant
                wrapMode: Text.WordWrap
                font.pixelSize: 12
            }
            ToolButton { text: root.explanationOpen ? "▾  How memory locks work" : "▸  How memory locks work"; onClicked: root.explanationOpen = !root.explanationOpen }
            StyledText {
                Layout.fillWidth: true
                visible: root.explanationOpen
                text: "A lock prevents new swap use for the app’s whole process group, including its children. File-backed memory can still be reclaimed, and existing swap is not read back immediately. This reduces one source of delays; it cannot guarantee speed or prevent apps from being closed when RAM runs out.\n\nRSS is memory currently resident in RAM. Shared pages may appear in several PIDs, so adding RSS values can overcount. Group memory also includes cache and kernel allocations. Release restores the group’s previous swap limit; it does not close the app or force it into swap."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Appearance.m3colors.m3onSurfaceVariant
            }
        }
    }
    StyledText { Layout.fillWidth: true; visible: !!root.error; text: root.error; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
    StyledText { Layout.fillWidth: true; visible: !!root.readError; text: root.readError; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
    StyledText { Layout.fillWidth: true; visible: !root.ready && !root.readError; text: "Reading process memory…"; color: Appearance.m3colors.m3onSurfaceVariant }
    StyledText { Layout.fillWidth: true; visible: !!root.notice && !root.error; text: root.notice; color: Appearance.m3colors.m3success }
    SettingsButton { visible: !root.ready; text: "Retry"; enabled: !read.running; onClicked: root.refresh() }

    ColumnLayout {
        visible: root.state.enabled && root.ready
        Layout.fillWidth: true
        spacing: 12
        Flow {
            Layout.fillWidth: true
            spacing: 22
            StyledText { text: root.protectedProcesses.length + " protected PIDs"; font.weight: Font.DemiBold; color: Appearance.m3colors.m3success }
            StyledText { text: "Available RAM  " + root.bytes(root.state.memory.available); font.weight: Font.DemiBold; color: root.state.memory.low ? root.warningColor : Appearance.m3colors.m3primary }
            StyledText { text: root.protectedProcesses.filter(p => p.large_rss).length + " with large RSS"; color: root.warningColor }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.state.memory.low || root.state.memory.swap_total === 0
            text: root.state.memory.low ? "RAM is running low. Review large locks before adding more." : "Swap is currently off. Locks affect future swap use if swap is enabled."
            wrapMode: Text.WordWrap
            color: root.warningColor
        }
        RowLayout {
            Layout.fillWidth: true
            ToolButton { text: root.preferencesOpen ? "▾  Automation and reminders" : "▸  Automation and reminders"; onClicked: root.preferencesOpen = !root.preferencesOpen }
            Item { Layout.fillWidth: true }
            SettingsButton { objectName: "memoryRefresh"; text: read.running ? "Refreshing…" : "Refresh"; enabled: !read.running && !root.busy; onClicked: root.refresh() }
        }
        ColumnLayout {
            visible: root.preferencesOpen
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { text: "Follow saved process names"; font.weight: Font.Medium }
                    StyledText { Layout.fillWidth: true; text: root.state.rules.length ? "Automatically protect new matches: " + root.state.rules.map(r => r.name).join(", ") : "No saved names. Add rules with noswap watch in a terminal."; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
                }
                Switch { objectName: "memoryAutomatic"; checked: root.state.automatic; enabled: !root.busy; Accessible.name: "Follow saved process names"; onClicked: root.run([root.state.automatic ? "off" : "on", "automatic"]) }
            }
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { text: "Remind me to review old locks"; font.weight: Font.Medium }
                    StyledText { Layout.fillWidth: true; text: "After " + (root.state.remind_days ?? 2) + " days, at most once a day. Releasing a group pauses automatic re-locking for that group."; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
                }
                Switch { objectName: "memoryReminders"; checked: root.state.reminders; enabled: !root.busy; Accessible.name: "Remind about old locks"; onClicked: root.run(["reminders", root.state.reminders ? "off" : "on"]) }
            }
        }
        TabBar {
            Layout.fillWidth: true
            currentIndex: root.tab
            onCurrentIndexChanged: root.tab = currentIndex
            MemoryTab { objectName: "memoryTabLocked"; text: "Locked" }
            MemoryTab { objectName: "memoryTabSuggested"; text: "Suggested" }
            MemoryTab { objectName: "memoryTabSearch"; text: "Search PID" }
        }
        SettingsField {
            objectName: "memorySearch"
            Layout.fillWidth: true
            visible: root.tab === 2
            placeholderText: "Search by PID or process name…"
            Accessible.name: "Search processes by PID or name"
            selectByMouse: true
            onTextChanged: root.query = text
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: root.tab === 0 ? "Protected processes" : root.tab === 1 ? "Up to 6 groups to consider" : root.rows.length + " matching processes"
                wrapMode: Text.WordWrap
                font.weight: Font.Medium
            }
            ComboBox {
                objectName: "memorySort"
                model: ["RSS · largest first", "Swap · largest first", "Name · A–Z", "PID · ascending"]
                currentIndex: root.sortIndex
                onActivated: root.sortIndex = currentIndex
                Accessible.name: "Sort processes"
                implicitWidth: 185
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.tab === 1 ? "Unlocked processes in your chosen order, one per group. Consider apps you return to often; high memory use alone does not mean an app needs a lock."
                : "RSS shows RAM in use now. Amber marks ≥ " + root.bytes(root.state.memory.large_rss) + " (1 GiB or 5% of RAM, whichever is larger)."
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        Repeater {
            model: root.rows.slice(0, root.shown)
            delegate: MemoryProcessRow {
                required property var modelData
                processData: modelData
                totalRam: root.state.memory.total || 0
                busy: root.busy
                onLockRequested: p => root.requestLock(p)
                onReleaseRequested: p => root.requestRelease(p)
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.rows.length === 0
            text: root.tab === 0 ? "No protected processes. Use Suggested or Search PID to choose an app."
                : root.tab === 1 ? "No eligible unlocked groups right now. Search PID shows all your processes and their status."
                : "No processes match. Try another PID or name, or refresh if an app just started."
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        SettingsButton { visible: root.rows.length > root.shown; text: "Show next 25 · " + (root.rows.length - root.shown) + " remaining"; onClicked: root.shown += 25 }
        StyledText { Layout.fillWidth: true; text: "Updated every 10 seconds while open. Only your processes are shown."; wrapMode: Text.WordWrap; font.pixelSize: 11; color: Appearance.m3colors.m3onSurfaceVariant }
        SettingsButton { text: "Open terminal process list"; onClicked: Quickshell.execDetached(["kitty", "--hold", root.helper, "list"]) }
    }
    // Failed restores remain actionable even if master off already stopped the timer.
    Repeater {
        model: root.ready ? root.state.locks.filter(r => r.status !== "locked" || !root.state.enabled || r.members.length === 0) : []
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: modelData.unit + " · " + modelData.status; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.warningColor }
            SettingsButton { text: "Restore limit…"; enabled: !root.busy; onClicked: { root.pending = modelData; root.pendingKind = "release"; confirm.open(); } }
        }
    }
    OomNotifications { Layout.fillWidth: true }

    component MemoryTab: TabButton {
        id: tabButton
        implicitHeight: 42
        background: Rectangle {
            radius: 10
            color: tabButton.checked ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerLow
            border.width: tabButton.checked || tabButton.activeFocus ? 1 : 0
            border.color: Appearance.m3colors.m3primary
        }
        contentItem: StyledText {
            text: tabButton.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.weight: tabButton.checked ? Font.DemiBold : Font.Normal
            color: tabButton.checked ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
        }
    }

    Dialog {
        id: confirm
        objectName: "memoryConfirm"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(600, parent.width - 32)
        height: Math.min(implicitHeight, parent.height - 40)
        padding: 20
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        onOpened: { acknowledge.checked = false; cancel.forceActiveFocus(); }
        readonly property bool risky: root.pendingKind === "lock" && !!root.pending.risky
        title: root.pendingKind === "lock" ? (risky ? "Review before locking" : "Lock this process group?") : root.pendingKind === "off" ? "Turn off memory locks?" : "Release this process group?"
        background: Rectangle { radius: 20; color: Appearance.m3colors.m3surfaceContainerHigh; border.color: Appearance.m3colors.m3outlineVariant; border.width: 1 }
        header: StyledText { text: confirm.title; padding: 20; font.pixelSize: 20; font.weight: Font.Medium; color: confirm.risky ? root.warningColor : Appearance.m3colors.m3onSurface }
        contentItem: ScrollView {
            id: dialogScroll
            clip: true
            contentWidth: availableWidth
            implicitHeight: dialogBody.implicitHeight
            ColumnLayout {
                id: dialogBody
                width: dialogScroll.availableWidth
                spacing: 12
                StyledText {
                    Layout.fillWidth: true
                    text: root.pendingKind === "lock" ? root.pending.process?.name + "   ·   PID " + root.pending.process?.pid + "\nRSS " + root.bytes(root.pending.process?.rss) + "   ·   Available RAM " + root.bytes(root.pending.memory?.available)
                        : root.pendingKind === "off" ? "Release recorded locks and stop automatic matching and reminders. Your saved names and preferences are kept for next time."
                        : "Restore the previous swap limit for this entire group. Its apps keep running. Automatic matching will leave this group released."
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    font.weight: Font.Medium
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.pendingKind !== "off"
                    text: (root.pending.unit || "") + (root.pendingKind === "lock" ? "\nGroup memory  " + root.bytes(root.pending.group_memory) + "   ·   Group swap  " + root.bytes(root.pending.group_swap) : "")
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.pendingKind === "lock"
                    text: "Locking prevents new swap use for this group. If RAM runs out, the system may close applications. File-backed pages can still be reclaimed."
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.pendingKind === "lock" ? (root.pending.warnings || []) : []
                    delegate: StyledText { required property string modelData; Layout.fillWidth: true; text: "• " + modelData; wrapMode: Text.WordWrap; color: root.warningColor }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.pendingKind === "off" || (root.pendingKind === "release" && root.pending.status !== "locked")
                    text: "This restores saved limits, including any changed by another tool since the lock was created."
                    wrapMode: Text.WordWrap
                    color: root.warningColor
                }
                StyledText { visible: root.pendingKind !== "off"; text: "Affected processes (" + (root.pending.members?.length || 0) + ")"; font.weight: Font.Medium }
                Repeater {
                    model: root.pendingKind === "off" ? [] : (root.pending.members || [])
                    delegate: StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        text: "PID  " + modelData.pid + "    ·    " + modelData.name + "    ·    RSS  " + root.bytes(modelData.rss)
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.pixelSize: 12
                    }
                }
            }
        }
        footer: ColumnLayout {
            spacing: 12
            CheckBox {
                id: acknowledge
                objectName: "memoryRiskAccepted"
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                visible: confirm.risky
                text: "I understand the risk and want to lock this group."
                contentItem: StyledText { text: acknowledge.text; leftPadding: acknowledge.indicator.width + acknowledge.spacing; wrapMode: Text.WordWrap; color: root.warningColor }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                spacing: 12
                Item { Layout.fillWidth: true }
                SettingsButton { id: cancel; objectName: "memoryCancel"; text: "Cancel"; onClicked: confirm.reject() }
                SettingsButton {
                    objectName: "memoryApply"
                    text: root.pendingKind === "lock" ? (confirm.risky ? "Lock anyway" : "Lock group") : root.pendingKind === "off" ? "Turn off and release" : "Release group"
                    enabled: !root.busy && (!confirm.risky || acknowledge.checked)
                    onClicked: root.acceptAction()
                }
            }
        }
    }
}
