import copy
from contextlib import ExitStack
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

path=Path(__file__).resolve().parents[1]/'dots/.local/bin/music-eq'
loader=importlib.machinery.SourceFileLoader('music_eq_lifecycle',str(path))
spec=importlib.util.spec_from_loader(loader.name,loader)
m=importlib.util.module_from_spec(spec);loader.exec_module(m)

class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.stack=ExitStack();self.addCleanup(self.stack.close)
        root=Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        for k,v in dict(CONFIG=root/'config.json',STATE=root/'state.json',SESSION=root/'session.json',MANUAL=root/'manual.json',RUNTIME=root).items():
            self.stack.enter_context(patch.object(m,k,v))
        self.cfg=dict(m.DEFAULT,tracks=[],fallback='automatic')
        m.write(m.CONFIG,self.cfg)
        self.current='baseline';self.gain='-0.85';self.bypass='2';self.loads=[]
        self.track=dict(source='spotify',player='spotify.1',url='spotify:track:A',title='A',artists=['Artist'],genres=[],playing=True)
        self.tracks=[self.track]
        self.preset=root/'preset.json';m.write(self.preset,{'output':{'limiter#0':{},'equalizer#0':{}}})
        self.stack.enter_context(patch.object(m,'preset_path',return_value=self.preset))
        self.stack.enter_context(patch.object(m,'run',return_value=Mock(returncode=1)))
        self.stack.enter_context(patch.object(m,'exchange',side_effect=self.exchange))
        self.stack.enter_context(patch.object(m,'controls',return_value={}))
        self.stack.enter_context(patch.object(m,'apply',side_effect=self.apply))
        self.w=self.watcher();self.w.update()
        self.assertEqual(self.current,'automatic')
    def watcher(self):
        w=m.Watcher.__new__(m.Watcher)
        w.key=None;w.last=None;w.before=None;w.held=False;w.observed=None;w.manual_id=None
        w.tracks=lambda cfg:self.tracks;w.loop=Mock()
        return w
    def exchange(self,cmd):
        if cmd=='get_last_loaded_preset:output':return self.current
        if cmd=='get_global_bypass':return self.bypass
        if cmd=='get_property:output:limiter:0:outputGain':return self.gain
        raise AssertionError(cmd)
    def apply(self,name,gain):self.current=name;self.gain=gain;self.loads.append(name)
    def pause(self):self.track['playing']=False;self.w.update()
    def resume(self):self.track['playing']=True;self.w.update()
    def manual(self):self.current='manual';self.w.update();self.assertTrue(self.w.held)
    def test_pause_does_not_reload_or_restore(self):
        self.pause();self.resume();self.assertEqual(self.loads,['automatic'])
    def test_click_then_immediate_pause_before_poll(self):
        self.current='manual';self.pause();self.resume()
        self.assertEqual(self.current,'manual');self.assertTrue(self.w.held)
    def test_select_while_paused(self):
        self.pause();self.manual();self.resume();self.assertEqual(self.current,'manual')
    def test_missing_player_and_reconnect(self):
        self.manual();self.tracks=[];self.w.update()
        self.track['player']='spotify.2';self.tracks=[self.track];self.w.update()
        self.assertEqual(self.current,'manual');self.assertTrue(self.w.held)
    def test_metadata_gap_and_tag_correction(self):
        self.manual();self.track['title']='';self.track['artists']=[];self.w.update()
        self.track.update(title='A (corrected tag)',artists=['Artist','Guest']);self.w.update()
        self.assertEqual(self.current,'manual');self.assertTrue(self.w.held)
    def test_partial_metadata_without_uri_preserves_hold(self):
        self.manual();self.track['url']='';self.w.update()
        self.assertTrue(self.w.held)
        self.track['url']='spotify:track:A';self.w.update();self.assertTrue(self.w.held)
    def test_overlap_and_return(self):
        self.manual();other=dict(self.track,source='jukebox',url='file:///b.flac')
        self.tracks=[self.track,other];self.w.update()
        self.tracks=[self.track];self.w.update();self.assertEqual(self.current,'manual')
    def test_new_song_expires_override_even_with_same_title(self):
        self.manual();self.track['url']='spotify:track:B';self.w.update()
        self.assertFalse(self.w.held);self.assertEqual(self.current,'automatic')
        self.track['url']='spotify:track:A';self.w.update();self.assertFalse(self.w.held)
    def test_new_source_expires_override(self):
        self.manual();self.track['source']='jukebox';self.w.update()
        self.assertFalse(self.w.held);self.assertEqual(self.current,'automatic')
    def test_new_song_while_paused_does_not_apply_until_play(self):
        self.manual();self.pause();self.track['url']='spotify:track:B';self.w.update()
        self.assertEqual(self.current,'manual');self.resume();self.assertEqual(self.current,'automatic')
    def test_select_for_new_song_while_paused(self):
        self.pause();self.track['url']='spotify:track:B';self.w.update()
        self.manual();self.resume()
        self.assertTrue(self.w.held);self.assertEqual(self.current,'manual')
    def test_new_paused_song_and_selection_in_one_update(self):
        self.pause();self.track['url']='spotify:track:B';self.current='manual';self.w.update()
        self.resume();self.assertTrue(self.w.held);self.assertEqual(self.current,'manual')
    def test_manual_survives_graceful_restart(self):
        self.manual();self.w.stop()
        self.w=self.watcher();self.w.load_session();self.w.update()
        self.assertEqual(self.current,'manual');self.assertTrue(self.w.held)
    def test_click_before_stop_is_not_lost(self):
        self.current='manual';self.w.stop()
        self.w=self.watcher();self.w.load_session();self.w.update()
        self.assertTrue(self.w.held);self.assertEqual(self.current,'manual')
    def test_automatic_restart_resumes_normally(self):
        self.w.stop();self.assertEqual(self.current,'baseline')
        self.w=self.watcher();self.w.load_session();self.w.update()
        self.assertEqual(self.current,'automatic');self.assertFalse(self.w.held)
    def test_explicit_same_preset_selection(self):
        m.write(m.MANUAL,dict(id=123,key=self.w.key,preset=self.current));self.w.update()
        self.assertTrue(self.w.held);self.pause();self.resume();self.assertTrue(self.w.held)
    def test_stale_receipt_does_not_hold_next_song(self):
        key=copy.deepcopy(self.w.key);self.track['url']='spotify:track:B';self.w.update()
        m.write(m.MANUAL,dict(id=123,key=key,preset=self.current));self.w.update()
        self.assertFalse(self.w.held)
    def test_bypass_and_route_do_not_clear_manual(self):
        self.manual();self.bypass='1';self.w.update();self.bypass='2'
        self.cfg['route']='headphones';m.write(m.CONFIG,self.cfg)
        with patch.object(m,'route',return_value='speakers'):self.w.update()
        with patch.object(m,'route',return_value='headphones'):self.w.update()
        self.assertTrue(self.w.held);self.assertEqual(self.current,'manual')
    def test_temporary_socket_failure_keeps_override(self):
        self.manual()
        with patch.object(m,'exchange',side_effect=ConnectionRefusedError):self.w.tick()
        self.w.update();self.assertTrue(self.w.held);self.assertEqual(self.current,'manual')

if __name__=='__main__':unittest.main()
