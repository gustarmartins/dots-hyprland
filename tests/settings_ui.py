#!/usr/bin/env python3
"""Exercise the real settings app in a disposable home and private X/DBus session.

Run: xvfb-run -a -s '-screen 0 1400x950x24' dbus-run-session -- python tests/settings_ui.py
No live settings, compositor, audio, or font changes are performed. Font preview
uses the real CLI; the apply helper is a fixture that edits only the test JSON.
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
OUT = Path(tempfile.mkdtemp(prefix='settings-ui-'))
RUNTIME = OUT / 'runtime'
RUNTIME.mkdir(mode=0o700)
shutil.copytree(REPO / 'dots/.config/quickshell/ii', OUT / 'config/quickshell/ii')
config = OUT / 'config/illogical-impulse/config.json'
config.parent.mkdir(parents=True)
initial = json.loads((REPO / 'profile/illogical-impulse/config.json').read_text())
initial['settingsTestSentinel'] = {'preserve': ['unrelated', 42]}
config.write_text(json.dumps(initial, indent=2))
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
            if (node.objectName === name) return node;
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
            const view = catalogPage.contentItem;
            const at = node.mapToItem(view, 0, 0);
            view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + at.y - 100));
        }
        function resize(width: int, height: int): void { root.width=width;root.height=height; }
        function value(path: string): string { let o=Config.options; for (const key of path.split(".")) o=o[key];return JSON.stringify(o); }
    }
'''
source = entry.read_text()
entry.write_text(source[:source.rfind('}')] + probe + '\n}\n')
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


def type_text(name, text):
    click(name)
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+a'], env=env, check=True)
    subprocess.run(['xdotool', 'type', '--clearmodifiers', '--delay', '1', text], env=env, check=True)
    subprocess.run(['xdotool', 'key', 'Tab'], env=env, check=True)


def screenshot(name):
    subprocess.run(['magick', 'import', '-window', 'root', str(OUT / (name + '.png'))], env=env, check=True, capture_output=True)


try:
    until(lambda: json.loads(call('settings', 'status'))['ready'])
    time.sleep(.3)
    baseline = json.loads(config.read_text())
    pages = json.loads(call('settings', 'status'))['pages']
    for page in pages:
        call('settings', 'open', page)
        time.sleep(.15)
        assert json.loads(call('settings', 'status'))['page'] == page
        if page in ['home', 'control', 'fonts']:
            screenshot(page)
    assert config.read_bytes() == initial_bytes, 'Opening pages wrote configuration'
    assert json.loads(config.read_text()) == baseline
    select('sidebar.keepRightSidebarLoaded')
    before = read('sidebar.keepRightSidebarLoaded')
    click('toggle:sidebar.keepRightSidebarLoaded')
    until(lambda: read('sidebar.keepRightSidebarLoaded') != before)
    select('resources.updateInterval')
    type_text('number:resources.updateInterval', '2500')
    until(lambda: read('resources.updateInterval') == 2500)
    type_text('number:resources.updateInterval', '0')
    time.sleep(.2)
    assert read('resources.updateInterval') == 2500, 'Invalid number was saved'
    select('apps.terminal')
    type_text('text:apps.terminal', 'fixture-terminal --flag')
    until(lambda: read('apps.terminal') == 'fixture-terminal --flag')
    select('ai.extraModels')
    original_models = read('ai.extraModels')
    call('test', 'text', 'text:ai.extraModels', '{bad json')
    click('save:ai.extraModels')
    time.sleep(.2)
    assert read('ai.extraModels') == original_models
    select('sidebar.quickToggles.style')
    # Activate the custom layout through the actual ComboBox keyboard path.
    click('choice:sidebar.quickToggles.style')
    subprocess.run(['xdotool', 'key', 'End', 'Return'], env=env, check=True)
    until(lambda: read('sidebar.quickToggles.style') == 'android')
    select('sidebar.quickToggles.android.toggles')
    count = len(read('sidebar.quickToggles.android.toggles'))
    click('quickTileExpand')
    click('quickTileAdd')
    until(lambda: len(read('sidebar.quickToggles.android.toggles')) == count + 1)
    call('settings', 'open', 'fonts')
    until(lambda: json.loads(call('test', 'locate', 'fontPreview'))['enabled'])
    click('fontPreview')
    until(lambda: json.loads(call('test', 'locate', 'fontApply'))['enabled'])
    before_apply = json.loads(config.read_text())
    click('fontApply')
    until(lambda: (OUT / 'font-apply-receipt').exists())
    until(lambda: not json.loads(call('settings', 'status'))['loading'])
    until(lambda: json.loads(call('test', 'value', 'appearance.fonts.main')) == 'Fixture Font')
    after_apply = json.loads(config.read_text())
    assert after_apply['settingsTestSentinel'] == {'preserve': ['unrelated', 42]}, 'Unrecognized user settings were lost'
    before_apply['appearance']['fonts']['main'] = 'Fixture Font'
    assert after_apply == before_apply, 'Font apply overwrote unrelated settings'
    call('settings', 'open', 'control')
    call('test', 'resize', '700', '600')
    time.sleep(.3)
    screenshot('compact')
    assert not any(x in (OUT / 'settings.log').read_text() for x in ['ReferenceError:', 'TypeError:', 'Unable to assign', 'Binding loop', 'Failed to load configuration'])
    print('PASS: all pages/read-only browsing, toggle and text persistence, numeric/JSON validation, tile editing, font preview/apply reload, unrelated-value preservation, compact rendering', flush=True)
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    log.close()
