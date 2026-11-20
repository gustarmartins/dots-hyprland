import QtQuick
import Quickshell.Io

Process {
    id: watcher
    required property string mimeType
    required property string cliphistBinary
    property bool captureEnabled: false
    signal stored()

    command: ["wl-paste", "--type", mimeType, "--watch", "bash", "-c",
        '"$1" store && printf "stored\\n"', "qs-cliphist-store", cliphistBinary]
    // Only a completion marker reaches QML; clipboard data goes directly to
    // cliphist. Refresh after storage finishes, including image copies.
    stdout: SplitParser {
        onRead: (line) => {
            if (line === "stored") watcher.stored()
        }
    }
    property Timer retry: Timer {
        interval: 2000
        onTriggered: if (watcher.captureEnabled) watcher.running = true
    }
    onRunningChanged: {
        if (!running && captureEnabled) retry.restart()
    }
}
