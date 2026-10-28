import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

path=Path(__file__).resolve().parents[1]/'dots/.local/bin/music-eq'
loader=importlib.machinery.SourceFileLoader('music_eq',str(path))
spec=importlib.util.spec_from_loader(loader.name,loader)
m=importlib.util.module_from_spec(spec);loader.exec_module(m)

class MusicEqTests(unittest.TestCase):
    def setUp(self):
        self.cfg=dict(m.DEFAULT,tracks=[dict(artist='Charli XCX',title='365',preset='exact')],
            artist_rules={'Charli xcx':'artist'},genre_rules={'Pop':'genre'},fallback='base')
    def test_precedence_and_versions(self):
        track=dict(artists=['CHARLI XCX'],title=' 365 ',genres=['Pop'])
        self.assertEqual(m.select(track,self.cfg),('exact','song rule'))
        track['title']='365 (live)'
        self.assertEqual(m.select(track,self.cfg)[0],'artist')
        self.cfg['artists']=False
        self.assertEqual(m.select(track,self.cfg)[0],'genre')
        self.cfg['genres']=False
        self.assertEqual(m.select(track,self.cfg)[0],'base')
    def test_local_recording_precedes_tags_and_excludes_spotify(self):
        self.cfg['file_rules']={'/music/osu!/audio.mp3':'osu-nightcore'}
        track=dict(source='jukebox',url='file:///music/osu%21/audio.mp3',artists=[],title='audio.mp3',genres=[])
        self.assertEqual(m.select(track,self.cfg),('osu-nightcore','local recording rule'))
        track['source']='spotify'
        self.assertEqual(m.select(track,self.cfg)[0],'base')
        track['source']='jukebox';track['url']='file://remote/music/osu!/audio.mp3'
        self.assertEqual(m.select(track,self.cfg)[0],'base')

    def test_collaborating_artist_list_matches_combined_rule(self):
        self.cfg['tracks']=[dict(artist='Manian; Tune Up!',title='Bounce - Nightcore Edit',preset='hard-dance')]
        self.assertEqual(m.select(dict(artists=['Manian','Tune Up!'],title='Bounce - Nightcore Edit',genres=[]),self.cfg)[0],'hard-dance')

    def test_unknown_artist_not_substring(self):
        self.assertEqual(m.select(dict(artists=['Not Charli xcx'],title='365',genres=[]),self.cfg)[0],'base')
    def test_preset_path_injection_rejected(self):
        for name in ['../bad','foo\nbar','', 'a'*101]:
            with self.assertRaises(ValueError): m.preset_path(name)
    def test_restore_only_owned_preset(self):
        w=m.Watcher.__new__(m.Watcher)
        w.before={'preset':'base','controls':{'output:equalizer:0:inputGain':'-5'}}
        w.last='auto';w.held=False
        with patch.object(m,'exchange',return_value='manual'),patch.object(m,'apply') as apply:
            w.restore();apply.assert_not_called()
    def test_restore_preserves_current_output_gain(self):
        w=m.Watcher.__new__(m.Watcher)
        w.before={'preset':'base','controls':{'output:equalizer:0:inputGain':'-5','output:limiter:0:outputGain':'-3'}}
        w.last='auto';w.held=False
        with patch.object(m,'exchange',side_effect=['auto','-1','','base']) as query,patch.object(m,'apply') as apply:
            w.restore();apply.assert_called_once_with('base','-1')
            self.assertIn(unittest.mock.call('set_property:output:equalizer:0:inputGain:-5'),query.call_args_list)
    def test_event_callback_is_one_shot(self):
        w=m.Watcher.__new__(m.Watcher);w.pending=42
        with patch.object(w,'tick') as tick:
            self.assertFalse(w.event_tick());self.assertEqual(w.pending,0);tick.assert_called_once()
    def test_gain_and_eq_readback(self):
        with tempfile.TemporaryDirectory() as d,patch.object(m,'PRESETS',Path(d)):
            m.write(Path(d)/'auto.json',{'output':{'limiter#0':{},'equalizer#0':{'input-gain':-5}}})
            with patch.object(m,'exchange',side_effect=['','auto','','-1','-5']) as query:
                m.apply('auto','-1')
                self.assertIn(unittest.mock.call('set_property:output:limiter:0:outputGain:-1'),query.call_args_list)
            with patch.object(m,'exchange',side_effect=['','auto','','-2']):
                with self.assertRaises(RuntimeError): m.apply('auto','-1')

if __name__=='__main__':unittest.main()
