#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

SOURCE=Path(__file__).resolve().parents[1]/'dots/.local/lib/agent-monitor/monitor.py'
spec=importlib.util.spec_from_file_location('agent_monitor',SOURCE)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
A='11111111-1111-4111-8111-111111111111'
B='22222222-2222-4222-8222-222222222222'


def process(pid,parent=0,tid=None,agent='',server=False,start=1):
    return dict(pid=pid,ppid=parent,start_ticks=start,env={'CODEX_THREAD_ID':tid} if tid else {},
        agent=agent,server=server,name='codex' if agent else 'worker',ticks=1,rss=1024,swap=2048,
        virtual=4096,cgroup='',age_seconds=100,resume_id=None,conversation=None)


class Attribution(unittest.TestCase):
    def test_shared_server_is_never_divided_or_ancestry_attributed(self):
        rows={1:process(1,agent='Codex',server=True),2:process(2,1),3:process(3,1,A)}
        owners,_=m.assign_workloads(rows,{1:{A,B}}, {})
        self.assertEqual(owners,{3:A})

    def test_dedicated_writer_children_and_nested_agent_boundary(self):
        rows={1:process(1,agent='Codex'),2:process(2,1),3:process(3,2,agent='Codex'),4:process(4,3)}
        owners,_=m.assign_workloads(rows,{1:{A},3:{B}}, {})
        self.assertEqual(owners,{2:A,4:B})

    def test_reparented_child_and_pid_reuse(self):
        rows={4:process(4)}
        self.assertEqual(m.assign_workloads(rows,{}, {(4,1):A})[0],{4:A})
        rows[4]['start_ticks']=2
        self.assertEqual(m.assign_workloads(rows,{}, {(4,1):A})[0],{})

    def test_inherited_server_launch_id_does_not_own_other_sessions(self):
        rows={1:process(1,tid=A,agent='Codex',server=True),2:process(2,1,A),3:process(3,1,B)}
        self.assertEqual(m.assign_workloads(rows,{1:{A,B}}, {})[0],{3:B})

    def test_conflicting_environment_is_unknown(self):
        rows={1:process(1,tid=A),2:process(2,1,A)}
        rows[2]['env']['CODEX_SESSION_ID']=B
        self.assertNotIn(2,m.assign_workloads(rows,{}, {(2,1):A})[0])

    def test_duplicate_names_and_thread_switch(self):
        meta={A:dict(name='Build',cwd='/work/project'),B:dict(name='Build',cwd='/work/project')}
        self.assertIsNone(m.title_session('⠋ Build | project',{A,B},meta))
        meta[B]['name']='Other'
        self.assertEqual(m.title_session('[ ! ] Action Required | Other | project',{A,B},meta),B)
        self.assertIsNone(m.title_session('arbitrary',{A,B},meta))

    def test_resume_argv_and_stale_tmux_hint_do_not_override_current_title(self):
        rows={1:process(1,agent='Codex',server=True),10:process(10),11:process(11,10,agent='Codex')}
        rows[11]['resume_id']=A
        meta={A:dict(id=A,name='Old',cwd='/work'),B:dict(id=B,name='Current',cwd='/work')}
        pane=dict(socket='/tmp/sock',session='$1',name='Phone',window='@1',pane='%1',pid=10,title='Current | work',hint=A)
        with patch.object(m,'scan_processes',return_value=rows),patch.object(m,'writer_ids',side_effect=lambda pid:{A,B} if pid==1 else set()), \
             patch.object(m,'metadata',return_value=(meta,[])),patch.object(m,'tmux_inventory',return_value=([pane],[],[])), \
             patch.object(m,'kitty_inventory',return_value=([],[])):
            snapshot=m.Monitor().sample()
        session=next(s for s in snapshot['sessions'] if s['id']==B)
        self.assertEqual(session['clients'][0]['pid'],11)
        self.assertIn('detached',session['clients'][0]['routes'][0])
        self.assertEqual(snapshot['shared'][0]['rss'],1024)
        self.assertEqual(session['rss'],0)

    def test_background_client_does_not_label_foreground_kitty_window(self):
        rows={1:process(1,agent='Codex',server=True),10:process(10),11:process(11,10,agent='Codex')}
        rows[10]['tpgid']=99;rows[11]['pgrp']=11
        meta={A:dict(id=A,name='Session',cwd='/work')}
        window=dict(socket='unix:fixture',id=7,pid=10,title='Session | work')
        with patch.object(m,'scan_processes',return_value=rows),patch.object(m,'writer_ids',side_effect=lambda pid:{A} if pid==1 else set()), \
             patch.object(m,'metadata',return_value=(meta,[])),patch.object(m,'tmux_inventory',return_value=([],[],[])), \
             patch.object(m,'kitty_inventory',return_value=([window],[])):
            snapshot=m.Monitor().sample()
        client=snapshot['unmatched_clients'][0]
        self.assertEqual(client['kitty'],[])
        self.assertIsNone(client['session_id'])
        self.assertIn('background job',client['routes'][0])

    def test_open_fd_without_lock_is_not_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'1/fd').mkdir(parents=True);(root/'1/fdinfo').mkdir()
            (root/'1/fd/3').symlink_to('/tmp/thread-writer-locks/'+A+'.lock')
            (root/'1/fdinfo/3').write_text('pos:\t0\n')
            self.assertEqual(m.writer_ids(1,root),set())
            (root/'1/fdinfo/3').write_text('lock: 1: FLOCK ADVISORY WRITE 1 00:00:1 0 EOF\n')
            self.assertEqual(m.writer_ids(1,root),{A})

    def test_environment_allowlist_never_exports_tokens(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)
            (path/'environ').write_bytes(b'OPENAI_API_KEY=secret\0CODEX_THREAD_ID='+A.encode()+b'\0SSH_CONNECTION=private-address\0')
            self.assertEqual(m.environment(path),{'CODEX_THREAD_ID':A,'ssh':True})

    def test_real_reparentable_workload_environment_and_memory(self):
        env=dict(os.environ,CODEX_THREAD_ID=A,CODEX_SESSION_ID=A)
        child=subprocess.Popen(['python3','-c','import time; x=bytearray(8*1024*1024); time.sleep(8)'],env=env)
        try:
            time.sleep(.15)
            rows=m.scan_processes();owner,_=m.assign_workloads(rows,{}, {})
            self.assertEqual(owner[child.pid],A)
            self.assertGreater(rows[child.pid]['rss'],8*1024*1024)
            self.assertNotIn('argv',m.process_view(rows[child.pid]))
        finally:
            child.terminate();child.wait(timeout=3)


if __name__=='__main__':unittest.main()
