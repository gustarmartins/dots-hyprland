#!/usr/bin/env python3
"""Exercise the real memory tile models with isolated helpers, home and D-Bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
MODELS = REPO / 'dots/.config/quickshell/ii/modules/common/models/quickToggles'
TILES = ['ZramRecompress', 'ZramWriteback', 'ZramAlgo', 'MemoryMode',
         'MemoryCompact', 'MemoryDropCaches', 'GpuMemory']
HELPERS = ['memory-tools.sh', 'memory-mode.sh', 'zram-algo-mode.sh']
EXPECTED = {
    'memory-tools.sh recompress-status', 'memory-tools.sh recompress-run',
    'memory-tools.sh recompress-cycle', 'memory-tools.sh writeback-status',
    'memory-tools.sh writeback-cold', 'memory-tools.sh writeback-all',
    'memory-tools.sh compact-memory', 'memory-tools.sh compact-zram',
    'memory-tools.sh drop-caches', 'memory-tools.sh gpu-status',
    'memory-tools.sh gpu-report', 'memory-tools.sh gpu-evict',
    'memory-mode.sh get_state', 'memory-mode.sh report', 'memory-mode.sh toggle',
    'zram-algo-mode.sh status', 'zram-algo-mode.sh next', 'zram-algo-mode.sh live',
}

for legacy in (False, True):
    with tempfile.TemporaryDirectory(prefix='memory-widgets-') as tmp:
        root = Path(tmp)
        config = root / 'config'
        model_dir = config / 'modules/common/models/quickToggles'
        model_dir.mkdir(parents=True)
        (config / 'Stub.qml').write_text('import QtQuick\nQtObject {}\n')
        for name in ['QuickToggleModel'] + [t + 'Toggle' for t in TILES]:
            shutil.copy2(MODELS / (name + '.qml'), model_dir)
        for name in ('services', 'modules/common', 'modules/common/functions', 'modules/common/widgets'):
            folder = config / name
            folder.mkdir(parents=True, exist_ok=True)
            (folder / 'Stub.qml').write_text('import QtQuick\nQtObject {}\n')
        (config / 'services/Translation.qml').write_text(
            'pragma Singleton\nimport Quickshell\nSingleton { function tr(s) { return s; } }\n')
        for directory in ('runtime', 'bin', '.local/bin', 'cache'):
            (root / directory).mkdir(parents=True, mode=0o700)
        shim = '''#!/bin/bash
printf '%s %s %s\\n' ORIGIN "${0##*/}" "$*" >> "$HOME/calls"
case "${0##*/}:$1" in
 memory-tools.sh:recompress-status) cat "$HOME/mode" 2>/dev/null || echo tier1 ;;
 memory-tools.sh:recompress-cycle) echo tier2 > "$HOME/mode" ;;
 memory-tools.sh:writeback-status) echo 'Guarded · 2.0 GiB boot quota' ;;
 memory-tools.sh:gpu-status) echo 'GPU fixture' ;;
 memory-mode.sh:get_state) echo off ;;
 zram-algo-mode.sh:status) echo 'lz4 + zstd:3/zstd:9/zstd:15 + disk' ;;
esac
exit 0
'''
        for helper in HELPERS:
            for directory, origin in [('bin', 'system')] + ([('.local/bin', 'legacy')] if legacy else []):
                file = root / directory / helper
                file.write_text(shim.replace('ORIGIN', origin))
                file.chmod(0o755)
        declarations = '\n'.join(f'{tile}Toggle {{ id: tile{i} }}' for i, tile in enumerate(TILES))
        actions = '\n'.join(f'tile{i}.mainAction(); if (tile{i}.altAction) tile{i}.altAction();' for i in range(len(TILES)))
        (config / 'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.modules.common.models.quickToggles
ShellRoot {
''' + declarations + '''
Timer { interval: 900; running: true; onTriggered: {
 console.log("MEMORY_INITIAL " + JSON.stringify([tile0.statusText,tile1.statusText,tile2.statusText,tile3.statusText,tile6.statusText]));
''' + actions + '''
} }
Timer { interval: 2400; running: true; onTriggered: {
 console.log("MEMORY_FINAL " + tile0.statusText); Qt.quit();
} }
}
''')
        env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root/'xdg'),
                   XDG_CACHE_HOME=str(root/'cache'), XDG_RUNTIME_DIR=str(root/'runtime'),
                   QT_QPA_PLATFORM='offscreen', PATH=str(root/'bin') + ':/usr/bin')
        env.pop('QS_CONFIG_PATH', None)
        env.pop('QS_CONFIG_NAME', None)
        result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(config)],
                                env=env, text=True, capture_output=True, timeout=12)
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        initial = next(line.split('MEMORY_INITIAL ', 1)[1] for line in output.splitlines() if 'MEMORY_INITIAL ' in line)
        assert json.loads(initial) == ['tier1', 'Guarded · 2.0 GiB boot quota',
            'lz4 + zstd:3/zstd:9/zstd:15 + disk', 'Disk swap · off', 'GPU fixture'], output
        assert 'MEMORY_FINAL tier2' in output, output
        calls = [line.split(' ', 1) for line in (root/'calls').read_text().splitlines()]
        assert all(origin == ('legacy' if legacy else 'system') for origin, call in calls), calls
        assert EXPECTED <= {call for origin, call in calls}, calls
        print(f'PASS: {"legacy user" if legacy else "system"} helpers; seven QML models, status, clicks and tier refresh')
