#!/usr/bin/env python3
"""Exercise merged workspace widgets on two private Wayland outputs.

Run with dbus-run-session -- python3 tests/quickshell_workspace_integration.py.
Requires KWin Wayland, Hyprland (Lua), Kitty, grim and the patched Quickshell.
No live compositor, configuration, input, or audio service is used.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix='qs-workspaces-'))
RUNTIME = Path(tempfile.mkdtemp(prefix='qw-'))
RUNTIME.chmod(0o700)
env = os.environ.copy()
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
    env.pop(key, None)
env.update(HOME=str(OUT / 'home'), XDG_CONFIG_HOME=str(OUT / 'config'),
           XDG_DATA_HOME=str(OUT / 'data'), XDG_CACHE_HOME=str(OUT / 'cache'),
           XDG_STATE_HOME=str(OUT / 'state'), XDG_RUNTIME_DIR=str(RUNTIME),
           QT_QPA_PLATFORM='offscreen', AQ_DRM_DEVICES='/nonexistent-test-device',
           QT_NO_XDG_DESKTOP_PORTAL='1', NO_AT_BRIDGE='1', XDG_CURRENT_DESKTOP='')
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME',
                'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'QT_QPA_PLATFORM'], env=env, check=True)
processes, logs = [], []


def launch(args, name):
    log = (OUT / (name + '.log')).open('w')
    logs.append(log)
    process = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
    processes.append(process)
    return process


def until(fn, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = fn()
            if result:
                return result
        except (subprocess.SubprocessError, json.JSONDecodeError):
            pass
        time.sleep(.06)
    raise AssertionError('Timeout; inspect ' + str(OUT))


def ctl(*args):
    return subprocess.check_output(['hyprctl', *args], env=env, text=True, timeout=5).strip()


try:
    shell = OUT / 'config/quickshell/ii'
    shutil.copytree(Path(os.environ.get('QS_TEST_SHELL_ROOT', str(REPO / 'dots/.config/quickshell/ii'))), shell)
    widget = shell / 'modules/ii/bar/Workspaces.qml'
    widget.write_text(widget.read_text().replace('    id: root\n', '    id: root\n    property alias testModel: wsModel\n', 1))
    settings = OUT / 'config/illogical-impulse/config.json'
    settings.parent.mkdir(parents=True)
    settings.write_text(json.dumps({'bar': {'workspaces': {'shown': 5, 'alwaysShowNumbers': True, 'showAppIcons': True}}}))
    entry = shell / 'workspace-test.qml'
    entry.write_text('''//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.ii.bar as Bar
import qs.services
ShellRoot {
 id: root
 property bool vertical: false
 property var panels: []
 function labels(node) {
  let result=[];
  function visit(n) {
   if (n.text !== undefined) { let at=n.mapToItem(node,0,0); result.push({text:n.text,visible:n.visible,opacity:n.opacity,color:String(n.color),x:at.x,y:at.y,width:n.width,height:n.height}); }
   for (const c of (n.children ?? [])) visit(c);
  }
  visit(node); return result;
 }
 Variants {
  model: Quickshell.screens
  PanelWindow {
   id: panel
   required property var modelData
   screen: modelData
   anchors { top: true; left: true; right: true }
   implicitHeight: root.vertical ? 240 : 48
   color: "#202028"
   property alias widget: spaces
   Bar.BarContent { x: 160; width: 1100; height: 48 }
   Bar.Workspaces { id: spaces; width: implicitWidth; height: implicitHeight; vertical: root.vertical }
   Component.onCompleted: root.panels.push(panel)
  }
 }
 IpcHandler {
  target: "test"
  function state(): string { return JSON.stringify({ready: Config.ready, distro: SystemInfo.distroId,
   panels: root.panels.map(p => ({screen:p.screen.name, labels:root.labels(p.widget), active:p.widget.testModel.activeWorkspace,
    count:p.widget.testModel.shownCount, occupied:p.widget.testModel.occupied,
    biggest:p.widget.testModel.biggestWindow.map(w=>w?.class ?? ""),
    fake:p.widget.testModel.fakeWorkspace, special:p.widget.testModel.specialWorkspaceActive,
    specialName:p.widget.testModel.specialWorkspaceName, group:p.widget.testModel.group,
    ids:p.widget.testModel.occupied.map((_,i)=>p.widget.testModel.getWorkspaceIdAt(i)),
    width:p.widget.width,height:p.widget.height,padding:p.widget.widgetPadding,
    index:p.widget.workspaceIndexInGroup,hover:p.widget.hoverIndex,vertical:p.widget.vertical}))}); }
  function configure(count: int, vertical: bool): void { Config.options.bar.workspaces.shown=count; root.vertical=vertical; }
  function special(index: int): void { root.panels[index].widget.toggleSpecial(); }
  function selectHovered(index: int): void { root.panels[index].widget.switchWorkspaceToHovered(); }
  function osRelease(text: string): string { SystemInfo.applyOsRelease(text); return JSON.stringify({id:SystemInfo.distroId,name:SystemInfo.distroName,icon:SystemInfo.distroIcon}); }
 }
}''')
    launch(['kwin_wayland', '--virtual', '--width', '1280', '--height', '720',
            '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities', '--socket', 'test-parent'], 'kwin')
    until(lambda: (RUNTIME / 'test-parent').exists())
    env.update(WAYLAND_DISPLAY='test-parent', QT_QPA_PLATFORM='wayland')
    config = OUT / 'hyprland.lua'
    config.write_text('hl.monitor({output="",mode="1280x720@60",position="auto",scale=1})\n'
                      'hl.config({animations={enabled=false},misc={disable_hyprland_logo=true,disable_splash_rendering=true},input={follow_mouse=0}})\n')
    launch(['Hyprland', '--config', str(config)], 'hyprland')
    socket = until(lambda: next((RUNTIME / 'hypr').glob('*/.socket.sock'), None))
    env['HYPRLAND_INSTANCE_SIGNATURE'] = socket.parent.name
    env['WAYLAND_DISPLAY'] = until(lambda: next((p.name for p in RUNTIME.glob('wayland-*') if not p.name.endswith('.lock')), None))
    until(lambda: json.loads(ctl('-j', 'monitors')))
    ctl('output', 'create', 'headless', 'QS-SECOND')
    until(lambda: len(json.loads(ctl('-j', 'monitors'))) == 2)
    ctl('eval', 'hl.monitor({output="QS-SECOND",mode="1280x720@60",position="1280x0",scale=1}); hl.workspace_rule({workspace="6",monitor="QS-SECOND"}); hl.dispatch(hl.dsp.focus({workspace="6"}))')
    qs = launch([os.environ.get('QS_TEST_BINARY', 'qs'), '-p', str(entry)], 'shell')

    def call(*args):
        return subprocess.check_output([os.environ.get('QS_TEST_BINARY', 'qs'), '-p', str(entry), 'ipc', 'call', 'test', *args], env=env, text=True, stderr=subprocess.DEVNULL, timeout=5).strip()

    def state():
        return json.loads(call('state'))

    s = until(lambda: (s if s['ready'] and len(s['panels']) == 2 and s['distro'] != 'unknown' and {p['active'] for p in s['panels']} == {1, 6} else None) if (s := state()) else None)
    assert {p['active'] for p in s['panels']} == {1, 6}, s
    assert all(p['padding'] == 4 and p['width'] == 110 and not p['special'] for p in s['panels']), s
    for p in s['panels']:
        assert p['ids'] == ([1, 2, 3, 4, 5] if p['active'] == 1 else [6, 7, 8, 9, 10]), p
    launch(['kitty', '--config', 'NONE', '--class', 'kitty', '/usr/bin/sleep', '300'], 'client')
    until(lambda: any('kitty' in p['biggest'] and p['active'] == 6 and p['fake'] == -9999 for p in state()['panels']))
    ctl('dispatch', 'hl.dsp.focus({workspace="1"})')
    s = until(lambda: (s if any(p['active'] == 1 and p['fake'] == 1 for p in s['panels']) else None) if (s := state()) else None)
    assert any(p['active'] == 6 and p['fake'] == -9999 for p in s['panels']), s
    ctl('dispatch', 'hl.dsp.focus({workspace="7"})')
    until(lambda: any(p['active'] == 7 and p['index'] == 1 for p in state()['panels']))
    second = next(i for i, p in enumerate(state()['panels']) if p['screen'] == 'QS-SECOND')
    call('selectHovered', str(second))
    until(lambda: any(p['active'] == 6 for p in state()['panels']))
    call('special', str(second))
    until(lambda: any(p['special'] and p['specialName'] == 'special' for p in state()['panels']))
    call('special', str(second))
    until(lambda: all(not p['special'] for p in state()['panels']))
    call('configure', '3', 'false')
    s = until(lambda: (s if all(p['count'] == 3 and p['width'] == 66 for p in s['panels']) else None) if (s := state()) else None)
    assert all(len(p['ids']) == 3 and len(p['occupied']) == 3 and len(p['biggest']) == 3 for p in s['panels']), s
    call('configure', '5', 'true')
    until(lambda: all(p['vertical'] and p['height'] == 110 for p in state()['panels']))
    time.sleep(.6)
    subprocess.run(['grim', str(OUT / 'vertical.png')], env=env, check=True, timeout=10)
    call('configure', '5', 'false')
    until(lambda: all(not p['vertical'] and p['width'] == 110 for p in state()['panels']))
    time.sleep(.6)
    subprocess.run(['grim', str(OUT / 'horizontal.png')], env=env, check=True, timeout=10)
    # Pixel assertions catch invisible shader-mask labels even when QML reports
    # visible=True and exposes the expected text and geometry.
    screenshot = Image.open(OUT / 'horizontal.png').convert('RGB')
    monitors = {m['name']: m for m in json.loads(ctl('-j', 'monitors'))}
    left = min(m['x'] for m in monitors.values())
    top = min(m['y'] for m in monitors.values())
    for panel in state()['panels']:
        monitor = monitors[panel['screen']]
        for label in panel['labels']:
            if label['text'] not in ('8', '9', '10'):
                continue
            x = monitor['x'] - left + int(label['x'])
            y = monitor['y'] - top + int(label['y'])
            pixels = screenshot.crop((x, y, x + int(label['width']), y + int(label['height'])))
            contrast = sum(max(abs(c - b) for c, b in zip(pixel, (32, 32, 40))) > 16
                           for pixel in (pixels.getpixel((x, y)) for y in range(pixels.height) for x in range(pixels.width)))
            assert contrast >= 3, ('Workspace label is not painted', panel['screen'], label)
    for quote in ['"', "'"]:

        r = json.loads(call('osRelease', f'PRETTY_NAME={quote}Manjaro Linux{quote}\nID={quote}manjaro{quote}\n'))
        assert r == {'id': 'manjaro', 'name': 'Manjaro Linux', 'icon': 'manjaro-symbolic'}, r
    r = json.loads(call('osRelease', 'PRETTY_NAME="Arch Linux"\nID=arch\n'))
    assert r['id'] == 'arch' and r['icon'] == 'arch-symbolic', r
    for panel in state()['panels']:
        assert {'8', '9', '10'} <= {label['text'] for label in panel['labels'] if label['visible']}, panel
    widget.write_text(widget.read_text() + "\n")
    until(lambda: (OUT / 'shell.log').read_text().count('Configuration Loaded') >= 2)
    until(lambda: state()['ready'] and len(state()['panels']) == 2)
    assert qs.poll() is None
    shell_log = (OUT / 'shell.log').read_text()
    errors = [line for line in shell_log.splitlines() if any(x in line for x in ['TypeError', 'ReferenceError', 'is not a type', 'Cannot assign', 'Binding loop', 'Failed to load configuration'])]
    assert not errors, errors
    assert 'Reloading configuration' in shell_log, 'Hot reload was not exercised'
    (OUT / 'final.json').write_text(json.dumps(state(), indent=2))
    print('PASS: two monitors, populated/unfocused and empty workspaces, group selection, special toggle, live count changes, both orientations, distro parsing. Artifacts:', OUT, flush=True)
finally:
    for process in reversed(processes):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    for log in logs:
        log.close()
