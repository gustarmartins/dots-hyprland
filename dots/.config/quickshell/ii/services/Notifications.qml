pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer
        property bool retiring: false

        onNotificationChanged: {
            if (notification === null && !retiring) {
                root.discardNotifications([notificationId], false);
            }
        }
    }

    // Native provider URLs name objects in this process, not durable files.
    function persistentImage(image) {
        return typeof image === "string" && !image.startsWith("image://qsimage/") ? image : "";
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": persistentImage(notif.image),
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            if (!notifObject) {
                destroy();
                return;
            }
            if (notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property bool historyReady: false
    property bool historyWritable: true
    property bool historyLoadStarted: false
    property bool shuttingDown: false
    property bool savePending: false
    property bool waitingForReload: false
    property list<Notification> pendingNotifications: []
    property var popupList: list.filter((notif) => notif.popup);
    // Quick Settings has its own live notification preview, but opening it must
    // not swallow the normal popup. Silent mode is the explicit popup gate.
    property bool popupInhibited: silent
    readonly property var latestTimeForApp: {
        const latest = {};
        for (const notif of root.list)
            latest[notif.appName] = Math.max(latest[notif.appName] ?? 0, notif.time);
        return latest;
    }
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }

    function scheduleSave() {
        if (shuttingDown) return;
        savePending = true;
        if (historyReady && historyWritable && !saveTimer.running) saveTimer.start();
    }

    function flushSave(blocking = false) {
        if (blocking) {
            root.shuttingDown = true;
            notifFileView.blockWrites = true;
        }
        saveTimer.stop();
        if (!historyReady || !historyWritable || !savePending) return;
        savePending = false;
        notifFileView.setText(stringifyList(root.list));
    }

    Timer {
        id: saveTimer
        interval: 100
        onTriggered: root.flushSave()
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: notification => {
            notification.tracked = true;
            if (!root.historyReady) {
                root.pendingNotifications = [...root.pendingNotifications, notification];
                return;
            }
            root.addNotification(notification);
        }
    }

    function addNotification(notification) {
        if (!notification) return;
        const notif = notifComponent.createObject(root, {
            notificationId: notification.id + root.idOffset,
            notification: notification,
            time: Date.now(),
        });
        root.list = [...root.list, notif];
        if (!root.popupInhibited) {
            notif.popup = true;
            if (notification.expireTimeout !== 0) {
                notif.timer = notifTimerComponent.createObject(notif, {
                    notificationId: notif.notificationId,
                    interval: notification.expireTimeout < 0
                        ? (Config.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                });
            }
            root.unread++;
        }
        root.notify(notif);
        scheduleSave();
    }

    function markAllRead() {
        root.unread = 0;
    }

    function stopTimer(notif) {
        const timer = notif?.timer;
        if (!timer) return;
        notif.timer = null;
        timer.stop();
        timer.destroy();
    }

    // Remove membership before dismiss(): the server can synchronously clear
    // the Notification pointer and reenter this function.
    function discardNotifications(ids, dismissServer = true) {
        const wanted = new Set(ids);
        const removed = root.list.filter(notif => wanted.has(notif.notificationId) && !notif.retiring);
        if (removed.length === 0) return;
        for (const notif of removed) {
            notif.retiring = true;
            stopTimer(notif);
        }
        root.list = root.list.filter(notif => !wanted.has(notif.notificationId));
        for (const notif of removed) {
            root.discard(notif.notificationId);
            if (dismissServer && notif.notification?.tracked) notif.notification.dismiss();
            notif.destroy();
        }
        scheduleSave();
    }

    function discardNotification(id) {
        discardNotifications([id]);
    }

    function discardAllNotifications() {
        discardNotifications(root.list.map(notif => notif.notificationId));
        root.discardAll();
    }

    function cancelTimeout(id) {
        stopTimer(root.list.find(notif => notif.notificationId === id));
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null) {
            stopTimer(root.list[index]);
            root.list[index].popup = false;
        }
        root.timeout(id);
    }

    function timeoutAll() {
        for (const notif of root.popupList.slice()) timeoutNotification(notif.notificationId);
    }

    function attemptInvokeAction(id, notifIdentifier) {
        const notif = root.list.find(notif => notif.notificationId === id);
        const action = notif?.notification?.actions.find(action => action.identifier === notifIdentifier);
        if (action) action.invoke();
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function finishLoading() {
        root.historyReady = true;
        const pending = root.pendingNotifications.slice();
        root.pendingNotifications = [];
        for (const notification of pending) addNotification(notification);
        if (savePending) scheduleSave();
        root.initDone();
    }

    function refresh() {
        // A live server owns newer records; only load history at startup.
        if (historyReady) return;
        if (historyLoadStarted) notifFileView.reload();
        else historyLoadStarted = true;
    }

    PersistentProperties {
        reloadableId: "notificationHistoryGeneration"
        property bool initialized: false
        onLoaded: {
            if (initialized) root.waitingForReload = true;
            else {
                initialized = true;
                root.refresh();
            }
        }
    }
    Connections {
        target: Quickshell
        function onReloadCompleted() {
            // Defer until the outgoing ShellRoot's deferred destruction has
            // flushed its last pending write.
            if (root.waitingForReload) {
                root.waitingForReload = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    FileView {
        id: notifFileView
        path: root.historyLoadStarted ? Qt.resolvedUrl(root.filePath) : ""
        onLoaded: {
            if (root.historyReady) return;
            try {
                const saved = JSON.parse(text());
                if (!Array.isArray(saved)) throw new Error("Expected a notification list");
                let migrated = false;
                root.list = saved.map(notif => {
                    const image = root.persistentImage(notif.image);
                    migrated = migrated || image !== (notif.image ?? "");
                    return notifComponent.createObject(root, {
                        notificationId: notif.notificationId,
                        actions: [],
                        appIcon: notif.appIcon ?? "",
                        appName: notif.appName ?? "",
                        body: notif.body ?? "",
                        image: image,
                        summary: notif.summary ?? "",
                        time: notif.time,
                        urgency: notif.urgency,
                    });
                });
                root.idOffset = root.list.reduce((maxId, notif) => Math.max(maxId, notif.notificationId), 0);
                root.savePending = migrated;
                root.finishLoading();
            } catch (error) {
                // Never overwrite an unreadable history with an empty list.
                console.warn("[Notifications] Could not load history:", error);
                root.historyWritable = false;
                root.finishLoading();
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.finishLoading();
                root.scheduleSave();
            } else {
                console.warn("[Notifications] Could not read history:", error);
                root.historyWritable = false;
                root.finishLoading();
            }
        }
    }
}
