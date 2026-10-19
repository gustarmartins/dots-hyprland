pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root
    property string executable: "/usr/local/libexec/cryod-desktop/cryod-control-client"
    property string socketPath: "/run/cryod/control.sock"
    property string peerUid: "0"
    property string notificationExecutable: "/usr/bin/notify-send"
    property bool viewActive: false
    property bool owner: false
    property string subscriptionId: ""
    property int suggestionCursor: 0
    property double suggestionInterval: 10000
    property double suggestionDue: 0
    property string suggestionError: ""
    property bool notificationAutomatic: false
    property bool available: false
    property var apps: []
    property var collected: []
    property var choices: []
    property string catalogRevision: ""
    property var pending: null
    property var heldOffer: null
    property var notificationOffer: null
    property string responseText: ""
    property string error: ""
    property string message: ""
    property int generation: 1
    property int notificationGeneration: 0
    property int notificationId: 0
    property int closingId: 0
    property string notificationChoice: ""
    property string notificationName: ""
    property var withdrawnOffers: []
    property int resultCode: 0
    property bool stoppingTransport: false
    property bool stoppingPrompt: false
    readonly property bool enabled: Config.ready && Config.options.cryod.enabled
    readonly property bool suggestionsWanted: owner && enabled && Config.options.cryod.freezeSuggestions === true
    readonly property bool busy: pending !== null || transport.running || prompt.running || notificationOffer !== null || stoppingTransport || stoppingPrompt
    readonly property bool prompting: prompt.running

    function start() { owner = true; syncSuggestions(); }
    function scheduleSuggestions(delay) {
        if (!suggestionsWanted) return;
        suggestionDue = Date.now() + Math.max(0, delay);
        armSuggestions();
    }
    function armSuggestions() {
        suggestionsTimer.stop();
        if (!suggestionsWanted || busy || suggestionDue <= 0) return;
        suggestionsTimer.interval = Math.max(1, Math.min(2147483647, suggestionDue - Date.now()));
        suggestionsTimer.start();
    }
    function syncSuggestions() {
        if (suggestionsWanted) {
            if (suggestionDue <= 0) scheduleSuggestions(1);
            else armSuggestions();
            return;
        }
        suggestionsTimer.stop(); subscriptionId = ""; suggestionCursor = 0; suggestionDue = 0; suggestionError = "";
        if (pending?.context?.automatic === true) {
            generation++; stoppingTransport = true; transport.running = false;
        }
        if (notificationAutomatic && notificationOffer) {
            generation++; stoppingPrompt = true; notificationChoice = "";
            withdrawnOffers = [...withdrawnOffers.slice(-15), notificationOffer.offer.operation_id];
            closeNotification(notificationId);prompt.running = false;
        }
    }
    function pollSuggestions() {
        if (!suggestionsWanted || busy) return;
        if (Date.now() < suggestionDue) { armSuggestions(); return; }
        if (!subscriptionId) submit(query("start-suggestions"), "suggest-start", {automatic:true});
        else submit(query("recommend", {subscription_id:subscriptionId, cursor:suggestionCursor}),
            "suggest-poll", {automatic:true, cursor:suggestionCursor});
    }

    function appName(appId) {
        return DesktopEntries.byId(appId)?.name || DesktopEntries.byId(appId.replace(/\.desktop$/, ""))?.name
            || appId.replace(/\.desktop$/, "");
    }
    function escaped(text) { return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function preference(app) {
        const choice = app.rule?.permissions?.freeze;
        return choice === "allow" ? "Freezing allowed" : choice === "deny" ? "Automatic freezing denied" : "Not allowed yet";
    }
    function explain(reply) {
        const reason = reply?.reason || "";
        if (reason.includes("always-awake")) return "This app is marked Always awake.";
        if (reason.includes("policy-changed") || reason.includes("revision")) return "Your preferences changed. Refresh and try again.";
        if (reason.includes("offer") || reason.includes("app-changed")) return "This request expired or the app changed. Try again.";
        return "CryoD could not confirm the choice. Refresh to check its current state.";
    }
    function submit(command, purpose, context = {}) {
        if (!enabled || pending !== null || transport.running || stoppingTransport) return false;
        pending = {command:command, purpose:purpose, context:context, generation:generation};
        responseText = "";
        transport.running = true;
        return true;
    }
    function query(command, fields = {}) { return Object.assign({version:1, scope:"application-consent", command:command}, fields); }
    function refresh(clearError = true) {
        if (!enabled || busy) return;
        collected = []; choices = []; catalogRevision = "";
        if (clearError) error = "";
        submit(query("catalog", {cursor:0}), "catalog", {cursor:0});
    }
    function ask(app, automatic = false) {
        if (!enabled || busy || (!automatic && !available) || !app || !(app.pid > 1)
                || (automatic && (!suggestionsWanted || !subscriptionId))) return;
        error = ""; message = "";
        const fields = automatic ? {pid:app.pid, automatic:true, subscription_id:subscriptionId} : {pid:app.pid};
        submit(query("propose", fields), "propose", {appId:app.app_id, pid:app.pid, birth:app.start_ticks, automatic:automatic});
    }
    function saveOffer(offer, choice) {
        if (!enabled || !offer || !["allow", "deny"].includes(choice)) return;
        submit(query("decide", {ticket:offer.ticket, choice:choice}), "decide", {operation:offer.offer.operation_id});
    }
    function closeNotification(id) {
        if (id > 0 && id <= 2147483647 && !closePrompt.running) {
            closingId = id;
            closePrompt.running = true;
        }
    }
    function finish() {
        const request = pending;
        pending = null;
        stoppingTransport = false;
        if (!request || request.generation !== generation || !enabled) return;
        let reply = null;
        try { reply = JSON.parse(responseText); } catch (_) {}
        if (resultCode !== 0 || !reply || reply.scope !== "application-consent" || reply.ok !== true) {
            if (request.context?.automatic === true) {
                suggestionError = "Suggestions are waiting for CryoD.";
                if (reply?.reason === "suggestion-session-expired") subscriptionId = "";
                suggestionCursor = 0;scheduleSuggestions(suggestionInterval);return;
            }
            if (request.purpose === "catalog") available = false;
            error = explain(reply);
            // A disconnected client does not prove that the durable save failed.
            // Read its receipt once; never repeat a decision automatically.
            if (request.purpose === "decide") submit(query("receipt", {operation_id:request.context.operation}), "receipt");
            return;
        }
        if (request.purpose === "suggest-start") {
            if (typeof reply.subscription_id !== "string" || !/^[0-9a-f-]{36}$/.test(reply.subscription_id)) {
                suggestionError = "Suggestions are unavailable.";scheduleSuggestions(suggestionInterval);return;
            }
            subscriptionId = reply.subscription_id;suggestionCursor = 0;suggestionError = "";scheduleSuggestions(1);
        } else if (request.purpose === "suggest-poll") {
            const interval = Number(reply.interval_ms);
            if (!Number.isSafeInteger(interval) || interval <= 0 || !Array.isArray(reply.apps) || reply.apps.length > 1
                    || !Number.isInteger(reply.next_cursor) || reply.next_cursor < 0 || reply.next_cursor > 64
                    || (reply.next_cursor !== 0 && reply.next_cursor <= request.context.cursor)) {
                suggestionError = "CryoD suggestion timing or app information is unavailable.";
                scheduleSuggestions(suggestionInterval);return;
            }
            suggestionInterval = interval;suggestionError = "";suggestionCursor = reply.next_cursor;
            scheduleSuggestions(suggestionCursor ? 1 : suggestionInterval);
            const candidate = reply.apps.find(app => app.recommended === true && typeof app.app_id === "string"
                && Number.isInteger(app.pid) && app.pid > 1 && typeof app.start_ticks === "string");
            if (candidate) ask(candidate, true);
        } else if (request.purpose === "catalog") {
            if (!Array.isArray(reply.apps) || reply.apps.length > 64 || !Number.isInteger(reply.next_cursor)
                    || reply.next_cursor < 0 || reply.next_cursor > 64) { available = false; error = "App information is unavailable."; return; }
            collected = [...collected, ...reply.apps];
            if (request.context.cursor === 0) {
                choices = Array.isArray(reply.choices) ? reply.choices : [];
                catalogRevision = reply.saved_revision || "";
            }
            if (!catalogRevision || reply.saved_revision !== catalogRevision) {
                available = false; error = "Your preferences changed. Refresh and try again."; return;
            }
            if (reply.next_cursor > request.context.cursor) {
                submit(query("catalog", {cursor:reply.next_cursor}), "catalog", {cursor:reply.next_cursor});
                return;
            }
            if (reply.next_cursor !== 0 || collected.length > 64) { available = false; return; }
            const merged = new Map();
            for (const rule of choices) {
                if (rule.selector?.kind === "application") merged.set(rule.selector.app_id, {app_id:rule.selector.app_id, rule:rule});
            }
            for (const app of collected) {
                if (typeof app.app_id === "string" && Number.isInteger(app.pid) && app.pid > 1 && typeof app.start_ticks === "string")
                    merged.set(app.app_id, Object.assign({}, merged.get(app.app_id) || {}, app));
            }
            apps = Array.from(merged.values()).sort((a, b) => appName(a.app_id).localeCompare(appName(b.app_id)));
            available = true;
        } else if (request.purpose === "propose") {
            const offer = reply.offer;
            if (!reply.ticket || !offer || offer.selector?.app_id !== request.context.appId
                    || offer.target?.pid !== request.context.pid || offer.target?.start_ticks !== request.context.birth) {
                error = "The app changed. Refresh and try again.";
                return;
            }
            heldOffer = reply; notificationOffer = reply;
            notificationAutomatic = request.context.automatic === true;
            notificationName = escaped(appName(offer.selector.app_id));
            notificationId = 0; notificationChoice = ""; notificationGeneration = generation;
            prompt.running = true;
        } else {
            if (reply.state === "saved" && reply.choice_current === true) {
                message = "Preference saved."; error = "";
            } else { message = ""; error = "Preferences changed. Refresh to see the current choice."; }
            refresh(false);
        }
    }
    function stop() {
        generation++;
        suggestionsTimer.stop(); subscriptionId = ""; suggestionCursor = 0; suggestionDue = 0; suggestionError = "";
        stoppingTransport = transport.running || pending !== null;
        stoppingPrompt = prompt.running || notificationOffer !== null;
        notificationChoice = "";
        if (notificationOffer) {
            withdrawnOffers = [...withdrawnOffers.slice(-15), notificationOffer.offer.operation_id];
        }
        closeNotification(notificationId);
        notificationId = 0;
        prompt.running = false; transport.running = false;
        available = false; apps = []; collected = []; choices = []; error = ""; message = "";
    }
    onEnabledChanged: { if (!enabled) stop(); else { if (viewActive) refresh(); syncSuggestions(); } }
    onSuggestionsWantedChanged: syncSuggestions()
    onBusyChanged: armSuggestions()
    onViewActiveChanged: if (viewActive && enabled) refresh()
    Connections {
        target: Notifications
        function onNotify(wrapper) {
            const notification = wrapper?.notification;
            const operation = notification?.hints["x-cryod-consent"];
            if (!operation) return;
            if (root.withdrawnOffers.includes(operation)) root.closeNotification(notification.id);
            else if (root.notificationOffer?.offer?.operation_id === operation) {
                root.notificationId = notification.id;
                if (!root.enabled) root.closeNotification(notification.id);
            }
        }
    }
    Process {
        id: transport
        command: [root.executable, "--socket", root.socketPath, "--peer-uid", root.peerUid]
        stdinEnabled: true
        onStarted: {
            if (root.pending) write(JSON.stringify(root.pending.command) + "\n");
            else running = false;
        }
        stdout: StdioCollector { onStreamFinished: root.responseText = text }
        onExited: (code, status) => { root.resultCode = code; completed.restart(); }
    }
    Timer { id: completed; interval: 0; onTriggered: root.finish() }
    Timer { id: suggestionsTimer; onTriggered: root.pollSuggestions() }
    Timer {
        interval: 6000
        running: root.pending !== null
        onTriggered: {
            if (transport.running) transport.running = false;
            else { root.resultCode = 75; completed.restart(); }
        }
    }
    Process {
        id: prompt
        command: [root.notificationExecutable, "--app-name=CryoD", "--icon=preferences-system-performance",
            "--transient", "--print-id", "--wait", "--expire-time=-1", "--action=yes=Yes", "--action=no=No",
            "--hint=string:x-cryod-consent:" + (root.notificationOffer?.offer?.operation_id || ""),
            "Pause " + root.notificationName + " when idle?",
            "Allow CryoD to monitor this app and pause it when it is safely idle? No saves a denial and stops future suggestions."]
        stdout: SplitParser {
            onRead: line => {
                const value = line.trim();
                if (/^[0-9]+$/.test(value)) {
                    const id = Number(value);
                    if (id > 0 && id <= 2147483647) {
                        root.notificationId = id;
                        if (!root.enabled || root.notificationGeneration !== root.generation) root.closeNotification(id);
                    }
                } else if (value === "yes" || value === "no") root.notificationChoice = value === "yes" ? "allow" : "deny";
            }
        }
        onExited: (code, status) => {
            const offer = root.notificationOffer;
            const choice = root.notificationChoice;
            const current = root.notificationGeneration === root.generation;
            root.stoppingPrompt = false;
            root.notificationId = 0; root.notificationChoice = ""; root.notificationOffer = null; root.heldOffer = null;
            root.notificationAutomatic = false;
            if (code === 0 && current && choice && root.enabled) root.saveOffer(offer, choice);
        }
    }
    Timer { interval: 300000; running: prompt.running; onTriggered: {
        root.notificationChoice = "";
        root.closeNotification(root.notificationId);
        prompt.running = false;
    } }
    Timer { interval: 6000; running: root.notificationOffer !== null && !prompt.running; onTriggered: {
        root.notificationOffer = null;root.heldOffer = null;root.notificationChoice = "";root.notificationAutomatic = false;
        root.stoppingPrompt = false;root.error = "Notifications are unavailable.";
    } }
    Process {
        id: closePrompt
        command: ["/usr/bin/gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.CloseNotification", String(root.closingId)]
    }
}
