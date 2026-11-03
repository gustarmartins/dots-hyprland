---
name: android-adb-reconnect
description: Reconnect explicitly selected Android ADB endpoints for a current request, with one attempt by default and no unattended background retries.
---

# Android ADB reconnect

Gustavo's November 2 on-demand directive supersedes the former automatic
15-round background retry policy. Read `/home/gus/ANDROID_DEVICE_LAB.md` before
device access. Reconnect only when the current task actually needs that device.

Run `scripts/reconnect.py --now --endpoint HOST:PORT` for one attempt. Include
another explicitly selected route only when needed; route order is preserved
and a successful connection stops further connections. An active recovery may
use explicit finite `--attempts`, `--interval` and `--deadline` values. Do not
detach it, schedule it, keep repeating it after completion or use it to wait for
a future device report. Continue independent offline work when access fails.

The helper uses ADB connection/state commands only: no phone shell, UI, root,
app launch, setting or reboot. It disconnects only a selected endpoint currently
labelled offline. It never kills the shared ADB server or changes keys. A
root-only failure is not evidence that the transport needs reconnecting.

A transport may say `device` while its shell is unresponsive. Only when the
current task has established that with a bounded roundtrip and checked concrete
conflicting commands may it disconnect that exact endpoint and reconnect once.
Do not repeat shell probes merely to monitor availability.

Exit0 means transport connected, not identity/root/framework readiness. Pin the
endpoint and verify current model, device, firmware, boot and privilege before
subsequent attribution or mutation. Exit2 means failure or invalid invocation;
exit3 means authorization needed; exit4 means an identical helper holds its
host lock. Reconcile an uncertain submitted operation instead of replaying it.
