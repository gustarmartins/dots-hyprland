pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: !!(sink?.ready && sink?.audio)
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio?.volume ?? 0
    
    function friendlyDeviceName(node) {
        const raw = String(node?.nickname || node?.description || node?.name || "");
        const lower = raw.toLowerCase();
        if (lower.includes("jieli") || lower.includes("usb composite device")) {
            return node?.isSink === false ? Translation.tr("QCY H3 Mic (USB)") : Translation.tr("QCY H3 (USB DAC)");
        }
        return (node?.nickname || node?.description || Translation.tr("Unknown"));
    }
    function deviceIcon(node, isSink) {
        if (!isSink) return "mic";
        const text = `${node?.name ?? ""} ${node?.nickname ?? ""} ${node?.description ?? ""}`.toLowerCase();
        if (text.includes("qcy") || text.includes("jieli") || text.includes("headphone") || text.includes("headset") || text.includes("bluez") || text.includes("usb"))
            return "headphones";
        if (text.includes("hdmi") || text.includes("displayport") || text.includes("dp-"))
            return "monitor";
        return "speaker";
    }
    function appNodeDisplayName(node) {
        return (node?.properties?.["application.name"] || node?.description || node?.name || Translation.tr("Unknown"))
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);
    signal deviceEvent(string title, string subtitle, string iconName);

    // Physical audio hotplug & active output tracking
    property string lastDeviceTitle: ""
    property string lastDeviceSubtitle: ""
    property string lastDeviceIcon: "headphones"
    property bool deviceMonitorReady: false
    property var knownDeviceMap: ({})
    property string lastDefaultSinkKey: ""
    property double recentHotplugAt: 0

    function isPhysicalAudioNode(node) {
        if (!node || node.isStream || !node.audio) return false;
        const name = String(node.name ?? "");
        if (!name || name.startsWith("easyeffects_") || name.startsWith("ee_")) return false;
        if (name === "Dummy-Driver" || name === "Freewheel-Driver") return false;
        return name.startsWith("alsa_output.") || name.startsWith("alsa_input.") || name.startsWith("bluez_");
    }

    function stableDeviceKey(node) {
        const name = String(node?.name ?? "");
        const base = name.replace(/\.(analog-stereo|pro-output-\d+|pro-input-\d+|iec958-stereo|mono-fallback)$/, "");
        return `${base}:${node?.isSink ? "out" : "in"}`;
    }

    function emitDeviceAlert(title, subtitle, iconName, soundName) {
        root.lastDeviceTitle = title;
        root.lastDeviceSubtitle = subtitle;
        root.lastDeviceIcon = iconName;
        root.deviceEvent(title, subtitle, iconName);
        if (soundName) root.playSystemSound(soundName);
        const desktopIcon = iconName === "mic" ? "audio-input-microphone"
            : (iconName === "headphones" ? "audio-headphones" : "audio-speakers");
        Quickshell.execDetached([
            "notify-send",
            "--app-name=Audio",
            `--icon=${desktopIcon}`,
            title,
            subtitle
        ]);
    }

    function snapshotPhysicalDevices() {
        const map = {};
        const nodes = [...root.outputDevices, ...root.inputDevices];
        for (const node of nodes) {
            if (!isPhysicalAudioNode(node)) continue;
            const key = stableDeviceKey(node);
            map[key] = {
                key: key,
                name: String(node.name ?? ""),
                label: friendlyDeviceName(node),
                isSink: !!node.isSink,
                icon: deviceIcon(node, !!node.isSink),
                cardKey: String(node.name ?? "").replace(/^alsa_(output|input)\./, "card.").replace(/\.[^.]+$/, ""),
            };
        }
        return map;
    }

    function reconcileAudioDevices() {
        const current = snapshotPhysicalDevices();
        if (!root.deviceMonitorReady) {
            root.knownDeviceMap = current;
            root.lastDefaultSinkKey = root.sink && isPhysicalAudioNode(root.sink) ? stableDeviceKey(root.sink) : "";
            root.deviceMonitorReady = true;
            return;
        }

        const prev = root.knownDeviceMap;
        const added = Object.values(current).filter(item => !prev[item.key]);
        const removed = Object.values(prev).filter(item => !current[item.key]);
        root.knownDeviceMap = current;

        const addedSinks = added.filter(i => i.isSink);
        const addedCards = new Set(addedSinks.map(i => i.cardKey));
        const addedStandaloneInputs = added.filter(i => !i.isSink && !addedCards.has(i.cardKey));

        for (const item of addedSinks) {
            root.recentHotplugAt = Date.now();
            const isDefault = root.sink && stableDeviceKey(root.sink) === item.key;
            emitDeviceAlert(
                Translation.tr("%1 connected").arg(item.label),
                isDefault ? Translation.tr("Active audio output") : Translation.tr("Audio output ready"),
                item.icon,
                "device-added"
            );
        }
        for (const item of addedStandaloneInputs) {
            root.recentHotplugAt = Date.now();
            emitDeviceAlert(
                Translation.tr("%1 connected").arg(item.label),
                Translation.tr("Audio input ready"),
                item.icon,
                "device-added"
            );
        }

        const removedSinks = removed.filter(i => i.isSink);
        const removedCards = new Set(removedSinks.map(i => i.cardKey));
        const removedStandaloneInputs = removed.filter(i => !i.isSink && !removedCards.has(i.cardKey));

        for (const item of removedSinks) {
            root.recentHotplugAt = Date.now();
            const activeLabel = root.sink ? friendlyDeviceName(root.sink) : Translation.tr("None");
            emitDeviceAlert(
                Translation.tr("%1 disconnected").arg(item.label),
                Translation.tr("Output: %1").arg(activeLabel),
                item.icon,
                "device-removed"
            );
        }
        for (const item of removedStandaloneInputs) {
            root.recentHotplugAt = Date.now();
            emitDeviceAlert(
                Translation.tr("%1 disconnected").arg(item.label),
                Translation.tr("Audio input removed"),
                item.icon,
                "device-removed"
            );
        }
    }

    Timer {
        id: deviceInitTimer
        interval: 2000
        running: true
        repeat: false
        onTriggered: root.reconcileAudioDevices()
    }

    Timer {
        id: deviceSyncTimer
        interval: 350
        repeat: false
        onTriggered: root.reconcileAudioDevices()
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() {
            if (root.deviceMonitorReady)
                deviceSyncTimer.restart();
        }
    }

    Timer {
        id: sinkSwitchNotifyTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (!root.deviceMonitorReady || !root.sink || !root.isPhysicalAudioNode(root.sink)) return;
            const key = root.stableDeviceKey(root.sink);
            if (!key || key === root.lastDefaultSinkKey) return;
            root.lastDefaultSinkKey = key;
            if (Date.now() - root.recentHotplugAt < 1200) return;
            const label = root.friendlyDeviceName(root.sink);
            const icon = root.deviceIcon(root.sink, true);
            root.lastDeviceTitle = Translation.tr("Audio output");
            root.lastDeviceSubtitle = label;
            root.lastDeviceIcon = icon;
            root.deviceEvent(root.lastDeviceTitle, root.lastDeviceSubtitle, icon);
        }
    }

    // Controls
    function toggleMute() {
        if (!root.ready) return;
        Audio.sink.audio.muted = !Audio.sink.audio.muted
    }

    function toggleMicMute() {
        if (!source?.ready || !source?.audio) return;
        Audio.source.audio.muted = !Audio.source.audio.muted
    }

    function incrementVolume() {
        if (!root.ready) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume = Math.min(1, Audio.sink.audio.volume + step);
    }
    
    function decrementVolume() {
        if (!root.ready) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume -= step;
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        id: volumeMonitor
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink?.audio?.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }
    Connections {
        target: root
        // A replacement device owns its volume; do not compare it with the old one.
        function onSinkChanged() {
            volumeMonitor.lastReady = false;
            volumeMonitor.lastVolume = 0;
            if (root.deviceMonitorReady) sinkSwitchNotifyTimer.restart();
        }
        function onReadyChanged() {
            if (!root.ready) { volumeMonitor.lastReady = false; volumeMonitor.lastVolume = 0; }
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
