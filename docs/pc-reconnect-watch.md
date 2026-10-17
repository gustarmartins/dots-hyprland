# PC reconnection alerts

Super+I → Company accounts provides a master arm/stop switch, desktop delivery,
optional repeat mode, linked Codex wake and a labelled notification test. Search
for SSH, reconnect, polling or PC. Feature controls are hidden while disarmed.

The helper uses a systemd user timer once per minute. There is no resident
watcher process between checks. A probe uses existing pinned, batch-only SSH
credentials and runs a short Windows `cmd.exe` echo. It never opens a remote
desktop, sends physical input, or changes the remote machine's settings.
An unreachable SSH connection times out after four seconds (eight-second outer
limit). Only an authenticated expected response marks the host online. A VPN
ping, AnyDesk presence or Wi-Fi association alone does not trigger this SSH
access alert. Real alerts request no automatic expiry and remain in Quickshell
history; the owner's Do Not Disturb setting still controls popup visibility.

Private configuration belongs in `~/.config/pc-reconnect-watch/config.json`:
`sshAlias`, `displayName`, `desktop`, `repeat`, and `wakeCodex`. Enabling a Codex
wake also requires the existing `threadId` and a `wakeMessage` under 1,000 UTF-8
bytes. The installed native `codex queue --thread ... --message ...` continues
that same task; it does not open a terminal or create a separate writer.
Do not store account data, thread IDs, host addresses, credentials or private
prompts in this repository. SSH credentials remain in SSH's existing setup.

Install the helper and units, reload the user manager, configure the alias, then
run `pc-reconnect-watch on`. `status`, `off`, and `test` inspect, stop all owned
work, and test desktop notification delivery. State is private under
`~/.local/state/pc-reconnect-watch`. The default sends one alert, queues the
configured Codex continuation, and disarms. Repeat mode alerts on each new
offline-to-online transition. Failed delivery retries without duplicating the
channel that already succeeded. Checks never overlap. The master off switch
stops the timer and any running check, including its owned SSH child.

Dependencies: Python, OpenSSH with an existing pinned alias, systemd user units,
libnotify and a running Quickshell notification service. Codex is required only
for task wake. The watcher checks only while this PC is running and can reach
the network; a queued Codex message still requires its account/server to work.
Power policy and any subsequent remote work are separate, explicitly authorized
steps described by the private continuation prompt.
