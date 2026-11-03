# Android diagnostics on demand

The November 2 owner directive stops unattended Android discovery, reconnect and
telemetry. The former login watcher queried LAN discovery and known Tailscale
endpoints every ten seconds. It and the legacy fifteen-minute Poco snapshot
timer are masked. No new background service replaces them.

The shared ADB server, USB, authorization keys, Tailscale and company services
remain independent. Raw, explicitly requested `adb -s SERIAL ...` commands work
normally. This is a managed-helper and workflow policy, not a network firewall.
Future zsh and user-service processes set `ADB_MDNS_AUTO_CONNECT=0`; the managed
connectors set it directly too. This disables paired-device automatic connection
when a future server starts, as defined by the
[ADB implementation](https://android.googlesource.com/platform/packages/modules/adb/+/da537075677d85a6c3614020ee2fed893d191534/client/transport_mdns.cpp).
It does not retrofit a running server, suppress ordinary transport keepalives,
or prevent an external application from explicitly issuing raw ADB commands.

`android-adb-on-demand` defaults to a local list from
`~/.config/adb-wifi-connect/endpoints` and issues no ADB or network request.
`adbc fe`, `adbc ultra`, `adbc munch` and `adbc --endpoint HOST:PORT` explicitly
connect selected saved endpoints once. `adb-connect-all` is a deliberate,
synchronous one-shot batch; its former asynchronous mode is refused and it never
restarts the shared server. `adb-wifi-connect connect` requires `--now` and an
explicit selector. Watch mode is refused.

The existing reconnect skill now requires `--now` and defaults to one attempt.
Extra attempts must be explicitly bounded for a current recovery task. A
user-opened live monitor or specifically requested timed capture remains allowed
while needed; it must not become unattended telemetry.

The discoverable `android-on-demand` skill and machine/device instructions carry
this behavior across agent sessions. Skills use the standard required name,
description and instruction entrypoint documented in
[OpenAI's skill guidance](https://developers.openai.com/plugins/concepts/skills).

Host-only tests replace ADB with a recording fake and verify silent default
behavior, explicit endpoint selection, refusal of watching/background batches,
single-attempt recovery and preservation of healthy/unauthorized transports.
No test polls a phone.
