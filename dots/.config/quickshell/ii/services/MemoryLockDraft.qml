pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings-window lifetime, so navigating away cannot destroy a pending apply.
Singleton {
    id: root
    property var snapshot: ({enabled:false, automatic:false, reminders:false, locks:[], rules:[], processes:[], memory:{}})
    property var baseline: ({enabled:false, automatic:false, reminders:false, rules:[]})
    property var draft: ({enabled:false, automatic:false, reminders:false, rules:[]})
    property string revision: ""
    property bool initialized: false
    property bool ready: false
    property string error: ""
    property string readError: ""
    property string notice: ""
    property var operations: []
    property var results: []
    property bool acknowledged: false
    property int editVersion: 0
    property int serial: 0
    property int observers: 0
    property int applyEpoch: 0
    property int readEpoch: 0
    property string nameText: ""
    property bool nameShared: false
    property var inspectQueue: []
    property var inspecting: ({})
    property var submitted: ({})
    property int submittedVersion: 0
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/noswap"
    readonly property bool reading: read.running
    readonly property bool applying: applyProcess.running
    readonly property bool dirty: initialized && (JSON.stringify(draft) !== JSON.stringify(baseline) || operations.length > 0)
    readonly property bool checking: operations.some(o => o.kind === "preview")
    readonly property bool needsReview: operations.some(o => o.risky) || (!draft.enabled && snapshot.locks.some(r => r.status.startsWith("changed")))
    readonly property bool canApply: ready && dirty && !applying && !checking && (!needsReview || acknowledged)
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    function config(data) {
        const value = data.settings || {enabled:data.enabled, automatic:data.automatic, reminders:data.reminders,
            rules:data.rules.map(r => ({name:r.name, shared:!!r.force}))};
        return {enabled:value.enabled, automatic:value.automatic, reminders:value.reminders,
            rules:value.rules.map(r => ({name:r.name, shared:r.shared})).sort((a,b) => a.name.localeCompare(b.name))};
    }
    function attach() { observers++; refresh(); }
    function detach() { observers = Math.max(0, observers - 1); }
    function refresh() { if (!read.running && !applying) { readEpoch = applyEpoch; read.running = true; } }
    function changed() { editVersion++; acknowledged = false; error = ""; notice = "Choices are staged. Apply all when ready."; }
    function setSwitch(key, value) {
        const next = clone(draft); next[key] = value; draft = next;
        if (key === "enabled" && !value) operations = operations.filter(o => o.kind === "release" || o.kind === "timer");
        changed();
    }
    function addNames(value, shared) {
        const names = [...new Set(value.split(",").map(s => s.trim()).filter(Boolean))];
        if (!names.length || names.some(n => !/^[A-Za-z_][A-Za-z0-9_.+-]{0,127}$/.test(n))) {
            error = "Enter exact process names separated by commas; no PIDs, paths or wildcards."; return false;
        }
        const next = clone(draft);
        next.rules = next.rules.filter(r => !names.includes(r.name)).concat(names.map(n => ({name:n, shared:shared}))).sort((a,b) => a.name.localeCompare(b.name));
        draft = next; nameText = ""; changed(); return true;
    }
    function removeName(name) { const next = clone(draft); next.rules = next.rules.filter(r => r.name !== name); draft = next; changed(); }
    function setShared(name, value) { const next = clone(draft); next.rules = next.rules.map(r => r.name === name ? {name:r.name, shared:value} : r); draft = next; changed(); }
    function nameStatus(name) {
        const live = (snapshot.saved_names || []).find(r => r.name === name);
        return live ? live.message : "Staged for future launches";
    }
    function operationFor(p) { return operations.find(o => o.group === p.group || (p.lock_id && o.lock_id === p.lock_id)); }
    function inFlight(p) { return applying && (submitted.operations || []).some(o => o.group === p.group || (p.lock_id && o.lock_id === p.lock_id)); }
    function removeOperation(id) {
        if (applying && (submitted.operations || []).some(o => o.id === id)) return;
        operations = operations.filter(o => o.id !== id); changed();
    }
    function selectLock(p) {
        if (!ready || inFlight(p)) return;
        const existing = operationFor(p);
        if (existing) { removeOperation(existing.id); return; }
        const id = "selection-" + (++serial);
        operations = operations.concat([{id:id, kind:"preview", group:p.group, label:"Check " + p.name + " · PID " + p.pid}]);
        inspectQueue = inspectQueue.concat([{id:id, pid:p.pid, start:p.start, boot:snapshot.boot, group:p.group, name:p.name}]);
        changed(); nextPreview();
    }
    function nextPreview() {
        if (inspect.running) return;
        while (inspectQueue.length) {
            const item = inspectQueue[0]; inspectQueue = inspectQueue.slice(1);
            if (!operations.some(o => o.id === item.id)) continue;
            inspecting = item;
            inspect.command = [helper,"inspect",String(item.pid),"--expect-start",String(item.start),"--expect-boot",item.boot,"--json"];
            inspect.running = true; return;
        }
    }
    function selectRelease(p) {
        if (!ready || inFlight(p)) return;
        const existing = operationFor(p);
        if (existing) { removeOperation(existing.id); return; }
        const record = snapshot.locks.find(r => r.id === p.lock_id);
        if (!record) return;
        operations = operations.concat([{id:"selection-" + (++serial), kind:"release", lock_id:record.id, group:p.group,
            label:"Release " + record.unit, risky:record.status.startsWith("changed"),
            warnings:record.status.startsWith("changed") ? ["This group changed outside Memory locks. Applying restores its recorded previous limit."] : [],
            members:record.members}]);
        changed();
    }
    function discard() {
        if (applying) return;
        baseline = config(snapshot); revision = snapshot.config_revision || ""; draft = clone(baseline);
        operations = []; inspectQueue = []; results = []; nameText = ""; acknowledged = false; editVersion++;
        error = ""; notice = "Unapplied choices discarded.";
    }
    function applyAll() {
        if (!canApply) return;
        submitted = {schema:1, expected_revision:revision, settings:clone(draft), operations:clone(operations), acknowledge:acknowledged};
        submittedVersion = editVersion; error = ""; notice = "Applying selected changes… You can keep editing the next draft.";
        applyEpoch++;
        applyProcess.command = [helper,"batch","--payload",JSON.stringify(submitted)]; applyProcess.running = true;
    }
    function finishApply(result) {
        results = result.items || [];
        if (result.conflict) { error = result.message; return; }
        const complete = new Set(results.filter(r => r.ok).map(r => r.id));
        operations = operations.filter(o => !complete.has(o.id));
        for (const item of results) {
            if (!item.ok && item.retry && !operations.some(o => o.id === item.retry.id)) operations = operations.concat([item.retry]);
        }
        if (result.settings) {
            baseline = config({settings:result.settings}); revision = result.config_revision;
            if (result.ok && editVersion === submittedVersion) draft = clone(baseline);
        }
        const failed = results.filter(r => !r.ok);
        error = result.ok ? "" : result.message || failed.map(r => r.label + ": " + r.message).join("\n") || "The helper did not finish. Your draft is retained; refresh before retrying.";
        notice = result.ok ? (dirty ? "Applied. New edits remain staged for the next Apply all." : "All selected changes applied.") : "Successful changes are recorded. Unfinished changes remain in your draft.";
    }
    Process {
        id: read
        command: [root.helper,"dashboard","--json"]
        stdout: StdioCollector { id: readOut }
        stderr: StdioCollector { id: readErr }
        onExited: (code, status) => {
            if (root.readEpoch !== root.applyEpoch) { Qt.callLater(root.refresh); return; }
            try {
                if (code !== 0) throw new Error(readErr.text.trim() || "Could not read process memory.");
                const value = JSON.parse(readOut.text);
                if (value.schema !== 2 || !value.config_revision || !Array.isArray(value.processes)) throw new Error("Update noswap to the batch-capable version.");
                const replaceDraft = !root.initialized || (!root.dirty && !root.applying);
                root.snapshot = value;
                if (replaceDraft) { root.baseline = root.config(value); root.draft = root.clone(root.baseline); root.revision = value.config_revision; }
                root.initialized = true; root.ready = true; root.readError = "";
            } catch (e) { root.ready = false; root.readError = e.message; }
        }
    }
    Process {
        id: inspect
        stdout: StdioCollector { id: inspectOut }
        stderr: StdioCollector { id: inspectErr }
        onExited: (code, status) => {
            const item = root.inspecting;
            if (root.operations.some(o => o.id === item.id)) {
                try {
                    if (code !== 0) throw new Error(inspectErr.text.trim() || "Could not preview " + item.name);
                    const value = JSON.parse(inspectOut.text);
                    const op = {id:item.id, kind:"lock", group:item.group, identity:value.identity,
                        label:"Lock " + item.name + " · " + value.unit, risky:value.risky, warnings:value.warnings || [], members:value.members};
                    root.operations = root.operations.map(o => o.id === item.id ? op : o);
                    root.acknowledged = false;
                } catch (e) { root.operations = root.operations.filter(o => o.id !== item.id); root.error = e.message; }
            }
            Qt.callLater(root.nextPreview);
        }
    }
    Process {
        id: applyProcess
        stdout: StdioCollector { id: applyOut }
        stderr: StdioCollector { id: applyErr }
        onExited: (code, status) => {
            try { root.finishApply(JSON.parse(applyOut.text)); }
            catch (e) { root.error = applyErr.text.trim() || "Apply was interrupted. Your draft is retained; refresh to review the current state."; }
            Qt.callLater(root.refresh);
        }
    }
    Timer { interval: 10000; repeat: true; running: root.observers > 0 && !root.applying; onTriggered: root.refresh() }
}
