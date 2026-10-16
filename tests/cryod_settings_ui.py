#!/usr/bin/env python3
"""Actual settings controls in a disposable home and private X/D-Bus session."""
from pathlib import Path
source = Path(__file__).with_name('settings_ui.py')
exec(compile(source.read_text().split('\ntry:\n    until(', 1)[0], str(source), 'exec'), globals())
try:
    until(lambda: json.loads(call('settings', 'status'))['ready'])
    call('settings', 'open', 'cryod')
    until(lambda: json.loads(call('test', 'locate', 'cryodMaster')))
    assert json.loads(call('test', 'locate', 'cryodFeatures')) is None
    click('cryodMaster')
    until(lambda: json.loads(call('test', 'locate', 'cryodFeatures')))
    click('cryodFocused');click('cryodVisible')
    until(lambda: json.loads(config.read_text()).get('cryod') ==
          dict(enabled=True, protectForeground=False, protectVisible=False))
    screenshot('cryod-settings')
    click('cryodMaster')
    until(lambda: json.loads(call('test', 'locate', 'cryodFeatures')) is None)
    until(lambda: not json.loads(config.read_text())['cryod']['enabled'])
    saved = json.loads(config.read_text())
    assert saved['settingsTestSentinel'] == initial['settingsTestSentinel']
    def unchanged(before, after, path=''):
        if isinstance(before, dict):
            for key, value in before.items():
                if not path and key == 'cryod':
                    continue
                assert key in after, path+key
                unchanged(value, after[key], path+key+'.')
        else:
            assert before == after, path
    unchanged(initial, saved)
    print('PASS: real CryoD settings master, hidden features, independent choices and unrelated config preservation')
finally:
    process.terminate();process.wait(timeout=10);log.close()
