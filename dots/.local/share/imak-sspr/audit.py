#!/usr/bin/env python3
"""Read-only Imak password audit archive. Uses the existing M365 login."""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import fcntl
import html
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import urlencode, urlparse
from urllib.request import Request, build_opener, HTTPRedirectHandler

ROOT = Path.home()/'.local/state/imak-sspr'
CONFIG = Path.home()/'.config/imak-sspr/config.json'
KEYWORDS = ('password', 'security info', 'authentication method', 'unlock user account')

def config():
    data=dict(desktop=True,resets=True,recovery=True)
    if CONFIG.exists():data.update(json.loads(CONFIG.read_text()))
    return data

def setting(key, value):
    data=config();data[key]=value
    CONFIG.parent.mkdir(parents=True,exist_ok=True);CONFIG.parent.chmod(0o700)
    atomic(CONFIG,json.dumps(data,indent=2)+'\n')

def cli(*args):
    p = subprocess.run(['/usr/bin/m365', *args],capture_output=True,text=True,timeout=120)
    if p.returncode:
        raise RuntimeError('Microsoft 365 request failed; check the existing login and Graph permissions')
    return p.stdout

def verify_tenant():
    token = cli('util','accesstoken','get','--resource','https://graph.microsoft.com','--output','text').strip().strip('"')
    part = token.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(part+'='*((4-len(part)%4)%4)))
    if not config().get('tenantId') or claims.get('tid') != config()['tenantId'] or 'AuditLog.Read.All' not in claims.get('scp','').split():
        raise RuntimeError('Refusing collection: wrong tenant or missing AuditLog.Read.All')

def clean(event):
    name = event.get('activityDisplayName','')
    if not any(word in name.lower() for word in KEYWORDS):
        return None
    initiated = event.get('initiatedBy') or {}
    user, app = initiated.get('user') or {}, initiated.get('app') or {}
    return dict(id=event['id'],time=event['activityDateTime'],activity=name,
                result=event.get('result'),service=event.get('loggedByService'),
                correlationId=event.get('correlationId'),
                actor=user.get('userPrincipalName') or app.get('displayName'),
                actorId=user.get('id') or app.get('servicePrincipalId'),
                ip=user.get('ipAddress'),
                targets=[dict(id=t.get('id'),user=t.get('userPrincipalName'),type=t.get('type'))
                         for t in event.get('targetResources',[])])

def connect():
    ROOT.mkdir(parents=True,exist_ok=True);ROOT.chmod(0o700)
    db=sqlite3.connect(ROOT/'audit.sqlite3')
    db.execute('CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, time TEXT NOT NULL, payload TEXT NOT NULL, notified INTEGER NOT NULL DEFAULT 0)')
    db.execute('CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
    (ROOT/'audit.sqlite3').chmod(0o600)
    return db

def atomic(path, text):
    tmp=path.with_suffix(path.suffix+'.tmp')
    tmp.write_text(text);tmp.chmod(0o600);os.replace(tmp,path)

def export(db):
    rows=db.execute('SELECT payload FROM events ORDER BY time,id').fetchall()
    atomic(ROOT/'events.jsonl',''.join(r[0]+'\n' for r in rows))
    lines=['Time (UTC) | Result | Activity | Actor | Target']
    for (raw,) in reversed(rows):
        x=json.loads(raw)
        fields=[x['time'],x.get('result'),x['activity'],x.get('actor'),', '.join(t.get('user') or t.get('id') or '' for t in x['targets'])]
        lines.append(' | '.join(str(v or '').replace('\n',' ').replace('\r',' ') for v in fields))
    atomic(ROOT/'events.txt','\n'.join(lines)+'\n')

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        return None

def notify(db):
    options=config();url=options.get('webhook')
    if not url and not options.get('desktop'):
        db.execute('UPDATE events SET notified=1 WHERE notified=0');db.commit();return 0
    if url and urlparse(url).scheme != 'https':
        raise RuntimeError('Webhook must use HTTPS')
    selected=[]
    for event_id,raw in db.execute('SELECT id,payload FROM events WHERE notified=0 ORDER BY time,id').fetchall():
        x=json.loads(raw);name=x['activity'].lower()
        kind='recovery' if 'security info' in name or 'authentication method' in name else 'resets'
        if 'flow activity progress' in name or 'started security info registration' in name or not options.get(kind):
            db.execute('UPDATE events SET notified=1 WHERE id=?',(event_id,));continue
        selected.append(x)
    db.commit()
    if not selected:return 0
    if url:
        for x in selected:
            body=json.dumps(dict(source='Company Entra password audit',tenant=options['tenantId'],event=x)).encode()
            req=Request(url,data=body,headers={'Content-Type':'application/json','Idempotency-Key':x['id']},method='POST')
            try:
                with build_opener(NoRedirect).open(req,timeout=15) as response:
                    if response.status not in range(200,300):raise RuntimeError()
            except Exception:
                raise RuntimeError('Webhook delivery failed; event remains queued') from None
    if options.get('desktop'):
        lines=[]
        for x in selected[-5:]:
            targets=', '.join(t.get('user') or t.get('id') or '' for t in x['targets'])
            lines.append(x['activity']+' ['+str(x.get('result'))+']\n'+(targets or x.get('actor') or ''))
        if len(selected)>5:lines.append(str(len(selected)-5)+' more events in password audit history.')
        summary='Company account activity' if len(selected)==1 else 'Company account activity: '+str(len(selected))+' events'
        p=subprocess.run(['/usr/bin/notify-send','--app-name=Company password audit','--icon=dialog-password',
                          '--expire-time=12000',summary,html.escape('\n\n'.join(lines))],capture_output=True,text=True,timeout=15)
        if p.returncode:raise RuntimeError('Desktop notification delivery failed; events remain queued')
    db.executemany('UPDATE events SET notified=1 WHERE id=?',[(x['id'],) for x in selected]);db.commit()
    return len(selected)

def collect():
    os.umask(0o077)
    ROOT.mkdir(parents=True,exist_ok=True);ROOT.chmod(0o700)
    with (ROOT/'collector.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return dict(status='another collection is running')
        verify_tenant()
        db=connect()
        previous=db.execute("SELECT value FROM metadata WHERE key='lastSuccess'").fetchone()
        now=datetime.now(timezone.utc)
        # Re-read the retained seven days to catch late ingestion and interrupted runs.
        since=(now-timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%SZ')
        url='https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?'+urlencode({'$filter':f'activityDateTime ge {since}','$top':'999'})
        inserted=0;scanned=0
        while url:
            u=urlparse(url)
            if u.scheme!='https' or u.hostname!='graph.microsoft.com' or u.path!='/v1.0/auditLogs/directoryAudits':
                raise RuntimeError('Refusing an unexpected audit pagination URL')
            data=json.loads(cli('request','--url',url,'--output','json'))
            for e in data.get('value',[]):
                scanned+=1;x=clean(e)
                if x:
                    cursor=db.execute('INSERT OR IGNORE INTO events(id,time,payload,notified) VALUES(?,?,?,?)',
                                      (x['id'],x['time'],json.dumps(x,ensure_ascii=False),int(not previous)))
                    inserted+=cursor.rowcount
            url=data.get('@odata.nextLink')
        db.execute('INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)',('lastSuccess',now.isoformat()))
        db.commit();export(db)
        atomic(ROOT/'status.json',json.dumps(dict(lastSuccess=now.isoformat(),scanned=scanned,newEvents=inserted,
               archivedEvents=db.execute('SELECT COUNT(*) FROM events').fetchone()[0],hostRequired=True),indent=2)+'\n')
        sent=notify(db);db.close()
        return dict(status='ok',scanned=scanned,newEvents=inserted,notifications=sent)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['collect','status','show','on','off','set','test'])
    parser.add_argument('key',nargs='?',choices=['desktop','resets','recovery']);parser.add_argument('value',nargs='?',choices=['on','off'])
    args=parser.parse_args();action=args.action
    if action=='collect':
        try:print(json.dumps(collect()))
        except Exception as e:print(f'Collection failed: {e}');raise SystemExit(1)
    elif action=='status':
        status=json.loads((ROOT/'status.json').read_text()) if (ROOT/'status.json').exists() else {}
        status.update({k:v for k,v in config().items() if k in ['desktop','resets','recovery']})
        status['enabled']=subprocess.run(['systemctl','--user','is-enabled','--quiet','imak-password-audit.timer'],capture_output=True).returncode==0
        print(json.dumps(status))
    elif action=='show':
        print((ROOT/'events.txt').read_text() if (ROOT/'events.txt').exists() else 'No events archived yet')
    elif action=='set':
        if not args.key or not args.value:parser.error('set requires a feature and on/off')
        setting(args.key,args.value=='on')
    elif action=='test':
        subprocess.run(['/usr/bin/notify-send','--app-name=Company password audit','--icon=dialog-password',
                        'Company password alerts — TEST','Desktop delivery test. No employee password was changed.'],check=True)
    else:
        subprocess.run(['systemctl','--user','enable' if action=='on' else 'disable','--now','imak-password-audit.timer'],check=True)
        if action=='off':subprocess.run(['systemctl','--user','stop','imak-password-audit.service'],check=True)

if __name__=='__main__':main()
