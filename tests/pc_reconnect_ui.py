#!/usr/bin/env python3
"""Private X/D-Bus/home UI check; no real host or Codex thread is contacted."""
from pathlib import Path
source=Path(__file__).with_name('settings_ui.py')
exec(compile(source.read_text().split('\ntry:\n    until(',1)[0],str(source),'exec'),globals())
p=OUT/'.local/bin/pc-reconnect-watch'
p.write_text('''#!/usr/bin/env python3
import json,sys
from pathlib import Path
p=Path.home()/'reconnect-fixture.json'
d=json.loads(p.read_text()) if p.exists() else dict(enabled=False,desktop=True,repeat=False,wakeCodex=True,displayName='Fixture PC')
a=sys.argv[1:]
if a[0]=='status':print(json.dumps(d))
else:
 with (Path.home()/'reconnect-calls.jsonl').open('a') as f:f.write(json.dumps(a)+'\\n')
 if a[0] in ('on','off'):d['enabled']=a[0]=='on'
 elif a[0]=='set':d[a[1]]=a[2]=='on'
 p.write_text(json.dumps(d))
''');p.chmod(0o755)
try:
    until(lambda:json.loads(call('settings','status'))['ready'])
    call('settings','open','company')
    until(lambda:json.loads(call('test','locate','pcReconnectMaster')))
    assert json.loads(call('test','locate','pcReconnectFeatures')) is None
    click('pcReconnectMaster');until(lambda:json.loads(call('test','locate','pcReconnectFeatures')))
    click('pcReconnectRepeat');click('pcReconnectWake');click('pcReconnectDesktop')
    until(lambda:not json.loads((OUT/'reconnect-fixture.json').read_text())['desktop'])
    screenshot('pc-reconnect')
    click('pcReconnectMaster');until(lambda:json.loads(call('test','locate','pcReconnectFeatures')) is None)
    assert config.read_bytes()==initial_bytes
    calls=[json.loads(l) for l in (OUT/'reconnect-calls.jsonl').read_text().splitlines()]
    assert calls==[['on'],['set','repeat','on'],['set','wakeCodex','off'],['set','desktop','off'],['off']],calls
    print('PASS: reconnection master, hidden controls, repeat/wake/desktop switches, unrelated settings preserved')
finally:
    process.terminate();process.wait(timeout=10);log.close()
