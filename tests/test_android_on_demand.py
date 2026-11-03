import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "dots/.local/bin"
TOOL = BIN / "android-adb-on-demand"
RECONNECT = ROOT / "skills/android-adb-reconnect/scripts/reconnect.py"


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
        fake.write_text("""#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['FAKE_ADB_LOG'],'a') as f:
    f.write(json.dumps({'args':args,'mdns':os.environ.get('ADB_MDNS_AUTO_CONNECT')})+'\\n')
p=Path(os.environ['FAKE_ADB_STATES']); states=json.loads(p.read_text())
if args==['devices']:
    print('List of devices attached')
    for endpoint,state in states.items(): print(endpoint+'\\t'+state)
elif args[0]=='connect':
    if os.environ.get('FAKE_ADB_CONNECT')=='success':
        states[args[1]]='device';p.write_text(json.dumps(states));print('connected to '+args[1])
    else: print('failed to connect to '+args[1]);raise SystemExit(1)
elif args[0]=='disconnect':
    states.pop(args[1],None);p.write_text(json.dumps(states));print('disconnected')
else: raise SystemExit('Unexpected ADB action: '+repr(args))
""")
        fake.chmod(0o755)
        self.env = {**os.environ, "PATH": str(self.base) + os.pathsep + os.environ["PATH"],
                    "ANDROID_ADB_BINARY": str(fake), "ANDROID_ADB_DEMAND_TOOL": str(TOOL),
                    "ADB_KNOWN_ENDPOINTS_FILE": str(self.known), "XDG_RUNTIME_DIR": str(self.base),
                    "FAKE_ADB_LOG": str(self.log), "FAKE_ADB_STATES": str(self.states)}

    def tearDown(self):
        self.directory.cleanup()

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def invoke(self, tool, *args):
        return subprocess.run([str(tool), *args], capture_output=True, text=True, env=self.env, timeout=5)

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
        for arguments in [("--device", "unknown"), ("--endpoint", "host:65536"), ("--endpoint", "-bad:7777")]:
            self.assertNotEqual(self.invoke(TOOL, "connect", "--now", *arguments).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_explicit_device_selects_only_requested_phone_once(self):
        self.env["FAKE_ADB_CONNECT"] = "success"
        self.assertEqual(self.invoke(TOOL, "connect", "--now", "--device", "fe").returncode, 0)
        self.assertEqual(self.calls(), [{"args": ["connect", "100.64.0.10:7777"], "mdns": "0"}])

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


if __name__ == "__main__":
    unittest.main()
