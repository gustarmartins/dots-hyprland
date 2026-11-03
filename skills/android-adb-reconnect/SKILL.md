---
name: android-adb-reconnect
description: Reconnect explicitly selected Android ADB endpoints for a current request, with one attempt by default and no unattended background retries.
---

# Android ADB reconnect

Gustavo's November 2 on-demand directive supersedes the former automatic
15-round background retry policy. Read `/home/gus/ANDROID_DEVICE_LAB.md` before
device access. Reconnect only when the current task actually needs that device.

Run `scripts/reconnect.py --now --endpoint HOST:PORT` for one attempt. Outside
an existing `android-adb-on-demand run` operation this creates an ephemeral
private scope and retires its connection before returning. Inside an operation
it uses that operation's private ADB route, keeping the connection only until
the outer operation ends. A successful standalone probe does not leave a
persistent transport for subsequent commands; wrap the whole intended task.

Another explicitly selected route is allowed when needed; order is preserved
and success stops alternate connections. Extra attempts require explicit finite
`--attempts`, `--interval` and `--deadline`. Do not detach it, schedule it, repeat
it after completion or use it to await a future report. Continue offline work
when access fails. An active engineering goal alone is not current demand.

The helper uses connection/state commands only, with no phone shell, UI, root,
launch, setting or reboot. It disconnects only a selected transport labelled
offline. It never kills the shared server or changes keys. A root-only failure
is not evidence that the transport needs reconnecting. Do not probe the shell
repeatedly to monitor availability.

Exit0 means transport connected during the operation, not identity/root or
framework readiness. Exit2 means failure or invalid invocation; exit3 means
authorization needed; exit4 means an identical helper holds its host lock.
Verify current model, device, firmware, boot and privilege before attribution or
mutation. Reconcile an uncertain submitted operation instead of replaying it.
