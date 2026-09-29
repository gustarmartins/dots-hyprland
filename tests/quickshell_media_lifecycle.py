#!/usr/bin/env python3
"""Real QML artwork and notification teardown regression on a private X server.

Run: xvfb-run -a dbus-run-session -- python3 tests/quickshell_media_lifecycle.py
Requires Xvfb and Quickshell; QS_TEST_BINARY may select a candidate executable.
Uses private home/cache/runtime directories, without controlling live media.
"""
import base64
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import zlib

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="qs-art-"))
shell = OUT / "ii"
shutil.copytree(REPO / "dots/.config/quickshell/ii", shell)
binary = os.environ.get("QS_TEST_BINARY", "qs")


def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data)))


# A valid one-pixel PNG plus padding exceeds Linux's exec per-argument limit.
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00"))
       + chunk(b"IEND", b"") + bytes(262144))
(shell / "art.json").write_text(json.dumps({
    "url": "data:image/png;base64," + base64.b64encode(png).decode()
}))
(shell / "art-test.qml").write_text('''//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.ii.mediaControls
import qs.modules.common.widgets
ShellRoot {
 id: root
 property string testUrl: ""
 property var notification: ({summary:"test",body:"test",image:"",urgency:1,actions:[],appName:"fixture",notificationId:1})
 FileView { path: Qt.resolvedUrl("art.json"); onLoaded: root.testUrl=JSON.parse(text()).url }
 Item { width: 500; height: 300
  NotificationItem { property int index:0; width:400; notificationObject:root.notification }
  PlayerControl { id: player; anchors.fill: parent; player:null; artUrl:root.testUrl; radius:16 }
 }
 IpcHandler { target:"test"
  function status(): string { return JSON.stringify({length:root.testUrl.length,direct:player.directArt,displayLength:player.displayedArtFilePath.length,downloaded:player.downloaded,path:player.displayedArtFilePath}); }
  function clear(): void { root.testUrl=""; root.notification=null; }
 }
}
''')
env = os.environ.copy()
for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
    env.pop(key, None)
runtime = OUT / "runtime"
runtime.mkdir(mode=0o700)
env.update(HOME=str(OUT), XDG_RUNTIME_DIR=str(runtime),
           XDG_CONFIG_HOME=str(OUT / "config"), XDG_CACHE_HOME=str(OUT / "cache"),
           XDG_STATE_HOME=str(OUT / "state"), XDG_DATA_HOME=str(OUT / "data"),
           QT_QPA_PLATFORM="xcb")
fixture = str(shell / "art-test.qml")


def call(action):
    return subprocess.run([binary, "-p", fixture, "ipc", "call", "test", action],
                          env=env, text=True, capture_output=True,
                          timeout=3, check=True).stdout.strip()


with (OUT / "shell.log").open("w") as log:
    process = subprocess.Popen([binary, "-p", fixture], env=env,
                               stdout=log, stderr=subprocess.STDOUT)
    try:
        end = time.monotonic() + 12
        while time.monotonic() < end:
            try:
                state = json.loads(call("status"))
                if state["length"] > 131072 and state["downloaded"]:
                    break
            except (ValueError, subprocess.CalledProcessError):
                pass
            time.sleep(.05)
        else:
            raise AssertionError("Fixture failed; inspect " + str(OUT))
        assert not state["direct"] and state["displayLength"] < 1024, state
        assert Path(state["path"].removeprefix("file://")).read_bytes() == png
        call("clear")
        cleared = json.loads(call("status"))
        assert cleared["displayLength"] == 0 and not cleared["downloaded"], cleared
        process.terminate()
        process.wait(timeout=4)
        logdata = (OUT / "shell.log").read_text()
        assert not any(error in logdata for error in (
            "Process failed to start", "Failed to load image", "of null"
        )), logdata[-2000:]
        result = {"large_data_url": state, "clear": cleared, "output": str(OUT)}
        (OUT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result))
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=4)
