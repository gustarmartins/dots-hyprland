#!/usr/bin/env python3
"""Read-only session attribution. Never reads transcripts, signals agents or changes cgroups."""
import argparse
from collections import defaultdict
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time

UUID = re.compile(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
ENV_KEYS = {'CODEX_HOME', 'CODEX_THREAD_ID', 'CODEX_SESSION_ID', 'TMUX', 'TMUX_PANE',
            'KITTY_WINDOW_ID', 'KITTY_LISTEN_ON'}
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config')))/'agent-monitor/config.json'
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))/'agent-monitor'
SNAPSHOT = RUNTIME/'snapshot.json'
DEFAULT = {'enabled': False, 'titles': True, 'interval': 5}


def clean(value, limit=160):
    return ''.join(c for c in str(value) if c.isprintable())[:limit]


def read_json(path, limit=4*1024*1024):
    with path.open('rb') as file:
        raw = file.read(limit+1)
    if len(raw)>limit: raise ValueError('Oversized JSON')
    return json.loads(raw)


def config():
    try:
        saved = read_json(CONFIG, 8192)
        return dict(DEFAULT, **{k:saved[k] for k in DEFAULT if k in saved})
    except FileNotFoundError:
        return dict(DEFAULT)


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.update-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as file: json.dump(data,file,ensure_ascii=False)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def command(args, timeout=1):
    result = subprocess.run(args,capture_output=True,text=True,timeout=timeout,check=False)
    if result.returncode: raise RuntimeError(clean(result.stderr))
    return result.stdout


def environment(proc):
    # Drop everything except attribution identifiers before storing any values.
    with (proc/'environ').open('rb') as file: raw=file.read(262144)
    values={}
    for pair in raw.split(b'\0'):
        key, sep, value=pair.partition(b'=')
        key=key.decode(errors='replace')
        if sep and key in ENV_KEYS: values[key]=value.decode(errors='replace')
        elif sep and key in ('SSH_CONNECTION','SSH_TTY'): values['ssh']=True
    return values


def process_stat(proc, hz, uptime):
    raw=(proc/'stat').read_text()
    end=raw.rfind(')'); fields=raw[end+2:].split()
    return {'pid':int(proc.name), 'name':clean(raw[raw.find('(')+1:end],80),
            'ppid':int(fields[1]), 'pgrp':int(fields[2]), 'tty':int(fields[4]), 'tpgid':int(fields[5]),
            'exec_key':tuple(fields[23:26]+fields[45:49]),
            'start_ticks':int(fields[19]), 'ticks':int(fields[11])+int(fields[12]),
            'age_seconds':max(0,uptime-int(fields[19])/hz)}


def agent_kind(argv, comm):
    if comm=='codex' or (argv and Path(argv[0]).name=='codex'):
        return 'Codex'
    first=[Path(arg).name for arg in argv[:3]]
    if comm=='agy' or 'agy' in first:return 'Antigravity'
    if comm=='claude' or 'claude' in first:return 'Claude'
    if comm=='gemini' or 'gemini' in first:return 'Gemini'
    return ''


def scan_processes(proc_root=Path('/proc'), previous=None):
    hz=os.sysconf('SC_CLK_TCK'); uptime=float((proc_root/'uptime').read_text().split()[0])
    rows={}; previous=previous or {}
    for proc in proc_root.iterdir():
        if not proc.name.isdigit():continue
        try:
            if proc.stat().st_uid!=os.getuid():continue
            row=process_stat(proc,hz,uptime)
            status={line.split(':',1)[0]:line.split(':',1)[1].strip() for line in (proc/'status').read_text().splitlines() if ':' in line}
            if int(status['Uid'].split()[0])!=os.getuid():continue
            for key,source in [('rss','VmRSS'),('swap','VmSwap'),('virtual','VmSize')]:
                row[key]=int(status[source].split()[0])*1024 if source in status else None
            key=(row['pid'],row['start_ticks'])
            cached=previous.get(key,{})
            if cached.get('exec_key')==row['exec_key']:
                row['env']=cached['env']
            else:
                try:row['env']=environment(proc)
                except OSError:row['env']={}
            argv=[]
            if row['name'] in ('codex','agy','claude','gemini','node','node-MainThread'):
                raw=(proc/'cmdline').read_bytes()[:65536]
                argv=[v.decode(errors='replace') for v in raw.split(b'\0') if v]
            row['agent']=agent_kind(argv,row['name'])
            row['server']=row['agent']=='Codex' and 'app-server' in argv[1:4]
            row['resume_id']=next((arg for i,arg in enumerate(argv) if i and argv[i-1]=='resume' and UUID.fullmatch(arg)),None)
            row['conversation']=next((arg.split('=',1)[1] for arg in argv[1:] if arg.startswith('--conversation=') and UUID.fullmatch(arg.split('=',1)[1])),None)
            row['cgroup']=(proc/'cgroup').read_text().strip().partition('::')[2]
            # PID reuse/exec races cannot join one identity's memory to another.
            if process_stat(proc,hz,uptime)['start_ticks']!=row['start_ticks']:continue
            rows[row['pid']]=row
        except (OSError,ValueError,KeyError,IndexError):continue
    return rows


def ancestors(pid, rows):
    seen=set()
    while pid in rows and pid not in seen:
        seen.add(pid);yield pid
        pid=rows[pid]['ppid']


def writer_ids(pid, proc_root=Path('/proc')):
    ids=set()
    try:
        for fd in (proc_root/str(pid)/'fd').iterdir():
            try:
                target=os.readlink(fd)
                if '/thread-writer-locks/' in target and target.endswith('.lock'):
                    tid=Path(target).stem
                    if not UUID.fullmatch(tid):continue
                    # An open file alone is not proof of a held writer lock.
                    info=(proc_root/str(pid)/'fdinfo'/fd.name).read_text()
                    if any(line.startswith('lock:') and 'WRITE' in line for line in info.splitlines()):ids.add(tid)
            except OSError:continue
    except OSError:pass
    return ids


def metadata(homes, ids):
    result={}; errors=[]
    for home in sorted(homes):
        path=Path(home)/'state_5.sqlite'
        if not path.is_file():continue
        try:
            with sqlite3.connect(path.as_uri()+'?mode=ro',uri=True,timeout=.15) as db:
                columns={r[1] for r in db.execute('PRAGMA table_info(threads)')}
                name='name' if 'name' in columns else "''"
                # Deliberately exclude title/preview/first_user_message: old schemas store prompts there.
                for tid in ids:
                    found=db.execute(f'SELECT id,{name},cwd FROM threads WHERE id=?',(tid,)).fetchone()
                    if found:
                        item={'id':found[0],'name':clean(found[1] or 'Unnamed session'),'cwd':clean(found[2],512)}
                        if tid in result and result[tid]!=item: errors.append('Conflicting session metadata')
                        else:result[tid]=item
        except (OSError,sqlite3.Error):errors.append('Some session names are unavailable')
    return result,errors


def tmux_inventory(rows):
    sockets={str(Path('/tmp')/f'tmux-{os.getuid()}'/'default')}
    for row in rows.values():
        value=row['env'].get('TMUX','')
        if value:sockets.add(value.rsplit(',',2)[0])
    panes=[];clients=[];errors=[];sep='\x1f'
    for endpoint in sorted(sockets)[:16]:
        path=Path(endpoint)
        try:
            if not path.is_socket() or path.stat().st_uid!=os.getuid():continue
            raw=command(['tmux','-S',endpoint,'list-panes','-a','-F',sep.join([
                '#{session_id}','#{session_name}','#{window_id}','#{pane_id}','#{pane_pid}',
                '#{pane_title}','#{@codex_session}'])])
            for line in raw.splitlines():
                fields=line.split(sep)
                if len(fields)!=7:continue
                session,name,window,pane,pid,title,hint=fields
                panes.append(dict(socket=endpoint,session=session,name=clean(name),window=window,
                    pane=pane,pid=int(pid),title=clean(title,300),hint=hint if UUID.fullmatch(hint) else ''))
            raw=command(['tmux','-S',endpoint,'list-clients','-F',sep.join(['#{client_pid}','#{session_id}','#{client_tty}','#{pane_id}'])])
            for line in raw.splitlines():
                fields=line.split(sep)
                if len(fields)!=4:continue
                pid=int(fields[0]);chain=list(ancestors(pid,rows))
                remote=any(rows[p]['env'].get('ssh') or rows[p]['name'].startswith('sshd') for p in chain)
                clients.append(dict(socket=endpoint,pid=pid,session=fields[1],remote=remote,pane=fields[3]))
        except (OSError,ValueError,RuntimeError,subprocess.TimeoutExpired):errors.append('A tmux server could not be inspected')
    return panes,clients,errors


def kitty_inventory(rows):
    endpoints=set()
    # Shared daemon environments retain stale terminal IDs. Only actual terminal clients/ancestors are used below.
    for row in rows.values():
        value=row['env'].get('KITTY_LISTEN_ON','')
        if value.startswith('unix:'):endpoints.add(value)
    windows=[];errors=[]
    for endpoint in sorted(endpoints)[:16]:
        try:
            document=json.loads(command(['kitten','@','--to',endpoint,'ls'],timeout=1))
            for os_window in document:
                for tab in os_window.get('tabs',[]):
                    for window in tab.get('windows',[]):
                        windows.append(dict(socket=endpoint,id=int(window['id']),pid=int(window['pid']),
                                            title=clean(window.get('title',''),300)))
        except (OSError,ValueError,RuntimeError,subprocess.TimeoutExpired):errors.append('A Kitty window could not be inspected')
    return windows,errors


def title_session(title, candidates, meta):
    # This is a displayed-title match, not an authenticated client/session binding.
    # Duplicate names stay unknown; command ownership never uses this inference.
    matches=[]
    for tid in candidates:
        item=meta.get(tid)
        if not item or item['name']=='Unnamed session':continue
        expected=item['name']+' | '+Path(item['cwd']).name
        if title==expected or title.endswith(' '+expected) or title.endswith('| '+expected):matches.append(tid)
    return matches[0] if len(matches)==1 else None


def explicit_thread(row):
    env=row.get('env',{})
    values={env[key] for key in ('CODEX_THREAD_ID','CODEX_SESSION_ID') if UUID.fullmatch(env.get(key,''))}
    return next(iter(values)) if len(values)==1 else None


def assign_workloads(rows, writers, prior):
    owners={};proof={}
    for pid,row in rows.items():
        if row['server'] or row['agent']:continue
        tid=explicit_thread(row)
        conflicting={row['env'][k] for k in ('CODEX_THREAD_ID','CODEX_SESSION_ID') if UUID.fullmatch(row['env'].get(k,''))}
        if len(conflicting)>1:continue
        # A shared daemon may itself have been started by a different agent.
        # Its inherited launch marker is not ownership of every later tool/MCP.
        inherited=False
        if tid:
            for parent in list(ancestors(pid,rows))[1:]:
                if rows[parent]['server']:
                    inherited=explicit_thread(rows[parent])==tid;break
                if rows[parent]['agent']=='Codex':
                    held=writers.get(parent,set())
                    inherited=bool(held) and tid not in held;break
        if tid and not inherited: owners[pid]=tid;proof[pid]='thread environment'
        elif (pid,row['start_ticks']) in prior:
            owners[pid]=prior[(pid,row['start_ticks'])];proof[pid]='previously observed identity'
    for pid,row in rows.items():
        if pid in owners or row['server'] or row['agent']:continue
        values={row['env'][k] for k in ('CODEX_THREAD_ID','CODEX_SESSION_ID') if UUID.fullmatch(row['env'].get(k,''))}
        if len(values)>1:continue
        for parent in list(ancestors(pid,rows))[1:]:
            if parent in owners:
                owners[pid]=owners[parent];proof[pid]='descendant';break
            ids=writers.get(parent,set())
            if ids:
                if len(ids)==1 and not rows[parent]['server']:
                    owners[pid]=next(iter(ids));proof[pid]='dedicated writer descendant'
                break
    return owners,proof


def memory_sum(items, field):
    values=[p[field] for p in items]
    return sum(v for v in values if v is not None) if all(v is not None for v in values) else None


def process_view(row):
    return {k:row.get(k) for k in ('pid','start_ticks','name','agent','ppid','rss','swap','virtual','cpu_percent','age_seconds','cgroup')}


class Monitor:
    def __init__(self):
        self.previous={};self.previous_time=None;self.owners={};self.peaks={}
        self.last_discovery=0;self.panes=[];self.clients=[];self.windows=[];self.discovery_errors=[]
        self.metadata={};self.metadata_time=0
    def sample(self):
        started=time.monotonic();cpu_started=time.process_time();rows=scan_processes(previous=self.previous)
        now=time.monotonic();elapsed=now-self.previous_time if self.previous_time is not None else None
        hz=os.sysconf('SC_CLK_TCK')
        for row in rows.values():
            prev=self.previous.get((row['pid'],row['start_ticks']))
            row['cpu_percent']=max(0,(row['ticks']-prev['ticks'])/hz/elapsed*100) if elapsed and prev else None
        writers={p:writer_ids(p) for p,row in rows.items() if row['agent']=='Codex'}
        owners,proof=assign_workloads(rows,writers,self.owners)
        ids=set(owners.values())|set().union(*writers.values())
        metadata_ids=ids|{row['resume_id'] for row in rows.values() if row.get('resume_id')}
        homes={str(Path.home()/'.codex')}
        for row in rows.values():
            if row['agent']=='Codex' or row['pid'] in owners:
                home=row['env'].get('CODEX_HOME')
                if home and Path(home).is_absolute():homes.add(home)
        # Names are small metadata-only SQLite reads; no rollout or pane capture.
        self.metadata,meta_errors=metadata(homes,metadata_ids)
        if now-self.last_discovery>=5:
            self.panes,self.clients,tmux_errors=tmux_inventory(rows)
            self.windows,kitty_errors=kitty_inventory(rows)
            self.discovery_errors=tmux_errors+kitty_errors;self.last_discovery=now
        # Resolve display routes from live ancestry, not inherited KITTY/TMUX variables alone.
        frontends=[]
        for pid,row in rows.items():
            if not row['agent'] or row['server']:continue
            chain=set(ancestors(pid,rows));pane=next((p for p in self.panes if p['pid'] in chain),None)
            window=next((w for w in self.windows if w['pid'] in chain),None)
            routes=[];title='';kitty=[]
            if pane:
                attached=[c for c in self.clients if c['socket']==pane['socket'] and c['session']==pane['session']]
                label='tmux '+pane['name']+' '+pane['pane']
                label+=' · SSH/Haven attached' if any(c['remote'] for c in attached) else ' · attached' if attached else ' · detached'
                foreground=row.get('pgrp')==rows.get(pane['pid'],{}).get('tpgid')
                routes.append(label+(' · background job' if not foreground else ''));title=pane['title'] if foreground else ''
                for client in attached:
                    if not foreground:continue
                    if client['pane']!=pane['pane']:continue
                    client_chain=set(ancestors(client['pid'],rows))
                    kitty.extend(w for w in self.windows if w['pid'] in client_chain)
            elif window:
                foreground=row.get('pgrp')==rows.get(window['pid'],{}).get('tpgid')
                routes.append('Kitty' if foreground else 'Kitty background job')
                if foreground:title=window['title'];kitty=[window]
            elif any(rows[p]['env'].get('ssh') or rows[p]['name'].startswith('sshd') for p in chain):routes.append('SSH terminal')
            else:routes.append('No local terminal attachment')
            held=writers.get(pid,set());tid=None;evidence='unresolved'
            if len(held)==1:tid=next(iter(held));evidence='writer lock'
            else:
                # Resume argv and tmux annotations are hints: a user may switch threads in the same TUI.
                tid=title_session(title,ids,self.metadata)
                if tid:evidence='displayed title match'
            item=process_view(row);item.update(session_id=tid,evidence=evidence,routes=routes,kitty=kitty,
                tmux={k:pane[k] for k in ('socket','pane','session')} if pane else None,
                resume_hint=row.get('resume_id'),resume_name=self.metadata.get(row.get('resume_id'),{}).get('name',''),name=self.metadata.get(tid,{}).get('name') or (row['agent']+' client'),
                conversation_id=row.get('conversation'))
            frontends.append(item)
        sessions={tid:dict(self.metadata.get(tid,{'id':tid,'name':'Unnamed session','cwd':''}),
            clients=[],workloads=[],writer_pids=[pid for pid,known in writers.items() if tid in known]) for tid in ids}
        for client in frontends:
            tid=client['session_id']
            if tid in sessions:sessions[tid]['clients'].append(client)
        for pid,tid in owners.items():
            item=process_view(rows[pid]);item['attribution']=proof[pid]
            sessions[tid]['workloads'].append(item)
        for tid,session in sessions.items():
            members=session['workloads'];clients=session['clients']
            session['rss']=memory_sum(members,'rss');session['swap']=memory_sum(members,'swap')
            session['client_rss']=memory_sum(clients,'rss');session['client_swap']=memory_sum(clients,'swap')
            session['cpu_percent']=sum(p['cpu_percent'] for p in members) if elapsed and all(p['cpu_percent'] is not None for p in members) else None
            old=self.peaks.get(tid,{})
            session['peak_cpu_percent']=max(old.get('cpu',0),session['cpu_percent'] or 0)
            session['peak_rss']=max(old.get('rss',0),session['rss'] or 0)
            self.peaks[tid]={'cpu':session['peak_cpu_percent'],'rss':session['peak_rss'],'seen':time.time()}
            members.sort(key=lambda p:(p['cpu_percent'] or 0,p['rss'] or 0),reverse=True)
            session['workload_count']=len(members);session['process_ids']=[p['pid'] for p in members]+[p['pid'] for p in clients];session['workloads']=members[:32]
        self.peaks={k:v for k,v in sorted(self.peaks.items(),key=lambda p:p[1]['seen'],reverse=True)[:256]}
        shared=[]
        for pid,row in rows.items():
            if not row['server']:continue
            item=process_view(row);item['session_ids']=sorted(writers.get(pid,set()));shared.append(item)
        attributed=set(owners)|{p['pid'] for p in frontends}|{p['pid'] for p in shared}
        unassigned=[process_view(row) for pid,row in rows.items() if pid not in attributed and
            ((row['rss'] or 0)>=256*1024**2 or (row['cpu_percent'] or 0)>=10)]
        unassigned.sort(key=lambda p:(p['cpu_percent'] or 0,p['rss'] or 0),reverse=True)
        self.previous={(p,row['start_ticks']):row for p,row in rows.items()}
        self.previous_time=now;self.owners={(p,rows[p]['start_ticks']):tid for p,tid in owners.items()}
        session_rows=sorted(sessions.values(),key=lambda s:(s['cpu_percent'] or 0,s['rss'] or 0),reverse=True)
        return dict(version=1,timestamp=time.time(),boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
            process_index=[dict(process_view(rows[pid]),session_id=tid,attribution=proof[pid]) for pid,tid in owners.items()],
            sessions=session_rows,unmatched_clients=[p for p in frontends if not p['session_id']],shared=shared,
            unattributed=unassigned[:12],warnings=sorted(set(meta_errors+self.discovery_errors)),
            scan_ms=round((time.monotonic()-started)*1000,2),scan_cpu_ms=round((time.process_time()-cpu_started)*1000,2),process_count=len(rows))


def serve():
    RUNTIME.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (RUNTIME/'writer.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        running=True
        def stop(*_):
            nonlocal running
            running=False
        signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
        monitor=Monitor()
        while running:
            settings=config()
            if not settings['enabled']:break
            start=time.monotonic();snapshot=monitor.sample();snapshot['config']=settings
            atomic_json(SNAPSHOT,snapshot)
            # Bounded periodic sampling, stopped by the feature master/service.
            deadline=start+max(2,min(60,float(settings['interval'])))
            while running and time.monotonic()<deadline:time.sleep(max(0,min(.25,deadline-time.monotonic())))
    SNAPSHOT.unlink(missing_ok=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['serve','status','snapshot','enable','disable','titles','identify'])
    parser.add_argument('value',nargs='?');parser.add_argument('--json',action='store_true')
    args=parser.parse_args()
    if args.command=='serve':serve();return
    if args.command in ('enable','disable','titles'):
        settings=config()
        if args.command=='titles':
            if args.value not in ('on','off'):parser.error('titles requires on or off')
            settings['titles']=args.value=='on'
        else:settings['enabled']=args.command=='enable'
        atomic_json(CONFIG,settings)
        if args.command!='titles':
            command(['systemctl','--user','enable' if settings['enabled'] else 'disable',
                     '--now','agent-monitor.service'],timeout=10)
        print(json.dumps(settings));return
    if args.command=='snapshot':
        monitor=Monitor();monitor.sample();time.sleep(.25);data=monitor.sample()
        data['config']=config()
    else:
        settings=config()
        try:data=read_json(SNAPSHOT)
        except FileNotFoundError:data={'sessions':[],'shared':[],'unmatched_clients':[],'unattributed':[],'timestamp':0}
        data['config']=settings;data['stale']=time.time()-data['timestamp']>max(20,settings['interval']*3)
    if args.command=='identify':
        if not args.value or not args.value.isdigit():parser.error('identify requires a PID')
        pid=int(args.value);matches=[]
        for session in data['sessions']:
            for p in session['clients']+session['workloads']:
                if p['pid']==pid:matches.append(dict(session_id=session['id'],name=session['name'],process=p))
        if not matches:
            for p in data.get('process_index',[]):
                if p['pid']==pid:
                    session=next((s for s in data['sessions'] if s['id']==p['session_id']),{})
                    matches.append(dict(session_id=p['session_id'],name=session.get('name','Unnamed session'),process=p))
        for p in data['shared']+data['unmatched_clients']+data['unattributed']:
            if p['pid']==pid:matches.append(p)
        try:
            birth=int(Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[19])
            boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
            matches=[entry for entry in matches if entry.get('process',entry).get('start_ticks')==birth and data.get('boot_id')==boot]
        except (OSError,ValueError,IndexError):matches=[]
        data={'pid':pid,'matches':matches,'stale':data.get('stale',False)}
    if args.json or args.command=='identify':print(json.dumps(data,ensure_ascii=False));return
    print('AI sessions — '+('monitoring' if data['config']['enabled'] else 'off')+(' (stale)' if data.get('stale') else ''))
    for s in data['sessions']:
        pids=','.join(str(p['pid']) for p in s['clients']) or 'no terminal'
        cpu='—' if s['cpu_percent'] is None else f'{s["cpu_percent"]:.1f}%'
        print(f'{s["name"]}\n  {s["id"]} | PID {pids} | jobs {s["workload_count"]} | CPU {cpu} | job RAM {(s["rss"] or 0)/1024**2:.1f} MiB | swap {(s["swap"] or 0)/1024**2:.1f} MiB')
    for p in data['shared']:
        print(f'Shared Codex server PID {p["pid"]}: RAM {(p["rss"] or 0)/1024**2:.1f} MiB, swap {(p["swap"] or 0)/1024**2:.1f} MiB, {len(p["session_ids"])} sessions')


if __name__=='__main__':
    try:main()
    except (OSError,ValueError,RuntimeError,subprocess.TimeoutExpired) as error:
        print(json.dumps({'error':str(error)}));sys.exit(1)
