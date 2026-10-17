"""Quickshell Mail: local, bounded extraction and an event-driven native host.

No body, code, link or credential is written to disk or logs. The runtime state
contains account labels and health only. Email HTML is parsed, never rendered.
"""
import argparse
import configparser
import ctypes
import fcntl
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import sys
import time
from urllib.parse import urlsplit

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "qs-mail"
CONFIG = CONFIG_DIR / "config.json"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "qs-mail"
DEFAULTS = dict(enabled=False, notifications=True, preview=True, codes=True, links=True, accounts=[])
EXTENSION_ID = "qs-mail@dots-hyprland"
THUNDERBIRD_CLASSES = ("org.mozilla.Thunderbird", "thunderbird", "Thunderbird")

SNI_XML = """<node>
  <interface name="org.kde.StatusNotifierItem">
    <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
    <method name="ProvideXdgActivationToken"><arg name="token" type="s" direction="in"/></method>
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionMovieName" type="s" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
  </interface>
</node>"""

MENU_XML = """<node>
  <interface name="com.canonical.dbusmenu">
    <method name="GetLayout">
      <arg name="parentId" type="i" direction="in"/>
      <arg name="recursionDepth" type="i" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="revision" type="u" direction="out"/>
      <arg name="layout" type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="properties" type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg name="id" type="i" direction="in"/>
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg name="id" type="i" direction="in"/>
      <arg name="eventId" type="s" direction="in"/>
      <arg name="data" type="v" direction="in"/>
      <arg name="timestamp" type="u" direction="in"/>
    </method>
    <method name="AboutToShow">
      <arg name="id" type="i" direction="in"/>
      <arg name="needUpdate" type="b" direction="out"/>
    </method>
    <property name="Version" type="u" access="read"/>
    <property name="Status" type="s" access="read"/>
  </interface>
</node>"""


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)


def atomic_json(path, data):
    private_dir(path.parent)
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(data, stream, ensure_ascii=False)
        stream.write("\n")
    os.replace(tmp, path)


def settings():
    try:
        value = json.loads(CONFIG.read_text())
        if not isinstance(value, dict): raise ValueError()
    except (OSError, ValueError):
        value = {}
    result = {**DEFAULTS, **value}
    for key in ("enabled", "notifications", "preview", "codes", "links"):
        result[key] = result[key] is True
    result["accounts"] = [a for a in result.get("accounts", []) if isinstance(a, str)] if isinstance(result.get("accounts"), list) else []
    return result


def safe_url(value):
    value = html.unescape(value).strip()
    if len(value) > 4096 or re.search(r"[\x00-\x20\x7f]", value): return ""
    try:
        parsed = urlsplit(value)
        if parsed.scheme.lower() not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password: return ""
        # Access the port too, to reject malformed authorities.
        _ = parsed.port
    except ValueError:
        return ""
    return value


class MailHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.text = []
        self.links = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ("script", "style", "head", "title"): self.hidden += 1
        if self.hidden: return
        if tag in ("p", "div", "br", "li", "tr"): self.text.append("\n")
        if tag == "a":
            link = safe_url(attrs.get("href", ""))
            if link and link not in self.links: self.links.append(link)

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head", "title") and self.hidden: self.hidden -= 1
        if not self.hidden and tag in ("p", "div", "li", "tr"): self.text.append("\n")
        elif not self.hidden and tag in ("b", "strong", "a", "td"): self.text.append(" ")

    def handle_data(self, data):
        if not self.hidden: self.text.append(data)


def clean_text(value):
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]", "", str(value))
    return "\n".join(line for line in (re.sub(r"[ \t]+", " ", s).strip() for s in value.splitlines()) if line)


def extract(subject, bodies):
    plain, rich, links = [], [], []
    for part in bodies[:32]:
        text = str(part.get("text", ""))[:65536]
        if part.get("type") == "text/plain": plain.append(text)
        elif part.get("type") == "text/html":
            parser = MailHTML()
            parser.feed(text)
            rich.append("".join(parser.text))
            links.extend(parser.links)
    body = clean_text("\n".join(plain) or "\n".join(rich))[:131072]
    # Search both MIME alternatives: some senders omit the code in plain text.
    search = clean_text(subject + "\n" + body + "\n" + "\n".join(rich))[:196608]
    candidates = []
    keyword = r"(?:verification|security|authentication|login|sign[ -]?in|one[ -]?time|confirmation|access|verify|c[oó]digo|verifica[çc][aã]o|seguran[çc]a|autentica[çc][aã]o|acesso|otp|2fa)"
    # Require an authentication phrase nearby; reject common order/invoice IDs.
    for line in search.splitlines():
        if not re.search(keyword, line, re.I): continue
        for match in re.finditer(r"(?<![\w/.:+-])(?:\d{4,8}|\d{3}[ -]\d{3}|[A-Z0-9]{6,8})(?![\w/.:+-])", line):
            code = re.sub(r"[ -]", "", match.group())
            if not any(c.isdigit() for c in code): continue
            if re.search(r"(?:order|invoice|pedido|fatura|phone|telefone)\s*(?:number|n[uú]mero|#|:)?\s*$", line[max(0, match.start()-35):match.start()], re.I): continue
            if len(code) == 4 and 1900 <= int(code) <= 2099: continue
            if code not in candidates: candidates.append(code)
    # Common HTML emails place the code alone on the next line.
    for match in re.finditer(keyword + r"[^\n\d]{0,65}\n\s*(\d{4,8}|\d{3}[ -]\d{3})(?![\w-])", search, re.I):
        code = re.sub(r"[ -]", "", match.group(1))
        if code not in candidates: candidates.append(code)
    # Ambiguous multi-code messages get no automatic code button.
    code = candidates[0] if len(candidates) == 1 else ""
    for link in re.findall(r"https?://[^\s<>\"']+", body):
        links.append(link.rstrip(".,;!?)"))
    unique = []
    for link in links:
        link = safe_url(link)
        if link and link not in unique and not re.search(r"unsubscribe|optout|opt-out", link, re.I): unique.append(link)
    unique.sort(key=lambda u: not bool(re.search(r"verify|confirm|login|sign.?in|auth|reset|activate", u, re.I)))
    return body, code, [{"url": u, "label": urlsplit(u).hostname} for u in unique[:3]]


def profile():
    configured = settings().get("profile")
    if configured and Path(configured).is_dir(): return Path(configured)
    base = Path.home() / ".thunderbird"
    parser = configparser.ConfigParser()
    parser.read(base / "profiles.ini")
    for section in parser.sections():
        if section.startswith("Install") and parser.has_option(section, "Default"):
            return base / parser[section]["Default"]
    for section in parser.sections():
        if section.startswith("Profile"):
            value = parser[section]
            return base / value["Path"] if value.get("IsRelative") == "1" else Path(value["Path"])
    raise RuntimeError("Open Thunderbird once to create a mail profile.")


def profile_running(prof):
    try:
        target = os.readlink(prof / "lock")
        pid = int(target.rsplit(":+", 1)[1])
        return "thunderbird" in Path(f"/proc/{pid}/comm").read_text().lower()
    except (OSError, ValueError, IndexError):
        return False


def hypr_json(*args):
    try:
        res = subprocess.run(["hyprctl", *args, "-j"], capture_output=True, text=True, timeout=2)
        return json.loads(res.stdout) if res.returncode == 0 else None
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def hypr_dispatch(expr):
    try:
        res = subprocess.run(["hyprctl", "dispatch", expr], capture_output=True, text=True, timeout=2)
        return res.returncode == 0 and not res.stdout.lstrip().lower().startswith(("error", "err:"))
    except (OSError, subprocess.SubprocessError):
        return False


def thunderbird_clients():
    clients = hypr_json("clients") or []
    return [
        c for c in clients
        if isinstance(c, dict)
        and (c.get("class") or c.get("initialClass") or "") in THUNDERBIRD_CLASSES
        and re.fullmatch(r"0x[0-9a-fA-F]+", str(c.get("address", "")))
    ]


def show_window(wait=0.0):
    deadline = time.monotonic() + max(0.0, wait)
    while True:
        clients = thunderbird_clients()
        if clients:
            client = next((c for c in clients if not c.get("floating")), clients[0])
            addr = f"address:{client['address']}"
            active_ws = hypr_json("activeworkspace") or {}
            ws_name = str(active_ws.get("name") or active_ws.get("id") or "")
            if ws_name and (client.get("workspace") or {}).get("name") != ws_name:
                hypr_dispatch(f"hl.dsp.window.move({{ window = {json.dumps(addr)}, workspace = {json.dumps(ws_name)}, follow = true }})")
            hypr_dispatch(f"hl.dsp.focus({{ window = {json.dumps(addr)} }})")
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.1)


def hide_window():
    clients = thunderbird_clients()
    hidden = False
    for client in clients:
        ws = (client.get("workspace") or {}).get("name", "")
        if ws == "special:mail":
            continue
        addr = f"address:{client['address']}"
        if hypr_dispatch(f'hl.dsp.window.move({{ window = {json.dumps(addr)}, workspace = "special:mail", follow = false }})'):
            hidden = True
    return hidden


def open_thunderbird(accounts=False):
    prof = profile()
    if not accounts and show_window():
        return
    args = ["thunderbird", "-profile", str(prof)]
    args += ["-chrome", "chrome://messenger/content/messenger/AccountManager.xhtml"] if accounts else ["-mail"]
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    show_window(wait=5.0)


def toggle_window():
    clients = thunderbird_clients()
    if not clients:
        open_thunderbird()
        return
    active_ws = (hypr_json("activeworkspace") or {}).get("name")
    if active_ws and any((c.get("workspace") or {}).get("name") == active_ws for c in clients):
        hide_window()
    else:
        show_window()


def account_inventory():
    """Read only account labels, never Thunderbird's credential databases."""
    try: source = (profile() / "prefs.js").read_text()
    except (OSError, RuntimeError): return []
    prefs = {}
    for key, value in re.findall(r'user_pref\("(mail\.(?:account\.[^\"]+|server\.[^\"]+|identity\.[^\"]+))", ("(?:[^"\\]|\\.)*")\);', source):
        if key.endswith((".server", ".identities", ".name", ".type", ".userName", ".useremail")):
            prefs[key] = json.loads(value)
    result = []
    for key, server in prefs.items():
        if not key.startswith("mail.account.") or not key.endswith(".server"): continue
        account = key.split(".")[2]
        typ = prefs.get(f"mail.server.{server}.type", "")
        if typ in ("", "none"): continue
        identity = prefs.get(f"mail.account.{account}.identities", "").split(",")[0]
        result.append(dict(id=account, name=prefs.get(f"mail.server.{server}.name", account), type=typ,
                           email=prefs.get(f"mail.identity.{identity}.useremail", "")))
    return result


def send_command(command):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(3)
        client.connect(str(RUNTIME / "bridge.sock"))
        client.sendall(json.dumps(command).encode() + b"\n")
        return json.loads(client.recv(4096))


def register_tray(preview_cb):
    try:
        from gi.repository import Gio, GLib
        conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except Exception:
        return lambda: None

    sni_props = {
        "Category": GLib.Variant("s", "Communications"),
        "Id": GLib.Variant("s", "thunderbird"),
        "Title": GLib.Variant("s", "Thunderbird Mail"),
        "Status": GLib.Variant("s", "Active"),
        "WindowId": GLib.Variant("i", 0),
        "IconName": GLib.Variant("s", "org.mozilla.Thunderbird"),
        "IconPixmap": GLib.Variant("a(iiay)", []),
        "OverlayIconName": GLib.Variant("s", ""),
        "OverlayIconPixmap": GLib.Variant("a(iiay)", []),
        "AttentionIconName": GLib.Variant("s", ""),
        "AttentionIconPixmap": GLib.Variant("a(iiay)", []),
        "AttentionMovieName": GLib.Variant("s", ""),
        "IconThemePath": GLib.Variant("s", ""),
        "Menu": GLib.Variant("o", "/MenuBar"),
        "ItemIsMenu": GLib.Variant("b", False),
        "ToolTip": GLib.Variant("(sa(iiay)ss)", ("org.mozilla.Thunderbird", [], "Thunderbird Mail", "Quickshell Mail (running in background)")),
    }
    menu_items = [
        (1, {"label": GLib.Variant("s", "Open Mail"), "enabled": GLib.Variant("b", True), "visible": GLib.Variant("b", True)}),
        (2, {"label": GLib.Variant("s", "Hide to Tray"), "enabled": GLib.Variant("b", True), "visible": GLib.Variant("b", True)}),
        (3, {"type": GLib.Variant("s", "separator"), "visible": GLib.Variant("b", True)}),
        (4, {"label": GLib.Variant("s", "Preview Unread Mail"), "enabled": GLib.Variant("b", True), "visible": GLib.Variant("b", True)}),
        (5, {"label": GLib.Variant("s", "Add / Manage Accounts"), "enabled": GLib.Variant("b", True), "visible": GLib.Variant("b", True)}),
    ]
    menu_map = dict(menu_items)
    root_layout = (0, {"children-display": GLib.Variant("s", "submenu")}, [GLib.Variant("(ia{sv}av)", (i, p, [])) for i, p in menu_items])

    def sni_call(_conn, _sender, _path, _iface, method, _params, invocation):
        if method in ("Activate", "SecondaryActivate"):
            toggle_window()
        elif method == "ContextMenu":
            show_window()
        invocation.return_value(None)

    def menu_call(_conn, _sender, _path, _iface, method, params, invocation):
        if method == "GetLayout":
            parent_id, _, _ = params.unpack()
            layout = root_layout if parent_id == 0 else (parent_id, menu_map.get(parent_id, {}), [])
            invocation.return_value(GLib.Variant("(u(ia{sv}av))", (1, layout)))
        elif method == "GetGroupProperties":
            ids, _ = params.unpack()
            wanted = [i for i, _ in menu_items if not ids or i in ids]
            invocation.return_value(GLib.Variant("(a(ia{sv}))", ([(i, menu_map[i]) for i in wanted],)))
        elif method == "GetProperty":
            item_id, name = params.unpack()
            val = menu_map.get(item_id, {}).get(name, GLib.Variant("s", ""))
            invocation.return_value(GLib.Variant("(v)", (val,)))
        elif method == "AboutToShow":
            invocation.return_value(GLib.Variant("(b)", (False,)))
        elif method == "Event":
            item_id, event_id, _, _ = params.unpack()
            if event_id == "clicked":
                if item_id == 1: open_thunderbird(False)
                elif item_id == 2: hide_window()
                elif item_id == 4: preview_cb()
                elif item_id == 5: open_thunderbird(True)
            invocation.return_value(None)
        else:
            invocation.return_value(None)

    def menu_prop(_conn, _sender, _path, _iface, prop):
        return GLib.Variant("u", 3) if prop == "Version" else GLib.Variant("s", "normal")

    sni_info = Gio.DBusNodeInfo.new_for_xml(SNI_XML).interfaces[0]
    menu_info = Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0]
    sni_reg = conn.register_object("/StatusNotifierItem", sni_info, sni_call, lambda _c, _s, _p, _i, prop: sni_props.get(prop), None)
    menu_reg = conn.register_object("/MenuBar", menu_info, menu_call, menu_prop, None)

    def register_watcher(*_args):
        conn.call(
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher",
            "RegisterStatusNotifierItem",
            GLib.Variant("(s)", ("/StatusNotifierItem",)),
            None,
            Gio.DBusCallFlags.NO_AUTO_START,
            1000,
            None,
            lambda c, res: (c.call_finish(res) if False else None),
        )

    watch_id = Gio.bus_watch_name_on_connection(
        conn, "org.kde.StatusNotifierWatcher", Gio.BusNameWatcherFlags.NONE, register_watcher, None
    )
    register_watcher()

    def cleanup():
        Gio.bus_unwatch_name(watch_id)
        if sni_reg: conn.unregister_object(sni_reg)
        if menu_reg: conn.unregister_object(menu_reg)

    return cleanup


def native_host():
    import dbus
    from gi.repository import GLib
    private_dir(RUNTIME)
    private_dir(CONFIG_DIR)
    lock = (RUNTIME / "bridge.lock").open("w")
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError: return
    cfg = settings()
    if not cfg["enabled"]: return
    loop = GLib.MainLoop()
    state = dict(connected=True, accounts=[], status="Connected to Thunderbird", pid=os.getpid())
    messages = {}
    session = os.urandom(16).hex()
    buffer = bytearray()

    def write(data):
        raw = json.dumps(data).encode()
        sys.stdout.buffer.write(struct.pack("=I", len(raw)) + raw)
        sys.stdout.buffer.flush()

    def state_write(): atomic_json(RUNTIME / "state.json", state)

    def receive(data):
        nonlocal cfg
        cfg = settings()
        if not cfg["enabled"]: loop.quit(); return
        typ = data.get("type")
        if typ == "accounts":
            state["accounts"] = [{k: str(a.get(k, ""))[:256] for k in ("id", "name", "email", "type")} for a in data.get("accounts", [])[:64]]
            state_write()
        elif typ == "status":
            # Only fixed status messages from our extension; never log message data.
            state["status"] = str(data.get("status", ""))[:180]; state_write()
        elif typ == "mail" and cfg["notifications"] and data.get("account") in cfg["accounts"]:
            key = str(data.get("key", ""))[:1024]
            if key in messages and not data.get("preview"): return
            body, code, links = extract(clean_text(data.get("subject", "")), data.get("bodies", []))
            # Never expose stale OTPs, including in explicit old-message previews.
            if not 0 <= time.time() * 1000 - float(data.get("date", 0)) < 15 * 60000: code = ""
            ref = os.urandom(12).hex()
            messages[key] = dict(ref=ref, messageId=int(data["messageId"]), account=data["account"])
            if len(messages) > 256: del messages[next(iter(messages))]
            metadata = dict(session=session, ref=ref, account=data["account"],
                            code=code if cfg["codes"] else "", expiresAt=float(data.get("date", 0)) + 15 * 60000,
                            links=links if cfg["links"] else [])
            summary = clean_text(data.get("sender", "Mail"))[:160]
            subject = clean_text(data.get("subject", "(No subject)"))[:300]
            content = html.escape(subject)
            if cfg["preview"] and body: content += "\n\n" + html.escape(body[:1800])
            # links are explicit actions; no remote HTML/images are passed to Qt.
            bus = dbus.SessionBus()
            notify = dbus.Interface(bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications"), "org.freedesktop.Notifications")
            notify.Notify("Mail", 0, "thunderbird", summary, content, dbus.Array([], signature="s"),
                          dbus.Dictionary({"x-qs-mail": json.dumps(metadata), "desktop-entry": "thunderbird"}, signature="sv"), -1)
            state["status"] = "Mail delivered to Quickshell"; state["lastDelivery"] = int(time.time()); state_write()

    def stdin_ready(fd, condition):
        chunk = os.read(fd, 65536)
        if not chunk: loop.quit(); return False
        buffer.extend(chunk)
        while len(buffer) >= 4:
            length = struct.unpack("=I", buffer[:4])[0]
            if length > 1024 * 1024: loop.quit(); return False
            if len(buffer) < length + 4: break
            raw = bytes(buffer[4:4+length]); del buffer[:4+length]
            try: receive(json.loads(raw))
            except Exception:
                state["status"] = "Could not deliver a mail preview. Check Thunderbird and Quickshell."; state_write()
        return True

    listener = socket.socket(socket.AF_UNIX)
    sock_path = RUNTIME / "bridge.sock"
    sock_path.unlink(missing_ok=True)
    listener.bind(str(sock_path)); os.chmod(sock_path, 0o600); listener.listen(4)

    def request_ready(fd, condition):
        with listener.accept()[0] as client:
            client.settimeout(1)
            try:
                request = json.loads(client.recv(4096))
                current = settings()
                if not current["enabled"]: raise ValueError()
                if request.get("type") == "ping":
                    client.sendall(b'{"ok":true}'); return True
                if request.get("type") == "open":
                    item = next((m for m in messages.values() if m["ref"] == request.get("ref")), None)
                    if request.get("session") != session or not item or item["account"] not in current["accounts"]: raise ValueError()
                    write(dict(type="open", messageId=item["messageId"]))
                    show_window()
                elif request.get("type") == "preview": write(dict(type="preview"))
                else: raise ValueError()
                client.sendall(b'{"ok":true}')
            except Exception: client.sendall(b'{"ok":false}')
        return True

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0 or libc.inotify_add_watch(fd, os.fsencode(CONFIG_DIR), 0x00000008 | 0x00000080 | 0x00000200) < 0:
        raise RuntimeError("Could not watch mail settings")

    def changed(fd, condition):
        nonlocal cfg
        os.read(fd, 65536)
        cfg = settings()
        write(dict(type="config", config={k: cfg[k] for k in DEFAULTS}))
        if not cfg["enabled"]: loop.quit()
        return True

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, stdin_ready)
    GLib.io_add_watch(listener.fileno(), GLib.IO_IN, request_ready)
    GLib.io_add_watch(fd, GLib.IO_IN, changed)
    tray_cleanup = register_tray(lambda: write(dict(type="preview")))
    write(dict(type="config", config={k: cfg[k] for k in DEFAULTS}))
    state_write()
    try: loop.run()
    finally:
        tray_cleanup()
        state.update(connected=False, status="Mail bridge stopped")
        state_write(); sock_path.unlink(missing_ok=True); os.close(fd)


def systemctl(*args, check=True):
    return subprocess.run(["systemctl", "--user", *args], check=check, capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser(description="Quickshell Mail controls")
    parser.add_argument("command", choices=["status", "set", "account", "run", "native", "open", "accounts", "preview", "message", "hide", "toggle"])
    parser.add_argument("args", nargs="*")
    arg = parser.parse_args()
    if arg.command == "native": native_host(); return
    if arg.command == "run":
        if not settings()["enabled"]:
            sys.exit(75)
        prof = profile()
        # Thunderbird's profile lock rejects a second owner. Never kill/adopt a
        # manually started client: only the systemd cgroup is stopped on disable.
        if profile_running(prof):
            sys.exit(75)
        os.execvp("thunderbird", ["thunderbird", "-profile", str(prof)])
    if arg.command == "status":
        try: state = json.loads((RUNTIME / "state.json").read_text())
        except (OSError, ValueError): state = {}
        try: state["connected"] = bool(send_command(dict(type="ping")).get("ok"))
        except (OSError, ValueError): state["connected"] = False
        print(json.dumps(dict(config=settings(), state=state, accounts=state.get("accounts") or account_inventory(),
                             running=systemctl("is-active", "qs-mail.service", check=False).returncode == 0)))
        return
    if arg.command in ("set", "account"):
        if len(arg.args) != 2 or arg.args[1] not in ("true", "false"): parser.error("expected KEY true|false")
        private_dir(CONFIG_DIR)
        with (CONFIG_DIR / "config.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            cfg = settings(); key, enabled = arg.args[0], arg.args[1] == "true"
            if arg.command == "account":
                cfg["accounts"] = sorted(set(cfg["accounts"] + [key])) if enabled else [a for a in cfg["accounts"] if a != key]
            elif key in ("enabled", "notifications", "preview", "codes", "links"): cfg[key] = enabled
            else: parser.error("unknown setting")
            atomic_json(CONFIG, cfg)
        if arg.command == "set" and key == "enabled":
            if enabled:
                systemctl("enable", "qs-mail.service")
                systemctl("start", "qs-mail.service")
            else:
                systemctl("disable", "--now", "qs-mail.service")
                # These units are explicitly adopted by the local installer.
                for unit in cfg.get("legacyUnits", []):
                    if re.fullmatch(r"goimapnotify@[A-Za-z0-9_-]+\.service", unit): systemctl("disable", "--now", unit)
        return
    if arg.command == "preview":
        if not send_command(dict(type="preview")).get("ok"): raise RuntimeError("Mail is disabled or disconnected")
    elif arg.command == "hide":
        hide_window()
    elif arg.command == "toggle":
        toggle_window()
    elif arg.command == "message":
        if len(arg.args) != 2: parser.error("expected SESSION REFERENCE")
        if not settings()["enabled"]: raise RuntimeError("Mail is disabled")
        try: opened = send_command(dict(type="open", session=arg.args[0], ref=arg.args[1])).get("ok")
        except (OSError, ValueError): opened = False
        if not opened:
            # Thunderbird IDs expire across restarts. Still provide useful access
            # without guessing another message or retaining message IDs on disk.
            open_thunderbird(False)
        else:
            show_window(wait=2.0)
    else:
        open_thunderbird(accounts=(arg.command == "accounts"))


if __name__ == "__main__":
    try: main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError):
        print("Mail action failed. Check Thunderbird or reconnect Quickshell Mail from its toolbar.", file=sys.stderr)
        sys.exit(1)
