---
name: android-on-demand
description: Perform Android ADB or Tailscale diagnostics and reconnection only for a current explicit need, with a temporary bounded connection and no unattended discovery or background polling. Use for device investigations, delivery preflight and connection recovery on Gustavo's workstation.
---

# Android on demand

Gustavo's November 2 directive replaces unattended device polling and reconnect
loops. An active engineering goal does not itself authorize idle telemetry.
Read `/home/gus/ANDROID_DEVICE_LAB.md` before device access.

Start with retained evidence. Do not contact a phone merely because it is online,
an agent resumed or a build is running. For FE, prefer existing CryoD receipts,
status and counters over whole-process argv walks or parallel Binder dumps;
choose the smallest measurement that can resolve the current question.

For a current network operation, run the whole command or installer in one scope:

```sh
android-adb-on-demand run --now --endpoint HOST:PORT --max-seconds 30 -- adb -s HOST:PORT shell id
android-adb-on-demand run --now --device munch --max-seconds 900 -- python3 /path/to/installer.py
```

The wrapper connects only selected saved/explicit endpoints and exports a private
`ADB_SERVER_SOCKET` to every child. Its PATH `adb` rejects server-route overrides
(`-H`, `-P`, `-L`, `-a`), other endpoints, discovery and server lifecycle changes.
Remove hardcoded `-P 5037` from callers; never bypass the private route. Absolute
SDK paths must honor `ADB_SERVER_SOCKET`. Nested scopes are refused; inside a
scope use its `adb` normally. Verify current device identity/root before any
attribution or mutation. Already-authorized work needs no repeated approval.

A transient user systemd service owns the operation, ADB server and descendants.
USB, emulator and mDNS discovery are disabled for that private server. The scope
retires them after success, failure, cancellation, parent death or its deadline,
including replacement servers started by the SDK. No server or retry loop is
kept between operations. Default duration is 60 seconds; choose an explicit
finite duration for a longer current operation (maximum one hour).

- No arguments lists saved endpoints without ADB or network requests.
- `adbc fe` / `android-adb-on-demand connect --now --device fe` is an ephemeral
  connectivity probe. Exit0 does **not** leave a usable connection behind.
- `adbc fe -- adb shell id` runs a short explicit operation. A connection result
  establishes transport only, not identity/root/framework readiness.
- Default failure ends after one attempt. The reconnect helper requires `--now`;
  outside a scope it creates its own ephemeral scope, inside it reuses that route.
  Additional finite attempts require a present recovery need. Reconcile an
  uncertain submitted install/write before retrying it.
- A user-opened monitor or requested timed recording is current demand while
  used. Give it a stop condition and stop collection once satisfied. Do not turn
  it into a login service, timer, detached retry job or future-availability poll.

Preserve USB, ADB keys, authorization, normal VPN traffic, IT services and other
projects. Do not stop the shared server or other owners' active forwards as
routine recovery. The former watcher and Poco snapshot timer are masked.
`ADB_MDNS_AUTO_CONNECT=0` also applies to future ordinary servers, but does not
stop TCP reconnects for previously registered transports. This policy enforces
managed operation lifetimes; arbitrary raw binaries/external tools remain an
explicit boundary, not a claim of a universal network firewall.
