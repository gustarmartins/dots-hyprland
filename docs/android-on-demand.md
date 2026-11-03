# Android diagnostics on demand

The November 2 owner directive stops unattended Android discovery, reconnect and
telemetry. The former login watcher queried LAN discovery and known Tailscale
endpoints every ten seconds. It and the legacy fifteen-minute Poco snapshot
timer are masked. No permanent background service replaces them.

`android-adb-on-demand` defaults to a local saved-endpoint list with no ADB/network
request. A deliberate operation runs as:

```sh
android-adb-on-demand run --now --device munch --max-seconds 900 -- python3 /path/to/installer.py
android-adb-on-demand run --now --endpoint HOST:PORT --max-seconds 30 -- adb -s HOST:PORT shell id
```

One temporary user systemd service contains its private foreground ADB server,
command and descendants. A unique Unix socket is exported through
`ADB_SERVER_SOCKET`. USB/emulator/mDNS discovery are off in this server; only
selected endpoints connect. The PATH shim rejects `-H/-P/-L/-a` server escapes,
other device endpoints, discovery and server/pairing lifecycle commands. Callers
must remove hardcoded port5037 arguments and preserve the exported socket.
Absolute SDK binaries that ignore/override it remain outside this guarantee.

The worker observes its caller through a Linux pidfd. Operation success, failure,
SIGINT/SIGTERM/SIGHUP, caller death and the explicit deadline retire the service.
`KillMode=control-group` and a second systemd runtime limit also remove detached
children and any ADB server the SDK auto-started after a server failure. No phone
query is used for cleanup. The private directory is deleted after the service's
children are stopped. Cleanup output distinguishes a retired connection from a
persistent connection and refuses to claim success when retirement is uncertain.

`adbc fe`, `adbc ultra`, `adbc munch`, explicit endpoint selectors and
`adb-connect-all` now perform ephemeral connectivity probes. They do not leave
transports registered after returning. `adbc fe -- COMMAND ...` runs a short
operation. The default operation limit is60 seconds, configurable up to one
hour. `adb-wifi-connect watch` and asynchronous batches refuse before ADB starts.
The reconnect helper requires `--now` and defaults to one attempt; standalone
use creates an ephemeral scope, nested use preserves the current private route.

Why a private server: `ADB_MDNS_AUTO_CONNECT=0` only disables paired-device mDNS
autoconnection. ADB also has a separate
[TCP ReconnectHandler](https://android.googlesource.com/platform/packages/modules/adb/+/45c08c5130b7f5f8787c0c226e72eb0d3a7f7f45/transport.cpp),
and its client can
[automatically restart a missing local server](https://android.googlesource.com/platform/packages/modules/adb/+/refs/tags/android-14.0.0_r27/client/adb_client.cpp).
Ending the owned server and containing replacements closes both lifetimes for
managed requests. The
[server implementation](https://android.googlesource.com/platform/packages/modules/adb/+/45c08c5130b7f5f8787c0c226e72eb0d3a7f7f45/client/main.cpp)
exposes separate USB, emulator and mDNS initialization switches.

Future ordinary zsh/user-service servers also receive `ADB_MDNS_AUTO_CONNECT=0`.
Existing shared-server transports/forwards and external programs are not silently
stopped. ADB keys, USB clients, Tailscale, other VPN traffic and company services
are preserved. This is managed-route enforcement and an agent workflow policy,
not a blanket firewall or a guarantee about arbitrary programs using raw ADB.

Host tests use a recording fake ADB with a local Unix socket and actual transient
user services. They exercise no-demand silence, exact endpoints, route-escape
refusal, bounded reconnect, startup/body failures, cancellation, timeout,
parent death, resistant/detached children and SDK server replacement. No fake
connect contacts a phone. The discoverable skill follows
[OpenAI's skill entrypoint format](https://developers.openai.com/plugins/concepts/skills).
