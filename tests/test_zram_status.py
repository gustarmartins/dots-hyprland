"""Read-only ZRAM status under the real shell helper's shared action lock."""
import errno
import fcntl
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'dots/.local/bin/zram-algo-mode.sh'


class ZramStatus(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='zram-status-')
        self.root = Path(self.directory.name)
        self.sysfs = self.root / 'sysfs'
        self.sysfs.mkdir()
        (self.sysfs / 'comp_algorithm').write_text('lzo [lz4] zstd\n')
        (self.sysfs / 'backing_dev').write_text('/dev/owned-fixture\n')
        self.config = self.root / 'config'
        self.config.write_text('[zram0]\ncompression-algorithm = lz4\n')
        self.levels = self.root / 'levels'
        self.levels.write_text('tier1=zstd:3\ntier2=zstd:9\ntier3=zstd:15\n')
        self.lock = self.root / 'lock'
        self.lock.write_text('unchanged lock contents\n')
        text = SOURCE.read_text()
        for old, new in (('CONF=/etc/systemd/zram-generator.conf', 'CONF=' + shlex.quote(str(self.config))),
                         ('LEVELS=/run/vmatlas-tier/levels', 'LEVELS=' + shlex.quote(str(self.levels))),
                         ('READ_LOCK=/run/lock/vmatlas-zram-tier.lock', 'READ_LOCK=' + shlex.quote(str(self.lock)))):
            self.assertEqual(text.count(old), 1)
            text = text.replace(old, new)
        self.assertEqual(text.count('/sys/block/zram0/'), 2)
        self.script = self.root / 'helper'
        self.script.write_text(text.replace('/sys/block/zram0/', str(self.sysfs) + '/'))
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
            child.communicate(timeout=2)
        self.directory.cleanup()

    def start(self, action='status'):
        child = subprocess.Popen(['bash', str(self.script), action], stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.children.append(child)
        return child

    def result(self, action='status'):
        child = self.start(action)
        output, error = child.communicate(timeout=1)
        self.assertEqual(child.returncode, 0, error)
        return output.strip()

    def fifo(self):
        path = self.sysfs / 'comp_algorithm'
        path.unlink()
        os.mkfifo(path)
        return path

    def test_live_staged_and_secondary_display_remain_exact(self):
        self.assertEqual(self.result(), 'lz4 + zstd:3/zstd:9/zstd:15 + NVMe')
        self.config.write_text('compression-algorithm = zstd\n')
        self.assertEqual(self.result('get_state'), 'lz4->zstd + zstd:3/zstd:9/zstd:15 + NVMe')
        self.assertEqual(self.lock.read_text(), 'unchanged lock contents\n')

    def test_busy_never_enters_even_a_blocking_sysfs_read(self):
        self.fifo()
        with self.lock.open('r+') as writer:
            fcntl.flock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for _ in range(6):
                self.assertEqual(self.result(), 'busy')
            self.assertEqual(self.result('staged'), 'lz4')

    def test_absent_lock_is_unknown_without_an_unprotected_read(self):
        self.fifo()
        self.lock.unlink()
        self.assertEqual(self.result(), 'unknown')
        self.assertFalse(self.lock.exists())

    def test_reader_holds_shared_lease_until_all_status_reads_end(self):
        pipe = self.fifo()
        child = self.start()
        with self.lock.open('r+') as writer:
            until = time.monotonic() + 1
            while True:
                try:
                    fcntl.flock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    fcntl.flock(writer, fcntl.LOCK_UN)
                except BlockingIOError:
                    break
                self.assertLess(time.monotonic(), until)
                time.sleep(.005)
            while True:
                try:
                    fd = os.open(pipe, os.O_WRONLY | os.O_NONBLOCK)
                    break
                except OSError as error:
                    self.assertEqual(error.errno, errno.ENXIO)
                    self.assertLess(time.monotonic(), until)
                    time.sleep(.005)
            os.write(fd, b'lzo [lz4] zstd\n')
            os.close(fd)
            output, error = child.communicate(timeout=1)
            self.assertEqual(child.returncode, 0, error)
            self.assertEqual(output.strip(), 'lz4 + zstd:3/zstd:9/zstd:15 + NVMe')
            fcntl.flock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB)


if __name__ == '__main__':
    unittest.main()
