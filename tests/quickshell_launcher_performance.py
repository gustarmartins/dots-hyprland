#!/usr/bin/env python3
"""Exercise launcher data and real result delegates with synthetic desktop entries and clipboard.

Run under a private Xvfb and D-Bus session. --reference accepts a saved shell tree
for a matched comparison and records its behavior without enforcing the new budget.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reference", type=Path)
args = parser.parse_args()
assert os.environ.get("DBUS_SESSION_BUS_ADDRESS") and f"/run/user/{os.getuid()}/bus" not in os.environ["DBUS_SESSION_BUS_ADDRESS"]
out = Path(tempfile.mkdtemp(prefix="qs-search-"))
shell = out / "config/quickshell/ii"
shutil.copytree(args.reference or repo / "dots/.config/quickshell/ii", shell)
directories = shell / "modules/common/Directories.qml"
directories.write_text(directories.read_text().split("    // Cleanup on init")[0] + "}\n")
for name in ("run", "home", "bin", "data/applications", "state", "cache", "config/illogical-impulse"):
    (out / name).mkdir(mode=0o700, parents=True, exist_ok=True)
(out / "config/illogical-impulse/config.json").write_text(json.dumps({
    "search":{"nonAppResultDelay":60,"prefix":{"showDefaultActionsWithoutPrefix":True}},
    "cryod":{"enabled":False}
}))
for i in range(128):
    (out / f"data/applications/test{i:03d}.desktop").write_text(
        f"[Desktop Entry]\nType=Application\nName=Fixture App {i:03d}\nExec=/usr/bin/true\n"
        "Icon=applications-system\nActions=alt;\n[Desktop Action alt]\nName=Alternate\nExec=/usr/bin/true\n")
qalc = out / "bin/qalc"
qalc.write_text('#!/bin/sh\nprintf "%s\\n" "$2" >> "$HOME/calculations"\nprintf "fixture %s\\n" "$2"\n')
qalc.chmod(0o755)
env = dict(os.environ, PATH=f'{out}/bin:/usr/bin', HOME=str(out/'home'),XDG_CONFIG_HOME=str(out/'config'),
           XDG_DATA_HOME=str(out/'data'),XDG_DATA_DIRS=str(out/'data'),XDG_RUNTIME_DIR=str(out/'run'),
           XDG_CACHE_HOME=str(out/'cache'),XDG_STATE_HOME=str(out/'state'),QT_QUICK_BACKEND='software',
           QT_NO_XDG_DESKTOP_PORTAL='1',XDG_CURRENT_DESKTOP='test',WAYLAND_DISPLAY='',HYPRLAND_INSTANCE_SIGNATURE='')
env["QT_HASH_SEED"]="0"
subprocess.run(['dbus-update-activation-environment',*[k for k in env if k.startswith(('XDG_','QT_'))],
                'HOME','PATH','DISPLAY','WAYLAND_DISPLAY','HYPRLAND_INSTANCE_SIGNATURE'],env=env,check=True)
entry = shell/'audit-search.qml'
entry.write_text('''//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.ii.overview
import qs.modules.waffle.startMenu
import qs.modules.waffle.startMenu.searchPage
ShellRoot {
    id: root
    property bool waffle: false
    Window {
        visible: true; width: 1000; height: 640
        Loader { active: !root.waffle; sourceComponent: SearchWidget {} }
        Loader { anchors.fill: parent; active: root.waffle
            sourceComponent: SearchResults { context: StartMenuContext {} } }
    }
    function fill() {
        Cliphist.entries = Array.from({length:256}, (_,i) => i+"\\tfixture row "+i);
        Emojis.list = Array.from({length:96}, (_,i) => "🌟 fixture emoji "+i);
    }
    IpcHandler {
        target: "fixture"
        function ready(): bool { return Config.ready && AppSearch.list.length >= 128; }
        function seed(): void { root.fill(); }
        function family(alternate: bool): void { root.waffle=alternate; }
        function query(text: string): string {
            const start=Date.now();
            LauncherSearch.query=text;
            const rows=LauncherSearch.results;
            const ms=Date.now()-start;
            const values=rows.map(r=>[r.name,r.type,r.id||"",(r.actions||[]).map(a=>a.name)]);
            const apps=rows.filter(r=>r.type==="App").map(r=>r.id);
            const expected=text.startsWith(">") ? AppSearch.fuzzyQuery(text.slice(1)).map(r=>r.id) : apps;
            return JSON.stringify({ms,values,nativeRows:rows.filter(r=>Qt.isQtObject(r)).length,
                correctOrder:JSON.stringify(apps)===JSON.stringify(expected)});
        }
    }
}''')

def call(method,*values):
    return subprocess.check_output(['/usr/bin/qs','-p',str(entry),'ipc','call','fixture',method,*values],
                                   env=env,text=True,stderr=subprocess.DEVNULL,timeout=6).strip()
def query(text):
    return json.loads(call('query',text))
def wait(check,seconds=10):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        try:
            if check(): return
        except (subprocess.SubprocessError,ValueError): pass
        time.sleep(.04)
    raise AssertionError(f"Fixture timed out. See {out}/shell.log")
with (out/'shell.log').open('w') as log:
    proc=subprocess.Popen(['/usr/bin/qs','-p',str(entry),'--no-color'],env=env,stdout=log,stderr=subprocess.STDOUT)
    try:
        wait(lambda:call('ready')=='true')
        call('seed')
        signatures={}
        timings={}
        counts={}
        for needle in (';','>Fixture App',':fixture'):
            samples=[]
            for _ in range(7):
                query('')
                response=query(needle)
                samples.append(response['ms'])
            values=response['values']
            assert response['correctOrder'],needle
            assert len(values)>30, (needle,len(values),out)
            if needle==';':
                assert len(values)==256 and values[-1][0]=='fixture row 255' and values[0][3]==['Copy','Delete'],values[:1]
            if needle.startswith('>'):
                assert any(row[2].startswith('test') and row[3]==['Alternate'] for row in values)
            # The calculator row is asynchronous. Check its value separately after the reply.
            canonical=[["<calculation>" if row[1]=="Math result" else row[0],*row[1:]] for row in values]
            signatures[needle]=hashlib.sha256(json.dumps(canonical,ensure_ascii=False).encode()).hexdigest()
            timings[needle]=statistics.median(samples)
            counts[needle]={'results':len(values),'nativeRows':response['nativeRows']}
        # Force both views to render the results, including nested action delegates.
        if not args.reference:
            call('family','true')
            for needle in (';','>Fixture App 001',':fixture'):
                assert query(needle)['values']
                time.sleep(.08)
            call('family','false')
        query('=6*7')
        wait(lambda:any(v[0]=='fixture 6*7' for v in query('=6*7')['values']))
        time.sleep(.25)
        invocations=(out/'home/calculations').read_text().splitlines().count('6*7')
        query('')
        if not args.reference:
            assert invocations==1,invocations
            assert counts[';']['nativeRows']==0 and counts[':fixture']['nativeRows']==0,counts
    finally:
        proc.terminate()
        try:proc.wait(timeout=4)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
logtext=(out/'shell.log').read_text()
errors=[line for line in logtext.splitlines() if any(msg in line for msg in ('TypeError:', 'ReferenceError:', 'Cannot assign', 'is not a function', 'Required property'))]
if errors and not args.reference: raise AssertionError((out,errors[:6]))
result={'status':'passed','reference':bool(args.reference),'timings_ms':timings,'rows':counts,'signatures':signatures,
        'calculator_calls':invocations,'errors':errors[:5],'output':str(out)}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
