#!/usr/bin/env python3
"""Real settings controls with a private monitor and synthetic session snapshot."""
from pathlib import Path
source=Path(__file__).with_name('settings_ui.py')
setup=source.read_text().split('\ntry:\n    until(',1)[0]
setup=setup.replace('        function value(path: string): string {','''        function agentState(): string { const node=root.testFind("agentSessions");return JSON.stringify({sessions:node.sessions.map(s=>s.name),enabled:node.configuration.enabled,titles:node.configuration.titles,expanded:node.expanded}); }
        function agentSort(index: int): void { const node=root.testFind("agentSessionSort");node.currentIndex=index;node.activated(index); }
        function value(path: string): string {''')
setup=setup.replace('process = subprocess.Popen(','''
monitor=OUT/'.local/bin/agent-monitor'
monitor_state=RUNTIME/'agent-monitor/snapshot.json';monitor_state.parent.mkdir(parents=True)
process_row=dict(pid=4242,start_ticks=1,name='codex',agent='Codex',ppid=1,rss=32*1024**2,swap=1024**2,virtual=600*1024**2,cpu_percent=1,age_seconds=7200,cgroup='',routes=['tmux Phone %2 · SSH/Haven attached'],evidence='displayed title match')
session=dict(id='11111111-1111-4111-8111-111111111111',name='Build maps',clients=[process_row],workloads=[],writer_pids=[77],rss=0,swap=0,client_rss=process_row['rss'],client_swap=process_row['swap'],cpu_percent=0,peak_cpu_percent=25,peak_rss=1024**2,workload_count=0,process_ids=[4242])
other=dict(session,id='22222222-2222-4222-8222-222222222222',name='Heavy render',clients=[],client_rss=0,client_swap=0,rss=512*1024**2,cpu_percent=120,process_ids=[])
monitor_state.write_text(json.dumps(dict(version=1,timestamp=time.time(),config=dict(enabled=False,titles=True),sessions=[session,other],shared=[dict(process_row,session_ids=[session['id'],other['id']])],unmatched_clients=[],unattributed=[])))
monitor.write_text("#!/usr/bin/python3\\nimport json,sys,time\\nfrom pathlib import Path\\np=Path("+repr(str(monitor_state))+");d=json.loads(p.read_text());a=sys.argv[1:]\\nif a[0] in ('enable','disable'):d['config']['enabled']=a[0]=='enable'\\nif a[0]=='titles':d['config']['titles']=a[1]=='on'\\nd['timestamp']=time.time();p.write_text(json.dumps(d));print(json.dumps(d))\\n")
monitor.chmod(0o755)
process = subprocess.Popen(''')
exec(compile(setup,str(source),'exec'),globals())
try:
    until(lambda:json.loads(call('settings','status'))['ready'])
    call('settings','open','agents')
    until(lambda:json.loads(call('test','locate','agentMonitorMaster')))
    assert not json.loads(call('test','agentState'))['enabled']
    assert json.loads(call('test','locate','agentMonitorDetails')) is None
    click('agentMonitorMaster')
    until(lambda:json.loads(call('test','agentState'))['enabled'])
    assert json.loads(call('test','agentState'))['sessions']==['Heavy render','Build maps']
    call('test','text','agentSessionSearch','4242')
    until(lambda:json.loads(call('test','agentState'))['sessions']==['Build maps'])
    click('agentDetails:11111111-1111-4111-8111-111111111111')
    assert json.loads(call('test','agentState'))['expanded'].startswith('11111111')
    click('agentMonitorTitles')
    until(lambda:not json.loads(call('test','agentState'))['titles'])
    call('test','text','agentSessionSearch','not-a-session')
    until(lambda:not json.loads(call('test','agentState'))['sessions'])
    call('test','text','agentSessionSearch','')
    call('test','agentSort','3')
    until(lambda:json.loads(call('test','agentState'))['sessions']==['Build maps','Heavy render'])
    call('test','reveal','agentSessionSearch');screenshot('agent-sessions')
    click('agentMonitorMaster')
    until(lambda:not json.loads(call('test','agentState'))['enabled'])
    assert json.loads(call('test','locate','agentMonitorDetails')) is None
    assert json.loads(config.read_text())==initial, 'unrelated desktop configuration changed'
    print('PASS: AI sessions page, master and title switches, CPU/name order, PID search, details, empty state and unchanged desktop config')
finally:
    process.terminate();process.wait(timeout=10);log.close()
