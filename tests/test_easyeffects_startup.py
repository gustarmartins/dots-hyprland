"""Startup regression checks; no live audio or session bus is contacted."""
import os
import runpy
import subprocess
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


HELPER = Path(__file__).resolve().parents[1] / 'dots/.local/bin/easyeffects-qs'


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.api = runpy.run_path(str(HELPER))
        self.ns = self.api['start'].__globals__
        self.ns['RUNTIME'] = self.root / 'runtime'
        self.ns['DATA'] = self.root / 'data/easyeffects'
        self.ns['CONFIG'] = self.root / 'config/easyeffects'
        self.ns['RUNTIME'].mkdir(parents=True, exist_ok=True)
        (self.ns['DATA'] / 'output').mkdir(parents=True, exist_ok=True)
        (self.ns['CONFIG'] / 'db').mkdir(parents=True, exist_ok=True)
        self.elapsed = 0
        self.clock = types.SimpleNamespace(monotonic=lambda: self.elapsed, sleep=self.advance, time=lambda: 1000.0)

    def tearDown(self):
        self.tempdir.cleanup()

    def advance(self, seconds):
        self.elapsed += seconds

    def test_manual_receipt_records_song_and_targets_current_unit(self):
        import json
        runtime=self.ns['RUNTIME']
        (runtime/'music-eq-session.json').write_text(json.dumps({'key':['spotify','spotify:track:A']}))
        command=Mock(return_value=types.SimpleNamespace(returncode=0))
        with patch.dict(self.ns, subprocess=types.SimpleNamespace(run=command)):
            self.api['notify_music_eq_manual']('manual')
        receipt=json.loads((runtime/'music-eq-manual.json').read_text())
        self.assertEqual(receipt['key'],['spotify','spotify:track:A'])
        self.assertEqual(receipt['preset'],'manual')
        self.assertIn('--signal=SIGUSR1',command.call_args.args[0])
        self.assertEqual(command.call_args.args[0][-1],'music-eq.service')
    def test_manual_receipt_without_watcher_is_optional(self):
        command=Mock()
        with patch.dict(self.ns, subprocess=types.SimpleNamespace(run=command)):
            self.api['notify_music_eq_manual']('manual')
        command.assert_not_called()

    def test_late_tray_is_allowed_time_to_register(self):
        def query(*args, **kwargs):
            return types.SimpleNamespace(returncode=0, stdout='b true' if self.elapsed >= 3 else 'b false')
        with patch.dict(self.ns, time=self.clock, subprocess=types.SimpleNamespace(run=query, TimeoutExpired=subprocess.TimeoutExpired)):
            self.assertTrue(self.api['wait_for_tray']())
        self.assertEqual(self.elapsed, 3)

    def test_absent_tray_has_bounded_grace(self):
        query = Mock(return_value=types.SimpleNamespace(returncode=1, stdout=''))
        with patch.dict(self.ns, time=self.clock, subprocess=types.SimpleNamespace(run=query, TimeoutExpired=subprocess.TimeoutExpired)):
            self.assertFalse(self.api['wait_for_tray']())
        self.assertEqual(self.elapsed, 15)

    def test_hung_bus_does_not_abort_audio_startup(self):
        def query(*args, **kwargs):
            self.advance(kwargs['timeout'])
            raise subprocess.TimeoutExpired('busctl', kwargs['timeout'])
        with patch.dict(self.ns, time=self.clock, subprocess=types.SimpleNamespace(run=query, TimeoutExpired=subprocess.TimeoutExpired)):
            self.assertFalse(self.api['wait_for_tray']())
        self.assertEqual(self.elapsed, 15)

    def test_audio_starts_without_tray_and_logs_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with patch.dict(self.ns, confirmed_state=lambda: {'active': False}, wait_for_tray=lambda: False,
                            state=lambda: {'active': True, 'bypassed': False, 'presets': []},
                            subprocess=types.SimpleNamespace(Popen=popen, STDOUT=subprocess.STDOUT)):
                with patch.dict('os.environ', XDG_STATE_HOME=directory):
                    self.api['start']()
            self.assertEqual(popen.call_args.args[0], ['easyeffects', '--hide-window', '--service-mode'])
            self.assertIn('starting audio processing', (Path(directory) / 'easyeffects-qs.log').read_text())

    def test_existing_instance_is_preserved(self):
        wait = Mock(side_effect=AssertionError('Unexpected second start'))
        with patch.dict(self.ns, confirmed_state=lambda: {'active': True}, wait_for_tray=wait):
            self.api['start']()
        wait.assert_not_called()

    def test_unresponsive_instance_is_not_duplicated(self):
        wait = Mock(side_effect=AssertionError('Unexpected second start'))
        with patch.dict(self.ns, state=lambda: {'known': False, 'error': 'unresponsive'}, wait_for_tray=wait):
            with self.assertRaisesRegex(RuntimeError, 'unresponsive'):
                self.api['start']()
        wait.assert_not_called()

    def test_start_clears_persisted_bypass_and_unbypasses_running_pipeline(self):
        rc = self.ns['CONFIG'] / 'db/easyeffectsrc'
        output_rc = self.ns['CONFIG'] / 'db/easyeffects_outputrc'
        rc.write_text('[EffectsPipelines]\nbypass=true\nresetBypassOnDeviceChange=false\n[Window]\nwidth=1100\n')
        output_rc.write_text('[Output][Equalizer#0][Band0]\ngain=3.5\n')
        popen = Mock()
        set_bypass = Mock()
        with patch.dict(self.ns, confirmed_state=lambda: {'active': False}, wait_for_tray=lambda: True,
                        state=lambda: {'active': True, 'bypassed': True, 'presets': []},
                        set_bypass=set_bypass,
                        subprocess=types.SimpleNamespace(Popen=popen, STDOUT=subprocess.STDOUT)):
            with patch.dict('os.environ', XDG_STATE_HOME=str(self.root / 'state')):
                self.api['start']()
        self.assertNotIn('bypass=true', rc.read_text())
        self.assertIn('resetBypassOnDeviceChange=false', rc.read_text())
        self.assertEqual(output_rc.read_text(), '[Output][Equalizer#0][Band0]\ngain=3.5\n')
        set_bypass.assert_called_once_with(False)

    def test_start_restores_quickshell_preset_only_when_newer_than_db(self):
        (self.ns['DATA'] / 'output/Music Profile.json').write_text('{}\n')
        output_rc = self.ns['CONFIG'] / 'db/easyeffects_outputrc'
        output_rc.write_text('[Output]\nplugins=equalizer#0\n')
        os.utime(output_rc, (500.0, 500.0))
        load_preset = Mock()
        with patch.dict(self.ns, time=self.clock, load_preset=load_preset):
            with patch.dict('os.environ', XDG_STATE_HOME=str(self.root / 'state')):
                self.api['save_selected_preset']('Music Profile')
                self.api['restore_saved_preset']({'presets': ['Music Profile']})
                load_preset.assert_called_once_with('Music Profile')
                load_preset.reset_mock()
                os.utime(output_rc, (1500.0, 1500.0))
                self.api['restore_saved_preset']({'presets': ['Music Profile']})
                load_preset.assert_not_called()

    def test_state_reports_unknown_without_error_while_startup_lock_held(self):
        with patch.dict(self.ns, exchange=Mock(side_effect=FileNotFoundError()), startup_locked=lambda: True):
            current = self.api['state']()
        self.assertFalse(current['known'])
        self.assertEqual(current['error'], '')

    def test_main_start_unbypasses_existing_instance_while_show_preserves_bypass(self):
        set_bypass = Mock()
        exchange = Mock()
        notify = Mock()
        with patch.dict(self.ns, start=lambda: None,
                        confirmed_state=lambda: {'active': True, 'bypassed': True},
                        set_bypass=set_bypass, exchange=exchange, notify_shell=notify):
            with patch.object(self.ns['sys'], 'argv', ['easyeffects-qs', 'start']):
                self.api['main']()
            set_bypass.assert_called_once_with(False)
            notify.assert_called_once_with()
            set_bypass.reset_mock()
            notify.reset_mock()
            with patch.object(self.ns['sys'], 'argv', ['easyeffects-qs', 'show']):
                self.api['main']()
            set_bypass.assert_not_called()
            exchange.assert_called_once_with('show_window', reply=False)
            notify.assert_not_called()


if __name__ == '__main__':
    unittest.main()
