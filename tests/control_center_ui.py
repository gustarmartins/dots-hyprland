#!/usr/bin/env python3
"""Exercise the real control center in an isolated home, X server, and D-Bus.
Run: xvfb-run -a -s '-screen 0 1400x1200x24' dbus-run-session -- python tests/control_center_ui.py
Only fixture tile callbacks run. No live audio, tuning, or settings are changed.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix='control-center-ui-'))
CONFIG = OUT / 'config/quickshell/ii'
shutil.copytree(REPO / 'dots/.config/quickshell/ii', CONFIG)
(OUT / 'runtime').mkdir(mode=0o700)
config_file = OUT / 'config/illogical-impulse/config.json'
config_file.parent.mkdir(parents=True)
initial = {'sidebar': {'quickToggles': {'style': 'android', 'android': {'columns': 7, 'toggles': [
    {'type': 'audio', 'size': 2}, {'type': 'mic', 'size': 2}, {'type': 'network', 'size': 3},
    {'type': 'darkMode', 'size': 1}, {'type': 'easyEffects', 'size': 2}]}},
    'quickSliders': {'enable': True, 'showVolume': True, 'showMic': True, 'showBrightness': False}},
    'testSentinel': {'preserve': [42, 'extension']}}
config_file.write_text(json.dumps(initial))
# Fixture services keep the real widgets independent of the desktop's helpers.
(CONFIG / 'services/EasyEffects.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool available: true
    property bool active: true
    property bool bypassed: false
    readonly property bool processing: active && !bypassed
    property bool busy: false
    property string error: ""
    property string preset: "codex-stinger-music-mekki"
    property var presets: ["Music", "Rock", "codex-stinger-music-mekki", "Test preset"]
    function selectPreset(name) { preset=name; }
    function fetchActiveState() {}
    function fetchAvailability() {}
    function toggle() {}
    function show() {}
}
''')
(CONFIG / 'services/DesktopEffects.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton { property var settings: ({preset:"balanced", panel_opacity:100}) }
''')
# Avoid the production Directories startup cleanup's shared /tmp paths.
p = CONFIG / 'modules/common/Directories.qml'
s = p.read_text(); s = s[:s.index('    // Cleanup on init')] + '}\n'; p.write_text(s)
# Any accidental action while arranging tiles is both harmless and observable.
p = CONFIG / 'modules/ii/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml'
s = p.read_text().replace('property var mainAction: toggleModel?.mainAction ?? null',
    'property int fixtureActions: 0\n    property var mainAction: (() => fixtureActions++)')
s = s.replace('    property bool editMode: false', '    property alias fixtureSizePopup: sizePopup\n    property bool editMode: false')
s = s.replace('altAction: toggleModel?.hasMenu ? (() => root.openMenu()) : (toggleModel?.altAction ?? null)',
    'altAction: (() => fixtureActions++)')
p.write_text(s)
for d in ['.local/bin', '.config/desktop-effects', '.local/state/user/generated', 'cache/notifications']:
    (OUT / d).mkdir(parents=True, exist_ok=True)
helper = OUT / '.local/bin/desktop-effects'; helper.write_text('#!/bin/sh\nexit 0\n'); helper.chmod(0o755)
entry = CONFIG / 'shell.qml'
entry.write_text('''//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.sidebarRight
ApplicationWindow {
    id: root
    visible: true
    width: 660
    height: 1080
    x: 0
    y: 0
    color: "#141313"
    SidebarRightContent { id: center; anchors.fill: parent }
    function find(name) {
        let queue=[root.contentItem]; let seen=new Set();
        while(queue.length) {
            let node=queue.shift(); if(!node || seen.has(node)) continue;
            seen.add(node); if(node.objectName===name) return node;
            for(let child of (node.children || [])) queue.push(child);
            if(node.item) queue.push(node.item);
            if(node.contentItem) queue.push(node.contentItem);
            if(node.popup) queue.push(node.popup);
            if(node.fixtureSizePopup) queue.push(node.fixtureSizePopup);
        }
        return null;
    }
    IpcHandler {
        target: "test"
        function locate(name: string): string {
            const node=root.find(name); if(!node) return "null";
            const at=node.mapToItem(root.contentItem,0,0);
            return JSON.stringify({x:at.x,y:at.y,width:node.width,height:node.height,visible:node.visible,name:node.name ?? ""});
        }
        function state(): string {
            const panel=root.find("controlTilePanel");
            let actions=0;
            for (const tile of Config.options.sidebar.quickToggles.android.toggles) actions += root.find("controlTile-"+tile.type)?.fixtureActions ?? 0;
            return JSON.stringify({edit:center.editMode,columns:panel?.columns,cellWidth:panel?.baseCellWidth,cellHeight:panel?.baseCellHeight,placement:panel?.placement,tiles:Config.options.sidebar.quickToggles.android.toggles,actions:actions});
        }
        function resize(width: int, height: int): void { root.width=width;root.height=height; }
        function capture(path: string): void { center.grabToImage(result => result.saveToFile(path)); }
        function flush(): void { Config.flushPendingWrites(); }
    }
}
''')
env = os.environ.copy()
for key in ['WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
    env.pop(key, None)
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
env.update(HOME=str(OUT), XDG_CONFIG_HOME=str(OUT / 'config'), XDG_STATE_HOME=str(OUT / '.local/state'),
    XDG_DATA_HOME=str(OUT / 'data'), XDG_CACHE_HOME=str(OUT / 'cache'), XDG_RUNTIME_DIR=str(OUT / 'runtime'),
    QT_QPA_PLATFORM='xcb', QT_QUICK_BACKEND='software', PIPEWIRE_REMOTE='control-center-test-no-server')
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_DATA_HOME',
    'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR', 'DISPLAY', 'QT_QPA_PLATFORM'], env=env, check=True)
log_path = OUT / 'ui.log'
log = log_path.open('w')
process = None

def start():
    global process
    process = subprocess.Popen(['qs','-p',str(entry),'--no-color'],env=env,stdout=log,stderr=subprocess.STDOUT)
    for _ in range(100):
        if process.poll() is not None: raise AssertionError(log_path.read_text())
        try:
            if call('state')['columns'] == 7: return
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError): pass
        time.sleep(.1)
    raise AssertionError(log_path.read_text())

def call(method, *args):
    value = subprocess.check_output(['qs','-p',str(entry),'ipc','call','test',method,*map(str,args)],env=env,stderr=subprocess.DEVNULL,text=True).strip()
    return json.loads(value) if value else None

def locate(name):
    v = call('locate',name); assert v and v['visible'], (name,v); return v

def click(name, button=1, dx=None, dy=None):
    v=locate(name); x=v['x']+(v['width']/2 if dx is None else dx); y=v['y']+(v['height']/2 if dy is None else dy)
    subprocess.run(['xdotool','mousemove','--sync',str(round(x)),str(round(y)),'click',str(button)],env=env,check=True)
    time.sleep(.3)

def drag(name, dx, dy):
    v=locate(name); x=round(v['x']+v['width']/2); y=round(v['y']+v['height']/2)
    subprocess.run(['xdotool','mousemove','--sync',str(x),str(y),'mousedown','1'],env=env,check=True)
    for step in range(1,6):
        subprocess.run(['xdotool','mousemove','--sync',str(round(x+dx*step/5)),str(round(y+dy*step/5))],env=env,check=True)
        time.sleep(.04)
    subprocess.run(['xdotool','mouseup','1'],env=env,check=True); time.sleep(.4)

try:
    start()
    time.sleep(.8)
    canvas = locate('controlTileCanvas'); assert abs(canvas['width'] - 628) < 2
    assert canvas['height'] == 7 * 80 - 8
    call('capture',OUT/'normal.png')
    normal_cell = call('state')['cellHeight']
    click('controlCenterEdit'); assert call('state')['edit']
    assert call('state')['cellHeight'] == normal_cell
    # Right-click size matrix, choose a 3×2 span with real pointer input.
    click('tileMove-audio',button=3)
    click('tileSizeGrid-audio',dx=2*31+14,dy=1*27+12)
    tile=next(t for t in call('state')['tiles'] if t['type']=='audio')
    assert (tile['size'],tile['height']) == (3,2),tile
    # Corner drag resizes another tile in both axes.
    dims=call('state')
    drag('tileResize-mic',dims['cellWidth']+8,dims['cellHeight']+8)
    tile=next(t for t in call('state')['tiles'] if t['type']=='mic')
    assert (tile['size'],tile['height']) == (3,2),tile
    # Drag the single-cell tile to an explicit free grid location.
    before=next(t for t in call('state')['placement']['tiles'] if t['type']=='darkMode')
    dims=call('state')
    target_x=(6-before['gridColumn'])*(dims['cellWidth']+8)
    target_y=(5-before['gridRow'])*(dims['cellHeight']+8)
    drag('tileMove-darkMode',target_x,target_y)
    tile=next(t for t in call('state')['tiles'] if t['type']=='darkMode')
    assert (tile['column'],tile['row']) == (6,5),tile
    # Deletion must work after model reordering, from both entry points.
    click('tileDelete-mic')
    assert not any(t['type']=='mic' for t in call('state')['tiles'])
    assert call('locate','controlTile-mic') is None, 'Deleted mic still rendered'
    click('tileMove-network',button=3)
    click('tileRemoveMenu-network')
    assert not any(t['type']=='network' for t in call('state')['tiles'])
    assert locate('controlTile-audio')['visible']
    assert locate('controlTile-audio')['name'] == 'Audio output', ('Tile retained the wrong service model', locate('controlTile-audio'))
    assert abs(locate('controlTile-audio')['width'] - (3*call('state')['cellWidth']+16)) < 1, 'Rendered span stale'
    assert call('state')['actions']==0, 'Editing invoked a tile action'
    # Wheel input over a tile scrolls without mutating the layout.
    wheel_before = call('state')['tiles']
    click('tileMove-audio', button=5)
    assert call('state')['tiles'] == wheel_before
    call('capture',OUT/'edit.png')
    click('controlCenterEdit'); assert not call('state')['edit']
    # Compact height must scroll the grid, retaining all widgets and the footer.
    call('resize',660,650); time.sleep(.3)
    viewport=locate('controlTileScroll'); assert viewport['height'] > 140
    assert viewport['y']+viewport['height'] <= 650
    call('capture',OUT/'short.png')
    call('resize',460,800); time.sleep(.3)
    for name in ['controlMoodPicker','controlPresetPicker','controlTileScroll']:
        v=locate(name); assert v['x']>=0 and v['x']+v['width']<=461, (name,v)
    call('capture',OUT/'narrow.png')
    # Dropdown selection changes only the requested fixture preset.
    click('controlPresetPicker'); subprocess.run(['xdotool','key','End','Return'],env=env,check=True); time.sleep(.2)
    click('controlTab-inbox'); click('controlTab-agenda'); click('controlTab-controls')
    expected=call('state')['tiles']; call('flush'); time.sleep(.2)
    saved=json.loads(config_file.read_text())
    assert saved['sidebar']['quickToggles']['android']['toggles']==expected
    assert saved['testSentinel']==initial['testSentinel']
    process.terminate(); process.wait(timeout=5)
    start(); assert call('state')['tiles']==expected
    source=log_path.read_text()
    bad=[line for line in source.splitlines() if ('ERROR:' in line or 'ReferenceError:' in line or 'Binding loop' in line or 'TypeError:' in line) and 'Translator' not in line]
    assert not bad,'\n'.join(bad)
    print('PASS: size picker, resize, placement, both delete controls after reorder, wheel safety, no tile actions, compact/narrow views, tabs, and restart persistence')
    print('ARTIFACTS',OUT)
finally:
    if process and process.poll() is None:
        process.terminate();process.wait(timeout=5)
    log.close()
