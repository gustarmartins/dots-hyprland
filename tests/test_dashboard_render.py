#!/usr/bin/env python3
"""Collector-free checks for incremental terminal output."""
import ast
import json
from pathlib import Path
import sys


def check(path):
    tree = ast.parse(Path(path).read_text())
    node = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'DashboardRenderer')
    ns = {}
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(path), 'exec'), ns)
    renderer = ns['DashboardRenderer']()
    frame = '\n'.join(f'\x1b[36mrow {i:02}: ' + ('x' * 95) + '\x1b[0m\x1b[K' for i in range(40))
    assert renderer.encode(frame, (120, 45))
    assert renderer.encode(frame, (120, 45)) == ''
    changed = frame.replace('row 20:', 'row XX:')
    patch = renderer.encode(changed, (120, 45))
    assert '\x1b[21;1H' in patch and '\x1b[20;1H' not in patch
    assert renderer.encode(changed, (120, 45), generation=1).startswith('\x1b[H\x1b[2J')
    assert renderer.encode(changed, (80, 20), generation=1).startswith('\x1b[H\x1b[2J')
    assert '\x1b[2;1H' in renderer.encode('short', (80, 20), generation=1)
    renderer = ns['DashboardRenderer']()
    old = new = 0
    for tick in range(300):
        rows = frame.split('\n')
        for i in [3, 11, 20, 30]:
            rows[i] = rows[i].replace('xxxxx', f'{tick // 25:05}', 1)
        output = '\n'.join(rows)
        old += len(('\x1b[H' + output + '\n\x1b[J').encode())
        new += len(renderer.encode(output, (120, 45)).encode())
    assert new < old / 50
    return {'script': Path(path).name, 'synthetic_before_bytes': old,
            'synthetic_after_bytes': new, 'real_network_measurement': False}


if __name__ == '__main__':
    paths = sys.argv[1:] or [Path(__file__).resolve().parents[1] / 'dots/.local/bin/vminfo']
    for path in paths:
        print(json.dumps(check(path)))
