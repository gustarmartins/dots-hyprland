#!/usr/bin/env python3
"""Real notification group input and action labels, on a private X server/bus.

Run: xvfb-run -a -s '-screen 0 1000x1200x24' dbus-run-session -- python tests/quickshell_notification_ui.py
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import runpy

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="notification-ui-", dir=os.environ.get("QS_AUDIT_OUTPUT")))
SHELL = OUT / "config/quickshell/ii"
shutil.copytree(REPO / "dots/.config/quickshell/ii", SHELL)
# Keep startup and all service state in the disposable home.
p = SHELL / "modules/common/Directories.qml"
p.write_text(p.read_text().split("    // Cleanup on init")[0] + "}\n")
(SHELL / "services/Mail.qml").write_text('''pragma Singleton
import Quickshell
Singleton { property var config: ({enabled:false,preview:true,accounts:[]}); function openMessage(data) {} }
''')
(SHELL / "services/DesktopEffects.qml").write_text('''pragma Singleton
import Quickshell
Singleton { property var settings: ({popup_opacity:100}); }
''')
runtime = tempfile.TemporaryDirectory(prefix="qs-nui-", ignore_cleanup_errors=True)  # Keep socket paths short.
(OUT / "cache/quickshell/notifications").mkdir(parents=True)
(OUT / "cache/quickshell/notifications/notifications.json").write_text("[]")
(OUT / "config/codex-notify").mkdir(parents=True)
(OUT / "config/codex-notify/config.json").write_text('{"enabled":true}')
helper = OUT / ".local/bin/codex-notify"
helper.parent.mkdir(parents=True)
helper.write_text("#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\nif sys.argv[1] == 'open': Path(" + repr(str(OUT / "opened.json")) + ").write_text(json.dumps(sys.argv[1:]))\nprint('{\"enabled\":true,\"focus\":true,\"reopen\":true}')\n")
helper.chmod(0o755)
ENTRY = SHELL / "shell.qml"
ENTRY.write_text('''//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.widgets
import qs.modules.settings
ApplicationWindow {
 id: root
 visible:true; width:660; height:1050; x:0; y:0; color:"#191a20"
 NotificationListView { id:list; anchors.fill:parent; anchors.margins:16; clip:true }
 CodexNotifications { visible:false }
 function nodes(start) {
  let queue=[start], result=[], seen=new Set();
  while(queue.length) {
   let n=queue.shift(); if(!n || seen.has(n)) continue;
   seen.add(n); result.push(n);
   for(let c of (n.children || [])) queue.push(c);
   if(n.item) queue.push(n.item);
   if(n.contentItem) queue.push(n.contentItem);
  }
  return result;
 }
 function find(kind, id) {
  const all=nodes(root.contentItem);
  if(kind==="group") return all.find(n => n.count >= 1 && n.altAction !== undefined && !String(n.objectName).startsWith("notificationExpand-"));
  if(kind==="card") return all.find(n => n.objectName==="notificationCard" && n.notificationObject.notificationId===id);
  if(kind==="arrow") return all.find(n => n.objectName==="notificationExpand-"+id);
  if(kind==="action") return nodes(find("card",id)).find(n => n.buttonText==="Open");
  if(kind==="accept") return nodes(find("card",id)).find(n => n.buttonText==="Accept");
 }
 IpcHandler { target:"test"
  function status(): string {
   const all=root.nodes(root.contentItem);
   return JSON.stringify({ready:Notifications.historyReady, list:Notifications.list.map(n => ({id:n.notificationId,nativeId:n.notification?.id,summary:n.summary})),
    cards:all.filter(n => n.objectName==="notificationCard").map(n => ({id:n.notificationObject.notificationId,expanded:n.expanded,
     groupExpanded:n.groupExpanded,height:n.height,width:n.width,
     texts:root.nodes(n).filter(c => c.text !== undefined && c.visible).map(c => ({text:c.text,width:c.width,height:c.height,lineCount:c.lineCount,truncated:c.truncated})),
     buttons:root.nodes(n).filter(c => c.buttonText !== undefined && c.visible && c.buttonText).map(c => ({text:c.buttonText,label:c.contentItem?.text,width:c.width}))}))});
  }
  function locate(kind:string,id:int): string {
   const n=root.find(kind,id); if(!n) return "null";
   const at=n.mapToItem(root.contentItem,0,0);
   return JSON.stringify({x:at.x,y:at.y,width:n.width,height:n.height,visible:n.visible,scale:n.scale,more:n.more});
  }
  function resize(width:int): void { root.width=width; }
 }
}
''')
env = os.environ.copy()
for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
    env.pop(key, None)
assert "/run/user/" + str(os.getuid()) + "/bus" not in env.get("DBUS_SESSION_BUS_ADDRESS", ""), "Use dbus-run-session"
env.update(HOME=str(OUT), XDG_CONFIG_HOME=str(OUT / "config"), XDG_CACHE_HOME=str(OUT / "cache"),
           XDG_STATE_HOME=str(OUT / "state"), XDG_DATA_HOME=str(OUT / "data"),
           XDG_RUNTIME_DIR=runtime.name, QT_QPA_PLATFORM="xcb", QT_QUICK_BACKEND="software",
           XDG_CURRENT_DESKTOP="NotificationTest", WAYLAND_DISPLAY="", HYPRLAND_INSTANCE_SIGNATURE="",
           QT_QPA_PLATFORMTHEME="", QT_NO_XDG_DESKTOP_PORTAL="1")
subprocess.run(["dbus-update-activation-environment", "HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "DISPLAY", "QT_QPA_PLATFORM",
                "XDG_CURRENT_DESKTOP", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XAUTHORITY",
                "QT_QPA_PLATFORMTHEME", "QT_NO_XDG_DESKTOP_PORTAL"], env=env, check=True)
bus = dbus.SessionBus()
actions = []
bus.add_signal_receiver(lambda n, a: actions.append((int(n), str(a))),
                        signal_name="ActionInvoked", dbus_interface="org.freedesktop.Notifications")


def call(method, *args):
    result = subprocess.check_output(["qs", "-p", str(ENTRY), "ipc", "call", "test", method, *map(str, args)],
                                     env=env, text=True, stderr=subprocess.DEVNULL, timeout=15).strip()
    return json.loads(result) if result else None


def wait_for(predicate):
    end = time.monotonic() + 8
    while time.monotonic() < end:
        ctx = GLib.MainContext.default()
        while ctx.pending():
            ctx.iteration(False)
        try:
            value = predicate()
            if value:
                return value
        except (subprocess.CalledProcessError, ValueError, StopIteration):
            pass
        time.sleep(.05)
    raise AssertionError("Timed out; inspect " + str(OUT))


def click(kind, id=0, button=1):
    at = call("locate", kind, id)
    assert at and at["visible"] and at["width"] > 0 and at["height"] > 0, (kind, at)
    subprocess.run(["xdotool", "mousemove", "--sync", str(round(at["x"] + at["width"] / 2)),
                    str(round(at["y"] + at["height"] / 2)), "click", str(button)], env=env, check=True)
    time.sleep(.4)


def card(id):
    return next(n for n in call("status")["cards"] if n["id"] == id)


log_path = OUT / "shell.log"
with log_path.open("w") as log:
    process = subprocess.Popen(["qs", "-p", str(ENTRY), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        wait_for(lambda: call("status")["ready"])
        iface = dbus.Interface(bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications"),
                               "org.freedesktop.Notifications")

        def notify(summary, action_list, app="Fixture", body=None, hints=None):
            native = int(iface.Notify(app, 0, "dialog-information", summary,
                         body or "First line of the notification body.\nSecond line.\nThird line.\nLast line of the body.",
                         dbus.Array(action_list, signature="s"), hints or {}, 0))
            wait_for(lambda: any(n["nativeId"] == native for n in call("status")["list"]))
            return native, next(n["id"] for n in call("status")["list"] if n["nativeId"] == native)

        title = "Long notification summary " * 12
        native1, id1 = notify(title, ["default", ""])
        native2, id2 = notify("Second notification", ["accept", "Accept"])
        time.sleep(.6)
        assert not card(id1)["groupExpanded"]
        click("group")
        assert all(card(i)["groupExpanded"] and not card(i)["expanded"] for i in (id1, id2))
        at = call("locate", "arrow", id1)
        assert at["more"]
        subprocess.run(["xdotool", "mousemove", "--sync", str(round(at["x"] + at["width"] / 2)), str(round(at["y"] + at["height"] / 2))], env=env, check=True)
        time.sleep(.3)
        assert call("locate", "arrow", id1)["scale"] > 1
        collapsed_height = card(id1)["height"]
        click("arrow", id1)
        first = card(id1)
        assert first["expanded"] and not card(id2)["expanded"]
        assert first["height"] > collapsed_height + 40, first
        assert any(t["text"] == title and t["lineCount"] > 1 and not t["truncated"] for t in first["texts"]), first
        assert any("Last line" in t["text"] for t in first["texts"]), first
        assert any(b["text"] == "Open" and b["label"] == "Open" and b["width"] > 40 for b in first["buttons"]), first
        subprocess.run(["import", "-window", "root", str(OUT / "expanded.png")], env=env, check=True)
        # A second card can expand and collapse without changing the first.
        click("arrow", id2)
        assert card(id1)["expanded"] and card(id2)["expanded"], call("status")
        click("arrow", id2, button=3)
        assert card(id1)["expanded"] and not card(id2)["expanded"]
        # Width changes must preserve readable labels and expanded state.
        call("resize", 420)
        time.sleep(.6)
        assert card(id1)["expanded"]
        assert all(b["width"] > 0 for b in card(id1)["buttons"])
        assert any(t["text"] == title and not t["truncated"] for t in card(id1)["texts"])
        subprocess.run(["import", "-window", "root", str(OUT / "narrow.png")], env=env, check=True)
        call("resize", 660)
        time.sleep(.4)
        click("group")
        assert all(not card(i)["groupExpanded"] and not card(i)["expanded"] for i in (id1, id2))
        click("group")
        click("arrow", id1)
        click("action", id1)
        wait_for(lambda: (native1, "default") in actions)
        assert all(n["id"] != id1 for n in call("status")["list"])
        # A single remaining notification uses the group's expansion control.
        wait_for(lambda: card(id2)["expanded"])
        click("accept", id2)
        wait_for(lambda: (native2, "accept") in actions)
        assert not call("status")["list"]
        # A routed message has its full body, including more than 24 lines.
        route = "0123456789abcdef0123456789abcdef"
        full_body = "\n".join("Line " + str(i) + ": full Codex response" for i in range(36))
        _, routed = notify("Full Codex notification", ["default", "Open session"], "Codex", body=full_body,
                           hints=dbus.Dictionary({"x-mekki-codex": route}, signature="sv"))
        time.sleep(.4)
        # The single group's button is found by the same expansion control.
        # Card click invokes the default action, so use the header's arrow.
        click("group")
        wait_for(lambda: card(routed)["expanded"])
        routed_card = card(routed)
        assert any("Line 35" in t["text"] and not t["truncated"] for t in routed_card["texts"])
        click("card", routed)
        wait_for(lambda: (OUT / "opened.json").exists())
        assert json.loads((OUT / "opened.json").read_text()) == ["open", route]
        wait_for(lambda: not call("status")["list"])
        formatter = runpy.run_path(str(REPO / "dots/.local/bin/codex-notify"))["format_message"]
        markdown_body = formatter("***Task ready*** — **bold**, *italic*, and `code_here`.\n\n- First item\n- Second item\n\n[Documentation](https://example.com)\n\n```sh\necho '<literal>'\necho '**keep these stars in code**'\n```")
        _, styled = notify("Markdown formatting test", [], "Codex", body=markdown_body,
                           hints=dbus.Dictionary({"x-mekki-codex": route}, signature="sv"))
        time.sleep(.5)
        click("group")
        wait_for(lambda: card(styled)["expanded"])
        assert any("<strong>Task ready</strong>" in t["text"] for t in card(styled)["texts"])
        subprocess.run(["import", "-window", "root", str(OUT / "markdown.png")], env=env, check=True)
        errors = [line for line in log_path.read_text().splitlines() if any(s in line for s in
                  ("ERROR", "TypeError", "ReferenceError", "Binding loop", "Cannot assign"))]
        assert not errors, errors
        result = {"status": "passed", "checks": ["group expansion", "independent card expansion and collapse",
                  "wrapped summary and body", "visible default action label", "narrow width",
                  "group collapse resets cards", "default and named actions reach sender", "single notification expansion",
                  "highlighted ellipsis hover", "full routed response and card-click session action", "rendered Markdown notification", "no QML errors"], "output": str(OUT)}
        (OUT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))
    finally:
        process.terminate()
        process.wait(timeout=5)
