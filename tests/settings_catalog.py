#!/usr/bin/env python3
"""Keep the settings catalog aligned with the fork's actual configuration schema."""
from pathlib import Path
import json
import re
import subprocess

REPO = Path(__file__).resolve().parents[1]
SHELL = REPO / 'dots/.config/quickshell/ii'


def schema():
    fields, stack = {}, []
    for line in (SHELL / 'modules/common/Config.qml').read_text().splitlines():
        m = re.match(r'(\s*)property\s+(JsonObject|list<\w+>|bool|int|real|string)\s+(\w+):\s*(.*)', line)
        if not m or len(m[1]) < 12:
            continue
        indent, typ, name, value = len(m[1]), *m.group(2, 3, 4)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if typ == 'JsonObject':
            stack.append((indent, name))
        else:
            fields['.'.join([s[1] for s in stack] + [name])] = (typ, value)
    return fields


def catalog():
    text = (SHELL / 'modules/settings/SettingsCatalog.js').read_text()
    return {name: json.loads(re.search(r'var ' + name + r' = (.*?);\n', text, re.S)[1])
            for name in ['entries', 'pages', 'retired', 'managed', 'timeUnits']}


def main():
    fields, data = schema(), catalog()
    preserved = json.loads(re.search(r'var paths = (.*?);', (SHELL / 'modules/common/ConfigKeys.js').read_text(), re.S)[1])
    assert set(preserved) == set(fields) and len(preserved) == len(fields), 'Config writer schema is stale'
    entries = data['entries']
    keys = [e['path'] for e in entries]
    assert len(keys) == len(set(keys)), 'Duplicate settings rows'
    classified = set(keys) | data['retired'].keys() | data['managed'].keys()
    assert set(fields) == classified, ('Unclassified/stale keys', set(fields) ^ classified)
    page_ids = {p['id'] for p in data['pages']}
    assert len(page_ids) == len(data['pages'])
    assert data['pages'][0]['id'] == 'design', 'Color and design must be the first destination'
    assert not page_ids.intersection({'effects', 'fonts'}), 'Design controls split across tabs again'
    assert all(e['page'] == 'design' for e in entries if e['path'].startswith('appearance.')), 'Appearance controls escaped Design'
    time_units = {
        'background.discovery.intervalMinutes':'min',
        'bar.autoHide.showWhenPressingSuper.delay':'ms', 'bar.weather.fetchInterval':'min',
        'notifications.timeout':'ms', 'osd.timeout':'ms', 'resources.updateInterval':'ms',
        'musicRecognition.timeout':'s', 'musicRecognition.interval':'s',
        'search.nonAppResultDelay':'ms', 'sidebar.translator.delay':'ms',
        'time.pomodoro.breakTime':'s', 'time.pomodoro.focus':'s', 'time.pomodoro.longBreak':'s',
        'updates.checkInterval':'min', 'hacks.arbitraryRaceConditionDelay':'ms',
    }
    numeric_time_keys = {path for path,(typ,_) in fields.items() if typ in ('int','real')
                         and re.search(r'(?i)(interval|delay|timeout|duration)',path)} & set(keys)
    assert numeric_time_keys <= time_units.keys(), ('Unreviewed time controls', numeric_time_keys-time_units.keys())
    assert data['timeUnits'] == {'ms':'milliseconds','s':'seconds','min':'minutes'}
    for entry in entries:
        assert entry['page'] in page_ids
        assert 0 < len(entry['title']) < 90 and '\\n' not in entry['title'], entry['path']
        for dep, value in entry.get('when', []):
            assert dep in fields, dep
        typ, default = fields[entry['path']]
        if entry['path'] in time_units:
            assert entry.get('unit') == time_units[entry['path']], ('Missing or incorrect time unit',entry)
            assert entry['scale'] == 1, ('Unit labels must not reinterpret stored values',entry)
        if 'unit' in entry:
            assert entry['unit'] in data['timeUnits'], entry
        if entry['kind'] == 'number':
            assert entry['min'] < entry['max'] and entry['step'] > 0 and entry['scale'] > 0
            literal = re.match(r'^(-?\d+(?:\.\d+)?)\s*(?://.*)?$', default)
            if literal:
                value = float(literal[1]) * entry['scale']
                assert entry['min'] <= value <= entry['max'], (entry['path'], value)
        if entry['kind'] == 'choice':
            literal = re.match(r'^("[^"]*"|-?\d+)\s*(?://.*)?$', default)
            if literal:
                assert json.loads(literal[1]) in [x['value'] for x in entry['choices']], entry['path']
    pattern = re.compile(r'Config\??\.options((?:\??\.[A-Za-z_]\w*)+)')
    consumed = set()
    for path in SHELL.rglob('*.qml'):
        if 'settings' in path.parts or path.name in ['settings.qml', 'Config.qml']:
            continue
        text = re.sub(r'/\*.*?\*/', '', path.read_text(), flags=re.S)
        text = re.sub(r'(?m)^\s*//.*$', '', text)
        consumed.update(m[1].replace('?.', '.').strip('.') for m in pattern.finditer(text))
    assert not consumed.intersection(data['retired']), 'A retired key has gained a runtime consumer'
    panel = (SHELL / 'modules/ii/sidebarRight/quickToggles/AndroidQuickPanel.qml').read_text()
    editor = (SHELL / 'modules/settings/QuickTileEditor.qml').read_text()
    runtime_tiles = json.loads(re.search(r'availableToggleTypes: (\[.*?\])', panel)[1])
    editor_tiles = json.loads(re.search(r'available: (\[.*?\])', editor)[1])
    assert runtime_tiles == editor_tiles, 'Tile editor and runtime support differ'
    profiles = json.loads(subprocess.check_output(['bash', str(REPO / 'dots/.local/bin/fontctl'), 'preset', 'catalog']))
    assert len(profiles) == 26 and len({p['id'] for p in profiles}) == 26
    print(f'PASS: {len(fields)} schema keys classified; {len(entries)} controls; {len(time_units)} time units verified; {len(profiles)} font profiles; tile catalog matches runtime')


if __name__ == '__main__':
    main()
