"""Routing lifecycle checks; never touch the owner's audio or systemd session."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
PATH = REPO / 'dots/.local/bin/mpv-spatial'
spec = importlib.util.spec_from_loader('mpv_spatial_helper', importlib.machinery.SourceFileLoader('mpv_spatial_helper', str(PATH)))
helper = importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)

class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory();self.root = Path(self.tmp.name)
        self.config_patch = patch.object(helper, 'CONFIG', self.root / 'config/spatial.json');self.config_patch.start()
        self.runtime_patch = patch.object(helper, 'RUNTIME', self.root / 'runtime');self.runtime_patch.start()
    def tearDown(self):
        self.runtime_patch.stop();self.config_patch.stop();self.tmp.cleanup()
    def test_missing_config_starts_off(self):
        self.assertEqual(helper.config(), {'enabled':False, 'automatic':True})
    def test_non_boolean_enable_is_rejected(self):
        helper.save({'enabled':'false', 'automatic':True})
        with self.assertRaises(ValueError): helper.config()
    def test_save_keeps_unrelated_options(self):
        helper.save({'enabled':False, 'automatic':True, 'owner_note':'keep'})
        helper.save(dict(helper.config(), automatic=False))
        self.assertEqual(helper.config()['owner_note'], 'keep')
    def test_runtime_is_private(self):
        p = helper.runtime();self.assertEqual(p.stat().st_mode & 0o777, 0o700)
        p.chmod(0o755)
        with self.assertRaises(RuntimeError): helper.runtime()
    def test_disabling_restores_routes_before_stopping_service(self):
        helper.save({'enabled':True,'automatic':True});events=[]
        def restore():
            self.assertFalse(helper.config()['enabled']);events.append('restore');return []
        with patch.object(helper,'restore_players',side_effect=restore), patch.object(helper,'clear_sink_users',side_effect=lambda s:events.append('fallback')), patch.object(helper,'run',side_effect=lambda a,**kw:events.append(a)):
            helper.set_enabled(False)
        self.assertEqual(events[:2], ['restore','fallback'])
        self.assertEqual(events[2], ['systemctl','--user','disable','--now','mpv-spatial.service'])
    def test_enabling_is_on_demand_and_never_changes_default(self):
        calls=[]
        with patch.object(helper,'sink_names',return_value={'normal'}), patch.object(helper,'default_sink',return_value='normal'), patch.object(helper,'refresh_players',return_value=[]), patch.object(helper,'any_active_spatial_player',return_value=False), patch.object(helper,'active',return_value=False), patch.object(helper,'run',side_effect=lambda a,**kw:calls.append(a)):
            helper.set_enabled(True)
        self.assertTrue(helper.config()['enabled'])
        self.assertEqual(calls,[['systemctl','--user','disable','mpv-spatial.service']])

    def test_acquire_starts_sink_without_changing_default_and_release_stops_when_idle(self):
        helper.save({'enabled':True,'automatic':True})
        calls=[]
        sinks_state=[{'normal'}]
        def fake_run(args, **kw):
            calls.append(args)
            if args == ['systemctl','--user','start','mpv-spatial.service']:
                sinks_state[0] = {'normal', helper.TARGET}
            elif args == ['systemctl','--user','stop','mpv-spatial.service']:
                sinks_state[0] = {'normal'}
            return subprocess.CompletedProcess(args, 0, '', '')
        with patch.object(helper,'sink_names',side_effect=lambda: set(sinks_state[0])), \
             patch.object(helper,'default_sink',return_value='normal'), \
             patch.object(helper,'run',side_effect=fake_run):
            helper.acquire_sink()
        self.assertIn(['systemctl','--user','start','mpv-spatial.service'], calls)
        self.assertFalse(any('set-default-sink' in a for a in calls))

        # Active player keeps the sink alive; idle/paused releases and stops service.
        with patch.object(helper,'any_active_spatial_player',return_value=True):
            self.assertFalse(helper.release_sink())
        with patch.object(helper,'any_active_spatial_player',return_value=False), \
             patch.object(helper,'restore_players',return_value=[]) as restore_mock, \
             patch.object(helper,'clear_sink_users') as clear_mock, \
             patch.object(helper,'active',return_value=True), \
             patch.object(helper,'sink_names',side_effect=lambda: set(sinks_state[0])), \
             patch.object(helper,'run',side_effect=fake_run):
            self.assertTrue(helper.release_sink())
            restore_mock.assert_called_once_with(only_idle=True, exclude_pid=None)
            clear_mock.assert_called_once()
        self.assertIn(['systemctl','--user','stop','mpv-spatial.service'], calls)

    def test_failed_start_restores_off_choice(self):
        helper.save({'enabled':False,'automatic':False,'owner_note':'keep'})
        def command(args,**kw):
            if 'disable' in args: raise RuntimeError('fixture startup failure')
        with patch.object(helper,'sink_names',return_value={'normal'}), patch.object(helper,'default_sink',return_value='normal'), patch.object(helper,'restore_players',return_value=[]), patch.object(helper,'clear_sink_users'), patch.object(helper,'run',side_effect=command):
            with self.assertRaises(RuntimeError): helper.set_enabled(True)
        self.assertEqual(helper.config(),{'enabled':False,'automatic':False,'owner_note':'keep'})
    def test_fallback_moves_only_streams_using_spatial_sink(self):
        calls=[]
        sinks=[{'name':'normal','index':1},{'name':helper.TARGET,'index':2}]
        streams=[{'index':10,'sink':1},{'index':20,'sink':2}]
        def command(args,**kw):
            calls.append(args)
            return subprocess.CompletedProcess(args,0,json.dumps(sinks if args[-1]=='sinks' else streams),'')
        with patch.object(helper,'run',side_effect=command),patch.object(helper,'default_sink',return_value='normal'):
            helper.clear_sink_users({'previous_default_sink':'normal'})
        self.assertEqual([a for a in calls if 'move-sink-input' in a],[['pactl','move-sink-input','20','normal']])
        self.assertFalse(any('set-default-sink' in a for a in calls))

    def test_hdmi_dolby_eld_detection(self):
        asound = self.root / 'asound/card0'
        asound.mkdir(parents=True)
        (asound / 'eld#0.0').write_text(
            'monitor_present\t1\neld_valid\t1\nmonitor_name\tARZOPA\nconnection_type\tHDMI\n'
            'sad0_coding_type\t[0x1] LPCM\nsad0_channels\t2\n'
        )
        lpcm = helper.hdmi_dolby_info(self.root / 'asound')
        self.assertFalse(lpcm['hdmi_dolby'])
        self.assertIn('ARZOPA', lpcm['hdmi_summary'])
        (asound / 'eld#0.1').write_text(
            'monitor_present\t1\neld_valid\t1\nmonitor_name\tDENON-AVR\nconnection_type\tHDMI\n'
            'sad0_coding_type\t[0x1] LPCM\nsad0_channels\t8\n'
            'sad1_coding_type\t[0xa] E-AC-3\nsad1_channels\t8\n'
            'sad2_coding_type\t[0xc] MLP\nsad2_channels\t8\n'
        )
        avr = helper.hdmi_dolby_info(self.root / 'asound')
        self.assertTrue(avr['hdmi_dolby'])
        self.assertIn('E-AC-3', avr['hdmi_codecs'])
        self.assertIn('DENON-AVR', avr['hdmi_summary'])

    def test_sofa_and_hrir_pipewire_conf_rendering(self):
        fake_hrir = self.root / 'hrir.wav'; fake_hrir.write_bytes(b'RIFF')
        fake_sofa = self.root / 'kemar.sofa'; fake_sofa.write_bytes(b'SOFA')
        with patch.object(helper, 'HRIR_PATH', fake_hrir), patch.object(helper, 'SOFA_CANDIDATES', (fake_sofa,)):
            hrir_conf = helper.render_pipewire_conf('atmos-7.1')
            self.assertIn('# spatial-profile: atmos-7.1', hrir_conf)
            self.assertIn('label = convolver', hrir_conf)
            self.assertIn('target.object      = "easyeffects_sink"', hrir_conf)
            sofa_conf = helper.render_pipewire_conf('sofa-kemar')
            self.assertIn('# spatial-profile: sofa-kemar', sofa_conf)
            self.assertIn('type = sofa label = spatializer', sofa_conf)
            self.assertIn(str(fake_sofa), sofa_conf)
            self.assertIn('target.object      = "easyeffects_sink"', sofa_conf)

class VerifiedPlayerSocket(unittest.TestCase):
    def test_ipc_is_bound_to_its_real_player(self):
        with tempfile.TemporaryDirectory(prefix='mpv-spatial-ipc-') as tmp:
            sock=Path(tmp)/'player.sock'
            player=subprocess.Popen(['mpv','--no-config','--idle=yes','--no-video','--no-terminal','--input-terminal=no','--ao=null','--input-ipc-server='+str(sock)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
            try:
                deadline=time.monotonic()+5
                while not sock.exists() and time.monotonic()<deadline:time.sleep(.02)
                self.assertTrue(sock.exists())
                client=helper.Client(sock,player.pid)
                try:self.assertEqual(client.get('pid'),player.pid)
                finally:client.close()
                with self.assertRaises(RuntimeError):helper.Client(sock,player.pid+99999)
            finally:
                player.terminate();player.wait(timeout=5);player.stderr.close()

if __name__=='__main__':unittest.main()
