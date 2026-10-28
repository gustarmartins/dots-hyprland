#!/usr/bin/env python3
"""Exercise Super taps against a private real Hyprland compositor.

Run: dbus-run-session -- python3 tests/hyprland_super_tap.py
Requires KWin Wayland and wtype. No input is sent to the owner's desktop.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

out = Path(tempfile.mkdtemp(prefix="super-tap-test-"))
rt = Path(tempfile.mkdtemp(prefix="st-"))
rt.chmod(0o700)
env = os.environ.copy()
for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
    env.pop(key, None)
env.update(XDG_RUNTIME_DIR=str(rt), XDG_CONFIG_HOME=str(out / "config"),
           XDG_CACHE_HOME=str(out / "cache"), XDG_DATA_HOME=str(out / "data"),
           XDG_STATE_HOME=str(out / "state"), QT_QPA_PLATFORM="offscreen",
           AQ_DRM_DEVICES="/nonexistent-test-device", QT_NO_XDG_DESKTOP_PORTAL="1",
           NO_AT_BRIDGE="1", XDG_CURRENT_DESKTOP="")
processes = []
logs = []


def launch(args, name):
    log = (out / (name + ".log")).open("w")
    logs.append(log)
    proc = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
    processes.append(proc)
    return proc


def until(check):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        try:
            value = check()
            if value:
                return value
        except (subprocess.SubprocessError, json.JSONDecodeError):
            pass
        time.sleep(0.08)
    raise RuntimeError("Timeout; logs: " + str(out))


def ctl(*args):
    result = subprocess.run(["hyprctl", *args], env=env, text=True, capture_output=True, timeout=5)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout.strip()


def expect(taps, chords):
    result = ctl("eval", f'assert(tap_count == {taps}, "taps=" .. tap_count); '
                 f'assert(chord_count == {chords}, "chords=" .. chord_count)')
    assert result == "ok", result


def keys(*args):
    subprocess.run(["wtype", *args], env=env, check=True, timeout=5)
    time.sleep(0.08)


try:
    launch(["kwin_wayland", "--virtual", "--width", "1280", "--height", "720",
            "--no-lockscreen", "--no-global-shortcuts", "--no-kactivities",
            "--socket", "test-parent"], "kwin")
    until(lambda: (rt / "test-parent").exists())
    env.update(WAYLAND_DISPLAY="test-parent", QT_QPA_PLATFORM="wayland")
    module = Path(__file__).resolve().parents[1] / "dots/.config/hypr/hyprland/super_tap.lua"
    config = out / "hyprland.lua"
    config.write_text('hl.monitor({output="",mode="1280x720@60",position="auto",scale=1})\n'
                      'hl.config({input={resolve_binds_by_sym=true},animations={enabled=false},misc={disable_hyprland_logo=true,disable_splash_rendering=true}})\n'
                      'tap_count = 0; chord_count = 0\n'
                      f'dofile({json.dumps(str(module))}).bind(function() tap_count = tap_count + 1 end)\n'
                      'hl.bind("SUPER + F13", function() chord_count = chord_count + 1 end)\n')
    launch(["Hyprland", "--config", str(config)], "hyprland")
    sock = until(lambda: next((rt / "hypr").glob("*/.socket.sock"), None))
    env["HYPRLAND_INSTANCE_SIGNATURE"] = sock.parent.name
    env["WAYLAND_DISPLAY"] = until(lambda: next((p.name for p in rt.glob("wayland-*")
                                                if not p.name.endswith(".lock")), None))
    until(lambda: json.loads(ctl("monitors", "-j")))
    assert not ctl("configerrors"), ctl("configerrors")
    taps = chords = 0
    for super_key in ("Super_L", "Super_R"):
        # wtype's modifier flags and physical key events are independent.
        press = ("-M", "logo", "-P", super_key)
        release = ("-p", super_key, "-m", "logo")
        keys(*press, *release)
        taps += 1
        expect(taps, chords)
        print(super_key, "bare tap: PASS", flush=True)
        for key in ("F13", "F14", "Shift_L", "Control_L", "Alt_L"):
            for super_first in (False, True):
                tail = (*release, "-p", key) if super_first else ("-p", key, *release)
                keys(*press, "-P", key, *tail)
                if key == "F13":
                    chords += 1
                expect(taps, chords)
        # A key already held when Super is pressed also disqualifies the tap.
        keys("-P", "F14", *press, "-p", "F14", *release)
        expect(taps, chords)
        # The next clean tap must still work after every cancellation.
        keys(*press, *release)
        taps += 1
        expect(taps, chords)
        print(super_key, "bound/unbound keys, modifiers, both release orders, recovery: PASS", flush=True)
    keys("-M", "logo", "-P", "Super_L", "-P", "Super_R",
         "-p", "Super_R", "-p", "Super_L", "-m", "logo")
    expect(taps, chords)
    # Mouse observers must remain transparent and must not consume app input.
    observers = [b for b in json.loads(ctl("binds", "-j")) if b["key"].startswith("mouse")]
    assert len(observers) == 12, observers
    assert all(b["non_consuming"] for b in observers), observers
    assert not ctl("configerrors")
    print("PASS; isolated compositor logs:", out, flush=True)
finally:
    for proc in reversed(processes):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    for log in logs:
        log.close()
