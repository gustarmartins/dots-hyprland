#!/usr/bin/env python3
"""Isolated QML test exercising real AndroidQuickToggleButton + HoldToConfirmOverlay."""
from pathlib import Path
import os, shutil, subprocess, tempfile

repo = Path(__file__).resolve().parents[1]
src_ii = repo / 'dots/.config/quickshell/ii'

with tempfile.TemporaryDirectory(prefix='danger-tiles-hold-test-') as tmp:
    root = Path(tmp)
    imports = root / 'imports'
    services = imports / 'qs/services'
    common = imports / 'qs/modules/common'
    functions = common / 'functions'
    widgets = common / 'widgets'
    models = common / 'models/quickToggles'
    tile_dir = root / 'androidStyle'
    for d in [services, common, functions, widgets, models, tile_dir]:
        d.mkdir(parents=True, exist_ok=True)

    (services / 'qmldir').write_text('module qs.services\nsingleton Translation 1.0 Translation.qml\n')
    (services / 'Translation.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function tr(t) { return t; } }\n')

    (common / 'qmldir').write_text('module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\nsingleton Config 1.0 Config.qml\n')
    (common / 'Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var m3colors: ({
        m3error: "#f2b8b5", m3onError: "#601410",
        m3errorContainer: "#8c1d18", m3onErrorContainer: "#f9dedc",
        m3primary: "#a8c7fa", m3primaryContainer: "#0842a0", m3onPrimaryContainer: "#d3e3fd",
        m3surfaceContainerHigh: "#222222", m3surfaceContainerHighest: "#333333",
        m3onSurface: "#ffffff", m3onSurfaceVariant: "#cccccc", m3outlineVariant: "#444444"
    })
    property var colors: ({
        colLayer1Hover: "#2a2a2a", colLayer1Active: "#353535",
        colLayer2Hover: "#2a2a2a", colLayer2Active: "#353535",
        colPrimary: "#a8c7fa", colPrimaryHover: "#b8d2fb", colPrimaryActive: "#c8ddfc",
        colSecondary: "#c2c7cf"
    })
    property var rounding: ({ small: 8, normal: 12 })
    property var animation: ({
        clickBounce: ({ numberAnimation: Qt.createComponent("AnimNum.qml") }),
        elementMoveFast: ({ numberAnimation: Qt.createComponent("AnimNum.qml"), colorAnimation: Qt.createComponent("AnimCol.qml") })
    })
}
''')
    (common / 'AnimNum.qml').write_text('import QtQuick\nNumberAnimation { duration: 10 }\n')
    (common / 'AnimCol.qml').write_text('import QtQuick\nColorAnimation { duration: 10 }\n')
    (common / 'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property var options: ({ sidebar: ({ quickToggles: ({ android: ({ toggles: [] }) }) }) }) }
''')

    (functions / 'qmldir').write_text('module qs.modules.common.functions\nsingleton ColorUtils 1.0 ColorUtils.qml\n')
    (functions / 'ColorUtils.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    function transparentize(c, amount) {
        const col = Qt.color(c);
        return Qt.rgba(col.r, col.g, col.b, Math.max(0, Math.min(1, 1 - amount)));
    }
    function mix(a, b, ratio) { return a; }
}
''')

    (widgets / 'qmldir').write_text(
        'module qs.modules.common.widgets\n'
        'GroupButton 1.0 GroupButton.qml\n'
        'HoldToConfirmOverlay 1.0 HoldToConfirmOverlay.qml\n'
        'StyledText 1.0 StyledText.qml\n'
        'MaterialSymbol 1.0 MaterialSymbol.qml\n'
        'StyledToolTip 1.0 StyledToolTip.qml\n'
        'RippleButton 1.0 RippleButton.qml\n'
    )
    (widgets / 'StyledText.qml').write_text('import QtQuick\nText {}\n')
    (widgets / 'MaterialSymbol.qml').write_text('import QtQuick\nText { property real iconSize: 20; property int fill: 0 }\n')
    (widgets / 'StyledToolTip.qml').write_text('import QtQuick\nItem { property bool extraVisibleCondition: false; property string text: "" }\n')
    (widgets / 'RippleButton.qml').write_text('import QtQuick\nItem { property string buttonText: ""; signal clicked() }\n')
    shutil.copy2(src_ii / 'modules/common/widgets/GroupButton.qml', widgets / 'GroupButton.qml')
    shutil.copy2(src_ii / 'modules/common/widgets/HoldToConfirmOverlay.qml', widgets / 'HoldToConfirmOverlay.qml')

    (models / 'qmldir').write_text('module qs.modules.common.models.quickToggles\nQuickToggleModel 1.0 QuickToggleModel.qml\n')
    shutil.copy2(src_ii / 'modules/common/models/quickToggles/QuickToggleModel.qml', models / 'QuickToggleModel.qml')

    shutil.copy2(src_ii / 'modules/ii/sidebarRight/quickToggles/TileGrid.js', root / 'TileGrid.js')
    shutil.copy2(
        src_ii / 'modules/ii/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml',
        tile_dir / 'AndroidQuickToggleButton.qml',
    )

    (root / 'tst_danger_tiles.qml').write_text('''import QtQuick
import QtTest
import qs.modules.common.models.quickToggles
import "androidStyle"

Item {
    width: 600; height: 400

    // 1. GPU Memory pattern: safe left-click report, dangerous right-click VRAM evict
    AndroidQuickToggleButton {
        id: gpuTile
        x: 20; y: 20
        buttonIndex: 0
        buttonData: ({ type: "gpuMemory" })
        expandedSize: true
        baseCellWidth: 90; baseCellHeight: 62; cellSpacing: 8; cellSize: 2
        property int reports: 0
        property int evicts: 0
        toggleModel: QuickToggleModel {
            name: "GPU Memory"
            icon: "memory_alt"
            statusText: "2.1 / 8.0G"
            altActionOnRightClick: true
            altActionRequiresHold: true
            altHoldDurationMs: 240
            altHoldLabel: "Evict VRAM"
            mainAction: () => gpuTile.reports++
            altAction: () => gpuTile.evicts++
        }
    }

    // 2. Triple Buffer pattern: hold to enable when off, instant click to disable when on
    AndroidQuickToggleButton {
        id: tbTile
        x: 240; y: 20
        buttonIndex: 1
        buttonData: ({ type: "tripleBuffer" })
        expandedSize: true
        baseCellWidth: 90; baseCellHeight: 62; cellSpacing: 8; cellSize: 2
        property int enables: 0
        property int disables: 0
        toggleModel: QuickToggleModel {
            id: tbModel
            name: "Triple buffer"
            icon: "filter_3"
            toggled: false
            statusText: toggled ? "Enabled" : "Off"
            mainActionRequiresHold: !toggled
            mainHoldDurationMs: 240
            mainHoldLabel: "Enable 3x buffer"
            mainAction: () => {
                if (tbModel.toggled) { tbModel.toggled = false; tbTile.disables++; }
                else { tbModel.toggled = true; tbTile.enables++; }
            }
        }
    }

    // 3. Compact 1x1 danger tile (Drop Caches pattern)
    AndroidQuickToggleButton {
        id: cacheTile
        x: 20; y: 120
        buttonIndex: 2
        buttonData: ({ type: "dropCaches" })
        expandedSize: false
        baseCellWidth: 80; baseCellHeight: 64; cellSpacing: 8; cellSize: 1
        property int drops: 0
        toggleModel: QuickToggleModel {
            name: "Drop Caches"
            icon: "delete_sweep"
            hasStatusText: false
            mainActionRequiresHold: true
            mainHoldDurationMs: 240
            mainHoldLabel: "Drop caches"
            mainAction: () => cacheTile.drops++
        }
    }

    TestCase {
        name: "AndroidDangerTilesHold"; when: windowShown

        function test_gpu_memory_left_safe_right_hold() {
            const hold = findChild(gpuTile, "tileHoldOverlay-gpuMemory");
            verify(hold !== null);

            // Safe left-click report runs immediately
            mouseClick(gpuTile, 60, 30, Qt.LeftButton);
            compare(gpuTile.reports, 1);
            compare(gpuTile.evicts, 0);

            // Accidental right-click does NOT evict VRAM
            mouseClick(gpuTile, 60, 30, Qt.RightButton);
            compare(gpuTile.evicts, 0);
            verify(hold.showEarlyHint);

            // Right-click hold to 100% executes evict once
            mousePress(gpuTile, 60, 30, Qt.RightButton);
            tryCompare(gpuTile, "evicts", 1, 900);
            mouseRelease(gpuTile, 60, 30, Qt.RightButton);
            compare(gpuTile.evicts, 1);
        }

        function test_triple_buffer_hold_enable_instant_disable() {
            // Accidental click when off does NOT enable
            mouseClick(tbTile, 60, 30, Qt.LeftButton);
            compare(tbTile.enables, 0);
            verify(!tbTile.toggled);

            // Hold left-click enables
            mousePress(tbTile, 60, 30, Qt.LeftButton);
            tryCompare(tbTile, "enables", 1, 900);
            verify(tbTile.toggled);
            mouseRelease(tbTile, 60, 30, Qt.LeftButton);
            // Trailing release after hold must NOT immediately disable it!
            compare(tbTile.disables, 0);
            verify(tbTile.toggled);

            // Wait for progress reset, then single click immediately disables
            wait(260);
            mouseClick(tbTile, 60, 30, Qt.LeftButton);
            compare(tbTile.disables, 1);
            verify(!tbTile.toggled);
        }

        function test_compact_tile_hold_and_edit_mode_cancels() {
            const hold = findChild(cacheTile, "tileHoldOverlay-dropCaches");
            mouseClick(cacheTile, 40, 32, Qt.LeftButton);
            compare(cacheTile.drops, 0);

            // Entering editMode mid-hold cancels safely
            mousePress(cacheTile, 40, 32, Qt.LeftButton);
            wait(80);
            verify(hold.holding);
            cacheTile.editMode = true;
            verify(!hold.holding);
            mouseRelease(cacheTile, 40, 32, Qt.LeftButton);
            cacheTile.editMode = false;
            compare(cacheTile.drops, 0);

            // Full hold fires once
            mousePress(cacheTile, 40, 32, Qt.LeftButton);
            tryCompare(cacheTile, "drops", 1, 900);
            mouseRelease(cacheTile, 40, 32, Qt.LeftButton);
            compare(cacheTile.drops, 1);
        }
    }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QT_FORCE_STDERR_LOGGING='1', QT_LOGGING_TO_CONSOLE='1')
    result = subprocess.run(
        ['/usr/lib/qt6/bin/qmltestrunner', '-input', str(root), '-import', str(imports),
         '-o', str(root / 'result.txt') + ',txt'],
        env=env, timeout=25,
    )
    print((root / 'result.txt').read_text() if (root / 'result.txt').exists() else 'No Qt test report')
    result.check_returncode()
