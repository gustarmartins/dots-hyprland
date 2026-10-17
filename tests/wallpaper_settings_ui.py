#!/usr/bin/env python3
"""Run the real Settings wallpaper workflow in a disposable home and X/DBus session.

xvfb-run -a -s '-screen 0 1400x950x24' dbus-run-session -- python tests/wallpaper_settings_ui.py

Only HTTP responses and the desktop apply command are fixtures. Real discovery,
validation, storage, history, prefetch and read-ahead code runs without changing
live wallpaper/colors. The copied rotation timer is accelerated for the test.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix='wallpaper-settings-ui-'))
RUNTIME = OUT / 'runtime'
RUNTIME.mkdir(mode=0o700)
shutil.copytree(REPO / 'dots/.config/quickshell/ii', OUT / 'config/quickshell/ii')
config = OUT / 'config/illogical-impulse/config.json'
config.parent.mkdir(parents=True)
initial = json.loads((REPO / 'profile/illogical-impulse/config.json').read_text())
initial['settingsTestSentinel'] = {'preserve': ['unrelated', 42]}
initial.setdefault('background', {})['discovery'] = {'theme':'mario', 'rotate':False, 'intervalMinutes':60, 'prefetchCount':3, 'prefetchAhead':False, 'storageLimitMiB':64, 'minFreeMiB':0}
from PIL import Image
import io
collection = OUT / 'Pictures/Wallpapers/Discovery'
collection.mkdir(parents=True)
state = OUT / 'state/wallpaper-discovery'
(state / 'sources').mkdir(parents=True)
for identity, color, applied in [('seed-current','navy',100),('seed-old','orange',50)]:
    path = collection / ('mario-' + identity + '.png')
    Image.new('RGB',(1920,1080),color).save(path)
    record = {'id':identity,'path':str(path),'theme':'mario','label':'Mario worlds','width':1920,'height':1080,'fetchedAt':applied,'appliedAt':applied,'queued':False}
    (state / 'sources' / (identity + '.json')).write_text(json.dumps(record))
    if identity == 'seed-current':
        initial['background']['wallpaperPath'] = str(path)
        (state / 'current.json').write_text(json.dumps(record))
config.write_text(json.dumps(initial, indent=2))
(OUT / 'config/user-dirs.dirs').write_text('XDG_PICTURES_DIR="$HOME/Pictures"\n')
initial_bytes = config.read_bytes()
(OUT / '.local/bin').mkdir(parents=True)
helper = OUT / '.local/bin/fontctl'
helper.write_text('''#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
root=Path.home()
if 'catalog' in sys.argv or '--preview' in sys.argv:
    raise SystemExit(subprocess.call(['bash', REAL, *sys.argv[1:]]))
p=root/'config/illogical-impulse/config.json'
data=json.loads(p.read_text());data['appearance']['fonts']['main']='Fixture Font'
p.write_text(json.dumps(data))
(root/'font-apply-receipt').write_text(json.dumps(sys.argv[1:]))
print('Applied fixture font')
'''.replace('REAL', repr(str(REPO / 'dots/.local/bin/fontctl'))))
helper.chmod(0o755)
for name, output in [('desktop-effects', '[]'), ('easyeffects-qs', '{}')]:
    p = OUT / '.local/bin' / name
    p.write_text('#!/bin/sh\nprintf \'%s\\n\' \'' + output + '\'\n')
    p.chmod(0o755)
env = os.environ.copy()
for key in ['WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
    env.pop(key, None)
env.update(HOME=str(OUT), XDG_CONFIG_HOME=str(OUT / 'config'),
           XDG_DATA_HOME=str(OUT / 'data'), XDG_CACHE_HOME=str(OUT / 'cache'),
           XDG_STATE_HOME=str(OUT / 'state'), XDG_RUNTIME_DIR=str(RUNTIME),
           QT_QPA_PLATFORM='xcb', QT_QUICK_BACKEND='software')
# Keep D-Bus-activated optional services inside the same disposable environment.
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
env.update(WAYLAND_DISPLAY='', HYPRLAND_INSTANCE_SIGNATURE='')
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME',
                'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'WAYLAND_DISPLAY',
                'HYPRLAND_INSTANCE_SIGNATURE', 'DISPLAY', 'QT_QPA_PLATFORM'], env=env, check=True)
entry = OUT / 'config/quickshell/ii/settings.qml'
# UI inspection is injected into the disposable copy, never the production app.
probe = r'''
    function testFind(name) {
        let queue = [root.contentItem]; let seen = new Set();
        while (queue.length) {
            const node = queue.shift();
            if (!node || seen.has(node)) continue;
            seen.add(node);
            if (node.objectName === name && node.visible) return node;
            for (const child of (node.children || [])) queue.push(child);
            if (node.item) queue.push(node.item);
            if (node.contentItem) queue.push(node.contentItem);
        }
        return null;
    }
    IpcHandler {
        target: "test"
        function locate(name: string): string {
            const node = root.testFind(name); if (!node) return "null";
            const at = node.mapToItem(null, node.width / 2, node.height / 2);
            return JSON.stringify({x:at.x,y:at.y,width:node.width,height:node.height,enabled:node.enabled,text:node.text ?? ""});
        }
        function text(name: string, value: string): void { const node=root.testFind(name); if (node) node.text=value; }
        function reveal(name: string): void {
            const node = root.testFind(name); if (!node) return;
            const view = root.currentPage === "design" && !root.searching ? designPage.contentItem : catalogPage.contentItem;
            const at = node.mapToItem(view, 0, 0);
            view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + at.y - 100));
        }
        function library(): string { return JSON.stringify({library:WallpaperDiscovery.library,busy:WallpaperDiscovery.busy,current:WallpaperDiscovery.current,next:WallpaperDiscovery.nextRotationAt,count:root.testFind("wallpaperHistoryGrid")?.count}); }
        function warmAhead(): void { WallpaperDiscovery.localPrefetchAttemptAt=0;WallpaperDiscovery.prefetchState=({attemptedAt:0});Config.options.background.discovery.prefetchAhead=true;Config.options.background.discovery.rotate=true;WallpaperDiscovery.rotationOwner=true; }
        function resize(width: int, height: int): void { root.width=width;root.height=height; }
        function value(path: string): string { let o=Config.options; for (const key of path.split(".")) o=o[key];return JSON.stringify(o); }
    }
'''
source = entry.read_text()
entry.write_text(source[:source.rfind('}')] + probe + '\n}\n')

# The real Python download pipeline reads an isolated fake HTTP provider.
# It writes real validated images and metadata but never uses the network.
site = OUT / 'python-fixture'; site.mkdir()
(site / 'sitecustomize.py').write_text(r"""
import io,json,urllib.request
from PIL import Image
class Response(io.BytesIO):
    def __init__(self,url,data):
        super().__init__(data);self.url=url;self.headers={'Content-Length':str(len(data))}
def open_fixture(request,timeout=None):
    url=request.full_url if hasattr(request,'full_url') else request
    items=[]
    for i in range(1,10):
        buffer=io.BytesIO();Image.new('RGB',(1920,1080),['red','green','blue'][i%3]).save(buffer,'PNG')
        image=buffer.getvalue()
        identity='fixture'+str(i)
        items.append(dict(id=identity,path='https://w.wallhaven.cc/full/fi/'+identity+'.png',url='https://wallhaven.cc/w/'+identity,category='general',purity='sfw',dimension_x=1920,dimension_y=1080,file_size=len(image),tags=[{'name':'Super Mario'}]))
        if url.endswith(identity+'.png'):return Response(url,image)
    if '/api/v1/search?' in url:return Response(url,json.dumps({'data':items}).encode())
    if '/api/v1/w/' in url:return Response(url,json.dumps({'data':next(i for i in items if i['id']==url.rsplit('/',1)[-1])}).encode())
    raise AssertionError('Unexpected external request: '+url)
urllib.request.urlopen=open_fixture
""")
env['PYTHONPATH'] = str(site)
# Accelerate only the copied rotation timer to exercise its real refill branch.
service = OUT / 'config/quickshell/ii/services/WallpaperDiscovery.qml'
service.write_text(service.read_text().replace('interval: 15000', 'interval: 100').replace('function libraryAction(args) {', 'function libraryAction(args) { console.log("TEST_ACTION", JSON.stringify(args), root.busy);'))
# The production apply entrypoint is replaced only in this disposable copy.
apply = OUT / 'config/quickshell/ii/scripts/colors/switchwall.sh'
apply.write_text("#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\np=Path(os.environ['XDG_CONFIG_HOME'])/'illogical-impulse/config.json'\nc=json.loads(p.read_text());c['background']['wallpaperPath']=sys.argv[-1]\np.write_text(json.dumps(c))\n(Path.home()/'apply-receipt').write_text(sys.argv[-1])\n")
apply.chmod(0o755)
# Remove shared /tmp cleanup from the copied Directories singleton.
p = OUT / 'config/quickshell/ii/modules/common/Directories.qml'
source = p.read_text(); p.write_text(source[:source.index('    // Cleanup on init')]+'}\n')

log = (OUT / 'settings.log').open('w')
process = subprocess.Popen(['qs', '-p', str(entry)], env=env, stdout=log, stderr=subprocess.STDOUT)
print('ARTIFACTS', OUT, flush=True)


def call(target, *args):
    return subprocess.check_output(['qs', '-p', str(entry), 'ipc', 'call', target, *args],
                                   env=env, text=True, stderr=subprocess.DEVNULL, timeout=5).strip()


def until(fn, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if process.poll() is not None:
            raise AssertionError((OUT / 'settings.log').read_text()[-5000:])
        try:
            value = fn()
            if value:
                return value
        except (subprocess.SubprocessError, json.JSONDecodeError, FileNotFoundError):
            pass
        time.sleep(.08)
    raise AssertionError('Timed out; see ' + str(OUT))


def read(path):
    obj = json.loads(config.read_text())
    for key in path.split('.'):
        obj = obj[key]
    return obj


def select(path):
    call('settings', 'search', path)
    until(lambda: json.loads(call('test', 'locate', 'setting:' + path)))
    time.sleep(.12)


def click(name):
    node = until(lambda: json.loads(call('test', 'locate', name)))
    if node['y'] < 145 or node['y'] > 735:
        call('test', 'reveal', name)
        time.sleep(.15)
        node = json.loads(call('test', 'locate', name))
    assert node['enabled'] and 0 <= node['x'] < 1180 and 145 <= node['y'] < 750, (name, node)
    windows = subprocess.check_output(['xdotool', 'search', '--name', '^illogical-impulse Settings$'], env=env, text=True).splitlines()
    subprocess.run(['xdotool', 'mousemove', '--window', windows[-1], str(round(node['x'])), str(round(node['y'])), 'click', '1'], env=env, check=True)
    time.sleep(.2)


def type_text(name, text):
    click(name)
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+a'], env=env, check=True)
    subprocess.run(['xdotool', 'type', '--clearmodifiers', '--delay', '1', text], env=env, check=True)
    subprocess.run(['xdotool', 'key', 'Tab'], env=env, check=True)


def screenshot(name):
    subprocess.run(['magick', 'import', '-window', 'root', str(OUT / (name + '.png'))], env=env, check=True, capture_output=True)


def state_value(): return json.loads(call('test','library'))

try:
    until(lambda: json.loads(call('settings','status'))['ready'])
    call('settings','open','wallpaper')
    until(lambda: state_value()['library'].get('count')==2 and not state_value()['busy'])
    assert state_value().get('count') is None, 'Wallpaper thumbnails loaded above controls'
    click('wallpaperLibraryToggle')
    until(lambda: state_value().get('count')==2)
    before = read('background.wallpaperPath')
    deadline = state_value()['next']
    click('wallpaperKeep-seed-old')
    until(lambda: state_value()['library'].get('keptCount')==1 and not state_value()['busy'])
    click('wallpaperHistoryKeptOnly')
    until(lambda: state_value()['count']==1)
    click('wallpaperHistoryKeptOnly')
    click('wallpaperPrefetch')
    until(lambda: state_value()['library'].get('queuedCount')==3 and not state_value()['busy'],timeout=40)
    assert read('background.wallpaperPath')==before, 'Prefetch changed wallpaper'
    assert not (OUT/'apply-receipt').exists(), 'Prefetch applied wallpaper/colors'
    assert state_value()['next']==deadline, 'Prefetch reset the rotation deadline'
    assert state_value()['library']['count']==5
    for wallpaper in state_value()['library']['entries']:
        assert Path(wallpaper['path']).is_file()
        assert Path(wallpaper['thumbnail']).is_file()
    screenshot('prefetched')
    click('wallpaperHistoryReadyOnly')
    until(lambda: state_value()['count']==3)
    target=next(e for e in state_value()['library']['entries'] if e.get('queued'))
    click('wallpaperRestore-'+target['id'])
    until(lambda: read('background.wallpaperPath')==target['path'] and not state_value()['busy'])
    assert state_value()['library']['queuedCount']==2
    assert (OUT/'apply-receipt').read_text()==target['path']
    click('wallpaperHistoryReadyOnly')
    click('wallpaperHistoryKeptOnly')
    until(lambda: state_value()['count']==1)
    click('wallpaperRestore-seed-old')
    until(lambda: state_value()['current'].get('id')=='seed-old' and not state_value()['busy'])
    assert read('background.wallpaperPath').endswith('mario-seed-old.png')
    assert read('settingsTestSentinel')=={'preserve':['unrelated',42]}
    click('wallpaperHistoryKeptOnly')
    queued=next(e for e in state_value()['library']['entries'] if e.get('queued'))
    click('wallpaperRestore-'+queued['id'])
    until(lambda: state_value()['library']['queuedCount']==1 and not state_value()['busy'])
    before_refill=read('background.wallpaperPath')
    call('test','warmAhead')
    until(lambda: state_value()['library']['queuedCount']==3 and not state_value()['busy'],timeout=40)
    assert read('background.wallpaperPath')==before_refill, 'Read-ahead applied a wallpaper'
    assert (OUT/'apply-receipt').read_text()==before_refill
    call('test','resize','700','650');time.sleep(.3)
    screenshot('narrow')
    assert not any(x in (OUT/'settings.log').read_text() for x in ['ReferenceError:', 'TypeError:', 'Unable to assign', 'Binding loop', 'Failed to load configuration'])
    print('PASS: Settings gallery, keep/filter, real batch prefetch, no colors/apply during prefetch, unchanged rotation deadline, offline apply/restore, automatic queue refill without apply, preserved unrelated settings, narrow rendering',flush=True)

finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    log.close()
