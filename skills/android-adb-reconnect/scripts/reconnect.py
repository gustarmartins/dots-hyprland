#!/usr/bin/env python3
"""Explicit, bounded ADB reconnect; one attempt by default, no device shell."""
import argparse,fcntl,hashlib,json,math,os,re,subprocess,sys,tempfile,time
from pathlib import Path

def command(adb,args,deadline):
    try:
        p=subprocess.run([adb,*args],capture_output=True,text=True,timeout=deadline,
                         env={**os.environ,'ADB_MDNS_AUTO_CONNECT':'0'})
        return p.returncode,p.stdout.strip()
    except subprocess.TimeoutExpired:
        return 124,''

def states(adb,deadline):
    rc,out=command(adb,['devices'],deadline)
    if rc:return {}
    return {p[0]:p[1] for line in out.splitlines() if len(p:=line.split())>=2 and p[1] in ('device','offline','unauthorized')}

def reconnect(endpoints,attempts,interval,deadline,adb='adb'):
    for attempt in range(1,attempts+1):
        before=states(adb,deadline)
        connected=next((e for e in endpoints if before.get(e)=='device'),None)
        if connected:
            print(json.dumps({'status':'connected','endpoint':connected,'attempt':attempt}),flush=True);return 0
        for endpoint in endpoints:
            if before.get(endpoint)=='unauthorized':continue
            if before.get(endpoint)=='offline':command(adb,['disconnect',endpoint],deadline)
            command(adb,['connect',endpoint],deadline)
            # Preserve caller route order and stop when the requested device
            # connects; do not also contact alternate routes unnecessarily.
            after=states(adb,deadline)
            if after.get(endpoint)=='device':
                print(json.dumps({'status':'connected','endpoint':endpoint,'attempt':attempt}),flush=True);return 0
        after=states(adb,deadline)
        connected=next((e for e in endpoints if after.get(e)=='device'),None)
        print(json.dumps({'attempt':attempt,'states':{e:after.get(e,'unavailable') for e in endpoints},'connected':connected}),flush=True)
        if connected:return 0
        if any(after.get(e)=='unauthorized' for e in endpoints):return 3
        if attempt<attempts:time.sleep(interval)
    return 2

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--endpoint',action='append',required=True)
    p.add_argument('--now',action='store_true',help='This active request needs a connection now')
    p.add_argument('--attempts',type=int,default=1)
    p.add_argument('--interval',type=float,default=10)
    p.add_argument('--deadline',type=float,default=4)
    a=p.parse_args(); endpoints=list(dict.fromkeys(a.endpoint))
    if not a.now:p.error('on-demand policy requires --now; no connection attempted')
    if not 1<=a.attempts<=15 or not math.isfinite(a.interval) or not math.isfinite(a.deadline) or a.interval<0 or a.deadline<=0:p.error('invalid retry limits')
    if any(not re.fullmatch(r'[A-Za-z0-9_.-]+:[0-9]{1,5}',e) for e in endpoints):p.error('use explicit hostname or IPv4:port endpoints')
    if not os.environ.get('ANDROID_ADB_SCOPE_SOCKET'):
        seconds=6+a.attempts*(2+3*len(endpoints))*a.deadline+(a.attempts-1)*a.interval
        if seconds>3600:p.error('retry operation exceeds the one-hour maximum')
        tool=os.environ.get('ANDROID_ADB_DEMAND_TOOL',str(Path.home()/'.local/bin/android-adb-on-demand'))
        argv=[tool,'run','--now','--no-connect','--max-seconds',str(seconds)]
        for endpoint in endpoints:argv+=['--endpoint',endpoint]
        return subprocess.call([*argv,'--',sys.executable,str(Path(__file__).resolve()),*sys.argv[1:]])
    if os.environ.get('ADB_SERVER_SOCKET')!=os.environ['ANDROID_ADB_SCOPE_SOCKET']:
        p.error('private ADB scope routing changed; refusing shared-server recovery')
    root=Path(os.environ.get('XDG_RUNTIME_DIR',tempfile.gettempdir()))/f'adb-reconnect-{os.getuid()}'
    root.mkdir(mode=0o700,exist_ok=True)
    key=hashlib.sha256('\n'.join(endpoints).encode()).hexdigest()[:20]
    with (root/(key+'.lock')).open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return 4
        return reconnect(endpoints,a.attempts,a.interval,a.deadline)
if __name__=='__main__':raise SystemExit(main())
