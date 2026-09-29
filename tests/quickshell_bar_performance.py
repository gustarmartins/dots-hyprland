#!/usr/bin/env python3
"""Private two-output Wayland comparison of the production resource popup.

Run with dbus-run-session -- python3 tests/quickshell_bar_performance.py.
No windows, input, configuration, or workspaces on the desktop are touched.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="qs-bar-performance-"))
# Hyprland appends a long instance signature; AF_UNIX paths are limited to 108 bytes.
runtime = Path(tempfile.mkdtemp(prefix="qb-"))
env = os.environ.copy()
for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
    env.pop(key, None)
env.update(HOME=str(OUT / "home"), XDG_CONFIG_HOME=str(OUT / "config"),
           XDG_DATA_HOME=str(OUT / "data"), XDG_CACHE_HOME=str(OUT / "cache"),
           XDG_STATE_HOME=str(OUT / "state"), XDG_RUNTIME_DIR=str(runtime),
           QT_QPA_PLATFORM="offscreen", AQ_DRM_DEVICES="/nonexistent-test-device",
           QT_NO_XDG_DESKTOP_PORTAL="1", NO_AT_BRIDGE="1", XDG_CURRENT_DESKTOP="")
processes, logs = [], []
binary = os.environ.get("QS_TEST_BINARY", "qs")


def launch(args, name):
    log = (OUT / (name + ".log")).open("w")
    logs.append(log)
    p = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
    processes.append(p)
    return p


def until(fn, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            result = fn()
            if result:
                return result
        except (json.JSONDecodeError, subprocess.CalledProcessError):
            pass
        time.sleep(.025)
    raise AssertionError("Timed out; logs: " + str(OUT))


def stop(p):
    if p.poll() is None:
        p.terminate()
        p.wait(timeout=6)


fixture = '''//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.ii.bar
import qs.services
ShellRoot {
 id: root
 property bool shown: false
 property int created: 0
 property int heartbeat: 0
 property real lastBeat: Date.now()
 property real maxGap: 0
 property var panels: []
 Timer { interval: 16; repeat: true; running: true; onTriggered: {
  let now = Date.now(); root.maxGap = Math.max(root.maxGap, now-root.lastBeat);
  root.lastBeat = now; root.heartbeat++;
 } }
 Variants {
  model: Quickshell.screens
  PanelWindow {
   id: panel
   required property var modelData
   screen: modelData
   property alias popup: popup
   anchors { bottom: true; left: true; right: true }
   implicitHeight: 45
   color: "#202028"
   Item {
    id: target
    x: 200; width: 250; height: 45
    property bool containsMouse: root.shown
    Resources { anchors.fill: parent }
   }
   ResourcesPopup {
    id: popup
    hoverTarget: target
    onActiveChanged: { if (active) root.created++; }
   }
   Component.onCompleted: root.panels.push(panel)
  }
 }
 IpcHandler {
  target: "test"
  function toggle(show: bool): void { root.maxGap = 0; root.shown = show; }
  function state(): string { return JSON.stringify({
   ready: Config.ready, created:root.created, heartbeat:root.heartbeat, gap:root.maxGap,
   memory:ResourceUsage.memoryTotal, cpu:ResourceUsage.cpuUsage,
   clock:ResourceUsage.cpuMaxClock, gpu:ResourceUsage.vramTotal,
   cpuSamples:ResourceUsage.cpuUsageHistory.length,
   memorySamples:ResourceUsage.memoryUsageHistory.length,
   workspaces:Hyprland.monitors.values.map(m=>m.activeWorkspace?.id),
   popups:root.panels.map(p=>({screen:p.screen.name,loaded:p.popup.active,
    visible:p.popup.active && p.popup.item.visible
        && p.popup.item.contentItem.children.some(i=>i.visible && i.width>0 && i.height>0),
    mapped:p.popup.active && p.popup.item.backingWindowVisible,
    inputEmpty:p.popup.active && p.popup.item.mask.item === null,
    popupScreen:p.popup.active ? p.popup.item.screen.name : ""}))
  }); }
 }
}
'''

try:
    launch(["kwin_wayland", "--virtual", "--width", "1920", "--height", "1080",
            "--no-lockscreen", "--no-global-shortcuts", "--no-kactivities",
            "--socket", "test-parent"], "kwin")
    until(lambda: (runtime / "test-parent").exists())
    env.update(WAYLAND_DISPLAY="test-parent", QT_QPA_PLATFORM="wayland")
    config = OUT / "hyprland.lua"
    config.write_text('hl.monitor({output="",mode="1920x1080@60",position="auto",scale=1})\n'
                      'hl.config({animations={enabled=false},misc={disable_hyprland_logo=true,disable_splash_rendering=true}})\n')
    launch(["Hyprland", "--config", str(config)], "hyprland")
    socket_path = until(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None))
    env["HYPRLAND_INSTANCE_SIGNATURE"] = socket_path.parent.name
    env["WAYLAND_DISPLAY"] = until(lambda: next((p.name for p in runtime.glob("wayland-*")
                                               if not p.name.endswith(".lock")), None))

    def ctl(*args):
        return subprocess.check_output(["hyprctl", *args], env=env, text=True, timeout=5)

    until(lambda: json.loads(ctl("-j", "monitors")))
    ctl("output", "create", "headless")
    until(lambda: len(json.loads(ctl("-j", "monitors"))) == 2)
    settings = OUT / "config/illogical-impulse/config.json"
    settings.parent.mkdir(parents=True)
    settings.write_text(json.dumps({"bar":{"bottom":True}, "resources":{"updateInterval":300}}))
    results = {}
    for variant in ("before", "after"):
        shell = OUT / variant / "ii"
        shutil.copytree(REPO / "dots/.config/quickshell/ii", shell)
        if variant == "before":
            for path in ("modules/ii/bar/StyledPopup.qml", "services/ResourceUsage.qml"):
                (shell / path).write_bytes(subprocess.check_output(
                    ["git", "show", "HEAD:dots/.config/quickshell/ii/" + path], cwd=REPO))
        qml = shell / "performance.qml"
        qml.write_text(fixture)

        def call(*args):
            return subprocess.check_output([binary, "-p", str(qml), "ipc", "call", "test", *args],
                                           env=env, text=True, stderr=subprocess.DEVNULL, timeout=12).strip()

        def state():
            return json.loads(call("state"))

        process = launch([binary, "-p", str(qml)], "shell-" + variant)
        until(lambda: state()["ready"] and len(state()["popups"]) == 2)
        samples = []
        for i in range(8):
            for show in (True, False):
                start = time.monotonic()
                call("toggle", str(show).lower())
                s = until(lambda: (s if all(p["visible"] == show for p in s["popups"]) else None)
                          if (s := state()) else None)
                elapsed = (time.monotonic()-start)*1000
                time.sleep(.12)
                s = state()
                samples.append({"show":show,"ms":round(elapsed,2),"gap":s["gap"]})
                if show and i == 0:
                    subprocess.run(["grim", str(OUT / (variant + ".png"))], env=env, check=True, timeout=10)
        final = state()
        if variant == "after":
            assert final["created"] == 2, final
            assert all(p["loaded"] and p["mapped"] and p["inputEmpty"] and not p["visible"] and p["screen"] == p["popupScreen"]
                       for p in final["popups"]), final
            assert final["memory"] > 1000000 and final["cpuSamples"] > 0, final
            assert final["clock"] > 0 and final["gpu"] > 1, final
            ctl("dispatch", "hl.dsp.focus({workspace=3})")
            until(lambda: 3 in state()["workspaces"])
        results[variant] = {"samples":samples,"final":final}
        stop(process)
    (OUT / "results.json").write_text(json.dumps(results, indent=2))
    print(json.dumps({"output":str(OUT),"results":results}, indent=2))
finally:
    for process in reversed(processes):
        stop(process)
    for log in logs:
        log.close()
