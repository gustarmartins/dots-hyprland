import copy
from contextlib import ExitStack
import fcntl
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

HELPER = Path(__file__).resolve().parents[1] / 'dots/.local/bin/disk-reclaim'
loader = importlib.machinery.SourceFileLoader('disk_reclaim', str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
REAL_REFERENCES = m.active_references
REAL_FILESYSTEM = m.filesystem
REAL_DISK_STATUS = m.disk_status


class Cleanup(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack(); self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory(prefix='disk-reclaim-test-')))
        self.project = self.root / 'project'; self.project.mkdir()
        for n in ('gradlew', 'build.gradle.kts', 'settings.gradle.kts'):
            (self.project / n).write_text('fixture build recipe')
        self.cache = self.project / 'app/build/intermediates'; self.cache.mkdir(parents=True)
        (self.cache / 'object.bin').write_bytes(b'fixture compiler output')
        self.stack.enter_context(patch.object(m, 'HOME', self.root))
        self.stack.enter_context(patch.object(m, 'STATE', self.root / 'state'))
        self.stack.enter_context(patch.object(m, 'CONFIG', self.root / 'config.json'))
        self.stack.enter_context(patch.object(m, 'MUTATION_LOCK', self.root / 'mutation.lock'))
        self.stack.enter_context(patch.object(m, 'filesystem', return_value=dict(token='fixture', fstype='btrfs')))
        self.stack.enter_context(patch.object(m, 'active_references', return_value=(set(), set(), set(), set())))
        self.stack.enter_context(patch.object(m, 'disk_status', return_value=[dict(name='nvme', mounted=True, free=m.GIB, total=10*m.GIB, token='fixture')]))

    def candidate(self, path=None, kind='android', metadata=None):
        c = dict(path=str(path or self.cache), kind=kind, project=str(self.project), scope=None,
                 recipe='fixture rebuild', filesystem='fixture', disk='nvme', metadata=str(metadata) if metadata else None)
        return m.enumerate_candidate(c)

    def test_removes_only_previewed_compiler_files(self):
        outputs = self.project / 'app/build/outputs'; outputs.mkdir()
        (outputs / 'release.apk').write_bytes(b'final deliverable')
        (self.cache / 'failure.log').write_text('failure evidence')
        (self.cache / 'signing.jks').write_bytes(b'private key')
        (self.cache / 'cache.lock').touch()
        c = self.candidate(); report, receipt = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 1)
        self.assertEqual(report['status'], 'completed')
        self.assertTrue(receipt.exists())
        self.assertFalse((self.cache / 'object.bin').exists())
        self.assertTrue((self.cache / 'failure.log').exists())
        self.assertTrue((self.cache / 'signing.jks').exists())
        self.assertTrue((self.cache / 'cache.lock').exists())
        self.assertEqual((outputs / 'release.apk').read_bytes(), b'final deliverable')
        self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)

    def test_newer_file_is_preserved(self):
        c = self.candidate(); (self.cache / 'object.bin').write_bytes(b'new compile output')
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 0)
        self.assertIn('changed', report['skipped'][0]['reason'])

    def test_root_symlink_swap_does_not_follow_target(self):
        c = self.candidate(); held = self.cache.with_name('held'); self.cache.rename(held)
        target = self.root / 'important'; target.mkdir(); (target / 'object.bin').write_bytes(b'user data')
        self.cache.symlink_to(target, target_is_directory=True)
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 0)
        self.assertEqual((target / 'object.bin').read_bytes(), b'user data')

    def test_ancestor_symlink_swap_is_rejected(self):
        c = self.candidate(); app = self.project / 'app'; actual = self.project / 'real-app'
        app.rename(actual); app.symlink_to(actual, target_is_directory=True)
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 0)
        self.assertTrue((actual / 'build/intermediates/object.bin').exists())

    def test_configured_build_redirect_is_resolved_and_pinned(self):
        build = self.project / 'app/build'; target = self.root / 'redirected-build'
        build.rename(target); build.symlink_to(target, target_is_directory=True)
        d = m.Discovery(); d.add(build / 'intermediates', 'android', 'fixture', self.project)
        c = m.enumerate_candidate(next(iter(d.roots.values())))
        self.assertEqual(c['path'], str(target / 'intermediates'))
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 1)
        self.assertTrue(build.is_symlink())

    def test_changed_configured_redirect_is_preserved(self):
        build = self.project / 'app/build'; target = self.root / 'redirected-build'
        build.rename(target); build.symlink_to(target, target_is_directory=True)
        d = m.Discovery(); d.add(build / 'intermediates', 'android', 'fixture', self.project)
        c = m.enumerate_candidate(next(iter(d.roots.values())))
        other = self.root / 'new-build'; other.mkdir(); (other / 'intermediates').mkdir()
        build.unlink(); build.symlink_to(other, target_is_directory=True)
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 0)
        self.assertTrue((target / 'intermediates/object.bin').exists())

    def test_shared_redirect_protects_every_build_owner(self):
        build = self.project / 'app/build'; target = self.root / 'shared-build'
        build.rename(target); build.symlink_to(target, target_is_directory=True)
        other = self.root / 'second-project'; (other / 'app').mkdir(parents=True)
        (other / 'app/build').symlink_to(target, target_is_directory=True)
        d = m.Discovery()
        d.add(build / 'intermediates', 'android', 'fixture', self.project)
        d.add(other / 'app/build/intermediates', 'android', 'fixture', other)
        c = next(iter(d.roots.values()))
        self.assertEqual(len(c['projects']), 2)
        self.assertEqual(m.busy(c, (set(), set(), {str(self.project)}, set())), 'active build in project')

    def test_partial_interruption_receipt_counts_deleted_files(self):
        (self.cache / 'second.bin').write_bytes(b'second compiler output')
        c = self.candidate(); c['files'].sort(key=lambda f: f['relative']); actual_unlink = os.unlink
        def interrupt_second(name, *args, **kwargs):
            if name == 'second.bin':
                raise KeyboardInterrupt()
            return actual_unlink(name, *args, **kwargs)
        with patch.object(m.os, 'unlink', side_effect=interrupt_second):
            with self.assertRaises(KeyboardInterrupt):
                m.execute_cleanup([c], [])
        receipt = next((m.STATE / 'receipts').glob('*/receipt.json'))
        report = json.loads(receipt.read_text())
        self.assertEqual(report['status'], 'interrupted')
        self.assertEqual(report['files_removed'], 1)

    def test_embedded_symlink_is_preserved_and_not_followed(self):
        target = self.root / 'outside.txt'; target.write_text('keep')
        (self.cache / 'link').symlink_to(target)
        report, _ = m.execute_cleanup([self.candidate()], [])
        self.assertEqual(report['files_removed'], 1)
        self.assertTrue((self.cache / 'link').is_symlink())
        self.assertEqual(target.read_text(), 'keep')

    def test_active_builder_and_inode_preserved(self):
        c = self.candidate()
        for refs in [(set(), set(), {str(self.project)}, set()),
                     (set(), {(c['files'][0]['id'][0], c['files'][0]['id'][1])}, set(), set())]:
            with patch.object(m, 'active_references', return_value=refs):
                report, _ = m.execute_cleanup([c], [])
                self.assertEqual(report['files_removed'], 0)
        self.assertTrue((self.cache / 'object.bin').exists())

    def test_build_output_lock_is_preserved(self):
        lock = self.project / '.gradle/cryomgr-build-output.lock'; lock.parent.mkdir(); lock.touch()
        with m.locked(lock):
            report, _ = m.execute_cleanup([self.candidate()], [])
        self.assertEqual(report['files_removed'], 0)
        self.assertTrue(lock.exists())

    def test_mutation_lock_is_respected(self):
        with m.locked(m.MUTATION_LOCK):
            report, _ = m.execute_cleanup([self.candidate()], [])
        self.assertEqual(report['files_removed'], 0)

    def test_mount_generation_change_is_rejected(self):
        c = self.candidate()
        with patch.object(m, 'filesystem', return_value=dict(token='new-mount')):
            report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 0)

    def test_source_recipe_change_is_rejected(self):
        c = self.candidate(); (self.project / 'build.gradle.kts').write_text('new source configuration')
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 0)

    def test_tracked_artifacts_are_not_cache(self):
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        subprocess.run(['git', '-C', str(self.project), 'add', '-f', str(self.cache / 'object.bin')], check=True)
        with self.assertRaisesRegex(ValueError, 'tracked'):
            self.candidate()

    def test_browser_and_recovery_paths_excluded(self):
        for part in ('.mozilla', '.ssh', 'Never_Delete', 'firefox-backup', 'snapshot-2026'):
            self.assertTrue(m.protected(self.root / part / 'app/build/intermediates'))
        (self.cache / 'cookies.sqlite').write_bytes(b'authentication')
        c = self.candidate(); self.assertNotIn('cookies.sqlite', [f['relative'] for f in c['files']])

    def test_trash_metadata_is_removed_only_with_item(self):
        trash = self.root / 'Trash'; (trash / 'files').mkdir(parents=True); (trash / 'info').mkdir()
        item = trash / 'files/discarded.mp4'; item.write_bytes(b'owner discarded this')
        info = trash / 'info/discarded.mp4.trashinfo'; info.write_text('[Trash Info]\nPath=/Videos/discarded.mp4\nDeletionDate=2026-10-25T12:00:00\n')
        c = self.candidate(item, 'trash', info)
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 1)
        self.assertFalse(item.exists()); self.assertFalse(info.exists())

    def test_updated_trash_metadata_prevents_removal(self):
        info = self.root / 'item.trashinfo'; info.write_text('original')
        c = self.candidate(self.cache / 'object.bin', 'trash', info)
        info.write_text('owner changed metadata')
        report, _ = m.execute_cleanup([c], [])
        self.assertEqual(report['files_removed'], 0)

    def test_browser_profile_in_trash_is_protected(self):
        trash = self.root / '.local/share/Trash'
        (trash / 'files/profile').mkdir(parents=True); (trash / 'info').mkdir()
        (trash / 'files/profile/sessionstore.jsonlz4').write_bytes(b'protected session')
        (trash / 'info/profile.trashinfo').write_text('[Trash Info]\nPath=/home/fixture/.mozilla/firefox/profile\nDeletionDate=2026-10-25T12:00:00\n')
        d = m.Discovery(); d.trash()
        self.assertEqual(d.roots, {})

    def test_preview_does_not_mutate_cache(self):
        before = (self.cache / 'object.bin').read_bytes(); c = self.candidate()
        self.assertEqual((self.cache / 'object.bin').read_bytes(), before)
        self.assertEqual(c['files'][0]['relative'], 'object.bin')
        self.assertFalse(m.STATE.exists())

    def test_open_file_in_real_child_process_is_found(self):
        child = subprocess.Popen([sys.executable, '-c', 'import sys,time; f=open(sys.argv[1]); print("ready",flush=True); time.sleep(30)',
                                  str(self.cache / 'object.bin')], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), 'ready')
            refs = REAL_REFERENCES()
            self.assertEqual(m.busy(self.candidate(), refs), 'open file')
        finally:
            child.terminate(); child.wait(timeout=3); child.stdout.close()

    def test_discovery_requires_module_build_recipe(self):
        d = m.Discovery(); d.walk_projects(self.project, 3)
        self.assertNotIn(str(self.cache), d.roots)
        (self.project / 'app/build.gradle.kts').write_text('fixture Android module')
        d = m.Discovery(); d.walk_projects(self.project, 3)
        self.assertIn(str(self.cache), d.roots)

    def test_deeper_discovery_can_revisit_shallow_tree(self):
        d = m.Discovery(); d.walk_projects(self.root, 0)
        self.assertNotIn(str(self.cache), d.roots)
        (self.project / 'app/build.gradle.kts').write_text('fixture Android module')
        d.walk_projects(self.root, 3)
        self.assertIn(str(self.cache), d.roots)

    def test_unmounted_sata_never_falls_back_to_nvme(self):
        with self.assertRaisesRegex(ValueError, 'not mounted'):
            REAL_FILESYSTEM(Path('/mnt/SSD/cache'), [dict(path='/', token='root', fstype='btrfs', readonly=False)])

    def test_aur_sources_require_clean_recipe_and_matching_checksum(self):
        pkg = self.root / '.cache/yay/example'; pkg.mkdir(parents=True)
        (pkg / 'PKGBUILD').write_text('retained recipe')
        payload = pkg / 'source.tar.gz'; payload.write_bytes(b'original downloaded source')
        checksum = m.digest(payload)
        (pkg / '.SRCINFO').write_text('pkgname = example\npkgver = 1.0\npkgrel = 1\nsource = https://example.test/source.tar.gz\nsha256sums = ' + checksum + '\n')
        package = pkg / 'example-1.0-1-x86_64.pkg.tar.zst'; package.write_bytes(b'compiled package')
        (pkg / 'unrelated.tar.gz').write_bytes(b'private data')
        def git(*args, **kwargs):
            return Mock(returncode=0, stdout='PKGBUILD\n.SRCINFO\n' if 'ls-files' in args else '')
        with patch.object(m, 'run', side_effect=git):
            d = m.Discovery(); d.aur()
            self.assertIn(str(payload), d.roots); self.assertIn(str(package), d.roots)
            self.assertNotIn(str(pkg / 'unrelated.tar.gz'), d.roots)
            payload.write_bytes(b'owner modified download')
            d = m.Discovery(); d.aur(); self.assertNotIn(str(payload), d.roots)

    def test_ccache_requires_owning_marker_and_preserves_config(self):
        cache = self.root / 'ccache'; shard = cache / '0'; shard.mkdir(parents=True)
        (shard / 'object').write_bytes(b'compiler cache result')
        d = m.Discovery(); d.ccache(cache); self.assertNotIn(str(shard), d.roots)
        (shard / 'CACHEDIR.TAG').write_text('Signature: 8a477f597d28d172789f06886806bc55\n')
        (cache / 'ccache.conf').write_text('max_size = 5G')
        d.ccache(cache); self.assertIn(str(shard), d.roots)
        candidate = m.enumerate_candidate(d.roots[str(shard)])
        report, _ = m.execute_cleanup([candidate], [])
        self.assertEqual(report['files_removed'], 1)
        self.assertTrue((shard / 'CACHEDIR.TAG').exists()); self.assertTrue((cache / 'ccache.conf').exists())


class Alerts(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack(); self.addCleanup(self.stack.close)
        root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.stack.enter_context(patch.object(m, 'CONFIG', root / 'config/config.json'))
        self.stack.enter_context(patch.object(m, 'STATE', root / 'state'))
        self.cfg = dict(m.DEFAULT, enabled=True); m.write_json(m.CONFIG, self.cfg)
        self.row = dict(name='nvme', mounted=True, free=20*m.GIB, total=100*m.GIB, token='disk', readonly=False)
        self.stack.enter_context(patch.object(m, 'disk_status', side_effect=lambda: [dict(self.row)]))
        self.notification = self.stack.enter_context(patch.object(m, 'notify', return_value=True))
        self.now = 1000000
        self.stack.enter_context(patch.object(m.time, 'time', side_effect=lambda: self.now))

    def test_notify_dedup_and_immediate_escalation(self):
        m.check_capacity(True); self.assertEqual(self.notification.call_count, 1)
        self.now += 30; m.check_capacity(True); self.assertEqual(self.notification.call_count, 1)
        self.row['free'] = 2*m.GIB; self.now += 30; m.check_capacity(True)
        self.assertEqual(self.notification.call_count, 2)

    def test_notification_failure_is_retried(self):
        self.notification.return_value = False; m.check_capacity(True)
        self.now += 30; self.notification.return_value = True; m.check_capacity(True)
        self.assertEqual(self.notification.call_count, 2)

    def test_master_off_does_not_notify_or_write_history(self):
        self.cfg['enabled'] = False; m.write_json(m.CONFIG, self.cfg)
        m.check_capacity(True); self.notification.assert_not_called()
        self.assertFalse((m.STATE / 'alerts.json').exists())

    def test_per_disk_and_desktop_off(self):
        for key in ('desktop', 'nvme'):
            cfg = dict(self.cfg); cfg[key] = False; m.write_json(m.CONFIG, cfg)
            m.check_capacity(True)
        self.notification.assert_not_called()

    def test_fast_growth_forecast_before_threshold(self):
        self.row['free'] = 80*m.GIB; m.check_capacity(True)
        self.row['free'] = 70*m.GIB; self.now += 60
        rows = m.check_capacity(True)
        self.assertEqual(rows[0]['level'], 'critical')
        self.assertAlmostEqual(rows[0]['eta_minutes'], 7)

    def test_forecast_ignores_changed_disk_and_stale_samples(self):
        history = [dict(time=self.now-60, free=100*m.GIB, token='other')]
        row = dict(self.row, free=60*m.GIB)
        self.assertIsNone(m.capacity_level(row, self.cfg, history, self.now)['eta_minutes'])
        history[0].update(token='disk', time=self.now-1000)
        self.assertIsNone(m.capacity_level(row, self.cfg, history, self.now)['eta_minutes'])

    def test_recovery_hysteresis_does_not_repeat_warning(self):
        m.check_capacity(True)
        self.row['free'] = int(32.1*m.GIB); self.now += 30; m.check_capacity(True)
        self.row['free'] = 31*m.GIB; self.now += 30; m.check_capacity(True)
        self.assertEqual(self.notification.call_count, 1)

    def test_disable_stops_owned_timer_and_service(self):
        with patch.object(m, 'run', return_value=Mock(returncode=0)) as command:
            m.control(False)
        self.assertFalse(m.config()['enabled'])
        calls = [c.args for c in command.call_args_list]
        self.assertIn(('systemctl', '--user', 'disable', '--now', m.TIMER), calls)
        self.assertIn(('systemctl', '--user', 'stop', m.SERVICE), calls)

    def test_status_does_not_send_notifications(self):
        with patch.object(m, 'run', return_value=Mock(returncode=0)):
            m.status()
        self.notification.assert_not_called()
        self.assertFalse((m.STATE / 'alerts.json').exists())

    def test_invalid_threshold_rejected_before_writing(self):
        cfg = dict(self.cfg, critical_nvme_gib=100)
        with self.assertRaises(ValueError):
            m.validate_config(cfg)
        self.assertEqual(m.config()['critical_nvme_gib'], 8)

    def test_monitor_identity_survives_private_mount_namespace(self):
        mount = dict(path='/', source='/dev/fixture', fstype='btrfs', token='namespace-1', readonly=True, super_readonly=False)
        with patch.object(m, 'mount_table', return_value=[mount]):
            first = REAL_DISK_STATUS()[0]
            mount['token'] = 'namespace-2'
            second = REAL_DISK_STATUS()[0]
        self.assertEqual(first['token'], second['token'])
        self.assertFalse(first['readonly'])


if __name__ == '__main__':
    unittest.main()
