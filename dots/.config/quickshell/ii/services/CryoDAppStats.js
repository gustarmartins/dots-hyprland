// Presentation history only; never used to grant an app permission.
var retentionMs = 30 * 24 * 60 * 60 * 1000;
var maxEntries = 256;
function validNumber(value) {
    return (typeof value === "number" || (typeof value === "string" && /^\d+$/.test(value)))
        && Number.isSafeInteger(Number(value)) && Number(value) >= 0;
}
function sanitize(rows, now) {
    if (!Array.isArray(rows)) return [];
    const unique = new Map();
    for (const row of rows.slice(0, maxEntries)) {
        if (!row || typeof row.app_id !== "string" || !row.app_id.length || row.app_id.length > 512
                || !validNumber(row.last_seen) || Number(row.last_seen) > now
                || now - Number(row.last_seen) > retentionMs) continue;
        const value = {app_id:row.app_id, last_seen:Number(row.last_seen)};
        if (validNumber(row.cpu_peak_x100) && validNumber(row.cpu_seen)
                && Number(row.cpu_seen) <= now && now - Number(row.cpu_seen) <= retentionMs) {
            value.cpu_peak_x100 = Number(row.cpu_peak_x100);
            value.cpu_seen = Number(row.cpu_seen);
        }
        unique.set(value.app_id, value);
    }
    return Array.from(unique.values()).sort((a,b) => b.last_seen - a.last_seen);
}
function observe(history, apps, now) {
    const rows = new Map(sanitize(history, now).map(row => [row.app_id, row]));
    for (const app of apps) {
        if (typeof app.app_id !== "string" || !app.app_id.length || app.app_id.length > 512
                || !Number.isInteger(app.pid) || app.pid <= 1 || typeof app.start_ticks !== "string") continue;
        const row = Object.assign({}, rows.get(app.app_id) || {}, {app_id:app.app_id, last_seen:now});
        if (validNumber(app.cpu_percent_x100)) {
            const cpu = Number(app.cpu_percent_x100);
            if (row.cpu_peak_x100 === undefined || cpu >= row.cpu_peak_x100) {
                row.cpu_peak_x100 = cpu; row.cpu_seen = now;
            }
        }
        rows.set(row.app_id, row);
    }
    return Array.from(rows.values()).sort((a,b) => b.last_seen - a.last_seen).slice(0,maxEntries);
}
function select(apps, name, query, filter, order, minimumCpu) {
    const text = query.trim().toLowerCase();
    const cpu = app => validNumber(app.stats?.cpu_peak_x100) ? Number(app.stats.cpu_peak_x100) : -1;
    const seen = app => app.pid > 1 || app.stats?.last_seen > 0;
    const recent = app => app.stats?.last_seen || 0;
    return apps.filter(app => (name(app.app_id) + " " + app.app_id).toLowerCase().includes(text)
        && (filter === "all" || (filter === "relevant" && (seen(app) || !!app.rule))
            || (filter === "seen" && seen(app)) || (filter === "running" && app.pid > 1)
            || (filter === "cpu" && cpu(app) > 0))
        && (minimumCpu === 0 || cpu(app) >= minimumCpu * 100))
        .sort((a,b) => {
            let result = 0;
            if (order === "cpu") result = cpu(b) - cpu(a) || recent(b) - recent(a);
            else if (order === "recent") result = Number(b.pid > 1) - Number(a.pid > 1) || recent(b) - recent(a);
            else if (order === "relevant") result = cpu(b) - cpu(a) || Number(seen(b)) - Number(seen(a)) || recent(b) - recent(a);
            return result || name(a.app_id).localeCompare(name(b.app_id)) || a.app_id.localeCompare(b.app_id);
        });
}
function dateLabel(timestamp) {
    const date = new Date(timestamp);
    const today = new Date();
    if (date.toDateString() === today.toDateString()) return "today";
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
        + "-" + String(date.getDate()).padStart(2, "0");
}
function summary(app) {
    const parts = [];
    if (app.pid > 1) parts.push("Running when refreshed");
    else if (app.stats?.last_seen) parts.push("Seen " + dateLabel(app.stats.last_seen));
    else parts.push("Not yet observed");
    if (validNumber(app.stats?.cpu_peak_x100))
        parts.push("Background CPU peak " + (Number(app.stats.cpu_peak_x100) / 100).toFixed(1) + "% · "
            + dateLabel(app.stats.cpu_seen));
    else parts.push("Background CPU not measured");
    return parts.join(" · ");
}
