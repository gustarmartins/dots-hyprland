#!/usr/bin/env python3
"""Actual widget animation/painter work pauses for hidden items and windows.

Run with xvfb-run -a dbus-run-session -- python3 tests/quickshell_hidden_animations.py.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
out = Path(tempfile.mkdtemp(prefix='qs-hidden-animation-'))
shell = out/'ii'
shutil.copytree(ROOT/'dots/.config/quickshell/ii', shell)
for directory in ('run', 'config/illogical-impulse', 'cache', 'state', 'data'):
    (out/directory).mkdir(parents=True, mode=0o700)
(out/'config/illogical-impulse/config.json').write_text('{}')
p = shell/'modules/common/Directories.qml'
p.write_text(p.read_text().split('    // Cleanup on init')[0]+'}\n')
p = shell/'modules/common/widgets/WavyLine.qml'
p.write_text(p.read_text().replace('    id: root', '    id: root\n    property int fixturePaints: 0', 1)
             .replace('    onPaint: {', '    onPaint: {\n        root.fixturePaints++;', 1))
fixture = shell/'shell.qml'
fixture.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.modules.common.widgets
Window {
 id: root; visible: true; width: 600; height: 400
 // Keep the global animation driver active while the tested window is hidden.
 Window {
  visible: true; width: 20; height: 20
  Rectangle { width:20;height:20;color:"red"; NumberAnimation on opacity {from:.2;to:1;duration:200;loops:Animation.Infinite} }
 }
 Item {
  id: group; anchors.fill:parent
  SineCookie { id:cookie; x:20;y:20; constantlyRotate:true }
  MaterialLoadingIndicator { id:busy; x:150;y:20;loading:true }
  StyledProgressBar { x:20;y:150;width:400;value:.7;wavy:true }
  StyledSlider { x:20;y:220;width:400;value:.6;configuration:StyledSlider.Configuration.Wavy }
 }
 function paints(node) {
  let n=node.fixturePaints ?? 0;
  for (const child of node.children ?? []) n+=paints(child);
  return n;
 }
 IpcHandler {
  target:"test"
  function groupVisible(shown:bool):void { group.visible=shown; }
  function windowVisible(shown:bool):void { root.visible=shown; }
  function state():string { return JSON.stringify({rotation:cookie.shapeRotation,
    busyRotation:busy.continuousRotation,shape:busy.shapeIndex,paintCount:root.paints(group)}); }
 }
}
''')
env = os.environ.copy()
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
env.update(HOME=str(out), XDG_CONFIG_HOME=str(out/'config'), XDG_STATE_HOME=str(out/'state'),
           XDG_CACHE_HOME=str(out/'cache'), XDG_DATA_HOME=str(out/'data'), XDG_RUNTIME_DIR=str(out/'run'),
           QT_QPA_PLATFORM='xcb', QT_QUICK_BACKEND='software', QT_NO_XDG_DESKTOP_PORTAL='1',
           NO_AT_BRIDGE='1', WAYLAND_DISPLAY='', HYPRLAND_INSTANCE_SIGNATURE='', XDG_CURRENT_DESKTOP='test')
for key in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME'):
    env.pop(key, None)
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME',
                'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_RUNTIME_DIR', 'QT_QPA_PLATFORM', 'DISPLAY',
                'QT_NO_XDG_DESKTOP_PORTAL', 'NO_AT_BRIDGE', 'WAYLAND_DISPLAY',
                'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP'], env=env, check=True)


def call(action, *args):
    result = subprocess.check_output(['qs', '-p', str(fixture), 'ipc', 'call', 'test', action, *args],
                                     env=env, text=True, stderr=subprocess.DEVNULL, timeout=3).strip()
    return json.loads(result) if result else None


with (out/'shell.log').open('w') as log:
    process = subprocess.Popen(['qs', '-p', str(fixture)], env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic()+8
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise AssertionError((out/'shell.log').read_text())
            try:
                if call('state')['rotation'] > 0:
                    break
            except (subprocess.SubprocessError, ValueError):
                pass
            time.sleep(.05)
        else:
            raise AssertionError('Visible animation did not start')
        before = call('state'); time.sleep(.4); after = call('state')
        assert after['rotation'] > before['rotation'], (before, after)
        assert after['paintCount'] > before['paintCount'], (before, after)
        assert after['busyRotation'] != before['busyRotation'], (before, after)
        for method in ('groupVisible', 'windowVisible'):
            call(method, 'false'); time.sleep(.25)
            before = call('state'); time.sleep(1); after = call('state')
            assert before == after, (method, before, after)
            call(method, 'true'); time.sleep(.4)
            resumed = call('state')
            assert resumed['rotation'] > after['rotation'], (method, after, resumed)
            assert resumed['paintCount'] > after['paintCount'], (method, after, resumed)
        print(json.dumps({'status':'passed','checks':['visible animation and paint',
              'hidden item idle','hidden window idle with another animated window','resume'], 'output':str(out)}))
    finally:
        if process.poll() is None:
            process.terminate(); process.wait(timeout=5)
errors = (out/'shell.log').read_text()
assert not any(s in errors for s in ('ReferenceError', 'TypeError', 'Binding loop detected')), errors
