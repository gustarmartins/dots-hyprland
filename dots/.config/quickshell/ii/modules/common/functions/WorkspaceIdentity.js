.pragma library

// Hyprland 0.57 omits numeric IDs for named and special workspaces.
// An empty monitor workspace is not an identity; two missing IDs never match.
function address(workspace) {
    if (!workspace) return "";
    if (workspace.address) return String(workspace.address);
    if (workspace.addressable_name) return String(workspace.addressable_name);
    if (workspace.id !== undefined && workspace.id !== null && workspace.id !== 0)
        return String(workspace.id);
    return "";
}

function matches(left, right) {
    const value = address(left);
    return value !== "" && value === address(right);
}

function visibleOnMonitor(window, monitor) {
    return !!monitor && (window.pinned === true
        || matches(window.workspace, monitor.activeWorkspace)
        || matches(window.workspace, monitor.specialWorkspace));
}
