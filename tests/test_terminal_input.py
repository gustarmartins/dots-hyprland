#!/usr/bin/env python3
"""Exercise dashboard input without importing collectors or executing actions."""
import ast
import json
import os
from pathlib import Path
import pty
import select
import signal
import sys
import time


def load_input(path):
    tree = ast.parse(Path(path).read_text())
    names = {'keyboard_input', '_partial_suffix', 'parse_terminal_input', 'RawTerminal'}
    constants = {'MOUSE_INPUT_ON', 'MOUSE_INPUT_OFF', 'PASTE_START', 'PASTE_END', '_dashboard_terminal_active'}
    nodes = [n for n in tree.body if
             (isinstance(n, (ast.FunctionDef, ast.ClassDef)) and n.name in names) or
             (isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id in constants for t in n.targets))]
    ns = {'sys': sys, 'os': os, 'select': select, 'time': time}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(path), 'exec'), ns)
    return ns


def check_packets(ns):
    packets = []
    for button in [0, 1, 2, 3, 32, 33, 34, 35, 64, 65, 66, 67, 128, 129]:
        for x, y in [(70, 75), (82, 87), (85, 81), (1, 1), (223, 223)]:
            for end in ['M', 'm']:
                packets.append(f'\x1b[<{button};{x};{y}{end}'.encode())
            packets.append(b'\x1b[M' + bytes([button + 32, x + 32, y + 32]))
    packets += [b'\x1b[200~fukrpwy\n\x1b[201~', b'\x1b[I', b'\x1b[O',
                b'\x1b]0;fukrpw\x07', b'\x1bPfwkrup\x1b\\']
    count = 0
    parse = ns['parse_terminal_input']
    for packet in packets:
        for split in range(len(packet) + 1):
            keys, pending, pasting = parse(packet[:split])
            more, pending, pasting = parse(pending + packet[split:] + b'q', pasting)
            assert keys + more == ['q'], (packet, split, keys, more)
            assert not pending and not pasting
            count += 1
    assert parse(b'fukrpw1234+- ')[0] == list('fukrpw1234+- ')
    assert parse('á猫'.encode(), text=True)[0] == ['á', '猫']
    return count


def check_prompt(ns):
    master, slave = pty.openpty()
    readfd, writefd = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            os.close(master)
            os.close(readfd)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            answer = ns['keyboard_input']('PROMPT> ')
            os.write(writefd, json.dumps(answer).encode())
            os._exit(0)
        except BaseException:
            os._exit(1)
    os.close(slave)
    os.close(writefd)
    try:
        output = b''
        deadline = time.monotonic() + 3
        while b'PROMPT> ' not in output and time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                output += os.read(master, 4096)
        assert b'PROMPT> ' in output
        os.write(master, b'\x1b[M fy\x1b[<2;100;80M\x1b[200~yes\n\x1b[201~')
        assert not select.select([readfd], [], [], .15)[0], 'mouse or paste submitted a prompt'
        os.write(master, 'não\n'.encode())
        assert select.select([readfd], [], [], 2)[0], 'keyboard input did not submit'
        assert json.loads(os.read(readfd, 1024)) == 'não'
        _, status = os.waitpid(pid, 0)
        assert status == 0
        pid = 0
    finally:
        if pid:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(master)
        os.close(readfd)


if __name__ == '__main__':
    for path in sys.argv[1:] or [str(Path(__file__).resolve().parents[1] / 'dots/.local/bin/vminfo')]:
        ns = load_input(path)
        count = check_packets(ns)
        check_prompt(ns)
        print(f'{Path(path).name}: {count} packet splits and PTY prompt test passed')
