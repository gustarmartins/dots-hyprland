#!/usr/bin/env python3
"""Real widget creation, resize, icon fallback and teardown in an isolated X server.

Run: xvfb-run -a dbus-run-session -- python3 tests/quickshell_widget_errors.py
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix='qs-widget-errors-'))
shell = OUT / 'ii'
shutil.copytree(REPO / 'dots/.config/quickshell/ii', shell)
for directory in ('runtime', 'config/illogical-impulse', 'cache/media/favicons', 'state', 'data'):
    (OUT / directory).mkdir(parents=True, mode=0o700)
(OUT / 'config/illogical-impulse/config.json').write_text('{}')
# The real Directories singleton cleans shared /tmp folders on startup.
p = shell / 'modules/common/Directories.qml'
p.write_text(p.read_text().split('    // Cleanup on init')[0] + '}\n')
# A cached local favicon avoids network traffic from the search fixture.
shutil.copy2('/usr/share/icons/breeze/status/22/network-wired.svg', OUT / 'cache/media/favicons/widget-fixture.invalid.ico')
(shell / 'shell.qml').write_text('''//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.ii.overview
ApplicationWindow {
 id: root
 width: 640; height: 480; visible: true
 property int step: 0
 property bool failed: false
 function check(condition, message) { if (!condition) { failed=true; console.log("FAIL", message); } }
 LauncherSearchResult { id: searchEntry; name: "https://widget-fixture.invalid/example" }
 Column {
  FloatingActionButton { id: fab; buttonText: "Create item"; expanded: true }
  Item { width: 100; height: 60; ToolbarPairedFab { id: paired } }
  NotificationAppIcon { id: icon; appIcon: "codex-widget-test-nonexistent"; summary: "Battery low" }
  Loader {
   id: resultLoader
   active: true
   sourceComponent: SearchItem { width: 600; entry: searchEntry }
  }
 }
 Timer {
  interval: 100; running: true; repeat: true
  onTriggered: {
   root.step++;
   if (root.step === 5) {
    root.check(!icon.hasAppIcon && icon.resolvedAppIcon === "", "missing theme icon must use Material fallback");
    root.check(fab.implicitHeight > 0 && fab.implicitWidth > fab.baseSize, "expanded FAB has label geometry");
    icon.appIcon="network-wired";
    resultLoader.item.entry=null;
   }
   if (root.step === 10) {
    root.check(icon.hasAppIcon, "valid theme icon remains available");
    icon.appIcon="codex-widget-test-nonexistent";
    resultLoader.item.entry=searchEntry;
   }
   if (root.step > 10 && root.step < 25) {
    fab.expanded=!fab.expanded;
    paired.enableShadow=!paired.enableShadow;
    resultLoader.active=!resultLoader.active;
    root.width=root.width===640 ? 420 : 640;
   }
   if (root.step === 30) {
    root.check(!icon.hasAppIcon, "icon fallback survives changing source");
    if (!root.failed) console.log("WIDGET_ERRORS_PASS");
    Qt.quit();
   }
  }
 }
}
''')
env = os.environ.copy()
for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'QS_CONFIG_PATH', 'QS_CONFIG_NAME'):
    env.pop(key, None)
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
env.update(HOME=str(OUT), XDG_CONFIG_HOME=str(OUT / 'config'), XDG_CACHE_HOME=str(OUT / 'cache'),
           XDG_STATE_HOME=str(OUT / 'state'), XDG_DATA_HOME=str(OUT / 'data'),
           XDG_RUNTIME_DIR=str(OUT / 'runtime'), QT_QPA_PLATFORM='xcb',
           QT_QUICK_BACKEND='software', PIPEWIRE_REMOTE='widget-test-no-server',
           WAYLAND_DISPLAY='', HYPRLAND_INSTANCE_SIGNATURE='', XDG_CURRENT_DESKTOP='Xvfb')
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME',
                'XDG_STATE_HOME', 'XDG_DATA_HOME', 'XDG_RUNTIME_DIR', 'DISPLAY', 'QT_QPA_PLATFORM',
                'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP'], env=env, check=True)
result = subprocess.run(['qs', '-p', str(shell), '--no-color'], env=env, capture_output=True, text=True, timeout=15)
output = result.stdout + result.stderr
(OUT / 'ui.log').write_text(output)
bad = [line for line in output.splitlines() if any(word in line for word in
       ('ERROR:', 'FAIL ', 'TypeError:', 'ReferenceError:', 'Binding loop', 'Cannot anchor', 'Could not load icon'))]
assert result.returncode == 0 and 'WIDGET_ERRORS_PASS' in output and not bad, output
print(json.dumps({'status': 'passed', 'artifacts': str(OUT),
                  'checks': ['FAB expansion', 'loaded shadow', 'missing and valid icons',
                             'search null entry', 'favicon size', 'repeated teardown and resize']}))
