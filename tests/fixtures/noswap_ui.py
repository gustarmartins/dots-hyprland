#!/usr/bin/env python3
"""Private UI fixture: JSON state only, never changes system memory policy."""
import json
import sys
import time
from pathlib import Path

root=Path.home();path=root/'fixture.json'
assert path.is_file(), 'Run only in the memory UI test home'
args=sys.argv[1:]
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps(args)+'\n')
data=json.loads(path.read_text())

def settings():
    return dict(enabled=data['enabled'],automatic=data['automatic'],reminders=data['reminders'],
                rules=sorted([dict(name=r['name'],shared=bool(r.get('force'))) for r in data['rules']],key=lambda r:r['name']))

def release(lock_id):
    for p in data['processes']:
        if p['lock_id']==lock_id:p.update(protected=False,can_lock=True,lock_id=None,age_days=None)
    data['locks']=[r for r in data['locks'] if r['id']!=lock_id]

if args[0]=='dashboard':
    if (root/'read-failure').exists():
        print('Fixture cannot read process memory',file=sys.stderr);sys.exit(1)
    data['settings']=settings();data['config_revision']=str(data.get('revision',0))
    print(json.dumps(data))
elif args[0]=='inspect':
    p=next(p for p in data['processes'] if p['pid']==int(args[1]))
    assert args[args.index('--expect-start')+1]==str(p['start'])
    assert args[args.index('--expect-boot')+1]==data['boot']
    members=[q for q in data['processes'] if q['group']==p['group']]
    print(json.dumps(dict(process=p,identity=dict(pid=p['pid'],start=p['start'],boot=data['boot']),unit=p['unit'],members=members,
                         memory=data['memory'],group_memory=sum(q['rss'] for q in members),group_swap=p['swap'],
                         risky=len(members)>1 or p['large_rss'],warnings=['Shared group: all listed processes will be protected.'] if len(members)>1 else [])))
elif args[0]=='batch':
    payload=json.loads(args[args.index('--payload')+1])
    if (root/'slow-apply').exists():
        (root/'apply-started').touch();time.sleep(4)
    data=json.loads(path.read_text())
    if payload['expected_revision']!=str(data.get('revision',0)):
        print(json.dumps(dict(ok=False,conflict=True,message='Memory settings changed elsewhere. Reload the saved settings and review your draft.',
                              items=[],settings=settings(),config_revision=str(data.get('revision',0)))));sys.exit(1)
    desired=payload['settings'];items=[]
    data.update({k:desired[k] for k in ('enabled','automatic','reminders')})
    data['rules']=[dict(name=r['name'],force=r['shared']) for r in desired['rules']]
    if not data['enabled']:
        for lock in data['locks'][:]:release(lock['id'])
    for op in payload['operations']:
        if op['kind']=='lock':
            if (root/'partial-failure').exists() and op['identity']['pid']==201:
                items.append(dict(id=op['id'],label=op['label'],ok=False,message='Fixture permission denied for browser',retry=op));continue
            if (root/'stale-preview').exists():
                items.append(dict(id=op['id'],label=op['label'],ok=False,message='Process or group changed since the preview.',retry=op));continue
            target=next(p for p in data['processes'] if p['pid']==op['identity']['pid'])
            lock_id='lock-'+str(target['pid'])
            for p in data['processes']:
                if p['group']==target['group']:p.update(protected=True,can_lock=False,lock_id=lock_id,age_days=0)
            data['locks'].append(dict(id=lock_id,unit=target['unit'],cgroup=target['group'],status='locked',members=[p for p in data['processes'] if p['group']==target['group']]))
        elif op['kind']=='release':release(op['lock_id'])
        items.append(dict(id=op['id'],label=op.get('label',op['kind']),ok=True))
    data['revision']=data.get('revision',0)+1;path.write_text(json.dumps(data))
    ok=all(r['ok'] for r in items)
    print(json.dumps(dict(ok=ok,conflict=False,items=items,settings=settings(),config_revision=str(data['revision']))))
    sys.exit(0 if ok else 1)
else:
    raise AssertionError('UI must stage choices and use one batch, not '+repr(args))
