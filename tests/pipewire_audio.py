#!/usr/bin/env python3
"""Unit and offscreen QML tests for PipeWire & kernel audio telemetry and UI."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
HELPER_PATH = REPO / 'dots/.local/bin/pipewire-audio-status'
spec = importlib.util.spec_from_loader(
    'pipewire_audio_status',
    importlib.machinery.SourceFileLoader('pipewire_audio_status', str(HELPER_PATH)),
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='pw-audio-helper-')
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_metadata_and_alsa_parsing(self):
        meta = helper.parse_pw_metadata(
            "Found \"settings\" metadata 32\n"
            "update: id:0 key:'clock.rate' value:'44100' type:''\n"
            "update: id:0 key:'clock.quantum' value:'1024' type:''\n"
            "update: id:0 key:'clock.force-quantum' value:'128' type:''\n"
            "update: id:0 key:'clock.force-rate' value:'0' type:''\n"
            "update: id:0 key:'clock.allowed-rates' value:'[ 44100, 48000, 96000, 192000 ]' type:''\n"
        )
        self.assertEqual(meta['clock.rate'], '44100')
        self.assertEqual(meta['clock.force-quantum'], '128')
        self.assertEqual(helper.parse_allowed_rates(meta['clock.allowed-rates']), [44100, 48000, 96000, 192000])

        card1 = self.root / 'asound/card1'
        (card1 / 'pcm0p/sub0').mkdir(parents=True)
        (card1 / 'pcm0p/sub0/hw_params').write_text(
            'access: MMAP_INTERLEAVED\nformat: S32_LE\nchannels: 2\nrate: 48000 (48000/1)\nperiod_size: 128\nbuffer_size: 8192\n'
        )
        (card1 / 'codec#0').write_text(
            'Codec: Realtek ALC892\nDefault PCM:\n    rates [0x5f0]: 44100 48000 96000 192000\n    bits [0xe]: 16 20 24\n'
        )
        card0 = self.root / 'asound/card0'
        card0.mkdir(parents=True)
        (card0 / 'eld#0.0').write_text(
            'monitor_present\t1\neld_valid\t1\nmonitor_name\tARZOPA\nconnection_type\tHDMI\n'
            'sad0_coding_type\t[0x1] LPCM\nsad0_channels\t2\n'
        )
        hw = helper.alsa_hardware_info(self.root / 'asound')
        self.assertEqual(hw['codec'], 'Realtek ALC892')
        self.assertTrue(hw['hwActive'])
        self.assertEqual(hw['hwFormat'], 'S32_LE')
        self.assertEqual(hw['hwRate'], 48000)
        self.assertEqual(hw['hwPeriod'], 128)
        self.assertEqual(hw['maxBits'], 24)
        self.assertFalse(hw['hdmiDolby'])

    def test_collect_status_builds_signal_chain_and_latency(self):
        meta_out = (
            "update: id:0 key:'clock.rate' value:'48000' type:''\n"
            "update: id:0 key:'clock.quantum' value:'1024' type:''\n"
            "update: id:0 key:'clock.force-quantum' value:'128' type:''\n"
            "update: id:0 key:'clock.force-rate' value:'0' type:''\n"
            "update: id:0 key:'clock.allowed-rates' value:'[ 44100, 48000, 96000, 192000 ]' type:''\n"
        )
        dump_out = json.dumps([
            {'id': 1, 'type': 'PipeWire:Interface:Node', 'info': {'state': 'running', 'props': {'node.name': 'easyeffects_sink', 'media.class': 'Audio/Sink'}}},
            {'id': 2, 'type': 'PipeWire:Interface:Node', 'info': {'state': 'running', 'props': {'node.name': 'effect_input.spatial-surround', 'media.class': 'Audio/Sink'}}},
            {'id': 3, 'type': 'PipeWire:Interface:Node', 'info': {'state': 'running', 'props': {'node.name': 'alsa_output.pci-0000_0b_00.3.analog-stereo', 'media.class': 'Audio/Sink', 'node.description': 'ALC892'}}},
            {'id': 4, 'type': 'PipeWire:Interface:Node', 'info': {'state': 'running', 'props': {'node.name': 'mpv', 'application.name': 'mpv', 'media.class': 'Stream/Output/Audio'}}},
        ])
        fake_hw = {
            'codec': 'Realtek ALC892', 'activePcm': {'format': 'S32_LE', 'rate': 48000, 'periodSize': 128},
            'hwActive': True, 'hwFormat': 'S32_LE', 'hwRate': 48000, 'hwChannels': 2, 'hwPeriod': 128,
            'maxBits': 24, 'supportedRates': [44100, 48000, 192000], 'supportedBits': [16, 24],
            'rateRange': '44.1k–192k', 'hdmiDolby': False, 'hdmiCodecs': [], 'hdmiOutputs': [], 'hdmiSummary': 'HDMI LPCM only',
        }
        fake_kern = {
            'release': '7.3.5-zen1-1-zen', 'shortRelease': '7.3.5-zen', 'preempt': 'PREEMPT_FULL', 'cstatePinned': True,
            'pipewire': {'cls': 'FF', 'prio': 88, 'thread': 'data-loop.0', 'label': 'FIFO 88', 'tone': 'good', 'rlimitRtprio': '90'},
            'easyeffects': {'cls': 'FF', 'prio': 83, 'label': 'FIFO 83'},
            'pipewirePulse': {'cls': 'FF', 'prio': 83, 'label': 'FIFO 83'},
        }
        with patch.object(helper, 'run_cmd', side_effect=[(0, meta_out, ''), (0, dump_out, '')]), \
             patch.object(helper, 'alsa_hardware_info', return_value=fake_hw), \
             patch.object(helper, 'kernel_info', return_value=fake_kern), \
             patch.object(helper, 'read_spatial_settings', return_value={'enabled': True, 'automatic': True, 'profile': 'sofa-kemar', 'passthrough': False}):
            st = helper.collect_status()
        self.assertTrue(st['available'])
        self.assertEqual(st['overall'], 'good')
        self.assertAlmostEqual(st['clock']['latencyMs'], 2.67, places=2)
        self.assertEqual([c['id'] for c in st['chain']], ['apps', 'spatial', 'easyeffects', 'dac'])
        self.assertEqual(st['spatial']['badge'], 'SOFA 3D')


class StripUiTests(unittest.TestCase):
    def test_strip_qml_offscreen(self):
        with tempfile.TemporaryDirectory(prefix='pw-audio-ui-') as tmp:
            root = Path(tmp)
            imports = root / 'imports'
            for name, qmldir in {
                'qs/services': 'module qs.services\nsingleton PipeWireAudio 1.0 PipeWireAudio.qml\nsingleton EasyEffects 1.0 EasyEffects.qml\n',
                'qs/modules/common': 'module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n',
                'qs/modules/common/widgets': 'module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\nMaterialSymbol 1.0 MaterialSymbol.qml\n',
            }.items():
                p = imports / name
                p.mkdir(parents=True)
                (p / 'qmldir').write_text(qmldir)

            (imports / 'qs/services/EasyEffects.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { property string preset: "disco-funk-atmos" }\n'
            )
            (imports / 'qs/services/PipeWireAudio.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool enabled: true
    property bool expandedByDefault: false
    property int watchers: 0
    property bool ready: true
    property bool available: true
    property bool busy: false
    property bool acting: false
    property string error: ""
    property string lastAction: ""
    property var data: ({
        available: true, overall: "good",
        clock: { rate: 48000, rateLabel: "48 kHz", rateShort: "48k", quantum: 1024, forceQuantum: 0, forceRate: 0, latencyMs: 21.33, mode: "Adaptive" },
        kernel: { shortRelease: "7.3.5-zen", preempt: "PREEMPT_FULL", cstatePinned: true, pipewire: { label: "FIFO 88", tone: "good" }, easyeffects: { label: "FIFO 83" } },
        hardware: { codec: "Realtek ALC892", active: true, format: "S32_LE", maxBits: 24, rateRange: "44.1k–192k", hdmiSummary: "HDMI LPCM only" },
        spatial: { enabled: true, active: true, state: "active", badge: "Atmos 7.1", tone: "good", passthrough: false },
        chain: [{ id: "apps", label: "mpv", tone: "info" }, { id: "spatial", label: "Atmos 7.1", tone: "good" }, { id: "easyeffects", label: "EasyEffects", tone: "good" }, { id: "dac", label: "ALC892", tone: "good" }]
    })
    function setQuantum(q) { lastAction = "q:" + q; let next = JSON.parse(JSON.stringify(data)); next.clock.forceQuantum = q; data = next; }
    function setRate(r) { lastAction = "r:" + r; let next = JSON.parse(JSON.stringify(data)); next.clock.forceRate = r; data = next; }
    function resetClock() { lastAction = "reset"; let next = JSON.parse(JSON.stringify(data)); next.clock.forceQuantum = 0; next.clock.forceRate = 0; data = next; }
    function refresh() { lastAction = "refresh"; }
}
''')
            (imports / 'qs/modules/common/Appearance.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { property var m3colors: ({'
                'm3primary:"#4fd8eb",m3onPrimary:"#00363d",m3primaryContainer:"#004f58",m3onPrimaryContainer:"#97f0ff",'
                'm3secondary:"#b1cbd0",m3onSecondary:"#1c3438",m3secondaryContainer:"#334b4f",m3onSecondaryContainer:"#cde7ec",'
                'm3tertiary:"#bac6ea",m3onTertiary:"#24304d",m3tertiaryContainer:"#3b4664",m3onTertiaryContainer:"#dae2ff",'
                'm3error:"#ffb4ab",m3onError:"#690005",m3errorContainer:"#93000a",m3onErrorContainer:"#ffdad6",'
                'm3surfaceContainer:"#1d2021",m3surfaceContainerHigh:"#272a2b",m3surfaceContainerHighest:"#323536",'
                'm3onSurface:"#e1e3e4",m3onSurfaceVariant:"#bfc8ca",m3outline:"#899294",m3outlineVariant:"#3f484a"'
                '}) }\n'
            )
            (imports / 'qs/modules/common/widgets/StyledText.qml').write_text('import QtQuick\nText {}\n')
            (imports / 'qs/modules/common/widgets/MaterialSymbol.qml').write_text(
                'import QtQuick\nText { property real iconSize: 16; font.pixelSize: iconSize }\n'
            )
            src = REPO / 'dots/.config/quickshell/ii/modules/ii/sidebarRight/PipeWireAudioStrip.qml'
            shutil.copy2(src, root / 'PipeWireAudioStrip.qml')
            (root / 'tst_pipewire_strip.qml').write_text('''import QtQuick
import QtTest
import qs.services
Item {
    width: 620; height: 420
    PipeWireAudioStrip { id: strip; width: 580; x: 20; y: 20 }
    TestCase {
        name: "PipeWireAudioStrip"; when: windowShown
        function test_compact_expand_and_clock_actions() {
            compare(PipeWireAudio.watchers, 1);
            verify(strip.height <= 36, "Collapsed strip must remain ultra-compact: " + strip.height);
            let header = findChild(strip, "pipewireAudioHeader");
            verify(header !== null);
            mouseClick(header);
            tryVerify(() => strip.expanded === true, 500);
            wait(300);
            verify(strip.height > 150, "Expanded strip height too small: " + strip.height);
            let q128 = findChild(strip, "pipewireQuantum-128");
            verify(q128 !== null);
            mouseClick(q128);
            compare(PipeWireAudio.lastAction, "q:128");
            let r96 = findChild(strip, "pipewireRate-96000");
            verify(r96 !== null);
            mouseClick(r96);
            compare(PipeWireAudio.lastAction, "r:96000");
            let resetBtn = findChild(strip, "pipewireClockReset");
            verify(resetBtn !== null && resetBtn.visible);
            mouseClick(resetBtn);
            compare(PipeWireAudio.lastAction, "reset");
            strip.visible = false;
            compare(PipeWireAudio.watchers, 0);
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            res = subprocess.run(
                ['/usr/lib/qt6/bin/qmltestrunner', '-input', str(root), '-import', str(imports), '-o', str(root / 'results.txt') + ',txt'],
                env=env, capture_output=True, text=True, timeout=25,
            )
            report = (root / 'results.txt').read_text() if (root / 'results.txt').exists() else res.stderr
            if res.returncode:
                self.fail(f'qmltestrunner failed:\n{report}\n{res.stderr}')
            self.assertNotIn('TypeError', report)
            self.assertNotIn('ReferenceError', report)
            self.assertNotIn('Binding loop', report)


if __name__ == '__main__':
    unittest.main()
