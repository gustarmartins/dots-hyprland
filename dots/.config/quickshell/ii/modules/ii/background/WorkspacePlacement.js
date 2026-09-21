.pragma library

// Use configured ranges, including empty workspaces, so opening or closing an
// application cannot change the parallax origin. Separate contiguous groups
// (1-5, 11-15, ...) each start at the same position on their assigned monitor.
function fraction(rules, monitorName, workspaceId, fallbackCount) {
    const ids = [...new Set(rules.filter(rule => rule.enabled !== false
        && rule.monitor === monitorName && /^\d+$/.test(rule.workspaceString))
        .map(rule => Number(rule.workspaceString)))].sort((a, b) => a - b);
    const index = ids.indexOf(workspaceId);
    if (index >= 0) {
        let first = index;
        let last = index;
        while (first > 0 && ids[first - 1] === ids[first] - 1) --first;
        while (last + 1 < ids.length && ids[last + 1] === ids[last] + 1) ++last;
        return last === first ? 0.5 : (index - first) / (last - first);
    }
    const count = Math.max(1, fallbackCount);
    return count <= 1 ? 0.5 : ((Math.max(1, workspaceId) - 1) % count) / (count - 1);
}
