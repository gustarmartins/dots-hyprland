pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options?.time?.secondPrecision || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    // The clock can briefly be unavailable while a reload replaces the singleton.
    function formatted(format) {
        return clock?.date ? (Qt.locale().toString(clock.date, format) ?? "") : "";
    }
    property string time: formatted(Config.options?.time?.format ?? "hh:mm")
    property string shortDate: formatted(Config.options?.time?.shortDateFormat ?? "dd/MM")
    property string date: formatted(Config.options?.time?.dateWithYearFormat ?? "dd/MM/yyyy")
    property string longDate: formatted(Config.options?.time?.dateFormat ?? "dddd, dd/MM")
    property string collapsedCalendarFormat: formatted("dddd, MMMM dd")
    property string uptime: "0h, 0m"

    Timer {
        interval: Config.options?.resources?.updateInterval ?? 3000
        running: true
        repeat: true
        onTriggered: fileUptime.reload()
    }

    FileView {
        id: fileUptime
        path: "/proc/uptime"
        onLoaded: {
            const textUptime = text();
            const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0);
            if (!Number.isFinite(uptimeSeconds) || uptimeSeconds < 0) return;

            // Convert seconds to days, hours, and minutes
            const days = Math.floor(uptimeSeconds / 86400);
            const hours = Math.floor((uptimeSeconds % 86400) / 3600);
            const minutes = Math.floor((uptimeSeconds % 3600) / 60);

            // Build the formatted uptime string
            let formatted = "";
            if (days > 0)
                formatted += `${days}d`;
            if (hours > 0)
                formatted += `${formatted ? ", " : ""}${hours}h`;
            if (minutes > 0 || !formatted)
                formatted += `${formatted ? ", " : ""}${minutes}m`;
            uptime = formatted;
        }
    }
}
