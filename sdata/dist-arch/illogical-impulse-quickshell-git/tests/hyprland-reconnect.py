#!/usr/bin/env python3
"""Exercise native IPC recovery against private sockets, without a compositor."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time

binary = os.environ.get("QS_TEST_BINARY", "quickshell")
output = Path(tempfile.mkdtemp(prefix="qs-hyprland-reconnect-"))
runtime = output / "runtime"
socket_dir = runtime / "hypr" / "test"
socket_dir.mkdir(parents=True)
runtime.chmod(0o700)
env = os.environ.copy()
for key in ("WAYLAND_DISPLAY", "DISPLAY"):
    env.pop(key, None)
env.update(XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE="test",
           QT_QPA_PLATFORM="offscreen")
state = {"workspace": 1, "address": "0x100"}
requests = []
stopping = threading.Event()


def listen(name):
    path = socket_dir / name
    path.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(path))
    server.listen()
    server.settimeout(.1)
    return server


def serve_requests(server):
    while not stopping.is_set():
        try:
            client, _ = server.accept()
        except socket.timeout:
            continue
        with client:
            request = client.recv(65536).decode()
            requests.append(request)
            workspace = {"id": state["workspace"], "name": str(state["workspace"])}
            window = {"address": state["address"], "workspace": workspace,
                      "monitor": 0, "title": "test", "class": "test", "size": [640, 480]}
            responses = {
                "j/status": {"configProvider": "lua"},
                "j/monitors": [{"id": 0, "name": "TEST-1", "width": 1920,
                                "height": 1080, "scale": 1, "focused": True,
                                "activeWorkspace": workspace}],
                "j/workspaces": [dict(workspace, monitor="TEST-1", monitorID=0)],
                "j/clients": [window] if state["address"] else [],
                "j/activewindow": window if state["address"] else {},
            }
            client.sendall(json.dumps(responses.get(request, {})).encode())


fixture = output / "shell.qml"
fixture.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
ShellRoot {
 property var monitors: Hyprland.monitors.values
 IpcHandler {
  target: "test"
  function state(): string { return JSON.stringify({
   workspace: Hyprland.focusedWorkspace?.id ?? -1,
   workspaces: Hyprland.workspaces.values.map(w=>w.id),
   clients: Hyprland.toplevels.values.map(t=>t.lastIpcObject.address),
   active: Hyprland.activeToplevel?.lastIpcObject.address ?? ""
  }); }
 }
}
''')


def read_state():
    result = subprocess.run([binary, "-p", str(fixture), "ipc", "call", "test", "state"],
                            env=env, capture_output=True, text=True, timeout=2)
    return json.loads(result.stdout)


def until(fn, timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = fn()
            if value:
                return value
        except (socket.timeout, json.JSONDecodeError):
            pass
        time.sleep(.025)
    raise AssertionError("Timed out; see " + str(output))


request_server = listen(".socket.sock")
worker = threading.Thread(target=serve_requests, args=(request_server,), daemon=True)
worker.start()
checks = []
event_server = event_client = process = None
try:
    with (output / "shell.log").open("w") as log:
        process = subprocess.Popen([binary, "-p", str(fixture)], env=env, stdout=log,
                                   stderr=subprocess.STDOUT)
        until(lambda: "j/status" in requests)
        # Listener initially missing: retry must also handle connection failure.
        time.sleep(.6)
        event_server = listen(".socket2.sock")
        event_client, _ = until(lambda: event_server.accept())
        until(lambda: read_state()["workspace"] == 1)
        until(lambda: read_state()["active"] == "0x100")
        checks.append("initially unavailable socket recovers")
        # Leave an incomplete event in the reader and miss destroy/create/focus.
        event_client.sendall(b"workspacev2>>99,unfinished")
        time.sleep(.1)
        state.update(workspace=3, address="0x200")
        event_client.close()
        event_client, _ = until(lambda: event_server.accept())
        until(lambda: read_state() == {"workspace": 3, "workspaces": [3],
                                      "clients": ["0x200"], "active": "0x200"})
        checks.append("disconnect reconciles focus and removes missed windows/workspaces")
        event_client.sendall(b"workspacev2>>4,4\n")
        until(lambda: read_state()["workspace"] == 4)
        checks.append("partial old event discarded and new events delivered")
        for workspace in (5, 6, 7):
            state.update(workspace=workspace, address="")
            event_client.close()
            event_client, _ = until(lambda: event_server.accept())
            until(lambda: read_state()["workspace"] == workspace)
            until(lambda: read_state()["clients"] == [] and read_state()["active"] == "")
        checks.append("repeated reconnect and empty active window recover")
        count = len(requests)
        time.sleep(.6)
        assert len(requests) == count, "unexpected periodic snapshot polling"
        checks.append("healthy connection does not poll snapshots")
        print(json.dumps({"checks": checks, "output": str(output)}, indent=2))
finally:
    if process:
        process.terminate()
        process.wait(timeout=5)
    if event_client:
        event_client.close()
    if event_server:
        event_server.close()
    stopping.set()
    worker.join(timeout=1)
    request_server.close()
