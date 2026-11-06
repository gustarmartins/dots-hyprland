import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("wake", str(Path(__file__).resolve().parents[1] / "dots/.local/libexec/codex-fe-wake.py"))
wake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wake)


class WakeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = patch.object(wake, "ROOT", Path(self.tmp.name))
        self.root.start()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.root.stop)
        self.config = {"owner_user_id": "123", "known_peer_ids": ["known"],
                       "hostname": "FE", "port": 7777}
        self.snapshot = {"BackendState": "Running", "Peer": {
            "key": {"ID": "known", "UserID": 123, "Online": True,
                    "TailscaleIPs": ["100.64.1.2"]}}}
        self.state = {"enabled": True, "requests": {"thread": {
            "status": "waiting", "not_before": 0, "reason": "pending qualification"}}}

    def run_check(self, **kwargs):
        with patch.object(wake, "terminal_goal", return_value=False), \
             patch.object(wake, "writer_present", return_value=True), \
             patch.object(wake, "resume_native_goal", return_value=True):
            return wake.check(self.state, self.config, snapshot=self.snapshot, **kwargs)

    def test_one_message_per_registration(self):
        calls = []
        def enqueue(tid, message):
            calls.append((tid, message))
            return subprocess.CompletedProcess([], 0, "queued-id", "")
        self.run_check(probe=lambda nodes: nodes[0], enqueue=enqueue)
        self.run_check(probe=lambda nodes: nodes[0], enqueue=enqueue)
        self.assertEqual(len(calls), 1)
        self.assertEqual(self.state["requests"]["thread"]["status"], "woken")
        self.assertIn("neither Android identity nor root", calls[0][1])

    def test_offline_does_not_probe_or_queue(self):
        self.snapshot["Peer"]["key"]["Online"] = False
        with patch.object(wake, "reachable", side_effect=AssertionError):
            result = self.run_check(probe=lambda _: self.fail("offline probe"))
        self.assertFalse(result["reachable"])
        self.assertEqual(self.state["requests"]["thread"]["status"], "waiting")

    def test_tcp_unreachable_keeps_wait_without_model_turn(self):
        self.run_check(probe=lambda nodes: None, enqueue=lambda *_: self.fail("queued"))
        self.assertEqual(self.state["requests"]["thread"]["status"], "waiting")

    def test_disabled_and_no_waiters_do_not_query(self):
        self.state["enabled"] = False
        with patch.object(wake.subprocess, "run", side_effect=AssertionError):
            self.assertFalse(wake.check(self.state, self.config)["checking"])
        self.state["enabled"] = True
        self.state["requests"] = {}
        with patch.object(wake.subprocess, "run", side_effect=AssertionError):
            self.assertFalse(wake.check(self.state, self.config)["checking"])

    def test_timeout_is_uncertain_never_automatically_resent(self):
        calls = []
        def enqueue(*args):
            calls.append(args)
            raise subprocess.TimeoutExpired("queue", 20)
        self.run_check(probe=lambda nodes: nodes[0], enqueue=enqueue)
        self.run_check(probe=lambda nodes: nodes[0], enqueue=enqueue)
        self.assertEqual(len(calls), 1)
        self.assertEqual(self.state["requests"]["thread"]["status"], "queue_outcome_uncertain")

    def test_wrong_owner_not_selected(self):
        self.snapshot["Peer"]["key"]["UserID"] = 999
        self.assertEqual(wake.fe_candidates(self.snapshot, self.config), [])

    def test_saved_lan_candidate_does_not_require_tailscale(self):
        self.config['lan_endpoints'] = ['192.168.0.22:7777']
        candidates = wake.fe_candidates({'BackendState': 'Stopped'}, self.config)
        self.assertEqual(candidates, [{'address': '192.168.0.22', 'port': 7777, 'route': 'lan'}])
        self.assertEqual(wake.fe_candidates(self.snapshot, self.config)[0], candidates[0])

    def test_live_lan_skips_tailscale_and_labels_notification_truthfully(self):
        self.config['lan_endpoints'] = ['192.168.0.22:7777']
        messages = []
        with patch.object(wake, 'terminal_goal', return_value=False), \
             patch.object(wake, 'writer_present', return_value=True), \
             patch.object(wake, 'resume_native_goal', return_value=True), \
             patch.object(wake.subprocess, 'run', side_effect=AssertionError('unneeded Tailscale call')):
            result = wake.check(self.state, self.config, probe=lambda rows: rows[0],
                                enqueue=lambda _, text: messages.append(text) or subprocess.CompletedProcess([], 0, '', ''))
        self.assertTrue(result['reachable'])
        self.assertIn('saved local-network route 192.168.0.22:7777', messages[0])
        self.assertNotIn('advertised online', messages[0])

    def test_offline_lan_uses_tailscale_fallback_without_reprobing_lan(self):
        self.config['lan_endpoints'] = ['192.168.0.22:7777']
        probes = []
        def probe(rows):
            probes.append([row['route'] for row in rows])
            return rows[0] if rows[0]['route'] == 'tailscale' else None
        with patch.object(wake, 'terminal_goal', return_value=False), \
             patch.object(wake, 'writer_present', return_value=True), \
             patch.object(wake, 'resume_native_goal', return_value=True), \
             patch.object(wake.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(self.snapshot), '')):
            result = wake.check(self.state, self.config, probe=probe,
                                enqueue=lambda *_: subprocess.CompletedProcess([], 0, '', ''))
        self.assertTrue(result['reachable'])
        self.assertEqual(probes, [['lan'], ['tailscale']])

    def test_invalid_lan_route_is_not_probed(self):
        for endpoint in ['192.168.0.22:0', '192.168.0.22:65536', '8.8.8.8:7777']:
            self.config['lan_endpoints'] = [endpoint]
            with self.assertRaises(ValueError):
                wake.fe_candidates(self.snapshot, self.config)

    def test_new_fe_registration_selected_without_old_ip(self):
        p = self.snapshot["Peer"]["key"]
        p.update(ID="new", HostName="FE", OS="android")
        self.assertEqual(wake.fe_candidates(self.snapshot, self.config)[0]["peer_id"], "new")

    def test_completed_tasks_not_restarted(self):
        with patch.object(wake, "terminal_goal", return_value=True):
            wake.check(self.state, self.config, snapshot=self.snapshot,
                       probe=lambda nodes: nodes[0], enqueue=lambda *_: self.fail("queued"))
        self.assertEqual(self.state["requests"]["thread"]["status"], "finished")

    def test_missing_writer_no_new_process(self):
        with patch.object(wake, "terminal_goal", return_value=False), \
             patch.object(wake, "writer_present", return_value=False):
            wake.check(self.state, self.config, snapshot=self.snapshot,
                       probe=lambda nodes: nodes[0], enqueue=lambda *_: self.fail("queued"))
        self.assertEqual(self.state["requests"]["thread"]["status"], "waiting")

    def test_completed_task_offline_retires_without_network(self):
        with patch.object(wake, "terminal_goal", return_value=True), \
             patch.object(wake.subprocess, "run", side_effect=AssertionError):
            result = wake.check(self.state, self.config,
                                probe=lambda _: self.fail("unneeded network probe"))
        self.assertEqual(result, {"waiting": 0, "checking": False})
        self.assertEqual(self.state["requests"]["thread"]["status"], "finished")

    def test_failed_goal_resume_does_not_consume_wait(self):
        with patch.object(wake, "terminal_goal", return_value=False), \
             patch.object(wake, "writer_present", return_value=True), \
             patch.object(wake, "resume_native_goal", return_value=False):
            wake.check(self.state, self.config, snapshot=self.snapshot,
                       probe=lambda nodes: nodes[0], enqueue=lambda *_: self.fail("queued"))
        self.assertEqual(self.state["requests"]["thread"]["status"], "waiting")

    def test_uncertain_native_input_not_repeated_or_queued(self):
        self.config['_native_resume_results'] = {'thread': {
            'resumed': False, 'attempted_controls': True,
            'reason': 'Draft restoration unverified'}}
        with patch.object(wake, 'terminal_goal', return_value=False), \
             patch.object(wake, 'writer_present', return_value=True), \
             patch.object(wake, 'resume_native_goal', return_value=False) as resume:
            for _ in range(2):
                wake.check(self.state, self.config, snapshot=self.snapshot,
                           probe=lambda nodes: nodes[0], enqueue=lambda *_: self.fail('queued'))
            self.assertEqual(resume.call_count, 1)
        self.assertTrue(self.state['requests']['thread']['native_resume_review'])

    def test_verified_resume_clears_old_draft_failure(self):
        self.state['requests']['thread']['last_issue'] = 'saved draft preserved'
        self.config['_native_resume_results'] = {'thread': {
            'resumed': True, 'draft_preserved': True, 'receipt': '/private/receipt.json'}}
        self.run_check(probe=lambda nodes: nodes[0],
                       enqueue=lambda *_: subprocess.CompletedProcess([], 0, 'queued-id', ''))
        req = self.state['requests']['thread']
        self.assertNotIn('last_issue', req)
        self.assertTrue(req['native_resume']['draft_preserved'])


if __name__ == "__main__":
    unittest.main()
