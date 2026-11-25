import importlib.machinery, importlib.util, math, pathlib, unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader(
    'eden_boost',
    str(pathlib.Path(__file__).resolve().parents[1] / 'dots/.local/bin/eden-audio-boost'),
)
spec = importlib.util.spec_from_loader(loader.name, loader)
b = importlib.util.module_from_spec(spec)
loader.exec_module(b)


class BoostTests(unittest.TestCase):
    def test_graph_is_linear_twelve_db_and_preserves_channels(self):
        g = b.graph(12)
        node = g['nodes'][0]
        self.assertEqual(node['name'], 'app_boost_gain')
        self.assertAlmostEqual(node['control']['Mult'], 3.9810717055)
        self.assertEqual(g['n_inputs'], 2)
        self.assertEqual(g['n_outputs'], 2)
        self.assertNotIn('volume', g)

    def test_infra_binaries_and_filter_nodes_are_excluded(self):
        s = {'index': 1, 'properties': {'application.name': 'EasyEffects', 'application.process.id': '42', 'object.serial': '55'}}
        with patch.object(b, '_proc_info', return_value=('easyeffects', 100, 1)):
            self.assertIsNone(b.stream_identity(s, {}, {'55': {'node.name': 'easyeffects_sink'}}))
        s2 = {'index': 2, 'properties': {'object.serial': '56'}}
        self.assertIsNone(b.stream_identity(s2, {}, {'56': {'node.name': 'effect_output.spatial-surround'}}))

    def test_native_stream_uses_verified_client_process(self):
        s = {'index': 1, 'corked': False, 'properties': {'object.serial': '55', 'application.name': 'PipeWire ALSA [osu!]'}}
        with patch.object(b, '_proc_info', return_value=('osu!', 987, 1)):
            r = b.stream_identity(s, {9: {'pipewire.sec.pid': 42}}, {'55': {'client.id': 9, '_state': 'running'}})
        self.assertEqual(r['pid'], 42)
        self.assertEqual(r['start'], 987)
        self.assertEqual(r['app_key'], 'exe:osu!')
        self.assertEqual(r['app_name'], 'osu!')
        self.assertTrue(r['running'])

    def test_missing_pid_is_not_name_matched(self):
        self.assertIsNone(b.stream_identity({'index': 1, 'properties': {'application.name': 'Firefox'}}, {}, {}))

    def test_resolve_target_prefers_focused_window_then_running_stream(self):
        s_ff = {'index': 1, 'corked': True, 'properties': {'application.process.id': '101', 'application.name': 'Firefox', 'object.serial': '10'}}
        s_osu = {'index': 2, 'corked': False, 'properties': {'application.process.id': '202', 'application.name': 'PipeWire ALSA [osu!]', 'object.serial': '20'}}
        nodes = {
            '10': {'client.id': 1, '_state': 'idle', '_params': {}},
            '20': {'client.id': 2, '_state': 'running', '_params': {}},
        }
        inv = (1234, [s_ff, s_osu], [], {}, nodes)

        def fake_proc(pid):
            return {101: ('firefox', 10, 1), 100: ('firefox', 9, 1), 202: ('osu!', 20, 1), 300: ('kitty', 30, 1)}.get(pid)

        with patch.object(b, '_proc_info', side_effect=fake_proc):
            # Focused Firefox matches Firefox even if osu! is running in background
            t = b.resolve_target(inv, focused={'pid': 100, 'exe': 'firefox', 'class': 'firefox', 'initialClass': 'firefox'})
            self.assertEqual(t['key'], 'exe:firefox')
            self.assertEqual(t['name'], 'Firefox')
            self.assertEqual(t['reason'], 'focused')

            # Focused terminal with no audio falls back to actively playing osu!
            t2 = b.resolve_target(inv, focused={'pid': 300, 'exe': 'kitty', 'class': 'kitty', 'initialClass': 'kitty'})
            self.assertEqual(t2['key'], 'exe:osu!')
            self.assertEqual(t2['name'], 'osu!')
            self.assertEqual(t2['reason'], 'playing')

            # Explicit preferred_key overrides focus/running
            t3 = b.resolve_target(inv, focused={'pid': 300, 'exe': 'kitty', 'class': 'kitty'}, preferred_key='exe:firefox')
            self.assertEqual(t3['key'], 'exe:firefox')
            self.assertEqual(t3['reason'], 'selected')

    def test_read_gain_supports_current_and_legacy_keys(self):
        self.assertAlmostEqual(b._read_gain({'app_boost_gain:Mult': 3.98}), 3.98)
        self.assertAlmostEqual(b._read_gain({'eden_boost_gain:Mult': 3.98}), 3.98)
        self.assertEqual(b._read_gain({}), -1)


if __name__ == '__main__':
    unittest.main()
