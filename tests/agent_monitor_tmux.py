#!/usr/bin/env python3
"""Private tmux servers and owned writer fixtures; never resumes a real Codex task."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import sqlite3
import subprocess
import tempfile
import time

repo=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('monitor',repo/'dots/.local/lib/agent-monitor/monitor.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
A='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
B='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
with tempfile.TemporaryDirectory(prefix='agent-tmux-') as directory:
    base=Path(directory);home=base/'codex';(home/'thread-writer-locks').mkdir(parents=True)
    with sqlite3.connect(home/'state_5.sqlite') as db:
        db.execute('create table threads (id text primary key,name text,cwd text)')
        db.executemany('insert into threads values (?,?,?)',[(A,'Phone task','/work'),(B,'Other task','/work')])
    script=base/'writer.py'
    script.write_text('''import ctypes,fcntl,os,sys,time
from pathlib import Path
ctypes.CDLL(None).prctl(15,b'codex',0,0,0)
fd=open(Path(os.environ['CODEX_HOME'])/'thread-writer-locks'/(sys.argv[1]+'.lock'),'w')
fcntl.flock(fd,fcntl.LOCK_EX)
time.sleep(60)
''')
    endpoints=[str(base/'one.sock'),str(base/'two.sock')]
    client=None
    def tmux(endpoint,*args):
        return subprocess.check_output(['tmux','-S',endpoint,'-f','/dev/null',*args],text=True,stderr=subprocess.DEVNULL).strip()
    def launch(endpoint,tid):
        return 'env CODEX_HOME='+shlex.quote(str(home))+' python3 '+shlex.quote(str(script))+' '+tid
    def sample():
        return m.Monitor().sample()
    def session(data,tid):return next(s for s in data['sessions'] if s['id']==tid)
    try:
        for endpoint,tid in zip(endpoints,[A,B]):
            tmux(endpoint,'new-session','-d','-s','Phone',launch(endpoint,tid))
        time.sleep(.15)
        first=sample();a=session(first,A);b=session(first,B)
        assert len(a['clients'])==len(b['clients'])==1
        assert a['clients'][0]['tmux']['pane']==b['clients'][0]['tmux']['pane']=='%0'
        assert a['clients'][0]['tmux']['socket']!=b['clients'][0]['tmux']['socket']
        assert 'detached' in a['clients'][0]['routes'][0]
        pid=a['clients'][0]['pid']
        env=dict(os.environ,SSH_CONNECTION='fixture remote session',TERM='xterm-256color')
        client=subprocess.Popen(['tmux','-S',endpoints[0],'-C','attach-session','-t','Phone'],
            stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,env=env)
        time.sleep(.1)
        connected=session(sample(),A)
        assert connected['clients'][0]['pid']==pid
        assert 'SSH/Haven attached' in connected['clients'][0]['routes'][0],connected
        client.terminate();client.wait(timeout=3);client=None
        # Replace only our disposable writer to emulate resume with a new PID.
        tmux(endpoints[0],'respawn-pane','-k','-t','Phone:0.0',launch(endpoints[0],A))
        time.sleep(.15)
        resumed=session(sample(),A)
        assert resumed['id']==A and resumed['name']=='Phone task'
        assert resumed['clients'][0]['pid']!=pid
        assert 'detached' in resumed['clients'][0]['routes'][0]
        print('PASS: two tmux sockets with identical pane IDs, detached mapping, SSH-style attachment, preserved writer during attach and new-PID resume')
    finally:
        if client is not None:client.terminate();client.wait(timeout=3)
        for endpoint in endpoints:
            subprocess.run(['tmux','-S',endpoint,'kill-server'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
