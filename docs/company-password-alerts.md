# Company password alerts

Open **Super+I → Company accounts**, or search for password, SSPR, recovery or
audit. The master switch starts/stops the owned fifteen-minute timer and stops
an in-flight collection when disabled. Feature controls are hidden while off.
Separate controls select desktop notifications, password outcomes/blocks and
recovery-method changes. Saved audit history remains available after disabling.

The helper owns account access and private configuration. It uses the existing
Microsoft 365 CLI login and Graph `AuditLog.Read.All`, validates the configured
tenant, and never changes passwords or employee sessions. Configure the tenant
locally in `~/.config/imak-sspr/config.json` as `tenantId`; account details and
tokens must stay outside this repository. Log in through Microsoft 365 CLI if
the existing session expires. Dependencies: Python, Microsoft 365 CLI,
systemd user services, and libnotify/Quickshell for desktop delivery.

Install the included helper, Python module and two user units, run
`systemctl --user daemon-reload`, perform `imak-password-audit collect`, then
`imak-password-audit on`. `status`, `show`, `test`, and `off` provide inspection,
history, a labelled delivery test, and shutdown. Notifications use the desktop's
existing popup and history service. Progress steps are archived without popups;
the first backfill is archived without alerts. The helper retains event IDs,
time, activity, actor, target, result and correlation metadata; it omits method
values, passwords, codes and modified-property payloads.

Logs live privately in `~/.local/state/imak-sspr/events.txt`, `events.jsonl` and
`audit.sqlite3`. The collector rereads seven days to catch delayed ingestion and
deduplicates by event ID. This PC and its CLI login must be available. Outages
longer than the tenant's retained audit window can leave gaps. Microsoft audit
ingestion means delivery is not immediate. Optional HTTPS webhook delivery is
configured only in the private helper config; no webhook secret belongs here.

The audit integration does not supply SSPR licensing. Employees need an eligible
Microsoft license and an explicitly registered recovery method. SSPR registration
prompts can be disabled independently of existing MFA/security policy. Native
Microsoft admin-reset emails cover administrator resets, not every employee.
