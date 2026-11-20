#!/usr/bin/env python3
"""Real clipboard capture/recovery on a private Wayland desktop and database.

Run: dbus-run-session -- python3 tests/quickshell_clipboard_lifecycle.py
Requires KWin Wayland, Hyprland (Lua), Quickshell, wl-clipboard, cliphist and PIL.
No live clipboard, shell, user configuration or compositor is changed.
"""
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="qs-clipboard-"))
RUNTIME = Path(tempfile.mkdtemp(prefix="qc-"))
RUNTIME.chmod(0o700)
env = os.environ.copy()
assert f"/run/user/{os.getuid()}/bus" not in env.get("DBUS_SESSION_BUS_ADDRESS", ""), "Use dbus-run-session"
for key in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QS_CONFIG_PATH", "QS_CONFIG_NAME"):
    env.pop(key, None)
env.update(HOME=str(OUT / "home"), XDG_CONFIG_HOME=str(OUT / "config"),
           XDG_DATA_HOME=str(OUT / "data"), XDG_CACHE_HOME=str(OUT / "cache"),
           XDG_STATE_HOME=str(OUT / "state"), XDG_RUNTIME_DIR=str(RUNTIME),
           QT_QPA_PLATFORM="offscreen", AQ_DRM_DEVICES="/nonexistent-test-device",
           QT_NO_XDG_DESKTOP_PORTAL="1", NO_AT_BRIDGE="1", XDG_CURRENT_DESKTOP="")
subprocess.run(["dbus-update-activation-environment", "HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
                "XDG_CACHE_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR", "QT_QPA_PLATFORM"], env=env, check=True)
processes, logs = [], []


def launch(args, name, process_env=None):
    log = (OUT / (name + ".log")).open("w")
    logs.append(log)
    process = subprocess.Popen(args, env=process_env or env, stdout=log, stderr=subprocess.STDOUT,
                               start_new_session=True)
    processes.append(process)
    return process


def until(fn, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = fn()
            if result:
                return result
        except (subprocess.SubprocessError, ValueError, FileNotFoundError):
            pass
        time.sleep(.08)
    raise AssertionError("Timeout; inspect " + str(OUT))


def ctl(*args):
    return subprocess.check_output(["hyprctl", *args], env=env, text=True, timeout=5).strip()


def ipc(target, method, *args):
    return subprocess.check_output(["qs", "-p", str(shell), "ipc", "call", target, method, *args],
                                   env=env, text=True, stderr=subprocess.DEVNULL, timeout=5).strip()


def status():
    return json.loads(ipc("cliphistService", "status"))


def watcher_pids():
    result = []
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            if (p / "comm").read_text().strip() != "wl-paste":
                continue
            if ("XDG_RUNTIME_DIR=" + str(RUNTIME)).encode() in (p / "environ").read_bytes().split(b"\0"):
                result.append(int(p.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return sorted(result)


def ready():
    s = status()
    return s if s["captureEnabled"] and s["textRunning"] and s["imageRunning"] and len(watcher_pids()) == 2 else None


def copy_text(text):
    subprocess.run(["wl-copy", "--type", "text/plain"], input=text.encode(), env=env, check=True, timeout=5)
    until(lambda: ipc("test", "contains", text) == "true")
    rows = subprocess.check_output([str(wrapper), "list"], env=env).splitlines()
    row = next(r for r in rows if text.encode() in r)
    decoded = subprocess.check_output([str(wrapper), "decode"], input=row, env=env)
    assert decoded == text.encode(), decoded


try:
    shell = OUT / "config/quickshell/ii"
    source = REPO / "dots/.config/quickshell/ii"
    shutil.copytree(source, shell)
    main_shell = (source / "shell.qml").read_text()
    start = main_shell.index('    IpcHandler {\n        target: "shellControl"')
    end = main_shell.index('\n    }', start) + len('\n    }')
    shell_control = main_shell[start:end]
    common = shell / "modules/common"
    (common / "Config.qml").write_text('''pragma Singleton
import Quickshell
Singleton {
 property var options: ({search:{sloppy:false},hacks:{arbitraryRaceConditionDelay:10}})
 function flushPendingWrites(): void {}
}
''')
    (common / "Directories.qml").write_text('''pragma Singleton
import Quickshell
Singleton { property string home: Quickshell.env("HOME") }
''')
    (shell / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
ShellRoot {
 SHELL_CONTROL
 Component.onCompleted: Cliphist.start()
 IpcHandler {
  target: "test"
  function pid(): int { return Quickshell.processId; }
  function contains(text: string): bool { return Cliphist.entries.some(e => e.endsWith("\\t" + text)); }
  function imageCount(): int { return Cliphist.entries.filter(e => Cliphist.entryIsImage(e)).length; }
  function reload(): void { Quickshell.reload(false); }
 }
}
'''.replace('SHELL_CONTROL', shell_control))
    wrapper = OUT / "home/.local/bin/cliphist"
    wrapper.parent.mkdir(parents=True)
    (OUT / "home/.local/share/cliphist").mkdir(parents=True)
    wrapper.write_text('#!/bin/sh\nexec /usr/bin/cliphist -db-path "$HOME/.local/share/cliphist/db" "$@"\n')
    wrapper.chmod(0o755)
    launch(["kwin_wayland", "--virtual", "--width", "640", "--height", "480", "--no-lockscreen",
            "--no-global-shortcuts", "--no-kactivities", "--socket", "test-parent"], "kwin")
    until(lambda: (RUNTIME / "test-parent").exists())
    parent_env = env | {"WAYLAND_DISPLAY": "test-parent", "QT_QPA_PLATFORM": "wayland"}
    config = OUT / "hyprland.lua"
    config.write_text('hl.monitor({output="",mode="640x480@60",position="auto",scale=1})\n'
                      'hl.config({animations={enabled=false},misc={disable_hyprland_logo=true,disable_splash_rendering=true,disable_watchdog_warning=true}})\n')

    def start_compositor(name):
        process = launch(["Hyprland", "--config", str(config)], name, parent_env)
        current = until(lambda: next((i for i in json.loads(subprocess.check_output(
            ["hyprctl", "instances", "-j"], env=env, text=True, timeout=5)) if i["pid"] == process.pid), None))
        env.update(HYPRLAND_INSTANCE_SIGNATURE=current["instance"], WAYLAND_DISPLAY=current["wl_socket"], QT_QPA_PLATFORM="wayland")
        until(lambda: json.loads(ctl("monitors", "-j")))
        assert not ctl("configerrors")
        return process

    compositor = start_compositor("hyprland-before")
    supervisor = launch(["bash", str(REPO / "dots/.config/hypr/hyprland/scripts/qs_respawn.sh"), "ii"], "shell")
    initial = until(ready)
    copy_text("clipboard-before-crash")
    image = io.BytesIO()
    Image.new("RGB", (12, 9), "#3582c4").save(image, format="PNG")
    subprocess.run(["wl-copy", "--type", "image/png"], input=image.getvalue(), env=env, check=True, timeout=5)
    until(lambda: ipc("test", "imageCount") == "1")
    rows = subprocess.check_output([str(wrapper), "list"], env=env).splitlines()
    row = next(r for r in rows if b"binary data" in r)
    assert subprocess.check_output([str(wrapper), "decode"], input=row, env=env) == image.getvalue()
    print("PASS: text and image saved, decoded and visible in the shell model", flush=True)
    before_pid = int(ipc("test", "pid"))
    ipc("shellControl", "restartForUpdate")
    until(lambda: int(ipc("test", "pid")) != before_pid)
    until(ready)
    assert supervisor.poll() is None
    assert ipc("test", "contains", "clipboard-before-crash") == "true"
    assert ipc("test", "imageCount") == "1"
    print("PASS: supervised update restart replaces only the shell and preserves captured history", flush=True)

    for i in range(3):
        ipc("test", "reload")
        until(ready)
        copy_text(f"clipboard-after-reload-{i}")
    print("PASS: three QML reloads retain exactly two capture processes", flush=True)

    previous = status()
    os.kill(previous["textPid"], signal.SIGTERM)
    recovered = until(lambda: (s if s["textRunning"] and s["textPid"] != previous["textPid"] else None) if (s := status()) else None)
    until(ready)
    copy_text("clipboard-after-watcher-exit")
    print("PASS: failed capture process recovers automatically", flush=True)

    old_signature = env["HYPRLAND_INSTANCE_SIGNATURE"]
    compositor.kill()
    compositor.wait(timeout=5)
    until(lambda: not watcher_pids())
    compositor = start_compositor("hyprland-after")
    assert env["HYPRLAND_INSTANCE_SIGNATURE"] != old_signature
    until(ready)
    assert supervisor.poll() is None
    copy_text("clipboard-after-compositor-crash")
    assert ipc("test", "contains", "clipboard-before-crash") == "true"
    assert ipc("test", "imageCount") == "1"
    print("PASS: compositor loss/restart restores capture and retains text/image history", flush=True)

    subprocess.run(["qs", "-p", str(shell), "kill"], env=env, check=True, timeout=5)
    supervisor.wait(timeout=5)
    until(lambda: not watcher_pids())
    assert supervisor.returncode == 0
    errors = [line for line in (OUT / "shell.log").read_text().splitlines() if any(t in line for t in
              ("TypeError", "ReferenceError", "is not a type", "Cannot assign", "Binding loop", "Failed to load configuration"))]
    assert not errors, errors
    print("PASS: clean shell exit stops capture; no QML errors. Artifacts:", OUT, flush=True)
finally:
    for process in reversed(processes):
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if process.poll() is None:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
    for log in logs:
        log.close()
