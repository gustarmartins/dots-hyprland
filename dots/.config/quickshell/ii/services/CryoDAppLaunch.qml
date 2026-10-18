pragma Singleton
import Quickshell
import qs.modules.common

Singleton {
    id: root
    property string executable: "/usr/local/libexec/cryod-desktop/cryod-app-launch"
    readonly property bool enabled: Config.ready && Config.options.cryod.enabled
        && Config.options.cryod.groupLaunches

    function launch(entry, action = null): bool {
        if (!enabled || entry.runInTerminal) return false;
        const selected = action ?? entry;
        const command = Array.from(selected.command);
        if (!command.length) return false;
        const actions = Object.create(null);
        for (const item of entry.actions) actions[item.id] = Array.from(item.command);
        const manifest = JSON.stringify({version: 1, app_id: entry.id,
            working_directory: entry.workingDirectory, command: Array.from(entry.command), actions: actions});
        // Only fixed shell code is evaluated. Every app argument stays separate,
        // including when the optional native helper is absent. Never retry an
        // app on exit status: its own error code does not mean launch failed.
        Quickshell.execDetached({workingDirectory: entry.workingDirectory, command: [
            "/bin/sh", "-c",
            'cryod_helper=$1; cryod_manifest=$2; cryod_action=$3; shift 3; '
                + 'if [ -x "$cryod_helper" ]; then exec "$cryod_helper" --manifest "$cryod_manifest" --action "$cryod_action" -- "$@"; fi; exec "$@"',
            "cryod-app-launch", executable, manifest, action?.id ?? "", ...command
        ]});
        return true;
    }
}
