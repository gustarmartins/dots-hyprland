import QtQuick
import qs.services

SettingRow {
    id: root
    property var effectsEditor: null
    readonly property bool loudness: setting.provider === "loudness"
    readonly property string effectKey: setting.provider === "tempo" ? (effectsEditor?.motionKey("tempo") ?? "tempo") : setting.provider
    providerValue: loudness ? MusicLoudness.autoInterval : effectsEditor?.draft[effectKey] ?? 100
    unavailableReason: loudness ? (!MusicLoudness.enabled || !MusicLoudness.autoMatch ? "Enable automatic loudness matching in Audio & night light." : MusicLoudness.busy ? "Updating loudness settings…" : "")
        : !effectsEditor?.ready || effectsEditor.busy ? "Loading desktop effects…" : ""
    onProviderEdited: next => {
        if (loudness) MusicLoudness.setAutoInterval(next);
        else effectsEditor.edit(effectKey, next);
    }
    Component.onCompleted: if (loudness) MusicLoudness.refresh()
}
