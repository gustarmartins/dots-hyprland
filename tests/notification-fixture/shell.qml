import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    id: root
    Component.onDestruction: { Notifications.flushSave(true); }
    property bool ready: Notifications.historyReady
    property list<QtObject> watched: []
    property list<QtObject> timers: []
    property int discarded: 0
    Timer { id: reloadTimer; interval: 1; onTriggered: Quickshell.reload(false) }
    Connections { target: Quickshell; function onReloadCompleted() { Quickshell.inhibitReloadPopup(); } }
    Connections {
        target: Notifications
        function onDiscard(id) { root.discarded++; }
    }
    IpcHandler {
        target: "audit"
        function status(): string {
            return JSON.stringify({ready: root.ready, pending: Notifications.savePending,
                path: Notifications.filePath, discarded: root.discarded,
                watchedLive: root.watched.filter(o => o !== null).length,
                timersLive: root.timers.filter(o => o !== null).length,
                list: Notifications.list.map(n => ({id: n.notificationId,
                    nativeId: n.notification?.id ?? -1, summary: n.summary, body: n.body,
                    image: n.image, popup: n.popup, timer: n.timer !== null, actions: n.actions}))});
        }
        function watch(): void {
            root.watched = Notifications.list.slice();
            root.timers = Notifications.list.map(n => n.timer).filter(t => t !== null);
        }
        function dismiss(id: int): void { Notifications.discardNotification(id); }
        function dismissMany(ids: string): void { Notifications.discardNotifications(JSON.parse(ids.slice(5))); }
        function clear(): void { Notifications.discardAllNotifications(); }
        function hover(id: int): void { Notifications.cancelTimeout(id); }
        function leave(id: int): void { Notifications.timeoutNotification(id); }
        function action(id: int, identifier: string): void { Notifications.attemptInvokeAction(id, identifier); }
        function reload(): void { reloadTimer.start(); }
        function stop(): void { Qt.quit(); }
    }
}
