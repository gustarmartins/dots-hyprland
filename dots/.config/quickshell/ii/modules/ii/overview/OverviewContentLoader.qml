import QtQuick

// Keep a recently opened grid through quick Super-key reversals. The window
// and preview captures still hide immediately; only the QML objects linger.
Loader {
    id: root
    property bool shown: false
    property bool featureEnabled: true
    property int unloadDelay: 2000
    property bool recentlyShown: false

    active: featureEnabled && (shown || recentlyShown)

    function updateRetention() {
        if (!featureEnabled) {
            releaseTimer.stop();
            recentlyShown = false;
        } else if (shown) {
            releaseTimer.stop();
            recentlyShown = true;
        } else if (recentlyShown) {
            releaseTimer.restart();
        }
    }
    onShownChanged: updateRetention()
    onFeatureEnabledChanged: updateRetention()
    Component.onCompleted: updateRetention()

    Timer {
        id: releaseTimer
        interval: Math.max(0, root.unloadDelay)
        onTriggered: root.recentlyShown = false
    }
}
