"""ZRAM busy labels with a real private flock and a simulated helper process."""
import fcntl
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


script = Path(__file__).resolve().parents[1] / 'dots/.local/bin/vminfo'
loader = importlib.machinery.SourceFileLoader('vminfo_zram', str(script))
spec = importlib.util.spec_from_loader(loader.name, loader)
vm = importlib.util.module_from_spec(spec)
loader.exec_module(vm)


class ZramActorTests(unittest.TestCase):
    def busy_label(self, verb, *, prefix='/usr/local/libexec/cryod-desktop', service=True,
                   evidence=True, uid=0, change_birth=False):
        with tempfile.NamedTemporaryFile() as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            fdinfo = Path(f'/proc/self/fdinfo/{lock.fileno()}').read_text()
            helper = prefix + '/memory-tool-apply'
            fields = {
                'cmdline': '\0'.join(('/bin/bash', helper, verb, '64', '1800', '')),
                'cgroup': '1:net_cls:/\n' + ('0::/system.slice/cryod.service' if service else '0::/user.slice/session-3.scope'),
                'fdinfo/9': fdinfo if evidence else None,
                'stat': '1234 (helper) S 100 0 1 34816',
                'loginuid': str(os.getuid()),
            }
            before = {'uid':uid, 'start':1}
            after = {'uid':uid, 'start':2} if change_birth else before
            with patch.object(vm, '_ZRAM_ACTION_LOCK', lock.name), \
                    patch.object(vm, '_read_proc_field', side_effect=lambda pid, name: fields.get(name)), \
                    patch.object(vm, 'read_process_identity', side_effect=[before, after]), \
                    patch('builtins.open', return_value=io.StringIO('1234\n')), \
                    patch.object(vm, '_read_zram_stats_unlocked') as sample:
                previous = {'sample_marker':17}
                value = vm.get_zram_stats(previous, ())
                sample.assert_not_called()
                self.assertTrue(value['busy'])
                self.assertEqual(value['sample_marker'], 17)
                self.assertEqual(previous, {'sample_marker':17})
                return value['activity']

    def test_both_native_pressure_commands_in_both_layouts(self):
        for layout in ('/usr/local/libexec/cryod-desktop', '/usr/lib/cryod-desktop'):
            for verb in ('writeback-bounded', 'writeback-pressure-bounded'):
                with self.subTest(layout=layout, verb=verb):
                    self.assertEqual(self.busy_label(verb, prefix=layout), 'CryoD writeback')

    def test_private_fdinfo_only_proves_a_helper_was_seen(self):
        self.assertEqual(self.busy_label('writeback-pressure-bounded', evidence=False),
                         'CryoD writeback helper seen')

    def test_same_command_from_a_terminal_keeps_terminal_attribution(self):
        self.assertEqual(self.busy_label('writeback-pressure-bounded', service=False),
                         'this terminal (your login) writeback')

    def test_unverified_owner_stays_unknown(self):
        for changes in ({'uid':1000}, {'change_birth':True}, {'prefix':'/unverified'}):
            with self.subTest(changes=changes):
                self.assertEqual(self.busy_label('writeback-pressure-bounded', **changes), 'owner unknown')
        self.assertEqual(self.busy_label('writeback-pressure-bounded-copy'), 'owner unknown')


if __name__ == '__main__':
    unittest.main()
