#!/usr/bin/env python3
"""Planner, account isolation, configuration roundtrip, and race regressions."""
import importlib.machinery
import importlib.util
import contextlib
import json
import os
from pathlib import Path
import sqlite3
import socket
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("codex_notify", str(REPO / "dots/.local/bin/codex-notify"))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
IDENT = "00000000-1111-2222-3333-444444444444"


class Notifications(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "account with spaces"
        self.home.mkdir()
        self.config = self.home / "config.toml"
        self.config.write_text('# Keep my comment\nmodel="keep-model"\n[tui]\nanimations=true\n[features]\nkeep_me=true\n')
        self.workspace = self.base / 'workspace with $(literal) and "quotes"'
        self.workspace.mkdir()
        self.rollout = self.base / "saved.jsonl"
        self.rollout.write_text("not read by this integration\n")
        with contextlib.closing(sqlite3.connect(self.home / "state_5.sqlite")) as db:
            db.execute("CREATE TABLE threads(id,cwd,name,model,reasoning_effort,archived,rollout_path,agent_path)")
            db.execute("INSERT INTO threads VALUES(?,?,?,?,?,?,?,?)", (IDENT, str(self.workspace), "Fixture", "saved-model", "high", 0, str(self.rollout), "/root"))
            db.commit()
        self.addCleanup(patch.stopall)
        patch.object(mod, "STATE", self.base / "state").start()
        patch.object(mod, "CONFIG", self.base / "config.json").start()
        self.cfg = {"enabled": True, "focus": True, "reopen": True}
        self.row = mod.metadata(self.home, IDENT)
        self.snap = {"rows": {}, "writers": [], "windows": [], "panes": [], "clients": [], "viewers": []}

    def writer(self, exclusive=True):
        writer = {"pid": 10, "ppid": 20, "start": 1, "comm": "codex", "exclusive": exclusive, "tty":123}
        self.snap["writers"] = [writer]
        self.snap["rows"] = {10: writer, 20: {"pid": 20, "ppid": 30, "comm":"zsh"}, 30: {"pid": 30, "ppid": 1,"comm":"kitty"}}

    def test_config_roundtrip_preserves_other_settings_and_comments(self):
        before = self.config.read_text()
        mod.configure(True, self.home)
        enabled = mod.tomllib.loads(self.config.read_text())
        self.assertEqual(enabled["tui"]["notifications"], ["approval-requested"])
        self.assertEqual(enabled["model"], "keep-model")
        mod.configure(True, self.home)  # Idempotent; don't save our own hook as previous.
        mod.configure(False, self.home)
        self.assertEqual(mod.tomllib.loads(before), mod.tomllib.loads(self.config.read_text()))
        self.assertIn("# Keep my comment", self.config.read_text())

    def test_existing_notify_and_notification_filter_restore(self):
        self.config.write_text('notify=["my-helper","a b"]\n[tui]\nnotifications=["agent-turn-complete","approval-requested"]\n')
        before = mod.tomllib.loads(self.config.read_text())
        mod.configure(True, self.home)
        self.assertEqual(mod.settings()["installation"]["notify"], ["my-helper", "a b"])
        mod.configure(False, self.home)
        self.assertEqual(mod.tomllib.loads(self.config.read_text()), before)

    def test_concurrent_config_changes_are_preserved(self):
        mod.configure(True, self.home)
        self.config.write_text('notify=["new-owner"]\n[tui]\nnotifications=false\n')
        with self.assertRaisesRegex(ValueError, "changed"):
            mod.configure(False, self.home)
        self.assertIn('notify=["new-owner"]', self.config.read_text())

    def test_token_is_account_specific_and_survives_service_restart(self):
        token, _ = mod.register(self.home, IDENT)
        self.assertEqual(mod.load_route(token)[1]["id"], IDENT)
        self.assertNotEqual(token, mod.token_for(self.base / "other-account", IDENT))
        with self.assertRaises(ValueError):
            mod.load_route("../../config")

    def test_missing_or_corrupted_route_is_not_guessed(self):
        token, _ = mod.register(self.home, IDENT)
        route = mod.route_path(token)
        route.write_text(json.dumps({"version": 1, "home": str(self.home), "id": "00000000-1111-2222-3333-555555555555"}))
        with self.assertRaises(ValueError):
            mod.load_route(token)

    def test_stopped_session_resumes_exact_id_and_original_settings(self):
        self.assertEqual(mod.plan(self.row, self.snap, self.cfg)["kind"], "resume")
        argv = mod.resume_argv(self.row)
        self.assertIn(IDENT, argv)
        self.assertIn(str(self.workspace), argv)
        self.assertIn("saved-model", argv)
        self.assertNotIn("--last", argv)
        self.assertNotIn("fork", argv)

    def test_direct_terminal_uses_writer_ancestry(self):
        self.writer()
        self.snap["windows"] = [{"pid": 20, "id": 4, "socket": "unix:test"}]
        result = mod.plan(self.row, self.snap, self.cfg)
        self.assertEqual(result["kind"], "focus")
        self.assertEqual(result["window"]["id"], 4)

    def test_detached_tmux_attaches_instead_of_resuming(self):
        self.writer()
        self.snap["panes"] = [{"pid": 20, "session": "$1", "pane": "%2", "window": "@3", "socket": "/tmp/private"}]
        self.assertEqual(mod.plan(self.row, self.snap, self.cfg)["kind"], "attach-tmux")

    def test_tmux_attached_to_kitty_focuses_its_exact_pane(self):
        self.writer()
        self.snap["rows"].update({40: {"pid": 40, "ppid": 50,"comm":"tmux"}, 50: {"pid": 50, "ppid": 1,"comm":"kitty"}})
        self.snap["panes"] = [{"pid": 20, "session": "$1", "pane": "%2", "window": "@3", "socket": "/tmp/private"}]
        self.snap["clients"] = [{"pid": 40, "session": "$1", "socket": "/tmp/private"}]
        self.snap["windows"] = [{"pid": 50, "id": 7, "socket": "unix:test"}]
        result = mod.plan(self.row, self.snap, self.cfg)
        self.assertEqual((result["kind"], result["pane"]["pane"], result["window"]["id"]), ("focus", "%2", 7))

    def test_shared_server_inherited_kitty_is_not_misattributed(self):
        self.writer(exclusive=False)
        self.snap["windows"] = [{"pid": 20, "id": 4, "socket": "unix:test"}]
        self.assertEqual(mod.plan(self.row, self.snap, self.cfg)["kind"], "await-background")

    def test_headless_writer_is_never_resumed_twice(self):
        self.writer()
        self.snap["writers"][0]["tty"] = 0
        self.assertEqual(mod.plan(self.row, self.snap, self.cfg)["kind"], "await-background")

    def test_headless_nested_job_does_not_focus_the_outer_terminal(self):
        self.writer()
        self.snap["writers"][0]["tty"] = 0
        self.snap["windows"] = [{"pid":20,"id":8,"socket":"unix:outer"}]
        self.assertEqual(mod.plan(self.row, self.snap, self.cfg)["kind"], "await-background")

    def test_nested_terminal_chooses_the_nearest_window(self):
        self.writer()
        self.snap["windows"] = [{"pid":10,"id":9,"socket":"unix:inner"},{"pid":20,"id":8,"socket":"unix:outer"}]
        self.assertEqual(mod.plan(self.row, self.snap, self.cfg)["window"]["id"], 9)

    def test_duplicate_writers_are_not_guessed(self):
        self.writer()
        self.snap["writers"].append(dict(self.snap["writers"][0], pid=99))
        with self.assertRaisesRegex(ValueError, "Multiple"):
            mod.plan(self.row, self.snap, self.cfg)

    def test_renamed_tmux_names_and_reused_pid_do_not_override_ownership(self):
        self.snap["panes"] = [{"pid": 20, "session": "$1", "pane": "%2", "window": "@3", "socket": "/tmp/private", "name": "Old codex name"}]
        self.snap["windows"] = [{"pid": 20, "id": 4, "socket": "unix:test"}]
        self.assertEqual(mod.plan(self.row, self.snap, self.cfg)["kind"], "resume")

    def test_missing_workspace_transcript_archived_and_subagent_fail_clearly(self):
        for key, value in [("cwd", "/missing-workspace"), ("rollout_path", "/missing-rollout"), ("archived", 1), ("agent_path", "/root/child")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                mod.plan(dict(self.row, **{key: value}), self.snap, self.cfg)

    def test_feature_controls_prevent_focus_or_new_windows(self):
        with self.assertRaises(ValueError):
            mod.plan(self.row, self.snap, dict(self.cfg, reopen=False))
        self.writer()
        self.snap["windows"] = [{"pid": 20, "id": 4, "socket": "unix:test"}]
        with self.assertRaises(ValueError):
            mod.plan(self.row, self.snap, dict(self.cfg, focus=False))

    def test_resume_environment_cannot_inherit_another_thread_or_account_token(self):
        with patch.dict(os.environ, {"CODEX_THREAD_ID": IDENT, "OPENAI_API_KEY": "fixture-key", "TMUX": "old", "KITTY_WINDOW_ID": "7"}):
            env = mod.clean_env(self.home)
        self.assertEqual(env["CODEX_HOME"], str(self.home))
        self.assertFalse(set(env) & {"CODEX_THREAD_ID", "OPENAI_API_KEY", "TMUX", "KITTY_WINDOW_ID"})

    def test_server_attachment_checks_the_actual_unix_peer_pid(self):
        path = self.base / "server.sock"
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(path))
            listener.listen()
            argv = b"codex\0app-server\0--listen\0unix://" + os.fsencode(path) + b"\0"
            with patch.object(Path, "read_bytes", return_value=argv):
                self.assertEqual(mod.server_endpoint({"pid": os.getpid()}, self.home), "unix://" + str(path))
                self.assertIsNone(mod.server_endpoint({"pid": os.getpid() + 100000}, self.home))

    def test_markdown_emphasis_lists_and_literal_code(self):
        output = mod.format_message("***Ready*** and **bold** and *italic*\n\n- First\n- Second\n\n`a_b **literal** <tag>`\n\n```sh\necho '<tag>'\necho '**literal**'\n```")
        self.assertIn("<em><strong>Ready</strong></em>", output)
        self.assertIn("<strong>bold</strong>", output)
        self.assertIn("<em>italic</em>", output)
        self.assertIn("<ul><li>First</li><li>Second</li></ul>", output)
        self.assertIn('a_b **literal** &lt;tag&gt;</font>', output)
        self.assertIn("<pre>echo &#x27;&lt;tag&gt;&#x27;\necho &#x27;**literal**&#x27;</pre>", output)

    def test_markdown_preserves_entities_and_escapes_raw_html_without_fetching_images(self):
        output = mod.format_message('<img src="file:///secret"> & literal &amp;\n\n![caption](https://example.com/image.png)\n\n[docs](https://example.com?a=1&b=2)')
        self.assertNotIn("<img", output)
        self.assertIn("&lt;img", output)
        self.assertIn("caption", output)
        self.assertNotIn("https://example.com/image.png", output)
        self.assertIn('<a href="https://example.com?a=1&amp;b=2">docs</a>', output)


if __name__ == "__main__":
    unittest.main()
