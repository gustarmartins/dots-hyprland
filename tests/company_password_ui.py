#!/usr/bin/env python3
"""Run with xvfb-run dbus-run-session; all account/service actions use a fixture."""
from pathlib import Path

# Reuse the real settings suite's disposable home, private D-Bus setup and UI probes.
source=Path(__file__).with_name('settings_ui.py')
prefix=source.read_text().split('\ntry:\n    until(',1)[0]
exec(compile(prefix,str(source),'exec'),globals())
p=OUT/'.local/bin/imak-password-audit'
p.write_text('''#!/usr/bin/env python3
import json,sys
from pathlib import Path
p=Path.home()/'company-fixture.json'
d=json.loads(p.read_text()) if p.exists() else dict(enabled=False,desktop=True,resets=True,recovery=True,archivedEvents=3,lastSuccess='2026-10-14T00:00:00Z')
a=sys.argv[1:]
if a[0]=='status':print(json.dumps(d))
else:
 with (Path.home()/'company-calls.jsonl').open('a') as f:f.write(json.dumps(a)+'\\n')
 if a[0] in ('on','off'):d['enabled']=a[0]=='on'
 elif a[0]=='set':d[a[1]]=a[2]=='on'
 p.write_text(json.dumps(d))
''');p.chmod(0o755)

try:
    until(lambda:json.loads(call('settings','status'))['ready'])
    call('settings','open','company')
    until(lambda:json.loads(call('test','locate','companyAlertsMaster')))
    assert json.loads(call('test','locate','companyAlertsFeatures')) is None
    click('companyAlertsMaster')
    until(lambda:json.loads(call('test','locate','companyAlertsFeatures')))
    click('companyAlertsDesktop');click('companyAlertsResets');click('companyAlertsRecovery')
    until(lambda:json.loads((OUT/'company-fixture.json').read_text())['recovery'] is False)
    fixture=json.loads((OUT/'company-fixture.json').read_text())
    assert all(not fixture[k] for k in ['desktop','resets','recovery'])
    screenshot('company-alerts')
    click('companyAlertsMaster')
    until(lambda:json.loads(call('test','locate','companyAlertsFeatures')) is None)
    assert config.read_bytes()==initial_bytes,'Company controls changed unrelated shell configuration'
    calls=[json.loads(l) for l in (OUT/'company-calls.jsonl').read_text().splitlines()]
    assert calls==[['on'],['set','desktop','off'],['set','resets','off'],['set','recovery','off'],['off']],calls
    print('PASS: company page, master off hides controls, feature switches, unrelated settings preserved')
finally:
    process.terminate();process.wait(timeout=10);log.close()
