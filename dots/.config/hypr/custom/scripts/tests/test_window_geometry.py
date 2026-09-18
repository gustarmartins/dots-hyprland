import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('geometry', Path(__file__).resolve().parents[1] / 'window-geometry.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)


class GeometryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name, filename in [('CONFIG', '.'), ('POSITIONS', 'positions.json'), ('GEO', 'enabled'), ('EXEMPTIONS', 'exemptions.txt')]:
            p = patch.object(g, name, self.root / filename)
            p.start()
            self.addCleanup(p.stop)
        self.mon = dict(id=1, x=1920, y=500, width=1920, height=1080, scale=1, reserved=[0, 30, 0, 10])
        self.client = dict(address='0xabc', pid=123, initialClass='app', **{'class':'app'}, title='Document', floating=False, monitor=1, workspace={'id':8})

    def test_missing_file_does_not_import_archive(self):
        (self.root / 'positions.json.old').write_text('{"app":{}}')
        self.assertEqual(g.positions(), {})
        self.assertFalse(g.POSITIONS.exists())

    def test_malformed_file_is_preserved(self):
        g.POSITIONS.write_text('{broken')
        with self.assertRaises(ValueError):
            g.positions()
        self.assertEqual(g.POSITIONS.read_text(), '{broken')

    def test_specific_title_precedes_app(self):
        self.assertEqual(g.lookup({'app': 1, 'app::Document': 2}, self.client), ('app::Document', 2))

    def test_geometry_clamps_on_actual_monitor(self):
        self.assertEqual(g.target_geometry(dict(w=4000,h=2000,x=-500,y=3000), self.mon), (1920,1040,1920,530))

    def test_scaled_rotated_monitor(self):
        mon = dict(self.mon, transform=1, scale=1.5, reserved=[0,0,0,0])
        self.assertEqual(g.usable(mon), (1920,500,720,1280))

    def test_fullscreen_is_not_eligible(self):
        self.assertFalse(g.eligible(dict(self.client, fullscreen=2)))
        self.assertFalse(g.eligible(dict(self.client, fullscreenClient=2)))

    def test_class_and_title_exemptions(self):
        g.EXEMPTIONS.write_text('different\ntitle:^Doc\n')
        self.assertTrue(g.exempt(self.client))
        g.EXEMPTIONS.write_text('ap\n')
        self.assertFalse(g.exempt(self.client))

    def query(self, *args, **kwargs):
        return {'clients':[self.client], 'monitors':[self.mon], 'activeworkspace':{'id':8}, 'activewindow':dict(self.client, size=[800,600], at=[2020,600])}[args[0]]

    def test_live_save_visible_without_reload(self):
        controller = g.Controller(self.root)
        g.GEO.touch()
        with patch.object(g, 'hypr', side_effect=self.query), patch.object(g, 'notify'), patch.object(g, 'dispatch') as dispatch:
            g.save('app')
            controller.event('openwindow>>abc,8,app,Document')
            controller.apply('0xabc')
            self.assertEqual(dispatch.call_args_list[-1].kwargs, dict(x=2020,y=600,relative=False))
            g.save('app')
            self.assertEqual(g.positions(), {})

    def test_master_off_does_not_tile_preexisting_float_or_reused_address(self):
        controller = g.Controller(self.root)
        with patch.object(g, 'hypr', side_effect=self.query), patch.object(g, 'dispatch') as dispatch:
            controller.command('toggle-master')
            self.assertEqual(controller.owned, {'0xabc':[123,'app']})
            self.client.update(floating=True, pid=456)
            controller.command('toggle-master')
            self.assertEqual(dispatch.call_count, 1)
        self.client['floating'] = True
        with patch.object(g, 'hypr', side_effect=self.query), patch.object(g, 'dispatch') as dispatch:
            controller.command('toggle-master')
            controller.command('toggle-master')
            dispatch.assert_not_called()

    def test_late_title_refines_once_and_never_falls_back(self):
        controller = g.Controller(self.root)
        g.GEO.touch()
        g.POSITIONS.write_text(json.dumps({'app':dict(w=800,h=600,x=0,y=30),'app::Document':dict(w=900,h=650,x=20,y=40)}))
        controller.event('openwindow>>abc,8,app,Starting')
        with patch.object(g, 'hypr', side_effect=self.query), patch.object(g, 'dispatch') as dispatch:
            self.client['title'] = 'Starting'
            controller.apply('0xabc')
            self.client['title'] = 'Document'
            controller.apply('0xabc')
            count = dispatch.call_count
            controller.apply('0xabc')
            self.client['title'] = 'Other'
            controller.apply('0xabc')
            self.assertEqual(dispatch.call_count, count)


if __name__ == '__main__':
    unittest.main()
