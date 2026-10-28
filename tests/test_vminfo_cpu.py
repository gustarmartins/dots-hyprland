"""CPU accounting regressions: interval time, process birth, gaps, and sorting."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / 'dots/.local/bin/vminfo'
loader = importlib.machinery.SourceFileLoader('vminfo', str(PATH))
spec = importlib.util.spec_from_loader(loader.name, loader)
vm = importlib.util.module_from_spec(spec)
loader.exec_module(vm)


def row(seconds, at, pid='10', start=1):
    return dict(pid=pid, start=start, cpu_ticks=round(seconds * vm._CLK_TCK),
                cpu_sample_time=at, pcpu_average=37.2)


class CpuTest(unittest.TestCase):
    def setUp(self):
        self.sampler = vm.ProcessCpuSampler()
        vm._cpu_mode = 'live'

    def test_first_sample_is_unknown_and_interval_is_not_lifetime(self):
        first = row(100, 1000)
        self.sampler.sample([first])
        self.assertIsNone(first['pcpu_live'])
        current = row(100.5, 1005)
        self.sampler.sample([current])
        self.assertAlmostEqual(current['pcpu_live'], 10)
        vm.apply_cpu_mode([current])
        self.assertAlmostEqual(current['pcpu'], 10)
        vm._cpu_mode = 'average'
        vm.apply_cpu_mode([current])
        self.assertEqual(current['pcpu'], 37.2)

    def test_multithreaded_usage_can_exceed_100(self):
        self.sampler.sample([row(0, 1)])
        current = row(6, 3)
        self.sampler.sample([current])
        self.assertEqual(current['pcpu_live'], 300)

    def test_pid_reuse_never_inherits_old_cpu(self):
        self.sampler.sample([row(3, 1)])
        current = row(30, 2, start=2)
        self.sampler.sample([current])
        self.assertIsNone(current['pcpu_live'])

    def test_missing_process_is_pruned_and_restart_needs_baseline(self):
        self.sampler.sample([row(3, 1)])
        self.sampler.sample([])
        self.assertFalse(self.sampler.previous)
        current = row(4, 2)
        self.sampler.sample([current])
        self.assertIsNone(current['pcpu_live'])

    def test_unreadable_counter_and_clock_regression_are_unknown(self):
        self.sampler.sample([row(3, 1)])
        for current in [row(4, 1), row(2, 2), row(3, 3, start=None)]:
            self.sampler.sample([current])
            self.assertIsNone(current['pcpu_live'])
        current = row(4, 4)
        current['cpu_ticks'] = None
        self.sampler.sample([current])
        self.assertIsNone(current['pcpu_live'])

    def test_resume_does_not_average_over_paused_time(self):
        self.sampler.sample([row(3, 1)])
        self.sampler.reset()
        current = row(50, 100)
        self.sampler.sample([current])
        self.assertIsNone(current['pcpu_live'])
        current = row(50, 105)
        self.sampler.sample([current])
        self.assertEqual(current['pcpu_live'], 0)

    def test_cpu_sort_keeps_unknown_below_measured_zero(self):
        rows = [dict(pid='a', pcpu=None), dict(pid='b', pcpu=0), dict(pid='c', pcpu=50)]
        self.assertEqual([r['pid'] for r in vm.sort_processes(rows, 1)], ['c', 'b', 'a'])
        self.assertEqual(vm.format_process_cpu(None), '…')
        self.assertEqual(vm.format_process_cpu(0), '0.0%')


if __name__ == '__main__':
    unittest.main()
