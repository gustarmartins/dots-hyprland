#!/usr/bin/env python3
"""Real Qt/SNI and QS recovery on a disposable X display and session bus.

Never touches the live bus, VPN, compositor, settings or apps. Compositor
discovery is stubbed because the failure being injected is D-Bus, not Wayland.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="qs-bus-"))
CONFIG = OUT / "config/quickshell/ii"
CONFIG.mkdir(parents=True)
env = os.environ.copy()
for key in ("DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_SESSION_BUS_ID"):
    env.pop(key, None)
env.update(HOME=str(OUT / "home"), XDG_CONFIG_HOME=str(OUT / "config"),
           XDG_DATA_HOME=str(OUT / "data"), XDG_CACHE_HOME=str(OUT / "cache"),
           XDG_STATE_HOME=str(OUT / "state"), XDG_RUNTIME_DIR=str(OUT),
           DBUS_SESSION_BUS_ADDRESS=f"unix:path={OUT}/bus", WAYLAND_DISPLAY="fixture-display",
           QT_QPA_PLATFORM="xcb", QT_QPA_PLATFORMTHEME="generic", NO_AT_BRIDGE="1",
           QT_NO_XDG_DESKTOP_PORTAL="1", XDG_CURRENT_DESKTOP="")
children, logs = [], []


def launch(args, name):
    log = (OUT / (name + ".log")).open("w")
    logs.append(log)
    p = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    children.append(p)
    return p


def until(fn, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = fn()
            if value:
                return value
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        time.sleep(.1)
    raise AssertionError("Timeout; inspect " + str(OUT))


def ipc(target, method):
    return subprocess.check_output(["/usr/bin/qs", "-c", "ii", "ipc", "call", target, method],
                                   env=env, text=True, stderr=subprocess.DEVNULL, timeout=2).strip()


def status():
    return json.loads(ipc("sessionBus", "status"))


def healthy():
    s = status()
    return s if s["state"] == "connected" else None


def items():
    result = subprocess.run(["busctl", "--address=" + env["DBUS_SESSION_BUS_ADDRESS"], "--timeout=1",
        "get-property", "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"],
        env=env, capture_output=True, text=True, timeout=2)
    return result.stdout.strip()


def start_bus(name):
    p = launch(["dbus-daemon", "--nofork", "--config-file=" + str(OUT / "bus.conf")], name)
    until(lambda: (OUT / "bus").exists())
    return p


def monitors():
    found = []
    for path in Path("/proc").iterdir():
        if not path.name.isdigit():
            continue
        try:
            cmd = (path / "cmdline").read_bytes().split(b"\0")
            if str(CONFIG / "scripts/session_bus.py").encode() in cmd and b"--pid" in cmd:
                found.append(int(path.name))
        except (PermissionError, FileNotFoundError, ProcessLookupError):
            pass
    return found


try:
    source = REPO / "dots/.config/quickshell/ii"
    (CONFIG / "scripts").mkdir()
    shutil.copy2(source / "scripts/session_bus.py", CONFIG / "scripts")
    shutil.copy2(source / "services/SessionBusRecovery.qml", CONFIG)
    (CONFIG / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 SessionBusRecovery {}
 IpcHandler { target: "test"; function reload(): void { Quickshell.reload(false); } }
}
''')
    bins = OUT / "bin"
    bins.mkdir()
    (bins / "hyprctl").write_text('#!/bin/sh\nprintf \'[{"instance":"fixture","wl_socket":"fixture-display"}]\\n\'\n')
    (bins / "qs").write_text('#!/bin/sh\nexec /usr/bin/qs "$@"\n')
    for path in bins.iterdir():
        path.chmod(0o755)
    env["PATH"] = str(bins) + ":/usr/bin:/bin"
    (OUT / "bus.conf").write_text(f'''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path={OUT}/bus</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>''')
    display = subprocess.Popen(["Xvfb", "-displayfd", "1", "-screen", "0", "800x600x24", "-nolisten", "tcp"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    children.append(display)
    env["DISPLAY"] = ":" + display.stdout.readline().strip()
    supervisor = launch(["bash", str(REPO / "dots/.config/hypr/hyprland/scripts/qs_respawn.sh"), "ii"], "supervisor")
    time.sleep(.4)
    assert not monitors(), "shell must not cache a dead connection before the bus exists"
    bus = start_bus("bus-before")
    initial = until(healthy)
    assert len(monitors()) == 1
    print("PASS: startup waits for the real bus before creating Qt services", flush=True)
    (OUT / "qt.py").write_text('''from PySide6.QtWidgets import QApplication,QSystemTrayIcon,QWidget
from PySide6.QtGui import QIcon,QPixmap
from PySide6.QtCore import QTimer
from PySide6.QtDBus import QDBusConnection
from pathlib import Path
import os,json,signal
app=QApplication([]);app.setQuitOnLastWindowClosed(False);app.setApplicationName('tray-fixture')
pixmap=QPixmap(16,16);pixmap.fill('blue')
tray=QSystemTrayIcon(QIcon(pixmap));tray.show()
window=QWidget();window.show();request=False
def close_request(*args):
 global request
 request=True
signal.signal(signal.SIGUSR1,close_request)
def sample():
 global request
 available=QSystemTrayIcon.isSystemTrayAvailable()
 if request:
  request=False
  if available:window.hide()
 p=Path(os.environ['XDG_RUNTIME_DIR'])/'qt.json'
 p.write_text(json.dumps({'pid':os.getpid(),'available':available,'visible':window.isVisible(),
  'dbus_connected':QDBusConnection.sessionBus().isConnected()}))
timer=QTimer();timer.timeout.connect(sample);timer.start(100);sample();app.exec()
''')
    qt = launch(["python3", str(OUT / "qt.py")], "qt-before")
    until(lambda: items().startswith("as 1"))
    for _ in range(3):
        ipc("test", "reload")
        until(lambda: healthy() and len(monitors()) == 1)
    assert status()["pid"] == initial["pid"]
    print("PASS: three QML reloads retain shell, tray item and exactly one monitor", flush=True)

    before = status()
    os.kill(before["monitorPid"], signal.SIGKILL)
    until(lambda: (s if s["monitorPid"] != before["monitorPid"] else None) if (s := healthy()) else None)
    assert status()["pid"] == before["pid"]
    assert len(monitors()) == 1
    print("PASS: monitor SIGKILL recovers without restarting the healthy shell", flush=True)

    os.kill(initial["pid"], signal.SIGKILL)
    after_shell = until(lambda: (s if s["pid"] != initial["pid"] else None) if (s := healthy()) else None)
    until(lambda: items().startswith("as 1"))
    os.kill(qt.pid, signal.SIGUSR1)
    until(lambda: not json.loads((OUT / "qt.json").read_text())["visible"])
    print("PASS: shell SIGKILL recovers; unchanged Qt client re-registers and closes to tray", flush=True)

    # Simulate the OOM also killing our monitor: generation tracking must not
    # depend on observing a disconnect notification in that process.
    os.kill(after_shell["monitorPid"], signal.SIGKILL)
    bus.kill(); bus.wait(timeout=3)
    assert status()["pid"] == after_shell["pid"]
    (OUT / "bus").unlink(missing_ok=True)
    bus = start_bus("bus-after")
    after_bus = until(lambda: (s if s["pid"] != after_shell["pid"] else None) if (s := healthy()) else None)
    assert after_bus["generation"] != after_shell["generation"]
    assert len(monitors()) == 1
    assert items() == "as 0"
    old_qt = json.loads((OUT / "qt.json").read_text())
    assert not old_qt["dbus_connected"]
    print("PASS: bus replacement triggers one shell restart; old Qt client correctly identified as disconnected", flush=True)

    qt.terminate(); qt.wait(timeout=3)
    qt = launch(["python3", str(OUT / "qt.py")], "qt-after")
    until(lambda: items().startswith("as 1"))
    os.kill(qt.pid, signal.SIGUSR1)
    until(lambda: not json.loads((OUT / "qt.json").read_text())["visible"])
    assert status()["pid"] == after_bus["pid"]
    print("PASS: fresh Qt client registers and closes to tray on the recovered shell", flush=True)

    subprocess.run(["/usr/bin/qs", "kill", "--pid", str(after_bus["pid"])], env=env, check=True, capture_output=True)
    supervisor.wait(timeout=5)
    until(lambda: not monitors())
    assert supervisor.returncode == 0
    print("PASS: explicit clean quit stops supervisor and monitor without respawning", flush=True)
finally:
    for p in reversed(children):
        if p.poll() is None:
            try: os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError: p.terminate()
    for p in children:
        try: p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try: os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError: p.kill()
            p.wait()
    for log in logs:
        log.close()
    print("Artifacts:", OUT, flush=True)
