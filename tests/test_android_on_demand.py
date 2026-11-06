import json
import importlib.util
import os
from pathlib import Path
import subprocess
import signal
import time
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "dots/.local/bin"
TOOL = BIN / "android-adb-on-demand"
RECONNECT = ROOT / "skills/android-adb-reconnect/scripts/reconnect.py"
_spec = importlib.util.spec_from_file_location("adb_scope", ROOT / "dots/.local/lib/android-on-demand/adb_scope.py")
SCOPE = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(SCOPE)


class AndroidDemandTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="android-demand-test-")
        self.base = Path(self.directory.name)
        self.log = self.base / "calls.jsonl"
        self.states = self.base / "states.json"
        self.states.write_text("{}")
        self.known = self.base / "endpoints"
        self.known.write_text("100.64.0.10:7777|SM-S711B|36\n100.64.0.11:6666|SM-S918B|37\n")
        fake = self.base / "adb"
        fake.write_bytes((ROOT / "tests/fixtures/fake_adb_on_demand.py").read_bytes())
        fake.chmod(0o755)
        self.env = {**os.environ, "PATH": str(self.base) + os.pathsep + os.environ["PATH"],
                    "ANDROID_ADB_BINARY": str(fake), "ANDROID_ADB_DEMAND_TOOL": str(TOOL),
                    "ADB_KNOWN_ENDPOINTS_FILE": str(self.known), "XDG_RUNTIME_DIR": str(self.base),
                    "FAKE_ADB_LOG": str(self.log), "FAKE_ADB_STATES": str(self.states)}

    def tearDown(self):
        for row in self.all_calls():
            if row["event"] != "server": continue
            status = Path(f"/proc/{row['pid']}/status")
            self.assertFalse(status.exists() and "State:\tZ" not in status.read_text(), row)
            self.assertFalse(Path(row["args"][1].removeprefix("localfilesystem:")).parent.exists(), row)
        self.directory.cleanup()

    def all_calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def calls(self):
        return [{"args": row["args"], "mdns": row["environment"]["ADB_MDNS_AUTO_CONNECT"]} for row in self.all_calls() if row["event"] == "client"]

    def invoke(self, tool, *args):
        return subprocess.run([str(tool), *args], capture_output=True, text=True, env=self.env, timeout=12)

    def test_default_is_local_only(self):
        result = self.invoke(TOOL)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["network_requests"], 0)
        self.assertEqual(self.calls(), [])

    def test_help_does_not_contact_adb(self):
        self.assertEqual(self.invoke(TOOL, "--help").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_watch_refuses_before_any_adb_command(self):
        self.assertNotEqual(self.invoke(TOOL, "watch", "--now").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_connect_requires_explicit_now(self):
        self.assertNotEqual(self.invoke(TOOL, "connect", "--endpoint", "100.64.0.10:7777").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_unknown_and_invalid_targets_do_not_send_requests(self):
        for arguments in [("--device", "unknown"), ("--endpoint", "host:65536"), ("--endpoint", "-bad:7777"), ("--max-seconds", "nan"), ("--timeout", "inf")]:
            self.assertNotEqual(self.invoke(TOOL, "connect", "--now", *arguments).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_explicit_device_selects_only_requested_phone_once(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        self.assertEqual(self.invoke(TOOL, "connect", "--now", "--device", "fe").returncode, 0)
        self.assertEqual(self.calls(), [{"args": ["connect", "100.64.0.10:7777"], "mdns": "0"}])

    def test_named_phone_prefers_lan_and_exports_actual_route(self):
        self.known.write_text("100.64.0.10:7777|SM-S711B|36\n192.168.0.22:7777|SM-S711B|36\n")
        self.env["FAKE_ADB_CONNECT"] = "success"
        result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--",
                             "python3", "-c", "import os; print(os.environ['ANDROID_SERIAL'])")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "192.168.0.22:7777")
        self.assertEqual([row["args"] for row in self.calls()], [["connect", "192.168.0.22:7777"]])

    def test_named_phone_falls_back_once_and_runs_body_once(self):
        self.known.write_text("100.64.0.10:7777|SM-S711B|36\n192.168.0.22:7777|SM-S711B|36\n")
        self.env["FAKE_ADB_CONNECT_RESULTS"] = json.dumps({"100.64.0.10:7777": "success"})
        result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--",
                             "python3", "-c", "import os; print(os.environ['ANDROID_SERIAL'])")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "100.64.0.10:7777")
        self.assertEqual([row["args"] for row in self.calls()],
                         [["connect", "192.168.0.22:7777"], ["connect", "100.64.0.10:7777"]])

    def test_lan_timeout_retires_client_then_uses_fallback(self):
        self.known.write_text("192.168.0.22:7777|SM-S711B|36\n100.64.0.10:7777|SM-S711B|36\n")
        self.env["FAKE_ADB_CONNECT_RESULTS"] = json.dumps({"192.168.0.22:7777": "timeout", "100.64.0.10:7777": "success"})
        result = self.invoke(TOOL, "connect", "--now", "--device", "fe", "--timeout", "0.2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([row["args"] for row in self.calls()],
                         [["connect", "192.168.0.22:7777"], ["connect", "100.64.0.10:7777"]])

    def test_no_available_phone_route_does_not_start_body(self):
        self.known.write_text("192.168.0.22:7777|SM-S711B|36\n100.64.0.10:7777|SM-S711B|36\n")
        result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--", "python3", "-c", "print('BODY_STARTED')")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("BODY_STARTED", result.stdout)
        self.assertEqual(len(self.calls()), 2)

    def test_adbc_without_arguments_only_lists_local_records(self):
        self.assertEqual(self.invoke(BIN / "adbc").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_adbc_named_target_is_explicit_one_shot(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        self.assertEqual(self.invoke(BIN / "adbc", "fe").returncode, 0)
        self.assertEqual([row["args"] for row in self.calls()], [["connect", "100.64.0.10:7777"]])

    def test_connect_all_never_restarts_server(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        self.assertEqual(self.invoke(BIN / "adb-connect-all").returncode, 0)
        self.assertEqual([row["args"] for row in self.calls()], [["connect", "100.64.0.10:7777"], ["connect", "100.64.0.11:6666"]])

    def test_background_batch_refused_before_network(self):
        self.assertNotEqual(self.invoke(BIN / "adb-connect-all", "--async").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_reconnect_without_now_is_silent(self):
        self.assertNotEqual(self.invoke(RECONNECT, "--endpoint", "100.64.0.10:7777").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_reconnect_failure_does_not_retry_by_default(self):
        self.assertEqual(self.invoke(RECONNECT, "--now", "--endpoint", "100.64.0.10:7777").returncode, 2)
        self.assertEqual(sum(row["args"][0] == "connect" for row in self.calls()), 1)
        self.assertTrue(all(row["mdns"] == "0" for row in self.calls()))

    def test_reconnect_refuses_nonfinite_timeouts_before_network(self):
        for option, value in [("--deadline", "nan"), ("--interval", "inf")]:
            self.assertNotEqual(self.invoke(RECONNECT, "--now", "--endpoint", "100.64.0.10:7777", option, value).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_reconnect_preserves_route_order_and_stops_on_success(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        self.assertEqual(self.invoke(RECONNECT, "--now", "--endpoint", "192.0.2.1:7777", "--endpoint", "100.64.0.10:7777").returncode, 0)
        self.assertEqual([row["args"] for row in self.calls() if row["args"][0] == "connect"], [["connect", "192.0.2.1:7777"]])

    def test_reconnect_leaves_healthy_and_unauthorized_transports(self):
        for state, expected in [("device", 0), ("unauthorized", 3)]:
            self.states.write_text(json.dumps({"100.64.0.10:7777": state}))
            self.assertEqual(self.invoke(RECONNECT, "--now", "--endpoint", "100.64.0.10:7777").returncode, expected)
        self.assertTrue(all(row["args"] == ["devices"] for row in self.calls()))

    def test_reconnect_disconnects_only_selected_offline_transport(self):
        self.states.write_text(json.dumps({"100.64.0.10:7777": "offline", "100.64.0.11:6666": "device"}))
        self.env["FAKE_ADB_CONNECT"] = "success"
        self.assertEqual(self.invoke(RECONNECT, "--now", "--endpoint", "100.64.0.10:7777").returncode, 0)
        self.assertEqual([row["args"] for row in self.calls() if row["args"][0] == "disconnect"], [["disconnect", "100.64.0.10:7777"]])
        self.assertEqual(json.loads(self.states.read_text())["100.64.0.11:6666"], "device")


    def test_run_inherits_private_socket_and_all_discovery_is_off(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--", "adb", "-s", "100.64.0.10:7777", "shell", "id")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("fake shell id", result.stdout)
        self.assertIn('"owned_transport_retired": true', result.stderr)
        for row in self.all_calls():
            self.assertTrue(row["socket"].startswith("localfilesystem:/run/user/"), row)
            self.assertIn("android-demand-", row["cgroup"])
            self.assertEqual(set(row["environment"].values()), {"0"})

    def test_server_routing_and_other_endpoint_overrides_refuse_before_client(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        cases = [["-P", "5037", "devices"], ["-P5037", "devices"], ["-H", "localhost", "devices"],
                 ["-L", "tcp:5037", "devices"], ["-a", "devices"], ["-s", "100.64.0.11:6666", "shell", "id"],
                 ["connect", "100.64.0.11:6666"], ["disconnect"], ["kill-server"], ["mdns", "services"],
                 ["wait-for-device", "connect", "100.64.0.11:6666"], ["wait-for-device", "kill-server"]]
        for prefix in ("nodaemon", "fork-server"):
            for tail in (["-H", "localhost", "devices"], ["-P", "5037", "devices"], ["-L", "tcp:5037", "devices"],
                         ["-a", "devices"], ["-s", "100.64.0.11:6666", "shell", "id"],
                         ["connect", "100.64.0.11:6666"], ["kill-server"]):
                cases.append([prefix, *tail])
        for args in cases:
            result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--", "adb", *args)
            self.assertNotEqual(result.returncode, 0, args)
        self.assertTrue(all(row["args"] == ["connect", "100.64.0.10:7777"] for row in self.calls()))

    def test_wait_prefix_validates_command_but_preserves_remote_shell_arguments(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--", "adb", "wait-for-device", "shell", "echo", "-P5037")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "fake shell echo -P5037")

    def test_one_scope_finishing_preserves_another_active_scope(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        marker = self.base / "first-ready"
        code = "import time;from pathlib import Path;Path(" + repr(str(marker)) + ").touch();time.sleep(30)"
        process = subprocess.Popen([str(TOOL), "run", "--now", "--device", "fe", "--max-seconds", "30", "--", "python3", "-c", code],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.wait_for_body(marker, process)
        first = next(row for row in self.all_calls() if row['event']=='server')
        try:
            result = self.invoke(TOOL, "connect", "--now", "--device", "ultra")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIsNone(process.poll())
            self.assertTrue(Path(f"/proc/{first['pid']}").exists())
            self.assertTrue(Path(first['args'][1].removeprefix('localfilesystem:')).exists())
        finally:
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=8)

    def test_operation_exit_code_is_preserved(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--", "python3", "-c", "raise SystemExit(7)")
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn('"owned_transport_retired": true', result.stderr)

    def test_hard_deadline_retires_resistant_descendant_and_preserves_unrelated_process(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        survivor = subprocess.Popen(["sleep", "20"])
        pidfile = self.base / "descendant.pid"
        code = "import os,signal,time;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path(" + repr(str(pidfile)) + ").write_text(str(os.getpid()));time.sleep(30)"
        try:
            started = time.monotonic()
            result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--max-seconds", "1", "--", "python3", "-c", code)
            self.assertEqual(result.returncode, 124, result.stderr)
            self.assertLess(time.monotonic() - started, 6)
            self.assertIsNone(survivor.poll())
            self.assertFalse(Path("/proc/" + pidfile.read_text()).exists())
        finally:
            survivor.terminate(); survivor.wait()

    def wait_for_body(self, marker, process):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if marker.exists(): return
            if process.poll() is not None: break
            time.sleep(.02)
        self.fail("Operation body failed to start")

    def test_cancel_retires_private_server(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        marker = self.base / "ready"
        code = "import time;from pathlib import Path;Path(" + repr(str(marker)) + ").touch();time.sleep(30)"
        process = subprocess.Popen([str(TOOL), "run", "--now", "--device", "fe", "--max-seconds", "30", "--", "python3", "-c", code],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.wait_for_body(marker, process)
        process.send_signal(signal.SIGINT)
        _, stderr = process.communicate(timeout=8)
        self.assertEqual(process.returncode, 130, stderr)
        self.assertIn('"owned_transport_retired": true', stderr)

    def test_killed_parent_retires_server_and_daemonized_body(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        marker = self.base / "ready"
        code = "import os,time;from pathlib import Path;os.setsid();Path(" + repr(str(marker)) + ").write_text(str(os.getpid()));time.sleep(30)"
        process = subprocess.Popen([str(TOOL), "run", "--now", "--device", "fe", "--max-seconds", "30", "--", "python3", "-c", code],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.wait_for_body(marker, process)
        process.kill()
        process.communicate(timeout=8)
        deadline = time.monotonic() + 4
        while Path("/proc/" + marker.read_text()).exists() and time.monotonic() < deadline: time.sleep(.02)
        self.assertFalse(Path("/proc/" + marker.read_text()).exists())

    def test_automatic_replacement_server_stays_in_operation_cleanup(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        self.env["FAKE_ADB_AUTO_REPLACE"] = "1"
        code = """import os,socket,subprocess,time
from pathlib import Path
path=os.environ['ADB_SERVER_SOCKET'].removeprefix('localfilesystem:')
with socket.socket(socket.AF_UNIX) as client:
    client.connect(path);client.sendall(b'0009host:kill');client.recv(4)
for _ in range(100):
    if not Path(path).exists():break
    time.sleep(.01)
raise SystemExit(subprocess.call(['adb','devices']))
"""
        result = self.invoke(TOOL, "run", "--now", "--device", "fe", "--", "python3", "-c", code)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len([row for row in self.all_calls() if row["event"] == "server"]), 2)
        self.assertIn('"owned_transport_retired": true', result.stderr)

    def test_failed_manager_queries_and_populated_cgroup_cannot_claim_retirement(self):
        unit = "android-demand-fixture.service"
        lease = {"unit": unit, "cgroup": "/user.slice/user-1000.slice/user@1000.service/app.slice/" + unit}
        ok = subprocess.CompletedProcess([], 0, "", "")
        failed = subprocess.CompletedProcess([], 1, "", "bus unavailable")
        stopped = subprocess.CompletedProcess([], 0, "LoadState=loaded\nActiveState=inactive\nControlGroup=\n", "")
        absent = subprocess.CompletedProcess([], 0, "LoadState=not-found\nActiveState=inactive\nControlGroup=\n", "")
        self.assertFalse(SCOPE.retirement_verified(ok, failed, lease, unit, lambda _: True))
        self.assertFalse(SCOPE.retirement_verified(failed, stopped, lease, unit, lambda _: True))
        self.assertFalse(SCOPE.retirement_verified(ok, stopped, lease, unit, lambda _: False))
        self.assertFalse(SCOPE.retirement_verified(ok, absent, lease, unit, lambda _: False))
        self.assertTrue(SCOPE.retirement_verified(failed, absent, lease, unit, lambda _: True))
        self.assertTrue(SCOPE.retirement_verified(ok, stopped, lease, unit, lambda _: True))

    def test_cgroup_proof_requires_absence_or_empty_population_and_processes(self):
        root = self.base / "cgroups"
        root.mkdir()
        path = root / "owned"
        self.assertTrue(SCOPE.cgroup_is_empty("/owned", root))
        path.mkdir()
        self.assertFalse(SCOPE.cgroup_is_empty("/owned", root))
        (path / "cgroup.events").write_text("populated 1\nfrozen 0\n")
        (path / "cgroup.procs").write_text("123\n")
        self.assertFalse(SCOPE.cgroup_is_empty("/owned", root))
        (path / "cgroup.events").write_text("populated 0\nfrozen 0\n")
        self.assertFalse(SCOPE.cgroup_is_empty("/owned", root))
        (path / "cgroup.procs").write_text("")
        self.assertTrue(SCOPE.cgroup_is_empty("/owned", root))

    def test_startup_failure_cleans_operation(self):
        self.env["FAKE_ADB_START_FAILURE"] = "1"
        result = self.invoke(TOOL, "connect", "--now", "--device", "fe")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('"owned_transport_retired": true', result.stderr)
        self.assertEqual(self.calls(), [])

if __name__ == "__main__":
    unittest.main()
