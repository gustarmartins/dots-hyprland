import qs.services

QuickToggleModel {
    name: "VRR"
    icon: "sync"
    toggled: Vrr.globalPolicy !== 0
    statusText: Vrr.error || (Vrr.monitors.some(m => m.mismatch) ? "Policy mismatch"
        : Vrr.monitors.some(m => m.gpu === true) ? "GPU enabled" : "GPU off")
    mainAction: () => Vrr.setPolicy("global", Vrr.globalPolicy === 0 ? 2 : 0)
    tooltipText: "Per-display variable refresh rate"
}
