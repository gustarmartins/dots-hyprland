#!/usr/bin/env python3
"""Load saved workspace routing after a fallback desktop, on private outputs.

Run: dbus-run-session -- python3 tests/hyprland_workspace_recovery.py
Requires KWin Wayland, Hyprland (Lua) and Kitty. Never touches the live desktop.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="workspace-recovery-"))
RUNTIME = Path(tempfile.mkdtemp(prefix="wr-"))
RUNTIME.chmod(0o700)
env = os.environ.copy()
assert f"/run/user/{os.getuid()}/bus" not in env.get("DBUS_SESSION_BUS_ADDRESS", ""), "Use dbus-run-session"
for key in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
    env.pop(key, None)
env.update(HOME=str(OUT / "home"), XDG_RUNTIME_DIR=str(RUNTIME),
           XDG_CONFIG_HOME=str(OUT / "config"), XDG_CACHE_HOME=str(OUT / "cache"),
           XDG_DATA_HOME=str(OUT / "data"), XDG_STATE_HOME=str(OUT / "state"),
           QT_QPA_PLATFORM="offscreen", AQ_DRM_DEVICES="/nonexistent-test-device",
           QT_NO_XDG_DESKTOP_PORTAL="1", NO_AT_BRIDGE="1", XDG_CURRENT_DESKTOP="")
subprocess.run(["dbus-update-activation-environment", "HOME", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME",
                "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "QT_QPA_PLATFORM"], env=env, check=True)
processes, logs = [], []


def launch(args, name):
    log = (OUT / (name + ".log")).open("w")
    logs.append(log)
    p = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    processes.append(p)
    return p


def until(fn, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = fn()
            if result:
                return result
        except (subprocess.SubprocessError, json.JSONDecodeError):
            pass
        time.sleep(.08)
    raise AssertionError("Timeout; inspect " + str(OUT))


def ctl(*args):
    return subprocess.check_output(["hyprctl", *args], env=env, text=True, timeout=5).strip()


def snapshot():
    return {key: json.loads(ctl(key, "-j")) for key in ("monitors", "workspaces", "clients", "activewindow")}


def client(name):
    return next((c for c in json.loads(ctl("clients", "-j")) if c["class"] == name), None)


def placement(workspace):
    return next((w["monitor"] for w in json.loads(ctl("workspaces", "-j")) if w.get("id") == workspace), None)


try:
    launch(["kwin_wayland", "--virtual", "--width", "640", "--height", "480", "--no-lockscreen",
            "--no-global-shortcuts", "--no-kactivities", "--socket", "test-parent"], "kwin")
    until(lambda: (RUNTIME / "test-parent").exists())
    env.update(WAYLAND_DISPLAY="test-parent", QT_QPA_PLATFORM="wayland")
    config = OUT / "hyprland.lua"
    initial_config = ('hl.monitor({output="",mode="640x480@60",position="auto",scale=1})\n'
                      'hl.monitor({output="DP-1",mode="640x480@60",position="0x0",scale=1})\n'
                      'hl.monitor({output="HDMI-A-1",mode="640x480@60",position="640x0",scale=1})\n'
                      'hl.config({animations={enabled=false},input={follow_mouse=0},misc={disable_hyprland_logo=true,disable_splash_rendering=true,disable_watchdog_warning=true}})\n')
    config.write_text(initial_config)
    compositor = launch(["Hyprland", "--config", str(config)], "hyprland")
    socket = until(lambda: next((RUNTIME / "hypr").glob("*/.socket.sock"), None))
    env["HYPRLAND_INSTANCE_SIGNATURE"] = socket.parent.name
    env["WAYLAND_DISPLAY"] = until(lambda: next((p.name for p in RUNTIME.glob("wayland-*") if not p.name.endswith(".lock")), None))
    until(lambda: json.loads(ctl("monitors", "-j")))
    ctl("output", "create", "headless", "DP-1")
    ctl("output", "create", "headless", "HDMI-A-1")
    until(lambda: len(json.loads(ctl("monitors", "-j"))) == 3)
    ctl("eval", 'hl.dispatch(hl.dsp.focus({workspace="2"})); hl.dispatch(hl.dsp.workspace.move({workspace="2",monitor="HDMI-A-1"})); hl.dispatch(hl.dsp.focus({workspace="2"}))')
    launch(["kitty", "--config", "NONE", "--class", "recover-workspace-2", "/usr/bin/sleep", "300"], "workspace2")
    moved = until(lambda: client("recover-workspace-2"))
    ctl("eval", 'hl.dispatch(hl.dsp.focus({workspace="3"})); hl.dispatch(hl.dsp.workspace.move({workspace="3",monitor="DP-1"})); hl.dispatch(hl.dsp.focus({workspace="3"}))')
    launch(["kitty", "--config", "NONE", "--class", "keep-workspace-3", "/usr/bin/sleep", "300"], "workspace3")
    foreground = until(lambda: client("keep-workspace-3"))
    assert placement(2) == "HDMI-A-1"
    before = snapshot()
    (OUT / "before.json").write_text(json.dumps(before, indent=2))
    assert before["activewindow"]["address"] == foreground["address"]

    production = REPO / "dots/.config/hypr/workspaces.lua"
    config.write_text(initial_config + "dofile(" + json.dumps(str(production)) + ")\n")
    ctl("reload")
    until(lambda: placement(2) == "DP-1")
    after = snapshot()
    (OUT / "after.json").write_text(json.dumps(after, indent=2))
    assert after["activewindow"]["address"] == foreground["address"]
    assert after["activewindow"]["workspace"]["id"] == 3
    assert client("recover-workspace-2")["workspace"]["id"] == 2
    assert client("recover-workspace-2")["pid"] == moved["pid"]
    arzopa = next(m for m in after["monitors"] if m["name"] == "HDMI-A-1")
    assert arzopa["activeWorkspace"]["id"] in range(6, 11), arzopa["activeWorkspace"]
    print("PASS: config load restores workspace 2 to AOC, ARZOPA uses its own group, foreground remains on workspace 3", flush=True)

    for _ in range(3):
        ctl("reload")
        time.sleep(.2)
        s = snapshot()
        assert placement(2) == "DP-1"
        assert s["activewindow"]["address"] == foreground["address"]
        assert len(s["clients"]) == 2
        assert not ctl("configerrors")
    print("PASS: repeated reloads preserve focus, workspace identities and windows", flush=True)

    ctl("output", "remove", "DP-1")
    until(lambda: "DP-1" not in {m["name"] for m in json.loads(ctl("monitors", "-j"))})
    ctl("reload")
    time.sleep(.3)
    assert not ctl("configerrors")
    assert len(json.loads(ctl("clients", "-j"))) == 2
    ctl("output", "create", "headless", "DP-1")
    until(lambda: placement(2) == "DP-1" and placement(3) == "DP-1")
    assert client("recover-workspace-2")["pid"] == moved["pid"]
    assert not ctl("configerrors")
    print("PASS: missing AOC is tolerated; reconnect restores its workspaces. Artifacts:", OUT, flush=True)
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
