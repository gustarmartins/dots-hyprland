"""One foreground request, one private ADB server, one disposable systemd cgroup."""
import json
import math
import os
from pathlib import Path
import select
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid


ISOLATION = {"ADB_MDNS": "0", "ADB_MDNS_AUTO_CONNECT": "0", "ADB_USB": "0", "ADB_EMU": "0"}


def process_birth(pid):
    return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]


def host_request(path, command):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(0.25)
        client.connect(str(path))
        body = command.encode()
        client.sendall(f"{len(body):04x}".encode() + body)
        reply = b""
        while len(reply) < 4:
            part = client.recv(4 - len(reply))
            if not part:
                break
            reply += part
        return reply == b"OKAY"


SHIM = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
config=json.loads((Path(__file__).resolve().parent/'route.json').read_text())
args=sys.argv[1:]
allowed=set(config['endpoints'])
index=0
while index<len(args):
    value=args[index]
    if value in ('-H','-P','-L','-a') or any(value.startswith(k) and value!=k for k in ('-H','-P','-L')):
        raise SystemExit('ADB scope refuses a server-routing override')
    if value in ('-s','-t'):
        if index+1>=len(args):raise SystemExit('Missing ADB selector')
        if value=='-s' and args[index+1] not in allowed:raise SystemExit('ADB scope refuses another device')
        index+=2;continue
    if value.startswith('-s') and value!='-s':
        if value[2:] not in allowed:raise SystemExit('ADB scope refuses another device')
        index+=1;continue
    if value in ('-d','-e'):raise SystemExit('USB and emulator selection are outside this network operation')
    if value in ('--one-device','--exit-on-write-error'):
        if value=='--one-device':raise SystemExit('ADB server lifecycle is outside this operation')
        index+=1;continue
    if value.startswith('-') and value not in ('--help','--version'):
        raise SystemExit('Unknown global ADB option in private operation: '+value)
    command=value;tail=args[index+1:]
    if command in ('kill-server','start-server','server','nodaemon','fork-server','attach','detach','pair','mdns'):
        raise SystemExit('ADB server lifecycle, discovery and pairing are outside this operation')
    if command in ('connect','disconnect') and (not tail or len(tail)!=1 or tail[0] not in allowed):
        raise SystemExit('ADB scope requires its exact endpoint')
    if command.startswith('wait-for-') and tail:
        index+=1;continue
    if command=='reconnect' and tail not in ([],['offline']):
        raise SystemExit('Unsupported reconnect target')
    break
os.environ['ADB_SERVER_SOCKET']=config['socket']
os.environ.pop('ANDROID_ADB_SERVER_PORT',None)
os.environ['ADB_MDNS']='0';os.environ['ADB_MDNS_AUTO_CONNECT']='0'
os.environ['ADB_USB']='0';os.environ['ADB_EMU']='0'
os.execv(config['adb'],[config['adb'],*args])
'''


def cgroup_is_empty(group, root=Path("/sys/fs/cgroup")):
    path = root / group.lstrip("/")
    try:
        path.stat()
    except FileNotFoundError:
        return True
    try:
        events = dict(line.split() for line in (path / "cgroup.events").read_text().splitlines())
        return events.get("populated") == "0" and not (path / "cgroup.procs").read_text().strip()
    except (OSError, ValueError):
        return False


def retirement_verified(stop, state, lease, unit, empty_reader=cgroup_is_empty):
    fields = dict(line.split("=", 1) for line in state.stdout.splitlines() if "=" in line)
    if state.returncode != 0 or fields.get("ActiveState") not in ("inactive", "failed"):
        return False
    if fields.get("ControlGroup") != "":
        return False
    absent = fields.get("LoadState") == "not-found"
    if stop.returncode != 0 and not absent:
        return False
    if not lease:
        # The worker records its cgroup before it can start ADB. An absent unit
        # with no lease never reached that point; there is no owned transport.
        return absent
    group = lease.get("cgroup", "")
    if (lease.get("unit") != unit or not group.startswith("/user.slice/")
            or not group.endswith("/" + unit) or ".." in group.split("/")):
        return False
    try:
        return empty_reader(group)
    except OSError:
        return False


class ScopeStopped(Exception):
    def __init__(self, code):
        self.code = code


def check_owner(owner_fd, deadline):
    if select.select([owner_fd], [], [], 0)[0]:
        raise ScopeStopped(125)
    if time.monotonic() >= deadline:
        raise ScopeStopped(124)


def run_child(argv, env, owner_fd, deadline, capture=False):
    """Use pidfds, never kill a recycled PID/process group. systemd owns cleanup."""
    check_owner(owner_fd, deadline)
    process = subprocess.Popen(argv, env=env, stdout=subprocess.PIPE if capture else None,
                               stderr=subprocess.PIPE if capture else None, text=True)
    with os.fdopen(os.pidfd_open(process.pid), "rb", buffering=0) as child_fd:
        ready, _, _ = select.select([owner_fd, child_fd], [], [], max(0, deadline - time.monotonic()))
        check_owner(owner_fd, deadline)
        if child_fd not in ready:
            raise ScopeStopped(124)
        if capture:
            stdout, stderr = process.communicate(timeout=1)
            return subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)
        return process.wait()


def worker(directory):
    base = Path(directory)
    config = json.loads((base / "request.json").read_text())
    (base / "request.json").unlink()  # Do not retain a copy of the caller's environment.
    # This process must be in the exact transient service, not run as a loose child.
    cgroup = Path("/proc/self/cgroup").read_text()
    group = next((line[3:] for line in cgroup.splitlines() if line.startswith("0::")), "")
    expected_user = f"/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service/"
    if not group.startswith(expected_user) or not group.endswith("/" + config["unit"]) or ".." in group.split("/"):
        raise RuntimeError("Private ADB worker requires its exact disposable systemd service")
    (base / "lease.json").write_text(json.dumps({"unit": config["unit"], "cgroup": group}))
    owner = config["owner_pid"]
    try:
        owner_fd = os.pidfd_open(owner)
        if process_birth(owner) != config["owner_birth"]:
            os.close(owner_fd)
            return 125
    except ProcessLookupError:
        return 125
    deadline = config["deadline"]
    socket_path = base / "server.sock"
    specification = f"localfilesystem:{socket_path}"
    env = {**config["environment"], **ISOLATION,
           "ADB_SERVER_SOCKET": specification, "ANDROID_ADB_SCOPE_SOCKET": specification,
           "ANDROID_ADB_SCOPE_UNIT": config["unit"],
           "ANDROID_ADB_SCOPE_MODULE": str(Path(__file__).resolve()),
           "ANDROID_ADB_BINARY": str(base / "adb"),
           "PATH": str(base) + os.pathsep + config["environment"].get("PATH", "")}
    env.pop("ANDROID_ADB_SERVER_PORT", None)
    env.pop("ADB_TRACE", None)
    if len(config["endpoints"]) == 1:
        env["ANDROID_SERIAL"] = config["endpoints"][0]
    else:
        env.pop("ANDROID_SERIAL", None)
    (base / "route.json").write_text(json.dumps({"adb": config["adb"], "socket": specification,
                                                "endpoints": config["endpoints"]}))
    shim = base / "adb"
    shim.write_text(SHIM)
    shim.chmod(0o700)
    server = None
    try:
        check_owner(owner_fd, deadline)
        server = subprocess.Popen([config["adb"], "-L", specification, "server", "nodaemon"],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, env=env)
        startup = min(deadline, time.monotonic() + 5)
        ready = False
        while time.monotonic() < startup and server.poll() is None:
            check_owner(owner_fd, deadline)
            try:
                ready = host_request(socket_path, "host:version")
            except OSError:
                pass
            if ready:
                break
            select.select([owner_fd], [], [], 0.025)
        if not ready:
            raise RuntimeError("Private ADB server did not become ready")
        failed = False
        if config["connect_first"]:
            for endpoint in config["endpoints"]:
                result = run_child([str(shim), "connect", endpoint], env, owner_fd,
                                   min(deadline, time.monotonic() + config["connect_timeout"]), True)
                message = result.stdout.strip()
                accepted = result.returncode == 0 and message in (f"connected to {endpoint}", f"already connected to {endpoint}")
                print(json.dumps({"endpoint": endpoint, "transport_connected_during_operation": accepted,
                                  "returncode": result.returncode, "message": message[:2048],
                                  "stderr": result.stderr.strip()[:2048], "device_identity_verified": False}),
                      file=sys.stderr if config["command"] else sys.stdout, flush=True)
                failed |= not accepted
        if failed:
            return 1
        if not config["command"]:
            return 0
        return run_child(config["command"], env, owner_fd, deadline)
    except ScopeStopped as stopped:
        return stopped.code
    finally:
        # Only this operation's private socket. Any server the SDK auto-replaced is
        # in the same service cgroup and is also retired by KillMode=control-group.
        try:
            host_request(socket_path, "host:kill")
        except OSError:
            pass
        os.close(owner_fd)


def execute(endpoints, seconds, connect_timeout, command=(), connect_first=True):
    if not math.isfinite(seconds) or not 0 < seconds <= 3600:
        raise ValueError("Operation duration must be finite, greater than zero and at most 3600 seconds")
    if os.environ.get("ANDROID_ADB_SCOPE_SOCKET"):
        raise RuntimeError("Already inside an on-demand operation; use its adb route directly")
    runtime = Path(f"/run/user/{os.getuid()}")
    if not runtime.is_dir() or runtime.stat().st_uid != os.getuid():
        raise RuntimeError("A local systemd user runtime is required; refusing a shared-server fallback")
    adb = shutil.which(os.environ.get("ANDROID_ADB_BINARY", "adb"))
    if not adb:
        raise RuntimeError("ADB binary not found")
    name = "android-demand-" + uuid.uuid4().hex
    unit = name + ".service"
    base = runtime / name
    base.mkdir(mode=0o700)
    identity = base.stat()
    config = {"unit": unit, "adb": str(Path(adb).resolve()), "endpoints": list(endpoints),
              "command": list(command), "connect_first": connect_first, "connect_timeout": connect_timeout,
              "environment": dict(os.environ), "owner_pid": os.getpid(), "owner_birth": process_birth(os.getpid()),
              "deadline": time.monotonic() + seconds}
    request = base / "request.json"
    request.write_text(json.dumps(config))
    request.chmod(0o600)
    lease_file = (base / "lease.json").open("w+b")
    os.chmod(base / "lease.json", 0o600)
    argv = ["systemd-run", "--user", "--wait", "--pipe", "--quiet", "--collect",
            "--expand-environment=no", f"--unit={unit}", "--service-type=exec",
            "--property=KillMode=control-group", f"--property=RuntimeMaxSec={seconds + 2}",
            "--property=TimeoutStopSec=2", "--property=SendSIGKILL=yes", "--property=UMask=0077",
            f"--property=RuntimeDirectory={name}", "--property=RuntimeDirectoryMode=0700",
            f"--working-directory={os.getcwd()}", sys.executable, str(Path(__file__).resolve()), "worker", str(base)]
    # systemd-run must find this user's bus even when a caller uses a separate test/runtime directory.
    manager_env = {**os.environ, "XDG_RUNTIME_DIR": str(runtime)}
    runner = None
    interrupted = None
    old_handlers = {}
    def cancel(signum, _frame):
        raise ScopeStopped(128 + signum)
    try:
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            old_handlers[signum] = signal.signal(signum, cancel)
        runner = subprocess.Popen(argv, env=manager_env)
        try:
            code = runner.wait(timeout=seconds + 8)
        except subprocess.TimeoutExpired:
            code = 124
    except ScopeStopped as stopped:
        interrupted = stopped.code
        code = stopped.code
    finally:
        # Stop only the unpredictable unique unit created by this invocation.
        # No shared ADB-server stop, USB enumeration or device request occurs here.
        for signum in old_handlers:
            signal.signal(signum, signal.SIG_IGN)
        stop = subprocess.run(["systemctl", "--user", "stop", unit], env=manager_env,
                              capture_output=True, text=True, timeout=5)
        if runner is not None:
            try:
                runner.wait(timeout=5)
            except subprocess.TimeoutExpired:
                runner.terminate()
                runner.wait(timeout=2)
        state = subprocess.run(["systemctl", "--user", "show", unit, "--property=LoadState", "--property=ActiveState", "--property=ControlGroup"],
                               env=manager_env, capture_output=True, text=True, timeout=3)
        lease_file.seek(0)
        try:
            lease = json.loads(lease_file.read() or b"{}")
        except (ValueError, OSError):
            lease = {"invalid": True}
        lease_file.close()
        retired = retirement_verified(stop, state, lease, unit)
        if retired and base.exists():
            current = base.stat()
            if (current.st_dev, current.st_ino) == (identity.st_dev, identity.st_ino):
                shutil.rmtree(base)
        retired = retired and not base.exists()
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)
        print(json.dumps({"on_demand_unit": unit, "owned_transport_retired": retired,
                          "persistent_connection": False if retired else None, "shared_server_control_requested": False,
                          "owned_cgroup": lease.get("cgroup")}), file=sys.stderr, flush=True)
        if not retired:
            raise RuntimeError("Private ADB cleanup could not be confirmed")
    return interrupted if interrupted is not None else code


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "worker":
        raise SystemExit("Internal private-operation worker only")
    try:
        raise SystemExit(worker(sys.argv[2]))
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
