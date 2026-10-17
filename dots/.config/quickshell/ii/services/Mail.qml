pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/qs-mail/config.json"
    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/qs-mail/state.json"
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/qs-mail"
    property var config: ({enabled:false, notifications:true, preview:true, codes:true, links:true, accounts:[]})
    property var state: ({connected:false})
    property var accounts: []
    property bool running: false
    readonly property bool enabled: config.enabled === true
    readonly property bool busy: command.running || status.running
    property string error: ""
    function refresh() { if (!status.running) status.running = true; }
    function run(args) {
        if (command.running) return;
        error = "";
        command.command = [helper, ...args];
        command.running = true;
    }
    function setFeature(key, value) { run(["set", key, value ? "true" : "false"]); }
    function setAccount(id, value) { run(["account", id, value ? "true" : "false"]); }
    function openMessage(data) { run(["message", data.session, data.ref]); }
    FileView {
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.config = JSON.parse(text()); } catch (_) { root.config = {enabled:false, accounts:[]}; } }
        onLoadFailed: root.config = {enabled:false, accounts:[]}
    }
    FileView {
        path: root.enabled ? root.statePath : ""
        watchChanges: root.enabled
        onFileChanged: reload()
        onLoaded: {
            try {
                root.state = JSON.parse(text());
                if (Array.isArray(root.state.accounts)) root.accounts = root.state.accounts;
            } catch (_) { root.state = {connected:false}; }
        }
        onLoadFailed: root.state = {connected:false}
    }
    Process {
        id: status
        command: [root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const data = JSON.parse(text); root.config = data.config; root.state = data.state; root.accounts = data.accounts; root.running = data.running; }
                catch (_) { root.error = "Install the mail integration to connect Thunderbird."; }
            }
        }
    }
    Process {
        id: command
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
        onExited: (code, exitStatus) => {
            if (code !== 0 && !root.error) root.error = "Mail action failed. Open Thunderbird to check its status.";
            root.refresh();
        }
    }
}
