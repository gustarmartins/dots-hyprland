#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch

source=Path(__file__).resolve().parents[1]/'dots/.config/kitty/window_title_bar.py'
with patch.dict(sys.modules,{'kitty':types.ModuleType('kitty'),'kitty.fast_data_types':types.SimpleNamespace(get_boss=lambda:None)}):
    spec=importlib.util.spec_from_file_location('agent_title',source)
    title=importlib.util.module_from_spec(spec);spec.loader.exec_module(title)

class Title(unittest.TestCase):
    def test_exact_window_and_process_birth_off_stale_and_ambiguous(self):
        with tempfile.TemporaryDirectory() as directory,patch.dict(os.environ,{'XDG_RUNTIME_DIR':directory}):
            path=Path(directory)/'agent-monitor/snapshot.json';path.parent.mkdir()
            pid=os.getpid();birth=int(Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[19])
            client=dict(pid=pid,start_ticks=birth,kitty=[dict(id=9,pid=123)])
            data=dict(config=dict(enabled=True,titles=True),timestamp=time.time(),sessions=[dict(clients=[client])],unmatched_clients=[])
            def check(expected):
                path.write_text(json.dumps(data));title._snapshot_deadline=0
                self.assertEqual(title.session_pid(9,123),expected)
            check(pid)
            with patch.object(title.json, 'loads', side_effect=AssertionError('Unchanged snapshot was parsed twice')):
                title._snapshot_deadline = 0
                self.assertEqual(title.session_pid(9, 123), pid)
            self.assertIsNone(title.session_pid(9,999))
            client['start_ticks']+=1;check(None)
            client['start_ticks']=birth;data['timestamp']=time.time()-25;check(None)
            data['timestamp']=time.time();data['config']['titles']=False;check(None)
            data['config']['titles']=True;data['config']['enabled']=False;check(None)
            path.write_text('{broken');title._snapshot_deadline=0
            self.assertIsNone(title.session_pid(9,123))

if __name__=='__main__':unittest.main()
