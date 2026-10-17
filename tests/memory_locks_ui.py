#!/usr/bin/env python3
"""Real Settings UI, isolated X/DBus/home; noswap mutations are fixture-only.
Run: xvfb-run -a -s '-screen 0 1400x1000x24' dbus-run-session -- python tests/memory_locks_ui.py
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix='memory-locks-ui-'))
RUNTIME = OUT/'runtime'; RUNTIME.mkdir(mode=0o700)
shutil.copytree(REPO/'dots/.config/quickshell/ii', OUT/'config/quickshell/ii')
config = OUT/'config/illogical-impulse/config.json'
config.parent.mkdir(parents=True)
shutil.copy2(REPO/'profile/illogical-impulse/config.json', config)
original_config = config.read_bytes()
bins = OUT/'.local/bin'; bins.mkdir(parents=True)
for name, result in [('oom-notify',dict(enabled=False)),('qs-mail',dict(config=dict(enabled=False),state={},running=False,accounts=[])),('easyeffects-qs',{}),('desktop-effects',[])]:
    p=bins/name;p.write_text('#!/usr/bin/env python3\nprint('+repr(json.dumps(result))+')\n');p.chmod(0o755)
# Prevent the notifications singleton from contacting the host notification store.
p=OUT/'config/quickshell/ii/services/Notifications.qml'
s=p.read_text()
if '    // Cleanup on init' in s:p.write_text(s[:s.index('    // Cleanup on init')]+'}\n')
GIB=1024**3
memory=dict(total=16*GIB,available=3*GIB,swap_total=32*GIB,large_rss=GIB,low=False)
def proc(pid,name,rss,group,locked=False,swap=0):
    return dict(pid=pid,name=name,rss=rss,swap=swap,start=100+pid,uid=os.getuid(),cgroup='/apps/'+group,
                group='/apps/'+group,unit=group,protected=locked,lock_id='group-a' if locked else None,
                age_days=2.3 if locked else None,group_count=2 if group=='editor.scope' else 1,
                group_memory=rss,group_swap=swap,can_lock=not locked,large_rss=rss>=GIB,reason='')
rows=[proc(101,'editor',3*GIB,'editor.scope',True),proc(102,'worker',256*1024**2,'editor.scope',True),
      proc(201,'browser',2*GIB,'browser.scope',swap=300*1024**2),proc(202,'music',400*1024**2,'music.scope'),
      proc(203,'render-helper',1500*1024**2,'render.scope')]
rows[2]['group_count']=2
rows += [proc(204,'browser-helper',128*1024**2,'browser.scope')]
fixture=dict(schema=2,boot='fixture-boot',sampled_at=time.time(),enabled=True,automatic=True,reminders=True,remind_days=2,
             rules=[dict(name='editor')],memory=memory,processes=rows,
             locks=[dict(id='group-a',unit='editor.scope',status='locked',age_days=2.3,members=rows[:2])])
(OUT/'fixture.json').write_text(json.dumps(fixture))
p=bins/'noswap'
p.write_text('''#!/usr/bin/env python3
import json,sys,time
from pathlib import Path
root=Path.home();path=root/'fixture.json';data=json.loads(path.read_text());args=sys.argv[1:]
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps(args)+'\\n')
if args[0]=='dashboard':
 if (root/'read-failure').exists():print('Fixture cannot read process memory',file=sys.stderr);sys.exit(1)
 print(json.dumps(data))
elif args[0]=='inspect':
 p=next(p for p in data['processes'] if p['pid']==int(args[1]))
 assert args[args.index('--expect-start')+1]==str(p['start'])
 assert args[args.index('--expect-boot')+1]==data['boot']
 members=[q for q in data['processes'] if q['group']==p['group']]
 print(json.dumps(dict(process=p,identity=dict(pid=p['pid'],start=p['start'],boot=data['boot']),unit=p['unit'],members=members,memory=data['memory'],group_memory=sum(q['rss'] for q in members),group_swap=p['swap'],risky=len(members)>1 or p['large_rss'],warnings=['Shared group: all listed processes will be protected.'] if len(members)>1 else [])))
elif args[0]=='lock':
 assert '--expect-identity' in args and '--force' in args
 if (root/'stale-preview').exists():print('Process or group changed since the preview. Refresh and review it again.',file=sys.stderr);sys.exit(1)
 target=next(p for p in data['processes'] if p['pid']==int(args[1]))
 for p in data['processes']:
  if p['group']==target['group']:p.update(protected=True,can_lock=False,lock_id='new-lock',age_days=0)
 data['locks'].append(dict(id='new-lock',unit=target['unit'],status='locked',members=[p for p in data['processes'] if p['group']==target['group']]))
 path.write_text(json.dumps(data))
elif args[0]=='unlock':
 for p in data['processes']:
  if p['lock_id']==args[1]:p.update(protected=False,can_lock=True,lock_id=None,age_days=None)
 data['locks']=[r for r in data['locks'] if r['id']!=args[1]];path.write_text(json.dumps(data))
elif args[0] in ('off','on'):
 if len(args)>1 and args[1]=='automatic':data['automatic']=args[0]=='on'
 else:data['enabled']=args[0]=='on'
 path.write_text(json.dumps(data))
''');p.chmod(0o755)
env=os.environ.copy()
env.update(HOME=str(OUT),XDG_CONFIG_HOME=str(OUT/'config'),XDG_DATA_HOME=str(OUT/'data'),XDG_CACHE_HOME=str(OUT/'cache'),
           XDG_STATE_HOME=str(OUT/'state'),XDG_RUNTIME_DIR=str(RUNTIME),QT_QPA_PLATFORM='xcb',QT_QUICK_BACKEND='software',
           WAYLAND_DISPLAY='',HYPRLAND_INSTANCE_SIGNATURE='',PATH=str(bins)+':'+env['PATH'])
assert '/run/user/'+str(os.getuid())+'/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS',''), 'Use private dbus-run-session'
subprocess.run(['dbus-update-activation-environment','HOME','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME',
                'XDG_STATE_HOME','XDG_RUNTIME_DIR','WAYLAND_DISPLAY','HYPRLAND_INSTANCE_SIGNATURE','DISPLAY','QT_QPA_PLATFORM'],env=env,check=True)
entry=OUT/'config/quickshell/ii/settings.qml'
probe=r'''
    function findMemoryNode(name) {
        let queue = [root.contentItem, Overlay.overlay]; let seen = new Set();
        while (queue.length) {
            let node=queue.shift(); if (!node || seen.has(node)) continue; seen.add(node);
            if (node.objectName === name && node.visible) return node;
            for (const child of (node.children || [])) queue.push(child);
            if (node.item) queue.push(node.item);
            if (node.contentItem) queue.push(node.contentItem);
        }
        return null;
    }
    IpcHandler {
        target: "memoryTest"
        function locate(name: string): string {
            const n=root.findMemoryNode(name); if(!n)return "null";
            const p=n.mapToItem(null,n.width/2,n.height/2);
            return JSON.stringify({x:p.x,y:p.y,width:n.width,height:n.height,enabled:n.enabled,text:n.text||""});
        }
        function state(): string {
            const n=root.findMemoryNode("memoryLocks");
            return JSON.stringify(n ? {ready:n.ready,enabled:n.state.enabled,rows:n.rows.map(p=>p.pid),tab:n.tab,error:n.error,readError:n.readError,pending:n.pendingKind,busy:n.busy} : {});
        }
        function reveal(name: string): void {
            const n=root.findMemoryNode(name);if(!n)return;
            const view=catalogPage.contentItem;
            const at=n.mapToItem(view,0,0);
            view.contentY=Math.max(0,Math.min(view.contentHeight-view.height,view.contentY+at.y-180));
        }
        function query(value: string): void { root.findMemoryNode("memorySearch").text=value; }
        function sort(value: int): void { root.findMemoryNode("memoryLocks").sortIndex=value; }
        function refresh(): void { root.findMemoryNode("memoryLocks").refresh(); }
        function resize(width: int, height: int): void { root.width=width;root.height=height; }
        function top(): void { catalogPage.contentItem.contentY=0; }
    }
'''
s=entry.read_text();entry.write_text(s[:s.rfind('}')]+probe+'\n}\n')
log=(OUT/'settings.log').open('w')
process=subprocess.Popen(['qs','-p',str(entry)],env=env,stdout=log,stderr=subprocess.STDOUT)
print('ARTIFACTS',OUT,flush=True)
def call(target,*args):
    return subprocess.check_output(['qs','-p',str(entry),'ipc','call',target,*args],env=env,text=True,stderr=subprocess.DEVNULL,timeout=5).strip()
def until(fn,timeout=15):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if process.poll() is not None:raise AssertionError((OUT/'settings.log').read_text()[-6000:])
        try:
            value=fn()
            if value:return value
        except (subprocess.SubprocessError,json.JSONDecodeError,KeyError,TypeError):pass
        time.sleep(.1)
    raise AssertionError('Timed out; see '+str(OUT)+'\n'+(OUT/'settings.log').read_text()[-3500:])
def state():return json.loads(call('memoryTest','state'))
def node(name):return json.loads(call('memoryTest','locate',name))
def window():return subprocess.check_output(['xdotool','search','--name','^illogical-impulse Settings$'],env=env,text=True).splitlines()[-1]
def click(name,dialog=False):
    n=until(lambda:node(name))
    if not dialog:
        call('memoryTest','reveal',name);time.sleep(.1);n=node(name)
    assert n['enabled'],(name,n)
    assert 0<=n['x']<=1180 and 0<=n['y']<=800,(name,n)
    subprocess.run(['xdotool','mousemove','--window',window(),str(round(n['x'])),str(round(n['y'])),'click','1'],env=env,check=True)
    time.sleep(.15)
def screenshot(name):
    subprocess.run(['magick','import','-window',window(),str(OUT/(name+'.png'))],env=env,check=True,capture_output=True)
def mutations():
    return [a for a in map(json.loads,(OUT/'calls.jsonl').read_text().splitlines()) if a[0] not in ('dashboard','inspect')]
try:
    until(lambda:json.loads(call('settings','status'))['ready'])
    call('settings','open','memory')
    until(lambda:state().get('ready'))
    assert state()['rows']==[101,102],state()
    call('memoryTest','top');time.sleep(.2);screenshot('locked')
    click('memoryTabSuggested')
    until(lambda:state()['tab']==1)
    assert state()['rows']==[201,203,202],state()  # one candidate per group
    click('memoryTabSearch');call('memoryTest','query','music')
    until(lambda:state()['rows']==[202])
    call('memoryTest','query','201');until(lambda:state()['rows']==[201])
    click('memoryAction:201')
    until(lambda:node('memoryApply'))
    assert not node('memoryApply')['enabled'],'Risk bypass must require explicit acknowledgement'
    screenshot('risk-dialog')
    click('memoryCancel',True)
    assert mutations()==[],mutations()
    click('memoryAction:201');until(lambda:node('memoryApply'))
    click('memoryRiskAccepted',True)
    assert node('memoryApply')['enabled']
    click('memoryApply',True)
    until(lambda:node('memoryAction:201')['text']=='Release…')
    assert mutations()[0][0]=='lock'
    assert '--expect-identity' in mutations()[0]
    click('memoryAction:201');until(lambda:node('memoryApply'))
    click('memoryApply',True)
    until(lambda:node('memoryAction:201')['text']=='Lock…')
    assert mutations()[-1]==['unlock','new-lock']
    call('memoryTest','query','does-not-exist');until(lambda:state()['rows']==[])
    call('memoryTest','query','');call('memoryTest','sort','1')
    until(lambda:state()['rows'][0]==201)
    call('memoryTest','sort','3');until(lambda:state()['rows']==[101,102,201,202,203,204])
    call('memoryTest','resize','700','650');call('memoryTest','top');time.sleep(.25);screenshot('compact')
    call('memoryTest','query','201');call('memoryTest','reveal','memoryAction:201');time.sleep(.15);screenshot('compact-process')
    click('memoryAction:201');until(lambda:node('memoryApply'));screenshot('compact-dialog');click('memoryCancel',True)
    call('memoryTest','resize','1180','800')
    call('memoryTest','query','201');click('memoryAction:201');until(lambda:node('memoryApply'))
    (OUT/'stale-preview').touch()
    click('memoryRiskAccepted',True);click('memoryApply',True)
    until(lambda:'changed since the preview' in state()['error'])
    assert node('memoryAction:201')['text']=='Lock…'
    (OUT/'stale-preview').unlink()
    (OUT/'read-failure').touch();call('memoryTest','refresh')
    until(lambda:not state()['ready'] and 'Fixture cannot read' in state()['readError'])
    assert node('memoryTabSearch') is None,'Failed reads must not leave stale actions enabled'
    (OUT/'read-failure').unlink();call('memoryTest','refresh')
    until(lambda:state()['ready'] and state()['readError']=='')
    call('memoryTest','query','202');click('memoryAction:202');until(lambda:node('memoryApply'))
    assert node('memoryRiskAccepted') is None,'Single small group should use a normal confirmation'
    assert node('memoryApply')['enabled']
    click('memoryCancel',True)
    click('memoryMaster');until(lambda:node('memoryApply'))
    click('memoryCancel',True);assert state()['enabled']
    click('memoryMaster');until(lambda:node('memoryApply'));click('memoryApply',True)
    until(lambda:not state()['enabled'])
    assert node('memoryTabSearch') is None,'Master off must hide owned feature UI'
    assert mutations()[-1]==['off','--force']
    assert config.read_bytes()==original_config,'Browsing memory tools changed desktop configuration'
    log.flush()
    issues=[line for line in (OUT/'settings.log').read_text().splitlines() if ('MemoryLocks.qml' in line or 'MemoryProcessRow.qml' in line) and any(e in line for e in ('Error','Unable to assign','Binding loop','Cannot assign','ReferenceError'))]
    assert not issues,issues
    print('PASS: RSS/swap sorting, candidates, PID/name search, risk cancel/override, guarded lock, group release, stale preview, master off and compact rendering; no real memory actions')
finally:
    process.terminate()
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:process.kill();process.wait()
    log.close()
