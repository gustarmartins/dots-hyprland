# Mail in Quickshell

Super+I → **Mail** connects Thunderbird to shell notifications. Thunderbird owns
accounts, OAuth, mailbox sync, search, reading and composition. Quickshell provides
previews, **Open mail**, **Copy code**, and link buttons labeled with their actual
destination host. The compact popup shows up to three actions; expand it for all
links. New accounts are opt-in for shell notifications.

Use **Add / manage accounts** for Thunderbird's account settings, then its **Add
Account** control. Microsoft 365 accounts should use Graph on Thunderbird 154 or
newer. Existing working OAuth IMAP accounts can continue using IMAP. EWS is being
retired for Exchange Online; existing EWS accounts are labeled in the Mail page.
Account switches here control Quickshell delivery, not Thunderbird's own sync.

The master switch enables the user service and starts Thunderbird hidden in the
background (`special:mail`) with a system tray icon. Pressing `Super+Q` on
Thunderbird's main window hides it back to `special:mail` instead of exiting, so
background mail checking and notifications stay active; secondary floating dialogs
still close normally. Left-clicking the tray icon toggles Thunderbird on the
current workspace, and right-clicking exposes **Open Mail**, **Hide to Tray**,
**Preview Unread Mail**, and **Add / Manage Accounts**. Off disables the service,
stops its entire process group, disconnects the bridge and removes mail previews
from Quickshell. A separately started Thunderbird is never killed; its extension
goes dormant on disable. If Thunderbird ever exits while Mail is enabled, the
user service automatically restarts it in the background.
No mail polling timer or model runs
in Quickshell. The disabled Mail settings entry remains available to enable it.

The four feature switches control new notifications, visible body previews,
verification-code extraction, and link actions. Codes use bounded local rules for
English and Portuguese authentication phrases, including multipart HTML mail.
Ambiguous multiple codes receive no automatic button. Codes older than fifteen
minutes are excluded. Links accept only HTTP(S), exclude credentials and obvious
unsubscribe URLs, and never open without a click. Extraction is heuristic and can
miss unusual message formats; **Open mail** remains available.

Messages over 2 MiB receive an envelope-only notification to bound preview work.
Email HTML is parsed as text. Remote images, scripts, attachments and encrypted
contents are not fetched/decrypted by the extension. Thunderbird's normal account
sync policy still applies. Message bodies, links and codes never go into bridge
logs or disk state. These mail notifications are excluded from shell history
serialization and expire on shell restart. Explicitly copying a code places it
on the normal desktop clipboard. The extension has read and native-messaging
permissions, with no send/delete/account-password access.

## Install

Dependencies: Thunderbird 140+ (154+ for Graph), Python 3, `python-gobject`,
`python-dbus`, systemd user services, Quickshell and the normal desktop D-Bus.

Apply the QML files through the normal dots deployment, then run:

```sh
python3 integrations/mail/install.py
```

Install the printed XPI in Thunderbird's Add-ons manager. Open Super+I → Mail,
turn it on, and enable notification accounts. Account configuration is private
in `$XDG_CONFIG_HOME/qs-mail/config.json` (mode 0600), outside the dots repository.
The optional `profile` setting selects an existing Thunderbird profile. The
installer does not access tokens or alter account configuration.

When migrating goimapnotify, stop/disable only the instance being replaced after
checking Thunderbird delivery. A local `legacyUnits` list can record explicitly
adopted instances; master Off also stops those. Do not run two notifiers for the
same account. Keep the old configuration for rollback.

## Validation and rollback

```sh
python3 tests/test_mail_bridge.py
node tests/mail_extension.cjs
dbus-run-session -- python3 tests/mail_native_integration.py
dbus-run-session -- python3 tests/quickshell_notification_integration.py
python3 tests/settings_catalog.py
xvfb-run -a -s '-screen 0 1400x950x24' dbus-run-session -- python3 tests/settings_ui.py
```

**Preview unread mail** exercises existing account content without marking it
read, sending mail or logging its contents. A successful preview proves body/API
and notification delivery, not latency for a newly arriving email. Incoming-event
tests and physical acceptance are separate.

For rollback, turn Mail off, remove **Quickshell Mail** from Thunderbird and
restore any explicitly migrated goimapnotify unit. Accounts and messages stay in
Thunderbird. Remove the installed helpers/unit/native-host manifest only after
turning it off. Laptop drain and long-duration resource use have not been
qualified; measure Thunderbird and its child processes together.

## Choice of backend

Thunderbird was chosen for its mature account UI, OAuth IMAP, native Microsoft
Graph support, mail search/composition, and documented message-event extension
API. Evolution is a capable alternate desktop client but would require a second
integration against its data services here. The prior goimapnotify script offers
cheap IMAP IDLE, but lacks account management and only emits a truncated preview.
The bridge keeps a single mailbox owner instead of adding another sync engine.

References: [Thunderbird Graph support](https://blog.thunderbird.net/2026/09/thunderbird-desktop-new-protocol-support-microsoft-graph-api/),
[messages API](https://webextension-api.thunderbird.net/en/mv2/messages.html),
[native messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging).
