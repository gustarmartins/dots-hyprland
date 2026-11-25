pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

// Guards shell reload and update-restart operations against tearing down an
// active WlSessionLock. Calling Quickshell.reload(false) or Qt.exit(75) while
// locked destroys ext_session_lock_v1 without unlocking, causing Hyprland to
// display its crashed-lockscreen screen.
Singleton {
    id: root

    property bool locked: false
    property int deferredActionDelayMs: 300
    property bool pendingReload: false
    property bool pendingRestartForUpdate: false

    function requestReload(): void {
        if (root.locked) {
            root.pendingReload = true;
            console.warn("[ShellControl] screen is locked; deferring reload until unlock");
            return;
        }
        Qt.callLater(() => {
            if (root.locked) {
                root.pendingReload = true;
                return;
            }
            Quickshell.reload(false);
        });
    }

    function requestRestartForUpdate(): void {
        Config.flushPendingWrites();
        if (root.locked) {
            root.pendingRestartForUpdate = true;
            console.warn("[ShellControl] screen is locked; deferring restartForUpdate until unlock");
            return;
        }
        // Run normal teardown. The session's existing supervisor handles exit 75.
        Qt.callLater(() => {
            if (root.locked) {
                root.pendingRestartForUpdate = true;
                return;
            }
            Qt.exit(75);
        });
    }

    function flushDeferred(): void {
        if (root.locked) {
            return;
        }
        if (root.pendingRestartForUpdate) {
            root.pendingRestartForUpdate = false;
            root.pendingReload = false;
            Config.flushPendingWrites();
            Qt.callLater(() => Qt.exit(75));
            return;
        }
        if (root.pendingReload) {
            root.pendingReload = false;
            Quickshell.reload(false);
        }
    }

    function statusJson(): string {
        return JSON.stringify({
            locked: root.locked,
            pendingReload: root.pendingReload,
            pendingRestartForUpdate: root.pendingRestartForUpdate
        });
    }

    onLockedChanged: {
        if (root.locked) {
            deferredTimer.stop();
        } else if (root.pendingReload || root.pendingRestartForUpdate) {
            deferredTimer.restart();
        }
    }

    Timer {
        id: deferredTimer
        interval: root.deferredActionDelayMs
        repeat: false
        onTriggered: root.flushDeferred()
    }
}
