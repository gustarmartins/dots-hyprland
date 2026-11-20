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
# Large transient builds should not crowd out apps; separate instances remain searchable.
rows += [proc(205,'java',8*GIB,'cryomgr-build-123.service'),
         proc(206,'browser',300*1024**2,'browser-other.scope')]
external=proc(207,'external',100*1024**2,'external.scope',True)
external.update(lock_id=None,can_lock=True)
rows.append(external)
fixture=dict(schema=2,boot='fixture-boot',sampled_at=time.time(),enabled=True,automatic=True,reminders=True,remind_days=2,
             rules=[dict(name='editor')],memory=memory,processes=rows,
             locks=[dict(id='group-a',unit='editor.scope',status='locked',age_days=2.3,members=rows[:2])])
(OUT/'fixture.json').write_text(json.dumps(fixture))
p=bins/'noswap'
shutil.copy2(REPO/'tests/fixtures/noswap_ui.py',p);p.chmod(0o755)
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
            return JSON.stringify({ready:MemoryLockDraft.ready,enabled:MemoryLockDraft.snapshot.enabled,
                draftEnabled:MemoryLockDraft.draft.enabled,rows:n ? n.rows.map(p=>p.pid) : [],tab:n ? n.tab : -1,
                error:MemoryLockDraft.error,readError:MemoryLockDraft.readError,dirty:MemoryLockDraft.dirty,
                applying:MemoryLockDraft.applying,checking:MemoryLockDraft.checking,ops:MemoryLockDraft.operations,
                names:MemoryLockDraft.draft.rules.map(r=>r.name),results:MemoryLockDraft.results,version:MemoryLockDraft.editVersion,
                windowWidth:root.width});
        }
        function reveal(name: string): void {
            const n=root.findMemoryNode(name);if(!n)return;
            const view=catalogPage.contentItem;
            const at=n.mapToItem(view,0,0);
            view.contentY=Math.max(0,Math.min(view.contentHeight-view.height,view.contentY+at.y-180));
        }
        function query(value: string): void { root.findMemoryNode("memorySearch").text=value; }
        function name(value: string): void { MemoryLockDraft.nameText=value; }
        function sort(value: int): void { root.findMemoryNode("memoryLocks").sortIndex=value; }
        function refresh(): void { root.findMemoryNode("memoryLocks").refresh(); }
        function resize(width: int, height: int): void { root.width=width;root.height=height; }
        function top(): void { catalogPage.contentItem.contentY=0; }
        function apply(): void { MemoryLockDraft.applyAll(); }
        function release(pid: int): void { MemoryLockDraft.selectRelease(MemoryLockDraft.snapshot.processes.find(p=>p.pid===pid)); }
        function remove(id: string): void { MemoryLockDraft.removeOperation(id); }
        function acknowledge(): void { MemoryLockDraft.acknowledged=true; }
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
    if not dialog and name not in ('memoryApplyAll','memoryDiscard','memoryReview'):
        call('memoryTest','reveal',name);time.sleep(.1);n=node(name)
    assert n['enabled'],(name,n)
    assert 0<=n['x']<=1180 and 0<=n['y']<=800,(name,n)
    subprocess.run(['xdotool','mousemove','--window',window(),str(round(n['x'])),str(round(n['y'])),'click','1'],env=env,check=True)
    time.sleep(.15)
def screenshot(name):
    subprocess.run(['magick','import','-window',window(),str(OUT/(name+'.png'))],env=env,check=True,capture_output=True)
def mutations():
    return [a for a in map(json.loads,(OUT/'calls.jsonl').read_text().splitlines()) if a[0] not in ('dashboard','inspect')]
def saved():
    click('memoryTabSaved')
def on_screen(name, bottom):
    n=until(lambda:node(name))
    assert n['height'] > 0 and n['y'] - n['height']/2 >= 0 and n['y'] + n['height']/2 <= bottom, (name,n)
    assert n['x'] - n['width']/2 >= 0 and n['x'] + n['width']/2 <= state()['windowWidth'], (name,n,state()['windowWidth'])
def tabs_fit():
    parent=node('memoryViews')
    names=['memoryTabSuggested','memoryTabSearch','memoryTabLocked','memoryTabSaved']
    if node('memoryTabReview'): names.append('memoryTabReview')
    for name in names:
        n=node(name)
        assert n['x']-n['width']/2 >= parent['x']-parent['width']/2-1, (name,n,parent)
        assert n['x']+n['width']/2 <= parent['x']+parent['width']/2+1, (name,n,parent)
try:
    until(lambda:json.loads(call('settings','status'))['ready'])
    call('settings','open','memory');until(lambda:state().get('ready'))
    assert state()['tab']==0 and state()['rows']==[201,203,202],state()
    assert not state()['dirty'] and mutations()==[]
    # The primary task must be visible immediately, without scrolling, at both sizes.
    for name in ('memorySearch','memoryTabSuggested','memoryAction:201','memoryAction:203','memoryApplyAll'):
        on_screen(name,800)
    tabs_fit()
    screenshot('initial-processes')
    call('memoryTest','resize','700','650');call('memoryTest','top');time.sleep(.2)
    for name in ('memorySearch','memoryAction:201','memoryAction:203','memoryApplyAll'):
        on_screen(name,650)
    tabs_fit()
    screenshot('compact-processes')
    call('memoryTest','resize','1180','800');call('memoryTest','top');time.sleep(.2)
    call('memoryTest','query','java')
    assert state()['tab']==1 and state()['rows']==[205], 'Build jobs must remain searchable in All'
    call('memoryTest','query','browser')
    assert state()['rows']==[201,206,204], 'All must retain separate instances and group members'
    call('memoryTest','query','external')
    assert node('memoryAction:207')['text']=='Protected' and not node('memoryAction:207')['enabled'], 'External protection must not offer a release or a new lock'
    click('memoryTabSuggested');call('memoryTest','top')
    # No existing locks must still open on usable suggestions.
    initial=(OUT/'fixture.json').read_text()
    empty=json.loads(initial);empty['locks']=[]
    for p in empty['processes']:
        p.update(protected=False,can_lock=True,lock_id=None,age_days=None)
    (OUT/'fixture.json').write_text(json.dumps(empty));call('memoryTest','refresh')
    until(lambda:state()['rows'] and state()['rows'][0]==101)
    on_screen('memoryAction:101',800)
    (OUT/'fixture.json').write_text(initial);call('memoryTest','refresh')
    until(lambda:state()['rows']==[201,203,202])
    saved()
    call('memoryTest','name','mpv, future-player');click('memorySaveName')
    assert state()['names']==['editor','future-player','mpv']
    assert state()['dirty'] and mutations()==[], 'Adding names must not write settings'
    call('settings','open','about');call('settings','open','memory')
    saved()
    until(lambda:node('memoryRemoveName:future-player'))
    assert state()['names']==['editor','future-player','mpv'], 'Navigation lost the draft'
    click('memoryTabSearch');call('memoryTest','query','201');click('memoryAction:201')
    call('memoryTest','query','202');click('memoryAction:202')
    until(lambda:len(state()['ops'])==2 and not state()['checking'])
    assert node('memoryAction:202')['text']=='Undo', 'Selected groups need a visible undo action'
    call('memoryTest','resize','700','650');call('memoryTest','top');time.sleep(.2)
    tabs_fit();on_screen('memoryReview',650);on_screen('memoryApplyAll',650);screenshot('compact-staged')
    call('memoryTest','resize','1180','800');call('memoryTest','top');time.sleep(.2)
    assert node('memoryConfirm') is None, 'Selections should not open blocking dialogs'
    assert mutations()==[] and not node('memoryApplyAll')['enabled']
    click('memoryReview')
    click('memoryRiskAccepted');assert node('memoryApplyAll')['enabled']
    screenshot('staged-review')
    (OUT/'partial-failure').touch();click('memoryApplyAll')
    until(lambda:not state()['applying'] and 'permission denied' in state()['error'])
    assert len(mutations())==1 and mutations()[0][0]=='batch'
    assert len(state()['ops'])==1 and state()['ops'][0]['identity']['pid']==201
    result={r['label']:r['ok'] for r in state()['results']}
    assert True in result.values() and False in result.values()
    (OUT/'partial-failure').unlink();click('memoryApplyAll')
    until(lambda:not state()['applying'] and not state()['dirty'])
    payload=json.loads(mutations()[-1][-1]);assert len(payload['operations'])==1
    assert payload['operations'][0]['identity']['pid']==201, 'Successful actions must not be resubmitted'
    assert set(r['name'] for r in payload['settings']['rules'])=={'editor','mpv','future-player'}
    # A slow helper must leave editing, navigation, and IPC responsive.
    saved()
    call('memoryTest','name','first-wave');click('memorySaveName')
    (OUT/'slow-apply').touch();before_calls=len(mutations());click('memoryApplyAll')
    until(lambda:(OUT/'apply-started').exists())
    assert not node('memoryApplyAll')['enabled']
    t=time.monotonic();call('memoryTest','state');assert time.monotonic()-t<1.5
    call('memoryTest','apply');assert len(mutations())==before_calls+1, 'Duplicate apply was submitted'
    call('memoryTest','name','next-wave');click('memorySaveName')
    assert 'next-wave' in state()['names']
    call('settings','open','about')
    until(lambda:not state()['applying'])
    assert state()['dirty'] and 'next-wave' in state()['names'], 'Edits during apply were lost'
    call('settings','open','memory');saved();until(lambda:node('memoryName'))
    (OUT/'slow-apply').unlink();click('memoryApplyAll')
    until(lambda:not state()['applying'] and not state()['dirty'])
    # Changing a saved row is also only a draft; Discard restores the saved list.
    click('memoryRemoveName:mpv');assert 'mpv' not in state()['names']
    count=len(mutations());click('memoryDiscard')
    assert 'mpv' in state()['names'] and len(mutations())==count
    # A concurrent CLI settings change must never be overwritten by a stale draft.
    call('memoryTest','name','conflicting-draft');click('memorySaveName')
    data=json.loads((OUT/'fixture.json').read_text());data['revision']+=1;data['reminders']=False
    (OUT/'fixture.json').write_text(json.dumps(data));click('memoryApplyAll')
    until(lambda:not state()['applying'] and 'changed elsewhere' in state()['error'])
    assert state()['dirty'] and 'conflicting-draft' in state()['names']
    call('memoryTest','refresh');time.sleep(.2);click('memoryDiscard')
    assert 'conflicting-draft' not in state()['names']
    # Multiple releases are selected first and submitted in one batch.
    call('memoryTest','release','201');call('memoryTest','release','202')
    assert len(state()['ops'])==2
    count=len(mutations());click('memoryApplyAll');until(lambda:not state()['applying'] and not state()['dirty'])
    assert len(mutations())==count+1
    assert len(json.loads(mutations()[-1][-1])['operations'])==2
    # Refresh failures preserve draft text and disable Apply without freezing navigation.
    call('memoryTest','name','retained-after-read-failure');click('memorySaveName')
    (OUT/'read-failure').touch();call('memoryTest','refresh')
    until(lambda:not state()['ready'])
    assert 'retained-after-read-failure' in state()['names'] and not node('memoryApplyAll')['enabled']
    assert node('memoryName')['enabled'], 'Status refresh failure froze draft editing'
    call('memoryTest','name','edited-while-status-unavailable');click('memorySaveName')
    assert 'edited-while-status-unavailable' in state()['names']
    call('settings','open','about');call('settings','open','memory')
    saved()
    (OUT/'read-failure').unlink();call('memoryTest','refresh');until(lambda:state()['ready'])
    assert 'retained-after-read-failure' in state()['names'];click('memoryDiscard')
    # Footer stays visible on a compact window; master off stages before applying.
    call('memoryTest','resize','700','650');call('memoryTest','top');time.sleep(.2);screenshot('compact-batch')
    assert 0<node('memoryApplyAll')['y']<650
    count=len(mutations());click('memoryMaster')
    assert not state()['draftEnabled'] and state()['enabled'] and len(mutations())==count
    assert node('memoryTabSearch') is None
    click('memoryApplyAll');until(lambda:not state()['enabled'] and not state()['dirty'])
    assert config.read_bytes()==original_config, 'Memory editing changed unrelated desktop configuration'
    issues=[line for line in (OUT/'settings.log').read_text().splitlines() if any(n in line for n in ('MemoryLocks.qml','MemoryProcessRow.qml','MemoryLockDraft.qml')) and any(e in line for e in ('Error','Unable to assign','Binding loop','Cannot assign','ReferenceError'))]
    assert not issues,issues
    print('PASS: stage multiple names and groups; no mutation before Apply all; partial retry only failed actions; slow apply remains editable; navigation retains drafts; concurrent changes rejected; compact footer and master off verified')

finally:
    process.terminate()
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:process.kill();process.wait()
    log.close()
