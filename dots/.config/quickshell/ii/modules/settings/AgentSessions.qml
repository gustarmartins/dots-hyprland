import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    objectName: "agentSessions"
    Layout.fillWidth: true
    spacing: 12
    property string helper: Directories.home.replace(/^file:\/\//, "") + "/.local/bin/agent-monitor"
    property string snapshotPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/" + Quickshell.env("UID")) + "/agent-monitor/snapshot.json"
    property var configuration: ({enabled:false, titles:true})
    property var snapshot: ({sessions:[], shared:[], unmatched_clients:[], unattributed:[], timestamp:0})
    property string error: ""
    property string query: ""
    property string expanded: ""
    property int sortIndex: 0
    property int shown: 12
    property double now: Date.now()
    property var action: ["status", "--json"]
    readonly property bool stale: now / 1000 - snapshot.timestamp > 20
    readonly property var sessions: {
        const term = query.trim().toLowerCase();
        return (snapshot.sessions || []).filter(s => (s.name + " " + s.id + " " +
            s.clients.concat(s.workloads).map(p => p.pid + " " + p.name).join(" ")+" "+(s.process_ids || []).join(" ")).toLowerCase().includes(term))
            .slice().sort((a,b) => sortIndex === 3 ? a.name.localeCompare(b.name) :
                sortIndex === 4 ? age(b)-age(a) : metric(b)-metric(a) || a.name.localeCompare(b.name));
    }
    function metric(s) { return sortIndex === 0 ? (s.cpu_percent || 0) : sortIndex === 1 ? (s.rss || 0)+(s.client_rss || 0) : (s.swap || 0)+(s.client_swap || 0); }
    function age(s) { return Math.max(0, ...s.clients.concat(s.workloads).map(p => p.age_seconds || 0)); }
    function bytes(value) { return value === null || value === undefined ? "Unknown" : value >= 1073741824 ? (value/1073741824).toFixed(2)+" GiB" : (value/1048576).toFixed(1)+" MiB"; }
    function cpu(value) { return value === null || value === undefined ? "Sampling…" : value.toFixed(1)+"%"; }
    function duration(seconds) { return seconds >= 3600 ? (seconds/3600).toFixed(1)+" h" : Math.floor(seconds/60)+" min"; }
    function run(args) { if (control.running) return; action=args; error=""; control.running=true; }
    function applyStatus(value) {
        if (value.error) { error=value.error; return; }
        configuration=value.config || value;
        if (value.sessions) snapshot=value;
    }
    Component.onCompleted: run(["status", "--json"])
    Timer { interval:5000; repeat:true; running:root.configuration.enabled && root.visible; onTriggered: root.now=Date.now() }
    FileView {
        path:root.configuration.enabled ? root.snapshotPath : ""
        watchChanges:root.configuration.enabled
        onFileChanged:reload()
        onLoaded: {
            try {
                const value=JSON.parse(text());
                if (value.version !== 1 || !Array.isArray(value.sessions)) throw new Error("Invalid snapshot");
                root.snapshot=value;root.configuration=value.config || root.configuration;root.now=Date.now();root.error="";
            } catch (_) { root.error="Session observations are unavailable."; }
        }
    }
    Process {
        id:control
        command:[root.helper, ...root.action]
        property string output:""
        stdout:StdioCollector { onStreamFinished:control.output=text }
        onExited:(code,status) => {
            try {
                const value=JSON.parse(output);
                if (code!==0) root.error=value.error || "Could not update monitoring.";
                else root.applyStatus(value);
            } catch (_) { root.error="The session monitor is unavailable."; }
        }
    }
    RowLayout {
        Layout.fillWidth:true
        StyledText { Layout.fillWidth:true; text:"Monitor AI sessions"; font.weight:Font.Medium }
        SettingsSwitch {
            objectName:"agentMonitorMaster"
            checked:root.configuration.enabled; enabled:!control.running
            onToggled:root.run([checked ? "enable" : "disable"])
        }
    }
    StyledText {
        Layout.fillWidth:true; wrapMode:Text.WordWrap
        text:"See which session owns a terminal or child workload. Monitoring observes processes without pausing or closing them."
    }
    StyledText { Layout.fillWidth:true; wrapMode:Text.WordWrap; visible:!!root.error; text:root.error; textFormat:Text.PlainText; color:Appearance.m3colors.m3error }
    ColumnLayout {
        objectName:"agentMonitorDetails"
        visible:root.configuration.enabled
        Layout.fillWidth:true; spacing:12
        RowLayout {
            Layout.fillWidth:true
            StyledText { Layout.fillWidth:true; text:"Show agent PID in Kitty titles" }
            SettingsSwitch {
                objectName:"agentMonitorTitles"
                checked:root.configuration.titles; enabled:!control.running
                onToggled:root.run(["titles", checked ? "on" : "off"])
            }
        }
        MaterialTextField { objectName:"agentSessionSearch"; Layout.fillWidth:true; placeholderText:"Search session name, ID, PID or workload"; onTextChanged:root.query=text }
        StyledComboBox {
            objectName:"agentSessionSort"
            model:["Sort: Workload CPU", "Sort: Resident RAM", "Sort: Swap", "Sort: Name", "Sort: Process age"]
            onActivated:root.sortIndex=currentIndex
        }
        StyledText {
            Layout.fillWidth:true; wrapMode:Text.WordWrap
            text:root.stale ? "Waiting for fresh observations…" : "Updated every 5 seconds · 100% CPU equals one core. RAM is resident memory; swap is shown separately."
        }
        StyledText {
            Layout.fillWidth:true; wrapMode:Text.WordWrap
            text:"Codex session names and IDs come from local metadata. A title match identifies the displayed session; workloads use thread IDs or verified ancestry. Shared server memory stays separate."
        }
        StyledText {
            Layout.fillWidth:true; wrapMode:Text.WordWrap; textFormat:Text.PlainText
            visible:(root.snapshot.warnings || []).length>0
            text:(root.snapshot.warnings || []).join(" · ")
            color:Appearance.m3colors.m3error
        }
        Repeater {
            model:root.sessions.slice(0,root.shown)
            delegate:ColumnLayout {
                required property var modelData
                Layout.fillWidth:true; spacing:5
                RowLayout {
                    Layout.fillWidth:true
                    StyledText { Layout.fillWidth:true; text:modelData.name; textFormat:Text.PlainText; wrapMode:Text.WordWrap; font.weight:Font.Medium }
                    SettingsButton { objectName:"agentDetails:"+modelData.id; text:root.expanded===modelData.id ? "Hide" : "Details"; onClicked:root.expanded=root.expanded===modelData.id ? "" : modelData.id }
                }
                StyledText { Layout.fillWidth:true; text:modelData.id; textFormat:Text.PlainText; wrapMode:Text.WrapAnywhere; color:Appearance.m3colors.m3onSurfaceVariant }
                StyledText {
                    Layout.fillWidth:true; wrapMode:Text.WordWrap; textFormat:Text.PlainText
                    text:modelData.clients.length ? modelData.clients.map(p => "PID "+p.pid+" · "+p.routes.join(", ")+" · "+p.evidence).join("\n") : "No terminal client matched · writer PID "+modelData.writer_pids.join(", ")
                }
                StyledText {
                    Layout.fillWidth:true; wrapMode:Text.WordWrap
                    text:"Workloads: "+modelData.workload_count+" · CPU "+root.cpu(modelData.cpu_percent)+" · RAM "+root.bytes(modelData.rss)+" · Swap "+root.bytes(modelData.swap)
                        +"\nTerminal clients: RAM "+root.bytes(modelData.client_rss)+" · Swap "+root.bytes(modelData.client_swap)
                }
                ColumnLayout {
                    visible:root.expanded===modelData.id
                    Layout.fillWidth:true
                    StyledText { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:"Oldest process: "+root.duration(root.age(modelData))+" · Observed workload peak: "+root.cpu(modelData.peak_cpu_percent)+" CPU, "+root.bytes(modelData.peak_rss)+" RAM" }
                    Repeater {
                        model:modelData.clients.concat(modelData.workloads)
                        delegate:StyledText {
                            required property var modelData
                            Layout.fillWidth:true; wrapMode:Text.WordWrap; textFormat:Text.PlainText
                            text:modelData.name+" · PID "+modelData.pid+" · CPU "+root.cpu(modelData.cpu_percent)+" · RAM "+root.bytes(modelData.rss)+" · Swap "+root.bytes(modelData.swap)
                                +" · Virtual "+root.bytes(modelData.virtual)+" · Age "+root.duration(modelData.age_seconds)
                                + (modelData.attribution ? " · "+modelData.attribution : "")
                        }
                    }
                }
                Rectangle { Layout.fillWidth:true; implicitHeight:1; color:Appearance.m3colors.m3outlineVariant }
            }
        }
        StyledText { visible:root.sessions.length===0; text:root.query ? "No matching sessions." : "No Codex sessions observed yet." }
        SettingsButton { visible:root.sessions.length>root.shown; text:"Show more"; onClicked:root.shown+=12 }
        StyledText { text:"Shared Codex servers"; font.weight:Font.Medium; visible:(root.snapshot.shared || []).length>0 }
        Repeater {
            model:root.snapshot.shared || []
            delegate:StyledText {
                required property var modelData
                Layout.fillWidth:true; wrapMode:Text.WordWrap
                text:"PID "+modelData.pid+" · "+modelData.session_ids.length+" session locks · CPU "+root.cpu(modelData.cpu_percent)
                    +" · RAM "+root.bytes(modelData.rss)+" · Swap "+root.bytes(modelData.swap)+" · Virtual "+root.bytes(modelData.virtual)+" · Age "+root.duration(modelData.age_seconds)
            }
        }
        StyledText { text:"Other agent clients"; font.weight:Font.Medium; visible:(root.snapshot.unmatched_clients || []).length>0 }
        Repeater {
            model:root.snapshot.unmatched_clients || []
            delegate:StyledText {
                required property var modelData
                Layout.fillWidth:true; wrapMode:Text.WordWrap; textFormat:Text.PlainText
                text:modelData.agent+" · PID "+modelData.pid+" · "+modelData.routes.join(", ")+" · RAM "+root.bytes(modelData.rss)+" · Swap "+root.bytes(modelData.swap)
                    +(modelData.conversation_id ? "\nLaunch conversation "+modelData.conversation_id : modelData.resume_hint ? "\nLaunched with "+modelData.resume_name+" · "+modelData.resume_hint+" (current session unconfirmed)" : " · Session ID unresolved")
            }
        }
        StyledText { text:"Heavy processes without session attribution"; font.weight:Font.Medium; visible:(root.snapshot.unattributed || []).length>0 }
        Repeater {
            model:root.snapshot.unattributed || []
            delegate:StyledText {
                required property var modelData
                Layout.fillWidth:true; wrapMode:Text.WordWrap; textFormat:Text.PlainText
                text:modelData.name+" · PID "+modelData.pid+" · CPU "+root.cpu(modelData.cpu_percent)+" · RAM "+root.bytes(modelData.rss)+" · Swap "+root.bytes(modelData.swap)
            }
        }
        StyledText {
            Layout.fillWidth:true; wrapMode:Text.WordWrap
            text:"Virtual size is address space, not RAM in use. Summed RSS can include shared pages more than once. Detached or old processes are not automatically abandoned. Peaks cover the current monitoring run; short jobs between samples may be missed."
        }
    }
}
