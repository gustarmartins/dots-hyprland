#!/usr/bin/env python3
"""Private fixtures only: no real browser profiles, D-Bus or compositor writes."""
import argparse
import importlib.machinery
import importlib.util
import json
import io
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
COMMAND = ROOT / 'dots/.local/bin/fontctl'
loader = importlib.machinery.SourceFileLoader('fontctl_browser', str(COMMAND.with_name('fontctl-browser')))
spec = importlib.util.spec_from_loader(loader.name, loader)
browser = importlib.util.module_from_spec(spec)
loader.exec_module(browser)


class BrowserFonts(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='fontctl-test-')
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        self.env = patch.dict(os.environ, {'HOME': str(self.home), 'XDG_CONFIG_HOME': str(self.home / '.config')})
        self.env.start()
        self.addCleanup(self.env.stop)

    def write(self, name, text):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_discover_profiles_ini_absolute_relative_xdg_and_secondary(self):
        external = self.home / 'external profile'
        external.mkdir()
        relative = self.home / '.mozilla/firefox/relative'
        relative.mkdir(parents=True)
        self.write('.mozilla/firefox/profiles.ini', '[Profile0]\nPath=relative\nIsRelative=1\n[Profile1]\nIsRelative=0\nPath=' + str(external))
        xdg = self.write('.config/mozilla/firefox/second/prefs.js', '').parent
        sandbox = self.write('.var/app/org.mozilla.firefox/.mozilla/firefox/third/user.js', '').parent
        backup = self.write('.mozilla/firefox/backups/date/profile/user.js', '').parent
        profiles = browser.firefox_profiles(self.home)
        self.assertEqual(set(profiles), {external, relative, xdg, sandbox})
        self.assertNotIn(backup, profiles)

    def test_userjs_preserves_unrelated_and_replaces_duplicate_overrides(self):
        values = browser.firefox_values('Fira Sans', 'Hack', 'Noto Serif', 'rgb')
        source = '// personal comment\nuser_pref("keep.me", 42);\nuser_pref("browser.display.use_document_fonts", 0);\nuser_pref("font.name.sans-serif.x-western", "SF Pro");\n'
        result = browser.merge_userjs(source, values)
        self.assertIn('// personal comment\nuser_pref("keep.me", 42);', result)
        self.assertNotIn('SF Pro', result)
        self.assertEqual(result.count('browser.display.use_document_fonts'), 1)
        self.assertIn('"browser.display.use_document_fonts", 1', result)
        self.assertEqual(browser.merge_userjs(result, values), result)

    def test_rendering_only_preserves_managed_fonts_and_website_choice(self):
        original = browser.merge_userjs('', browser.firefox_values('Fira Sans', 'Hack', 'Noto Serif', 'rgb'))
        result = browser.merge_userjs(original, browser.firefox_values('Other', 'Other', 'Other', 'none', True))
        self.assertIn('Fira Sans', result)
        self.assertIn('Hack', result)
        self.assertIn('"browser.display.use_document_fonts", 1', result)
        self.assertIn('"gfx.webrender.enable-subpixel-aa", false', result)
        self.assertNotIn('Other', result)

    def test_chromium_preserves_data_sizes_zoom_scripts_and_special_families(self):
        original = {'account_info': [{'name': 'fixture'}], 'partition': {'default_zoom_level': 1.2},
                    'webkit': {'webprefs': {'default_font_size': 18, 'default_fixed_font_size': 15,
                     'fonts': {'sansserif': {'Jpan': 'Noto Sans CJK JP'},
                               'math': {'Zyyy': 'STIX Two Math'}, 'cursive': {'Zyyy': 'Roboto'}}}}}
        result = browser.merge_chromium(original, 'Fira Sans', 'Hack', 'Noto Serif')
        self.assertEqual(result['account_info'], [{'name': 'fixture'}])
        self.assertEqual(result['partition']['default_zoom_level'], 1.2)
        prefs = result['webkit']['webprefs']
        self.assertEqual(prefs['default_font_size'], 18)
        self.assertEqual(prefs['default_fixed_font_size'], 15)
        self.assertEqual(prefs['fonts']['sansserif'], {'Jpan': 'Noto Sans CJK JP', 'Zyyy': 'Fira Sans', 'Latn': 'Fira Sans'})
        self.assertEqual(prefs['fonts']['math']['Zyyy'], 'STIX Two Math')
        self.assertNotIn('Zyyy', prefs['fonts']['cursive'])

    def test_running_chromium_is_never_written(self):
        path = self.write('.config/chromium/Default/Preferences', '{"keep": true}')
        (path.parent.parent / 'SingletonLock').symlink_to(f'{socket.gethostname()}-{os.getpid()}')
        args = argparse.Namespace(ui='Fira Sans', mono='Hack', serif='Noto Serif', subpixel='rgb', rendering_only=False)
        self.assertEqual(browser.apply(self.home, args), 1)
        self.assertEqual(path.read_text(), '{"keep": true}')

    def test_backups_and_firefox_prefs_not_touched(self):
        prefs = self.write('.mozilla/firefox/profile/prefs.js', 'user_pref("font.name.sans-serif.x-western", "SF Pro");\n')
        userjs = self.write('.mozilla/firefox/profile/user.js', '// original\n')
        args = argparse.Namespace(ui='Fira Sans', mono='Hack', serif='Noto Serif', subpixel='rgb', rendering_only=False)
        self.assertEqual(browser.apply(self.home, args), 0)
        self.assertIn('SF Pro', prefs.read_text())
        self.assertIn('Fira Sans', userjs.read_text())
        backups = list((self.home / '.config/fontctl/backups').glob('*/**/user.js'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), '// original\n')
        self.assertEqual(browser.apply(self.home, args), 0)
        self.assertEqual(len(list((self.home / '.config/fontctl/backups').glob('*/**/user.js'))), 1)

    def test_busy_during_atomic_write_preserves_original(self):
        path = self.write('Preferences', '{"original": 1}')
        with self.assertRaises(RuntimeError):
            browser.write_backed_up(path, '{}', self.home / 'backup', guard=lambda: True)
        self.assertEqual(path.read_text(), '{"original": 1}')

    def test_firefox_saved_defaults_are_not_reported_as_pending(self):
        values = browser.firefox_values('Fira Sans', 'Hack', 'Noto Serif', 'rgb')
        self.write('.mozilla/firefox/profile/user.js', browser.merge_userjs('', values))
        saved = {k: v for k, v in values.items() if browser.DEFAULT_PREFS.get(k) != v}
        self.write('.mozilla/firefox/profile/prefs.js', browser.merge_userjs('', saved))
        output = io.StringIO()
        with redirect_stdout(output):
            browser.status(self.home)
        self.assertIn('last saved preferences agree', output.getvalue())
        self.assertNotIn('startup differs', output.getvalue())

    def test_gtk_missing_keys_and_sections_are_created_and_unrelated_retained(self):
        self.write('.config/gtk-3.0/settings.ini', '[Settings]\ngtk-theme-name=Keep\n[Other]\nx=1\n')
        # Load functions only, with every path pointing to the disposable HOME.
        shell = COMMAND.read_text().rsplit('main "$@"', 1)[0]
        shell += '\nupdate_gtk3 "Fira Sans" 11 hintnone none ""\nupdate_gtk4 "Fira Sans" 11 hintfull rgb 98304\n'
        subprocess.run(['bash', '-c', shell], check=True, capture_output=True)
        gtk3 = (self.home / '.config/gtk-3.0/settings.ini').read_text()
        self.assertIn('gtk-theme-name=Keep', gtk3)
        self.assertIn('gtk-xft-hinting=0', gtk3)
        self.assertIn('gtk-xft-rgba=none', gtk3)
        self.assertIn('[Other]\nx=1', gtk3)
        gtk4 = (self.home / '.config/gtk-4.0/settings.ini').read_text()
        self.assertIn('gtk-xft-hintstyle=hintfull', gtk4)
        self.assertIn('gtk-xft-dpi=98304', gtk4)


if __name__ == '__main__':
    unittest.main()
