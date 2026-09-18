import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
ShellRoot {
    property var observed: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource,
        Pipewire.preferredDefaultAudioSink, Pipewire.preferredDefaultAudioSource]
    PwObjectTracker { objects: observed }
    IpcHandler {
        target: "probe"
        function status(): string {
            return JSON.stringify({nodes: Pipewire.nodes.values.map(n => n.name),
                sink: Pipewire.defaultAudioSink?.name ?? null,
                source: Pipewire.defaultAudioSource?.name ?? null,
                preferredSink: Pipewire.preferredDefaultAudioSink?.name ?? null,
                preferredSource: Pipewire.preferredDefaultAudioSource?.name ?? null})
        }
    }
}
