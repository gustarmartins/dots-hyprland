#!/usr/bin/env python3
"""Actual Kitty focus, tmux attachment, and background-lock waiting, privately.

Run: xvfb-run -a dbus-run-session -- python tests/codex_notification_native.py
Uses synthetic session metadata and tiny lock-holder processes, never real agents.
"""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="codex-notification-native-", dir=os.environ.get("QS_AUDIT_OUTPUT")))
runtime = tempfile.TemporaryDirectory(prefix="cnative-", ignore_cleanup_errors=True)
env = os.environ.copy()
assert "/run/user/" + str(os.getuid()) + "/bus" not in env.get("DBUS_SESSION_BUS_ADDRESS", ""), "Use dbus-run-session"
for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "CODEX_THREAD_ID"):
    env.pop(key, None)
account = OUT / "account with spaces"
account.mkdir()
env.update(HOME=str(OUT), CODEX_HOME=str(account), XDG_CONFIG_HOME=str(OUT / "config"), XDG_STATE_HOME=str(OUT / "state"),
           XDG_CACHE_HOME=str(OUT / "cache"), XDG_DATA_HOME=str(OUT / "data"), XDG_RUNTIME_DIR=runtime.name,
           QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", QT_NO_XDG_DESKTOP_PORTAL="1", TMUX_TMPDIR=runtime.name,
           XDG_CURRENT_DESKTOP="NotificationTest", WAYLAND_DISPLAY="", HYPRLAND_INSTANCE_SIGNATURE="",
           KITTY_CONFIG_DIRECTORY=str(OUT / "config/kitty"))
subprocess.run(["dbus-update-activation-environment", "HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
                "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "DISPLAY", "XAUTHORITY", "XDG_CURRENT_DESKTOP", "WAYLAND_DISPLAY",
                "HYPRLAND_INSTANCE_SIGNATURE", "QT_QPA_PLATFORMTHEME", "QT_NO_XDG_DESKTOP_PORTAL"], env=env, check=True)
helper = OUT / ".local/bin/codex-notify"
helper.parent.mkdir(parents=True)
shutil.copy2(REPO / "dots/.local/bin/codex-notify", helper)
helper.chmod(0o755)
kitty_config = OUT / "config/kitty/kitty.conf"
kitty_config.parent.mkdir(parents=True)
kitty_config.write_text("listen_on unix:@kitty-{kitty_pid}.sock\nallow_remote_control socket-only\nshell_integration disabled\nenable_audio_bell no\nconfirm_os_window_close 0\nlinux_display_server x11\n")
(account / "config.toml").write_text('[tui]\nanimations=false\n')
(account / "thread-writer-locks").mkdir()
ident = "10000000-1111-2222-3333-444444444444"
workspace = OUT / 'workspace with $(literal) and "quotes"'
workspace.mkdir()
rollout = OUT / "unread-fixture.jsonl"
rollout.write_text("fixture, never read\n")
with contextlib.closing(sqlite3.connect(account / "state_5.sqlite")) as db:
    db.execute("CREATE TABLE threads(id,cwd,name,model,reasoning_effort,archived,rollout_path,agent_path)")
    db.execute("INSERT INTO threads VALUES(?,?,?,?,?,?,?,?)", (ident, str(workspace), "Native fixture", "fixture", "high", 0, str(rollout), "/root"))
    db.commit()
token = hashlib.sha256((str(account) + "\0" + ident).encode()).hexdigest()[:32]
route_dir = OUT / "state/codex-notify/routes"
route_dir.mkdir(parents=True)
(route_dir / (token + ".json")).write_text(json.dumps({"version": 1, "home": str(account), "id": ident}))
writer = OUT / "writer.py"
writer.write_text('''import ctypes,fcntl,json,os,signal,sys,time
from pathlib import Path
ctypes.CDLL(None).prctl(15,b"codex",0,0,0)
lock=Path(sys.argv[1]).open("a")
fcntl.flock(lock,fcntl.LOCK_EX)
Path(sys.argv[2]).write_text(json.dumps({"pid":os.getpid()}))
signal.signal(signal.SIGHUP,lambda *_:sys.exit(0))
while True: signal.pause()
''')
ready = OUT / "writer-ready.json"
writer_argv = [sys.executable, str(writer), str(account / "thread-writer-locks" / (ident + ".lock")), str(ready)]
processes = []
socket_path = str(Path(runtime.name) / "tmux.sock")
checks = []


def run(*argv, timeout=15):
    return subprocess.check_output(argv, env=env, text=True, stderr=subprocess.PIPE, timeout=timeout).strip()


def call(*args):
    return json.loads(run(str(helper), *args))


def wait_for(fn):
    end = time.monotonic() + 12
    while time.monotonic() < end:
        try:
            value = fn()
            if value:
                return value
        except (FileNotFoundError, ValueError, subprocess.CalledProcessError):
            pass
        time.sleep(.1)
    raise AssertionError("Timed out; inspect " + str(OUT))


def stop_writer():
    pid = json.loads(ready.read_text())["pid"]
    assert str(writer).encode() in Path(f"/proc/{pid}/cmdline").read_bytes()
    os.kill(pid, signal.SIGTERM)
    wait_for(lambda: not Path(f"/proc/{pid}").exists() or Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] == "Z")
    ready.unlink()


try:
    call("on")
    # Real terminal with a stand-in writer: focus must reuse this exact window.
    log = (OUT / "kitty.log").open("w")
    direct = subprocess.Popen(["kitty", "--directory", str(workspace), *writer_argv], env=env, stdout=log, stderr=log)
    processes.append(direct)
    wait_for(ready.exists)
    writer_pid = json.loads(ready.read_text())["pid"]
    result = call("plan", token)
    if result["action"] != "focus":
        debug = run(sys.executable, "-c", "import runpy,json,sys,pathlib; m=runpy.run_path(sys.argv[1]); s=m['inventory'](pathlib.Path(sys.argv[2]),sys.argv[3]); print(json.dumps({k:s[k] for k in ['writers','windows','panes']}))", str(helper), str(account), ident)
        raise AssertionError((result, debug))
    assert call("open", token)["action"] == "focus"
    assert json.loads(ready.read_text())["pid"] == writer_pid
    checks.append("actual Kitty focus reuses the existing writer and window")
    stop_writer()
    direct.wait(timeout=5)
    assert call("plan", token)["action"] == "resume"
    checks.append("closed terminal plans an exact-ID resume")
    # A detached, renamed tmux session must retain its writer and gain a Kitty client.
    subprocess.run(["tmux", "-S", socket_path, "-f", "/dev/null", "new-session", "-d", "-s", "original", "-c", str(workspace), *writer_argv], env=env, check=True)
    wait_for(ready.exists)
    writer_pid = json.loads(ready.read_text())["pid"]
    run("tmux", "-S", socket_path, "rename-session", "-t", "original", "renamed-session")
    assert call("plan", token)["action"] == "attach-tmux"
    assert call("open", token)["action"] == "attach-tmux"
    pending = json.loads((OUT / "state/codex-notify" / (token + ".pending.json")).read_text())
    wait_for(lambda: run("tmux", "-S", socket_path, "list-clients", "-F", "#{client_pid}"))
    assert call("open", token)["action"] == "focus"
    assert len(run("tmux", "-S", socket_path, "list-clients", "-F", "#{client_pid}").splitlines()) == 1
    assert json.loads(ready.read_text())["pid"] == writer_pid
    checks.append("detached renamed tmux gains one real Kitty attachment without a new agent")
    # Select another window, then click: the correct original pane is selected.
    original_pane = run("tmux", "-S", socket_path, "display-message", "-p", "#{pane_id}")
    run("tmux", "-S", socket_path, "new-window", "-t", "renamed-session", "sleep", "60")
    assert run("tmux", "-S", socket_path, "display-message", "-p", "#{pane_id}") != original_pane
    assert call("open", token)["action"] == "focus"
    assert run("tmux", "-S", socket_path, "display-message", "-p", "#{pane_id}") == original_pane
    checks.append("click selects the exact tmux window and pane")
    stop_writer()
    run("tmux", "-S", socket_path, "kill-server")
    with contextlib.suppress(ProcessLookupError):
        os.kill(pending["pid"], signal.SIGTERM)
    (OUT / "state/codex-notify" / (token + ".pending.json")).unlink(missing_ok=True)
    # A headless writer must remain single: the new terminal waits on its kernel lock.
    headless = subprocess.Popen(writer_argv, env=env, stdout=log, stderr=log, start_new_session=True)
    processes.append(headless)
    wait_for(ready.exists)
    assert call("plan", token)["action"] == "await-background"
    assert call("open", token)["action"] == "await-background"
    pending = json.loads((OUT / "state/codex-notify" / (token + ".pending.json")).read_text())
    viewer = wait_for(lambda: json.loads((OUT / "state/codex-notify" / (token + ".viewer.json")).read_text()))
    assert headless.poll() is None and Path(f"/proc/{viewer['pid']}").exists()
    assert call("open", token)["action"] == "focus"
    checks.append("background writer is preserved and repeated clicks reuse its waiting terminal")
    os.kill(pending["pid"], signal.SIGTERM)
    wait_for(lambda: not Path(f"/proc/{viewer['pid']}").exists())
    assert headless.poll() is None
    checks.append("closing the waiting terminal leaves the background task alive")
    assert call("open", token)["action"] == "await-background"
    pending = json.loads((OUT / "state/codex-notify" / (token + ".pending.json")).read_text())
    viewer = wait_for(lambda: (v if (v := json.loads((OUT / "state/codex-notify" / (token + ".viewer.json")).read_text()))["pid"] != viewer["pid"] else None))
    call("off")
    stop_writer()
    headless.wait(timeout=5)
    wait_for(lambda: not Path(f"/proc/{viewer['pid']}").exists())
    checks.append("master off prevents a waiting terminal from starting Codex")
    with contextlib.suppress(ProcessLookupError):
        os.kill(pending["pid"], signal.SIGTERM)
    result = {"status": "passed", "checks": checks, "output": str(OUT)}
    (OUT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
finally:
    subprocess.run(["tmux", "-S", socket_path, "kill-server"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for p in processes:
        if p.poll() is None:
            p.terminate()
        p.wait(timeout=5)
    if ready.exists():
        with contextlib.suppress(OSError, AssertionError):
            stop_writer()
