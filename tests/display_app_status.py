#!/usr/bin/env python3
"""Verify display-app-status helper logic and DisplayAppStatusWidget QML in isolation."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / 'dots/.local/bin/display-app-status'
WIDGET = REPO / 'dots/.config/quickshell/ii/modules/ii/sidebarRight/DisplayAppStatusWidget.qml'


def run_helper_fixture(monitors, clients, layers, ds_opt=1, tear_opt=False, vrr_opt=1, extra_args=()):
    with tempfile.TemporaryDirectory(prefix='display-status-helper-') as tmp:
        root = Path(tmp)
        fixture = root / 'fixture.json'
        fixture.write_text(json.dumps({
            'monitors': monitors,
            'clients': clients,
            'layers': layers,
            'options': {
                'render:direct_scanout': {'option': 'render:direct_scanout', 'int': ds_opt, 'set': True},
                'general:allow_tearing': {'option': 'general:allow_tearing', 'bool': tear_opt, 'set': True},
                'misc:vrr': {'option': 'misc:vrr', 'int': vrr_opt, 'set': True},
            },
        }))
        fake = root / 'hyprctl'
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
data = json.loads(Path(os.environ['FIXTURE_JSON']).read_text())
args = [a for a in sys.argv[1:] if a != '-j']
if args[0] == 'getoption':
    print(json.dumps(data['options'][args[1]]))
else:
    print(json.dumps(data[args[0]]))
''')
        fake.chmod(0o755)
        env = dict(os.environ, PATH=f"{root}:/usr/bin:/bin", FIXTURE_JSON=str(fixture))
        out = subprocess.check_output(
            ['python3', str(HELPER), '--no-proc', *extra_args],
            env=env,
            text=True,
            timeout=10,
        )
        return json.loads(out)


def test_helper():
    base_mon = [
        {
            'id': 0, 'name': 'DP-1', 'description': 'AOC 27G2G4 0x00000A71',
            'make': 'AOC', 'model': '27G2G4', 'width': 1920, 'height': 1080,
            'refreshRate': 144.001, 'activeWorkspace': {'id': 4, 'name': '4'},
            'specialWorkspace': {'name': ''}, 'focused': False, 'vrr': True,
            'solitary': '5555daa28870', 'solitaryBlockedBy': None,
            'activelyTearing': False, 'tearingBlockedBy': ['NOT_TORN', 'USER', 'WINDOW'],
            'directScanoutTo': '5555daa28870', 'directScanoutBlockedBy': None,
            'disabled': False, 'currentFormat': 'XRGB8888',
            'hardwareCursorsInUse': True, 'hardwareDetails': {'vrrCapable': True},
        },
        {
            'id': 1, 'name': 'HDMI-A-1', 'description': 'GWD ARZOPA',
            'make': 'GWD', 'model': 'ARZOPA', 'width': 1920, 'height': 1080,
            'refreshRate': 144.0, 'activeWorkspace': {'id': 6, 'name': '6'},
            'specialWorkspace': {'name': ''}, 'focused': True, 'vrr': False,
            'solitary': '0', 'solitaryBlockedBy': ['WINDOWED', 'CANDIDATE'],
            'activelyTearing': False, 'tearingBlockedBy': ['NOT_TORN', 'USER', 'CANDIDATE'],
            'directScanoutTo': '0', 'directScanoutBlockedBy': ['CANDIDATE'],
            'disabled': False, 'currentFormat': 'XRGB8888',
            'hardwareCursorsInUse': True, 'hardwareDetails': {'vrrCapable': True},
        },
    ]
    osu_client = {
        'address': '0x5555daa28870', 'class': 'osu!', 'initialClass': 'osu!',
        'title': 'osu! - Test Beatmap', 'monitor': 0, 'workspace': {'id': 4, 'name': '4'},
        'mapped': True, 'hidden': False, 'floating': False,
        'fullscreen': 2, 'fullscreenClient': 2, 'xwayland': False,
        'contentType': 'game', 'tags': ['gamemode'], 'inhibitingIdle': True,
        'tearingHint': False, 'pid': 12345, 'focusHistoryID': 1,
    }

    # 1. Ideal fullscreen osu! with live direct scanout + VRR + gamemode + Wayland.
    res = run_helper_fixture(base_mon, [osu_client], {'DP-1': {'levels': {'2': [], '3': []}}})
    assert res['available'] and res['monitor']['name'] == 'DP-1'
    assert res['app']['name'] == 'osu!'
    assert res['fullscreen']['mode'] == 'native_fs' and res['fullscreen']['label'] == 'Native FS'
    assert res['scanout']['state'] == 'active' and res['scanout']['label'] == 'Scanout'
    assert res['gamemode']['state'] == 'active' and res['gamemode']['label'] == 'Game mode'
    assert res['vrr']['active'] is True and res['protocol']['label'] == 'Wayland'
    assert res['overall'] == 'good'

    # 2. Control Center open on DP-1 pauses direct scanout solely via OVERLAYS -> paused_panel.
    paused_mon = json.loads(json.dumps(base_mon))
    paused_mon[0]['directScanoutTo'] = '0'
    paused_mon[0]['solitary'] = '0'
    paused_mon[0]['directScanoutBlockedBy'] = ['CANDIDATE']
    paused_mon[0]['solitaryBlockedBy'] = ['OVERLAYS']
    layers_panel = {'DP-1': {'levels': {'2': [{'namespace': 'quickshell:sidebarRight'}], '3': []}}}
    res = run_helper_fixture(paused_mon, [osu_client], layers_panel)
    assert res['scanout']['state'] == 'paused_panel', res['scanout']
    assert 'HDMI-A-1' in res['tip'], res['tip']

    # 3. Forced fullscreen + XWayland + real DMA scanout blocker + armed tearing blocked by USER.
    bad_mon = json.loads(json.dumps(base_mon))
    bad_mon[0]['directScanoutTo'] = '0'
    bad_mon[0]['solitary'] = '0'
    bad_mon[0]['directScanoutBlockedBy'] = ['DMA']
    bad_mon[0]['solitaryBlockedBy'] = None
    bad_mon[0]['tearingBlockedBy'] = ['USER', 'NOT_TORN']
    bad_client = dict(osu_client, fullscreenClient=0, xwayland=True, tags=['tearing'], contentType='none', tearingHint=True)
    res = run_helper_fixture(bad_mon, [bad_client], {'DP-1': {'levels': {'2': [], '3': []}}}, ds_opt=1, tear_opt=False)
    assert res['fullscreen']['mode'] == 'forced_fs' and res['fullscreen']['tone'] == 'warn'
    assert res['scanout']['state'] == 'blocked' and 'Buffer incompatible' in res['scanout']['detail']
    assert res['protocol']['xwayland'] is True and res['protocol']['tone'] == 'warn'
    assert res['tearing']['state'] == 'blocked' and 'Disabled in Hyprland' in res['tearing']['detail']

    # 4. Active tearing with immediate page-flips.
    tear_mon = json.loads(json.dumps(base_mon))
    tear_mon[0]['activelyTearing'] = True
    tear_mon[0]['tearingBlockedBy'] = None
    tear_mon[0]['vrr'] = False
    tear_client = dict(osu_client, tags=['gamemode', 'tearing'], tearingHint=True)
    res = run_helper_fixture(tear_mon, [tear_client], {'DP-1': {'levels': {'2': [], '3': []}}}, tear_opt=True)
    assert res['tearing']['state'] == 'active' and res['tearing']['label'] == 'Tearing'

    # 5. Direct scanout disabled by user option.
    off_mon = json.loads(json.dumps(base_mon))
    off_mon[0]['directScanoutTo'] = '0'
    off_mon[0]['directScanoutBlockedBy'] = ['USER']
    res = run_helper_fixture(off_mon, [osu_client], {'DP-1': {'levels': {'2': [], '3': []}}}, ds_opt=0)
    assert res['scanout']['state'] == 'off' and res['scanout']['label'] == 'Scanout off'

    # 6. Empty workspace.
    res = run_helper_fixture(paused_mon, [], {'DP-1': {'levels': {'2': [], '3': []}}})
    assert res['app']['present'] is False and res['fullscreen']['label'] == 'Desktop'
    print('PASS: display-app-status helper scenarios verified')


def test_widget_qml():
    with tempfile.TemporaryDirectory(prefix='display-status-ui-') as tmp:
        root = Path(tmp)
        imports = root / 'imports'
        modules = {
            'qs/services': 'singleton DisplayAppStatus 1.0 DisplayAppStatus.qml\n',
            'qs/modules/common': 'singleton Appearance 1.0 Appearance.qml\n',
            'qs/modules/common/widgets': 'StyledText 1.0 StyledText.qml\nMaterialSymbol 1.0 MaterialSymbol.qml\n',
        }
        for name, entries in modules.items():
            d = imports / name
            d.mkdir(parents=True)
            (d / 'qmldir').write_text('module ' + name.replace('/', '.') + '\n' + entries)

        sample = {
            'available': True, 'error': '', 'overall': 'good',
            'monitor': {
                'name': 'DP-1', 'shortName': 'AOC 27G2G4', 'make': 'AOC', 'model': '27G2G4',
                'width': 1920, 'height': 1080, 'hz': 144, 'workspace': '4',
                'format': 'XRGB8888', 'hwCursor': True, 'sidebarOnMonitor': False,
            },
            'app': {'present': True, 'name': 'osu!', 'title': 'osu! - Test Map', 'pid': 4242, 'floating': False},
            'fullscreen': {'mode': 'native_fs', 'label': 'Native FS', 'tone': 'good', 'detail': 'Hyprland fullscreen · App native fullscreen'},
            'scanout': {'state': 'active', 'label': 'Scanout', 'tone': 'good', 'solitary': True, 'detail': 'Active direct scanout (Fullscreen)'},
            'vrr': {'active': True, 'capable': True, 'policy': 1, 'policyLabel': 'Always', 'label': 'VRR on', 'tone': 'good'},
            'gamemode': {'state': 'active', 'label': 'Game mode', 'tone': 'good', 'detail': 'Content: game · Tags: gamemode · Idle inhibit'},
            'protocol': {'xwayland': False, 'label': 'Wayland', 'tone': 'info'},
            'tearing': {'state': 'off', 'label': 'No tear', 'tone': 'neutral', 'detail': 'Synced (tearing gate off)'},
            'process': {
                'readable': True, 'presentMode': 'immediate', 'unorderedSubmitsDisabled': True,
                'lsfgDisabled': True, 'lsfgLoaded': False, 'vulkanLoaded': True, 'sdlDriver': 'wayland',
            },
            'tip': '',
        }

        (imports / 'qs/services/DisplayAppStatus.qml').write_text(f'''pragma Singleton
import QtQuick
QtObject {{
    property bool enabled: true
    property bool ready: true
    property bool available: true
    property bool busy: false
    property bool showProcessDetails: true
    property bool expandedByDefault: false
    property int watchers: 0
    property int refreshCount: 0
    property string error: ""
    property var data: ({json.dumps(sample)})
    function refresh() {{ refreshCount++; }}
}}
''')
        (imports / 'qs/modules/common/Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var m3colors: ({
        m3primary: "#ceca6a", m3primaryContainer: "#4b4900", m3onPrimaryContainer: "#ebe783",
        m3secondary: "#dabde2", m3secondaryContainer: "#553f5d", m3onSecondaryContainer: "#f7d8ff",
        m3tertiary: "#97ccf8", m3tertiaryContainer: "#184b6b", m3onTertiaryContainer: "#cbe6ff",
        m3error: "#ffb4ab", m3errorContainer: "#93000a", m3onErrorContainer: "#ffdad6",
        m3surfaceContainer: "#1a2026", m3surfaceContainerHigh: "#252b30", m3surfaceContainerHighest: "#30363b",
        m3onSurface: "#dee3ea", m3onSurfaceVariant: "#bdc8d4",
        m3outline: "#87929d", m3outlineVariant: "#3d4852"
    })
}
''')
        widgets = imports / 'qs/modules/common/widgets'
        (widgets / 'StyledText.qml').write_text('import QtQuick\nText { color: "#dee3ea" }\n')
        (widgets / 'MaterialSymbol.qml').write_text('import QtQuick\nText { property int iconSize: 16; font.pixelSize: iconSize }\n')
        shutil.copy2(WIDGET, root / 'DisplayAppStatusWidget.qml')

        (root / 'tst_display_app_status.qml').write_text('''import QtQuick
import QtQuick.Window
import QtTest
import qs.services

Rectangle {
    id: scene
    width: 620
    height: 360
    color: "#141313"

    DisplayAppStatusWidget {
        id: card
        x: 16
        y: 16
        width: scene.width - 32
    }

    TestCase {
        name: "DisplayAppStatusWidget"
        when: windowShown

        function init() {
            card.visible = true;
            card.expanded = false;
            DisplayAppStatus.refreshCount = 0;
            scene.width = 620;
        }

        function test_compact_summary_and_pills() {
            compare(findChild(card, "displayAppStatusMonitor").text, "AOC · 144Hz");
            compare(findChild(card, "displayAppStatusApp").text, "osu!");
            compare(findChild(card, "displayPillFullscreen").label, "Native FS");
            compare(findChild(card, "displayPillScanout").label, "Scanout");
            compare(findChild(card, "displayPillVrr").label, "VRR on");
            compare(findChild(card, "displayPillGame").label, "Game mode");
            compare(findChild(card, "displayPillProtocol").label, "Wayland");
            compare(findChild(card, "displayPillTearing").label, "No tear");
            verify(card.implicitHeight < 100);
        }

        function test_expand_shows_vulkan_and_refresh() {
            let collapsedH = card.implicitHeight;
            let header = findChild(card, "displayAppStatusHeader");
            mouseClick(header);
            verify(card.expanded);
            let details = findChild(card, "displayAppStatusDetails");
            tryVerify(() => details.height >= 130 && card.implicitHeight > collapsedH + 120, 1500);
            wait(120);
            let vk = findChild(card, "displayAppStatusVulkan");
            verify(vk.visible);
            verify(vk.value.indexOf("Present: immediate") >= 0);
            verify(vk.value.indexOf("WSI sync: safe") >= 0);
            verify(vk.value.indexOf("lsfg-vk: bypassed") >= 0);
            let refreshBtn = findChild(card, "displayAppStatusRefresh");
            mouseClick(refreshBtn);
            compare(DisplayAppStatus.refreshCount, 1);
        }

        function test_watchers_stop_when_hidden() {
            verify(DisplayAppStatus.watchers > 0);
            card.visible = false;
            compare(DisplayAppStatus.watchers, 0);
            card.visible = true;
            verify(DisplayAppStatus.watchers > 0);
            let win = scene.Window.window;
            win.visible = false;
            compare(DisplayAppStatus.watchers, 0);
            win.visible = true;
            verify(DisplayAppStatus.watchers > 0);
        }

        function test_narrow_layout_wraps_cleanly() {
            scene.width = 390;
            wait(30);
            let pills = findChild(card, "displayAppStatusPills");
            let p = pills.mapToItem(card, 0, 0);
            verify(p.x >= 0);
            verify(p.x + pills.width <= card.width + 1);
        }
    }
}
''')
        (root / 'runtime').mkdir(mode=0o700)
        env = dict(
            os.environ,
            HOME=str(root),
            QT_QPA_PLATFORM='offscreen',
            QT_QUICK_BACKEND='software',
            QT_QUICK_CONTROLS_STYLE='Basic',
            XDG_RUNTIME_DIR=str(root / 'runtime'),
            XDG_CONFIG_HOME=str(root / 'config'),
            XDG_CACHE_HOME=str(root / 'cache'),
        )
        res = subprocess.run(
            ['dbus-run-session', '--', '/usr/lib/qt6/bin/qmltestrunner', '-input', str(root), '-import', str(imports)],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        print(res.stdout)
        if res.returncode:
            print(res.stderr)
        res.check_returncode()


if __name__ == '__main__':
    test_helper()
    test_widget_qml()
