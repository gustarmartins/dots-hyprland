#!/usr/bin/env python3
"""Verify Light Mode Material 3 contrast and ComboBox hover/highlight readability in Settings.

Run: xvfb-run -a -s '-screen 0 1400x950x24' dbus-run-session -- python3 tests/settings_light_mode_ui.py
Uses a disposable home and private X/D-Bus session with Gustavo's real Light Mode Material palette.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
QS = os.environ.get('QS_TEST_BINARY', '/usr/bin/qs')
OUT = Path(tempfile.mkdtemp(prefix='settings-light-mode-'))
RUNTIME = OUT / 'runtime'
RUNTIME.mkdir(mode=0o700)
shutil.copytree(REPO / 'dots/.config/quickshell/ii', OUT / 'config/quickshell/ii')
config = OUT / 'config/illogical-impulse/config.json'
config.parent.mkdir(parents=True)
initial = json.loads((REPO / 'profile/illogical-impulse/config.json').read_text())
initial.setdefault('background', {}).setdefault('widgets', {}).setdefault('clock', {})['placementStrategy'] = 'leastBusy'
wt = initial.setdefault('appearance', {}).setdefault('wallpaperTheming', {})
wt['enableAppsAndShell'] = True
wt['enableTerminal'] = True
wt.setdefault('terminalGenerationProps', {})['forceDarkMode'] = True
config.write_text(json.dumps(initial, indent=2))

(OUT / '.local/bin').mkdir(parents=True)
effects_fixture = json.dumps(dict(
    preset='cinematic', blur=True, glow=True, live_blur=True, shadow=True,
    motion=False, rotate=False, aurora=False, stars=False, parallax=True,
    animation_profile='soft.lua', motion_source='profile', palette='aurora',
    tempo=100, travel=40, bounce=22, workspace_style='slidefade', window_style='popin',
    passes=3, blur_size=8, glow_strength=20, gaps=6, rounding=18, border=2,
    samples=12, ambient_strength=35, ambient_speed=100, popup_opacity=82, panel_opacity=94
))
fx_state = OUT / '.local/state/desktop-effects/state.json'
fx_state.parent.mkdir(parents=True)
fx_state.write_text(effects_fixture)
fx_presets = OUT / '.config/desktop-effects/presets.json'
fx_presets.parent.mkdir(parents=True)
fx_presets.write_text('[]')
p_fx = OUT / '.local/bin/desktop-effects'
p_fx.write_text(
    '#!/usr/bin/env python3\nimport json,sys\n'
    'if len(sys.argv)>1 and sys.argv[1]=="animations":\n'
    ' print(json.dumps([dict(value="soft.lua",displayName="Soft"),dict(value="spring.lua",displayName="Spring")]))\n'
    f'else:\n print({effects_fixture!r})\n'
)
p_fx.chmod(0o755)
p_ee = OUT / '.local/bin/easyeffects-qs'
p_ee.write_text("#!/bin/sh\nprintf '%s\\n' '{}'\n")
p_ee.chmod(0o755)

# Authentic Material 3 Light Mode palette (matching Matugen light output).
light_palette = {
    "background": "#f9f9ff",
    "error": "#ba1a1a",
    "error_container": "#ffdad6",
    "inverse_on_surface": "#edf0fd",
    "inverse_primary": "#53d7f1",
    "inverse_surface": "#2c303a",
    "on_background": "#171c25",
    "on_error": "#ffffff",
    "on_error_container": "#410002",
    "on_primary": "#ffffff",
    "on_primary_container": "#001f25",
    "on_secondary": "#ffffff",
    "on_secondary_container": "#001f25",
    "on_surface": "#171c25",
    "on_surface_variant": "#3f4759",
    "on_tertiary": "#ffffff",
    "on_tertiary_container": "#001a40",
    "outline": "#6f778b",
    "outline_variant": "#bec6dc",
    "primary": "#006878",
    "primary_container": "#a6eeff",
    "scrim": "#000000",
    "secondary": "#006878",
    "secondary_container": "#a6eeff",
    "shadow": "#000000",
    "surface": "#f9f9ff",
    "surface_bright": "#f9f9ff",
    "surface_container": "#eaedfa",
    "surface_container_high": "#e5e8f5",
    "surface_container_highest": "#dfe2ef",
    "surface_container_low": "#f1f3ff",
    "surface_container_lowest": "#ffffff",
    "surface_dim": "#d6dae6",
    "surface_tint": "#006878",
    "surface_variant": "#dae2f9",
    "tertiary": "#425e91",
    "tertiary_container": "#d7e2ff",
}
theme = OUT / 'state/quickshell/user/generated/colors.json'
theme.parent.mkdir(parents=True)
theme.write_text(json.dumps(light_palette, indent=2))

p = OUT / 'config/quickshell/ii/modules/common/Directories.qml'
t = p.read_text()
p.write_text(t[:t.index('    // Cleanup on init')] + '}\n')

env = os.environ.copy()
for key in ['WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
    env.pop(key, None)
env.update(
    HOME=str(OUT), XDG_CONFIG_HOME=str(OUT / 'config'),
    XDG_DATA_HOME=str(OUT / 'data'), XDG_CACHE_HOME=str(OUT / 'cache'),
    XDG_STATE_HOME=str(OUT / 'state'), XDG_RUNTIME_DIR=str(RUNTIME),
    QT_QPA_PLATFORM='xcb', QT_QUICK_BACKEND='software',
    QT_NO_XDG_DESKTOP_PORTAL='1', NO_AT_BRIDGE='1', XDG_CURRENT_DESKTOP='test',
    WAYLAND_DISPLAY='', HYPRLAND_INSTANCE_SIGNATURE='',
)
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME',
                'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'WAYLAND_DISPLAY',
                'HYPRLAND_INSTANCE_SIGNATURE', 'DISPLAY', 'QT_QPA_PLATFORM',
                'QT_NO_XDG_DESKTOP_PORTAL', 'NO_AT_BRIDGE', 'XDG_CURRENT_DESKTOP'], env=env, check=True)

entry = OUT / 'config/quickshell/ii/settings.qml'
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
        function themeState(): string {
            return JSON.stringify({
                darkmode: Appearance.m3colors.darkmode,
                bg: String(Appearance.m3colors.m3background),
                success: String(Appearance.m3colors.m3success),
                paletteLight: String(root.palette.light),
                paletteToolTipBase: String(root.palette.toolTipBase),
                paletteToolTipText: String(root.palette.toolTipText),
            });
        }
        function locate(name: string): string {
            const node = root.testFind(name); if (!node) return "null";
            const at = node.mapToItem(null, node.width / 2, node.height / 2);
            return JSON.stringify({x:at.x,y:at.y,width:node.width,height:node.height,visible:node.visible,enabled:node.enabled,checked:node.checked ?? null,currentText:node.currentText ?? ""});
        }
        function reveal(name: string): void {
            const node = root.testFind(name); if (!node) return;
            const view = root.currentPage === "design" && !root.searching ? designPage.contentItem : catalogPage.contentItem;
            const at = node.mapToItem(view, 0, 0);
            view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + at.y - 120));
        }
        function scrollDesign(y: real): void {
            designPage.contentItem.contentY = Math.max(0, Math.min(designPage.contentItem.contentHeight - designPage.contentItem.height, y));
        }
        function resize(width: int, height: int): void { root.width = width; root.height = height; }
        function comboState(name: string): string {
            const box = root.testFind(name); if (!box) return "null";
            const items = [];
            const list = box.popup?.contentItem;
            if (list && list.contentItem) {
                for (const child of list.contentItem.children) {
                    if (child && child.visible && child.itemLabel !== undefined) {
                        const pt = child.mapToItem(null, child.width / 2, child.height / 2);
                        items.push({
                            index: child.index,
                            label: child.itemLabel,
                            highlighted: child.highlighted,
                            hovered: child.hovered,
                            isCurrent: child.isCurrent,
                            bg: String(child.background.color),
                            fg: String(child.contentItem.children[0].color),
                            truncated: !!child.contentItem.children[0].truncated,
                            x: pt.x, y: pt.y,
                        });
                    }
                }
            }
            items.sort((a, b) => a.index - b.index);
            return JSON.stringify({
                popupVisible: !!box.popup?.visible,
                highlightedIndex: box.highlightedIndex,
                currentIndex: box.currentIndex,
                count: box.count,
                items: items,
            });
        }
    }
'''
source = entry.read_text()
entry.write_text(source[:source.rfind('}')] + probe + '\n}\n')
log = (OUT / 'settings.log').open('w')
process = subprocess.Popen([QS, '-p', str(entry)], env=env, stdout=log, stderr=subprocess.STDOUT)


def call(target, *args):
    return subprocess.check_output([QS, '-p', str(entry), 'ipc', 'call', target, *args],
                                   env=env, text=True, stderr=subprocess.DEVNULL, timeout=5).strip()


def until(fn, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if process.poll() is not None:
            raise AssertionError((OUT / 'settings.log').read_text()[-4000:])
        try:
            v = fn()
            if v:
                return v
        except Exception:
            pass
        time.sleep(0.08)
    raise AssertionError('Timed out; see ' + str(OUT))


def hex_to_lum(hex_str):
    h = hex_str.lstrip('#')
    if len(h) == 8:
        h = h[2:]
    r, g, b = (int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))
    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast_ratio(c1, c2):
    l1, l2 = hex_to_lum(c1), hex_to_lum(c2)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def screenshot(name):
    window = subprocess.check_output(['xdotool', 'search', '--name', '^illogical-impulse Settings$'], env=env, text=True).splitlines()[-1]
    subprocess.run(['magick', 'import', '-window', window, str(OUT / (name + '.png'))], env=env, check=True, capture_output=True)


try:
    until(lambda: json.loads(call('settings', 'status'))['ready'], timeout=45)
    tstate = until(lambda: json.loads(call('test', 'themeState')) if not json.loads(call('test', 'themeState'))['darkmode'] else None)
    assert tstate['darkmode'] is False, tstate
    assert contrast_ratio(tstate['success'], tstate['bg']) >= 4.5, f"Light mode success contrast too low: {tstate}"
    assert contrast_ratio(tstate['paletteToolTipText'], tstate['paletteToolTipBase']) >= 7.0, tstate

    call('settings', 'open', 'widgets')
    box = until(lambda: json.loads(call('test', 'locate', 'choice:background.widgets.clock.placementStrategy')))
    assert box['currentText'] == 'Calmest wallpaper area', box
    window = subprocess.check_output(['xdotool', 'search', '--name', '^illogical-impulse Settings$'], env=env, text=True).splitlines()[-1]
    subprocess.run(['xdotool', 'mousemove', '--window', window, str(round(box['x'])), str(round(box['y'])), 'click', '1'], env=env, check=True)
    state = until(lambda: (lambda s: s if s['popupVisible'] and len(s['items']) == 4 else None)(json.loads(call('test', 'comboState', 'choice:background.widgets.clock.placementStrategy'))))
    labels = [item['label'] for item in state['items']]
    assert labels == [
        'Free position',
        'Avoid open windows',
        'Calmest wallpaper area',
        'Busiest wallpaper area',
    ], labels
    assert not any(item['truncated'] for item in state['items']), state['items']

    # Hover the 4th item ("Busiest wallpaper area") — previously pure white-on-white!
    target = state['items'][3]
    subprocess.run(['xdotool', 'mousemove', '--window', window, str(round(target['x'])), str(round(target['y']))], env=env, check=True)
    time.sleep(0.25)
    hovered_state = json.loads(call('test', 'comboState', 'choice:background.widgets.clock.placementStrategy'))
    hovered_item = hovered_state['items'][3]
    assert hovered_item['hovered'] or hovered_item['highlighted'], hovered_item
    ratio_hover = contrast_ratio(hovered_item['fg'], hovered_item['bg'])
    assert ratio_hover >= 7.0, f"Hovered ComboBox item contrast failed WCAG AAA: {ratio_hover:.2f} ({hovered_item})"

    current_item = hovered_state['items'][2]
    assert current_item['isCurrent'], current_item
    ratio_current = contrast_ratio(current_item['fg'], current_item['bg'])
    assert ratio_current >= 7.0, f"Selected ComboBox item contrast failed WCAG AAA: {ratio_current:.2f} ({current_item})"

    screenshot('light-widgets-dropdown')
    # Also select "Open desktop space (avoid windows)" via real click!
    open_space = hovered_state['items'][1]
    subprocess.run(['xdotool', 'mousemove', '--window', window, str(round(open_space['x'])), str(round(open_space['y'])), 'click', '1'], env=env, check=True)
    until(lambda: json.loads(config.read_text())['background']['widgets']['clock']['placementStrategy'] == 'avoidWindows')

    # Verify Design page in Light Mode: "Keep terminal dark" must be visible up front (0 clicks!)
    call('settings', 'open', 'design')
    kitty_toggle = until(lambda: json.loads(call('test', 'locate', 'toggle:appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode')))
    assert kitty_toggle['visible'] and kitty_toggle['enabled'], kitty_toggle
    until(lambda: json.loads(call('test', 'locate', 'designGpuPresets'))['enabled'])
    time.sleep(0.25)
    screenshot('light-design')

    # Expand Color & theme details and verify clean flat layout (no nested boxes)
    colors_btn = until(lambda: json.loads(call('test', 'locate', 'designExpand:colors')))
    subprocess.run(['xdotool', 'mousemove', '--window', window, str(round(colors_btn['x'])), str(round(colors_btn['y'])), 'click', '1'], env=env, check=True)
    until(lambda: json.loads(call('test', 'locate', 'setting:appearance.wallpaperTheming.enableAppsAndShell')))
    time.sleep(0.25)
    screenshot('light-design-colors-expanded')
    # Collapse colors again, then scroll to GPU effects and expand it + Glass & shadows
    subprocess.run(['xdotool', 'mousemove', '--window', window, str(round(colors_btn['x'])), str(round(colors_btn['y'])), 'click', '1'], env=env, check=True)
    time.sleep(0.2)
    call('test', 'reveal', 'designExpand:gpu')
    time.sleep(0.2)
    gpu_btn = until(lambda: json.loads(call('test', 'locate', 'designExpand:gpu')))
    subprocess.run(['xdotool', 'mousemove', '--window', window, str(round(gpu_btn['x'])), str(round(gpu_btn['y'])), 'click', '1'], env=env, check=True)
    call('test', 'reveal', 'designExpand:glass')
    time.sleep(0.2)
    glass_btn = until(lambda: json.loads(call('test', 'locate', 'designExpand:glass')))
    subprocess.run(['xdotool', 'mousemove', '--window', window, str(round(glass_btn['x'])), str(round(glass_btn['y'])), 'click', '1'], env=env, check=True)
    time.sleep(0.25)
    screenshot('light-design-gpu-expanded')

    # Verify SettingsHome in Light Mode
    call('settings', 'open', 'home')
    time.sleep(0.25)
    screenshot('light-home')

    # Verify compact Light Mode Design layout
    call('settings', 'open', 'design')
    call('test', 'resize', '700', '650')
    call('test', 'scrollDesign', '0')
    time.sleep(0.3)
    screenshot('light-design-compact')

    log_text = (OUT / 'settings.log').read_text()
    bad = [line for line in log_text.splitlines() if any(w in line for w in ('ReferenceError:', 'TypeError:', 'Unable to assign', 'Binding loop'))]
    assert not bad, '\n'.join(bad)
    print(f'PASS: Light mode contrast verified (hover={ratio_hover:.1f}:1, selected={ratio_current:.1f}:1, success={contrast_ratio(tstate["success"], tstate["bg"]):.1f}:1); Keep terminal dark visible up front; clock placement updated to avoidWindows; artifacts={OUT}', flush=True)
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    log.close()
