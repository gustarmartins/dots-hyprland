#!/usr/bin/env python3
"""Filter and sort the real settings UI with retained CPU observations."""
from pathlib import Path
source = Path(__file__).with_name('settings_ui.py')
setup = source.read_text().split('\ntry:\n    until(', 1)[0]
setup = setup.replace('    function testFind(name) {', '''    function testFind(name) {''')
setup = setup.replace('        function value(path: string): string {', '''        function apps(): string { const control=root.testFind("cryodAppScope"); return JSON.stringify(control.parent.parent.parent.matchingApps.map(a=>a.app_id)); }
        function selectAppControl(name: string, index: int): void { const control=root.testFind(name);control.currentIndex=index;control.activated(index); }
        function value(path: string): string {''')
setup = setup.replace("process = subprocess.Popen(", '''
observations = OUT/'state/quickshell/cryod-app-observations.json'
observations.parent.mkdir(parents=True,exist_ok=True)
now=int(time.time()*1000)
observations.write_text(json.dumps(dict(version=1,apps=[
 dict(app_id='cpu-hog.desktop',last_seen=now,cpu_peak_x100=4250,cpu_seen=now),
 dict(app_id='light.desktop',last_seen=now-1000,cpu_peak_x100=250,cpu_seen=now-1000),
 dict(app_id='seen.desktop',last_seen=now-2000)])))
apps=OUT/'data/applications';apps.mkdir(parents=True,exist_ok=True)
for app,title in [('cpu-hog','CPU hog'),('light','Light app'),('seen','Seen app'),('never-used','A never used app')]:
 (apps/(app+'.desktop')).write_text('[Desktop Entry]\\nType=Application\\nName='+title+'\\nExec=/usr/bin/true\\n')
process = subprocess.Popen(''')
exec(compile(setup, str(source), 'exec'), globals())
try:
    until(lambda:json.loads(call('settings','status'))['ready'])
    call('settings','open','cryod');click('cryodMaster')
    until(lambda:json.loads(call('test','locate','cryodAppScope')))
    rows=until(lambda:json.loads(call('test','apps')))
    assert rows[0]=='cpu-hog.desktop', rows
    assert 'never-used.desktop' not in rows
    assert 'seen.desktop' in rows
    call('test','selectAppControl','cryodAppCpuMinimum','3')
    until(lambda:json.loads(call('test','apps'))==['cpu-hog.desktop'])
    call('test','selectAppControl','cryodAppCpuMinimum','0')
    call('test','selectAppControl','cryodAppScope','4')
    call('test','text','cryodAppSearch','never-used')
    until(lambda:json.loads(call('test','apps'))==['never-used.desktop'])
    call('test','selectAppControl','cryodAppScope','1')
    until(lambda:'No matching apps' in json.loads(call('test','locate','cryodAppCount'))['text'])
    call('test','text','cryodAppSearch','')
    call('test','selectAppControl','cryodAppScope','2')
    call('test','selectAppControl','cryodAppSort','1')
    until(lambda:json.loads(call('test','apps'))==['cpu-hog.desktop','light.desktop'])
    call('test','reveal','cryodAppScope');screenshot('cryod-app-stats')
    assert json.loads(observations.read_text())['apps'][0]['cpu_peak_x100']==4250
    print('PASS: real settings default hides unused apps, CPU order/threshold, installed search, empty state and read-only history')
finally:
    process.terminate();process.wait(timeout=10);log.close()
