"""Park/unpark UI regressions for dots/.local/bin/vminfo without touching live processes."""
import contextlib
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

PATH = Path(__file__).resolve().parents[1] / 'dots/.local/bin/vminfo'
loader = importlib.machinery.SourceFileLoader('vminfo_park_dots', str(PATH))
spec = importlib.util.spec_from_loader(loader.name, loader)
vm = importlib.util.module_from_spec(spec)
loader.exec_module(vm)


def row(pid, name='eglantine', state='T'):
    return dict(
        pid=str(pid), comm=name, raw_comm=name, cmdline='/usr/bin/' + name,
        uid=os.getuid(), user='gus', start=int(pid) * 10, owned=True,
        rss=19 << 20, swap=3 << 30, total_mem=(19 << 20) + (3 << 30),
        pcpu=0.0, pmem=0.1, state=state, oom_score=100, elapsed=500, threads=4,
    )


class VminfoParkingTests(unittest.TestCase):
    def test_dashboard_shows_parked_banner_prk_state_and_fits_bounds(self):
        rows = [row(101, 'eglantine', 'T'), row(102, 'firefox', 'S')]
        parked = [dict(id='592c6e532833', label='eglantine', mode='disk', state='parked',
                       processes=[dict(pid=101, start=1010, name='eglantine')])]
        mem = {'MemTotal': 16 << 30, 'MemAvailable': 8 << 30, 'SwapTotal': 8 << 30, 'SwapFree': 5 << 30}
        psi = {'some': dict(avg10=0, avg60=0, avg300=0), 'full': dict(avg10=0)}
        with patch.object(vm, 'read_parked_groups', return_value=(parked, {('101', 1010)})), \
             patch.object(vm, 'get_vm_knobs', return_value={}), \
             patch.object(vm, 'get_cryod_status', return_value={'state': 'observing', 'detail': 'ok', 'healthy': True}):
            for width, height in ((45, 24), (80, 24), (110, 40)):
                with self.subTest(width=width, height=height), \
                     patch.object(vm, 'get_term_size', return_value=(width, height)):
                    text = vm.draw_dashboard(mem, psi, {}, 0, False, {}, rows, 30, 0.0, {},
                                             dict(l1=0, l5=0, l15=0, running=1, total=2), 321)
                    lines = text.splitlines()
                    self.assertLessEqual(len(lines), height)
                    self.assertLessEqual(max(map(vm.visible_len, lines)), width - 1)
                    self.assertIn('unpark(1)', text)
                    self.assertIn('Parked (1):', text)
                    if width >= 65:
                        self.assertIn('PRK', text)

    def test_unpark_enter_defaults_to_only_group_and_checked_row_unparks_directly(self):
        term = Mock()
        target_row = row(101, 'eglantine', 'T')
        groups = [dict(id='592c6e532833', label='eglantine', mode='disk', state='parked',
                       rss=19 << 20, swap=3 << 30,
                       processes=[dict(pid=101, start=1010, uid=os.getuid(), name='eglantine')])]
        with patch.object(vm, '_fetch_parked_groups_json', return_value=groups), \
             patch.object(vm, 'keyboard_input', side_effect=['', '']), \
             patch.object(vm, 'subprocess', wraps=vm.subprocess) as sub, \
             contextlib.redirect_stdout(io.StringIO()):
            sub.run.return_value = Mock(returncode=0)
            vm.run_park_action(term, action='unpark')
            cmd = sub.run.call_args.args[0]
            self.assertIn('resume', cmd)
            self.assertIn('--allow-index', cmd)
            self.assertEqual(cmd[-1], '1')

        with patch.object(vm, '_fetch_parked_groups_json', return_value=groups), \
             patch.object(vm, 'keyboard_input', return_value=''), \
             patch.object(vm, 'subprocess', wraps=vm.subprocess) as sub, \
             contextlib.redirect_stdout(io.StringIO()):
            sub.run.return_value = Mock(returncode=0)
            vm.run_park_action(term, selected=[target_row], action='unpark')
            cmd = sub.run.call_args.args[0]
            self.assertIn('resume', cmd)
            self.assertIn('592c6e532833', cmd)


if __name__ == '__main__':
    unittest.main()
