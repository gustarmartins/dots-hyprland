---
name: android-on-demand
description: Perform Android ADB or Tailscale diagnostics and reconnection only for a current explicit need, with no unattended discovery or background polling. Use for device investigations, delivery preflight and connection recovery on Gustavo's workstation.
---

# Android on demand

Gustavo's November 2 directive replaces unattended device polling and reconnect
loops. An active engineering goal does not itself authorize idle telemetry.
Read `/home/gus/ANDROID_DEVICE_LAB.md` before device access.

- Start with retained evidence and host-only state. Do not contact a phone merely
  because it is online, an agent resumed, a build is running or a timer fired.
- When current information is needed for the actual task, issue the smallest
  explicit request against one selected endpoint. Ordinary `adb -s SERIAL ...`
  and existing root routes remain available; verify identity before attribution
  or mutation. No repeated user approval is needed for already-authorized work.
  If the caller's environment is unknown, prefix a raw ADB invocation with
  `ADB_MDNS_AUTO_CONNECT=0` so a new server does not auto-connect other devices.
- `android-adb-on-demand` with no arguments lists saved endpoints without ADB,
  discovery or network calls. For a deliberate connection use
  `android-adb-on-demand connect --now --endpoint HOST:PORT`, or `adbc fe`.
  A connection result establishes transport only, not device/root readiness.
- Connection failure ends the default attempt. Do not create a watcher, detached
  reconnect job, periodic wakeup, subnet sweep or repeated Tailscale probe.
  An active, explicitly scoped recovery can use the reconnect helper with
  `--now` and an explicit finite `--attempts`; its default is one attempt.
- A user-opened live monitor or a specifically requested timed recording is
  current demand while it is being used. Keep its duration/stop condition clear;
  stop owned collection when the request is satisfied. Never convert it into a
  persistent service or continue polling merely to wait for a future report.
- Reuse the shared ADB server. Preserve USB, device authorization, ADB keys,
  normal VPN traffic, IT services and other projects. Do not kill the server,
  clear credentials, stop Tailscale or add a broad network firewall as a shortcut.

The old `adb-wifi-connect.service` and `poco-state-snapshot.timer` are masked.
`adb-wifi-connect watch` refuses before any connection. Do not re-enable them
as ordinary recovery. This policy constrains managed helpers and agent workflow;
it is not a claim that arbitrary programs cannot use the raw ADB binary.
