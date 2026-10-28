#!/usr/bin/env python3
"""Exercise Super taps against a private real Hyprland compositor.

Run: dbus-run-session -- python3 tests/hyprland_super_tap.py
Requires KWin Wayland, Quickshell, wtype and grim. Tests the production Super
bindings and actual Overview.qml, including visible grid and layer creation.
No input is sent to the owner's desktop.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true', help='Reproduce the release-to-onPressed dispatch failure')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
out = Path(tempfile.mkdtemp(prefix="super-tap-test-"))
rt = Path(tempfile.mkdtemp(prefix="st-"))
rt.chmod(0o700)
env = os.environ.copy()
for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
    env.pop(key, None)
env.update(HOME=str(out / "home"), XDG_RUNTIME_DIR=str(rt), XDG_CONFIG_HOME=str(out / "config"),
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


def state():
    result = subprocess.run(["qs", "-c", "ii", "ipc", "call", "test", "state"],
                            env=env, text=True, capture_output=True, timeout=3)
    if result.returncode:
        return None
    return json.loads(result.stdout)


def expect(taps, chords):
    assert ctl("eval", f'assert(chord_count == {chords}, "chords=" .. chord_count)') == "ok"
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        current = state()
        if current and current["changes"] == taps and current["open"] == bool(taps % 2):
            if not current["open"] or current["gridVisible"]:
                break
        time.sleep(.05)
    else:
        raise AssertionError(f"Workspace view did not match taps={taps}: {current}; artifacts: {out}")
    time.sleep(.15)
    assert state()["changes"] == taps, "Unexpected delayed toggle"
    assert current["panelVisible"] == current["open"]
    layers = json.loads(ctl("layers", "-j"))
    mapped = any(layer["namespace"] == "quickshell:overview"
                 for monitor in layers.values() for level in monitor["levels"].values() for layer in level)
    assert mapped == current["open"], ("Overview layer mapping", current)


def keys(*args):
    subprocess.run(["wtype", *args], env=env, check=True, timeout=5)
    time.sleep(0.08)


try:
    launch(["kwin_wayland", "--virtual", "--width", "1280", "--height", "720",
            "--no-lockscreen", "--no-global-shortcuts", "--no-kactivities",
            "--socket", "test-parent"], "kwin")
    until(lambda: (rt / "test-parent").exists())
    env.update(WAYLAND_DISPLAY="test-parent", QT_QPA_PLATFORM="wayland")
    shell = out / "config/quickshell/ii"
    shutil.copytree(repo / "dots/.config/quickshell/ii", shell,
                    ignore=shutil.ignore_patterns("__pycache__", ".git"))
    settings = out / "config/illogical-impulse/config.json"
    settings.parent.mkdir(parents=True)
    settings.write_text(json.dumps({"overview": {"enable": True, "rows": 2, "columns": 4}}))
    directories = shell / "modules/common/Directories.qml"
    directories.write_text(directories.read_text().split('    // Cleanup on init')[0] + '}\n')
    overview = shell / "modules/ii/overview/Overview.qml"
    overview.write_text(overview.read_text().replace('    id: overviewScope',
        '    id: overviewScope\n    property alias testPanel: panelWindow\n    property alias testGrid: overviewLoader', 1))
    (shell / "shell.qml").write_text('''//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.ii.overview
ShellRoot {
 id: root
 property int changes: 0
 Overview { id: overview }
 Connections { target: GlobalStates; function onOverviewOpenChanged() { root.changes++; } }
 IpcHandler {
  target: "test"
  function state(): string {
   const grid=overview.testGrid.item;
   return JSON.stringify({ready:Config.ready,changes:root.changes,open:GlobalStates.overviewOpen,
    panelVisible:overview.testPanel.visible,
    gridVisible:overview.testGrid.active && grid !== null && grid.visible && grid.width > 0 && grid.height > 0,
    gridWidth:grid?.width ?? 0,gridHeight:grid?.height ?? 0,superDown:GlobalStates.superDown});
  }
 }
}
''')
    keybinds = (repo / "dots/.config/hypr/hyprland/keybinds.lua").read_text()
    start = keybinds.index('local qsScripts')
    end = keybinds.index('hl.bind("SUPER + V"', start)
    tap_bindings = keybinds[start:end]
    if args.baseline:
        old_start = tap_bindings.index('require("hyprland.super_tap").bind(function()')
        old_end = tap_bindings.index('\nend)', old_start) + len('\nend)')
        tap_bindings = tap_bindings[:old_start] + '''require("hyprland.super_tap").bind(function()
    hl.dispatch(hl.dsp.global("quickshell:searchToggle"))
end)''' + tap_bindings[old_end:]
    config = out / "hyprland.lua"
    config.write_text('hl.monitor({output="",mode="1280x720@60",position="auto",scale=1})\n'
                      'hl.config({input={resolve_binds_by_sym=true},animations={enabled=false},misc={disable_hyprland_logo=true,disable_splash_rendering=true}})\n'
                      'hl.env("qsConfig", "ii"); chord_count = 0\n'
                      + 'package.path = ' + json.dumps(str(repo / 'dots/.config/hypr/?.lua') + ';') + ' .. package.path\n'
                      + tap_bindings + '\n'
                      + 'hl.bind("SUPER + F13", function() chord_count = chord_count + 1 end)\n')
    launch(["Hyprland", "--config", str(config)], "hyprland")
    sock = until(lambda: next((rt / "hypr").glob("*/.socket.sock"), None))
    env["HYPRLAND_INSTANCE_SIGNATURE"] = sock.parent.name
    env["WAYLAND_DISPLAY"] = until(lambda: next((p.name for p in rt.glob("wayland-*")
                                                if not p.name.endswith(".lock")), None))
    until(lambda: json.loads(ctl("monitors", "-j")))
    assert not ctl("configerrors"), ctl("configerrors")
    launch(["qs", "-c", "ii"], "quickshell")
    until(lambda: (state() or {}).get("ready"))
    taps = chords = 0
    for super_key in ("Super_L", "Super_R"):
        # wtype's modifier flags and physical key events are independent.
        press = ("-M", "logo", "-P", super_key)
        release = ("-p", super_key, "-m", "logo")
        keys(*press, *release)
        taps += 1
        expect(taps, chords)
        assert state()["superDown"] is False, "Workspace-number hint remained held"
        if super_key == "Super_L":
            time.sleep(.4)
            subprocess.run(["grim", str(out / "workspace-view.png")], env=env, check=True, timeout=5)
        print(super_key, "actual workspace view visible: PASS", flush=True)
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
    # Super+Tab must toggle exactly once, with no second toggle on release.
    for _ in range(2):
        keys("-M", "logo", "-P", "Super_L", "-k", "Tab", "-p", "Super_L", "-m", "logo")
        taps += 1
        expect(taps, chords)
    print("Super+Tab actual view open/close without a release toggle: PASS", flush=True)
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
