#!/usr/bin/env python3
"""Isolated press-and-hold + reset regression for Boost Current App widget and danger tiles."""
from pathlib import Path
import os, shutil, subprocess, tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='current-app-boost-test-') as tmp:
    root = Path(tmp)
    imports = root / 'imports'
    services = imports / 'qs/services'
    common = imports / 'qs/modules/common'
    functions = common / 'functions'
    widgets = common / 'widgets'
    for d in [services, common, functions, widgets]:
        d.mkdir(parents=True, exist_ok=True)

    (services / 'qmldir').write_text('module qs.services\nsingleton EdenAudioBoost 1.0 EdenAudioBoost.qml\nsingleton Translation 1.0 Translation.qml\n')
    (services / 'Translation.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function tr(t) { return t; } }\n')
    (services / 'EdenAudioBoost.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool enabled: true
    property bool active: false
    property bool busy: false
    property int streams: 1
    property real db: 12
    property string targetKey: "exe:firefox"
    property string targetName: "Firefox"
    property string targetReason: "focused"
    property string activeApp: ""
    property string error: ""
    property int boosts: 0
    property int resets: 0
    property string lastTarget: ""
    function boost(k) { boosts++; lastTarget = k || ""; activeApp = targetName; active = true; }
    function reset() { resets++; active = false; activeApp = ""; }
}
''')
    (common / 'qmldir').write_text('module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n')
    (common / 'Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var m3colors: ({
        m3error: "#f2b8b5",
        m3onError: "#601410",
        m3errorContainer: "#8c1d18",
        m3onErrorContainer: "#f9dedc",
        m3primary: "#a8c7fa",
        m3onPrimary: "#062e6f",
        m3surfaceContainerHigh: "#222222",
        m3onSurface: "#ffffff",
        m3onSurfaceVariant: "#cccccc",
        m3outlineVariant: "#444444"
    })
}
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
        'StyledText 1.0 StyledText.qml\n'
        'MaterialSymbol 1.0 MaterialSymbol.qml\n'
        'HoldToConfirmOverlay 1.0 HoldToConfirmOverlay.qml\n'
    )
    (widgets / 'StyledText.qml').write_text('import QtQuick\nText {}\n')
    (widgets / 'MaterialSymbol.qml').write_text('import QtQuick\nText { property real iconSize: 20; property int fill: 0 }\n')
    shutil.copy2(
        repo / 'dots/.config/quickshell/ii/modules/common/widgets/HoldToConfirmOverlay.qml',
        widgets / 'HoldToConfirmOverlay.qml',
    )
    shutil.copy2(
        repo / 'dots/.config/quickshell/ii/modules/ii/sidebarRight/EdenBoostWidget.qml',
        root / 'EdenBoostWidget.qml',
    )

    (root / 'tst_boost.qml').write_text('''import QtQuick
import QtTest
import qs.services
import qs.modules.common.widgets

Item {
    width: 500; height: 320
    EdenBoostWidget { id: widget; width: 460; holdDurationMs: 260 }

    // Standalone danger tile hold test (left safe, right hold, pointer-leave cancel)
    Rectangle {
        id: tileBox
        y: 120; width: 220; height: 64; radius: 18; color: "#222"
        property int leftFires: 0
        property int rightFires: 0
        HoldToConfirmOverlay {
            id: tileHold
            cornerRadius: 18
            durationMs: 260
            showIdleGuard: true
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property int activeBtn: Qt.NoButton
            onPressed: e => {
                activeBtn = e.button;
                if (e.button === Qt.RightButton)
                    tileHold.startHold(() => tileBox.rightFires++, 260, "Evict VRAM", "Hold right-click", "#f2b8b5");
            }
            onPositionChanged: if (tileHold.holding && !containsMouse) tileHold.cancelHold(false)
            onReleased: e => {
                const b = activeBtn; activeBtn = Qt.NoButton;
                if (tileHold.holding) { tileHold.cancelHold(containsMouse); return; }
                if (tileHold.consumeCompleted()) return;
                if (b === Qt.LeftButton && containsMouse) tileBox.leftFires++;
            }
            onCanceled: { activeBtn = Qt.NoButton; tileHold.cancelHold(false); }
        }
    }

    TestCase {
        name: "PressAndHoldBoostAndDanger"; when: windowShown

        function test_boost_widget_hold_and_instant_reset() {
            const overlay = findChild(widget, "currentAppBoostHold");
            const progressFill = findChild(widget, "holdProgressFill");
            verify(overlay !== null);
            verify(progressFill !== null);

            // Accidental quick click does NOT boost and shows early-release hint
            mouseClick(widget, 120, 28);
            compare(EdenAudioBoost.boosts, 0);
            verify(overlay.showEarlyHint);

            // Partial hold released early cancels and rewinds without firing
            mousePress(widget, 120, 28, Qt.LeftButton);
            wait(110);
            verify(overlay.holding);
            verify(overlay.progress > 0.1 && overlay.progress < 0.95);
            mouseRelease(widget, 120, 28, Qt.LeftButton);
            compare(EdenAudioBoost.boosts, 0);
            tryCompare(overlay, "progress", 0, 500);

            // Full press-and-hold completes and passes locked targetKey
            mousePress(widget, 120, 28, Qt.LeftButton);
            tryCompare(EdenAudioBoost, "boosts", 1, 900);
            compare(EdenAudioBoost.lastTarget, "exe:firefox");
            verify(EdenAudioBoost.active);
            mouseRelease(widget, 120, 28, Qt.LeftButton);
            // Release after completion must NOT accidentally reset!
            compare(EdenAudioBoost.resets, 0);
            verify(EdenAudioBoost.active);

            // Single click while active immediately resets!
            mouseClick(widget, 120, 28);
            compare(EdenAudioBoost.resets, 1);
            verify(!EdenAudioBoost.active);
        }

        function test_danger_tile_safe_left_click_and_right_hold() {
            // Safe left-click fires immediately
            mouseClick(tileBox, 60, 30, Qt.LeftButton);
            compare(tileBox.leftFires, 1);
            compare(tileBox.rightFires, 0);

            // Accidental quick right-click does NOT fire danger action
            mouseClick(tileBox, 60, 30, Qt.RightButton);
            compare(tileBox.rightFires, 0);
            verify(tileHold.showEarlyHint);

            // Moving pointer off tile mid-hold cancels without firing
            mousePress(tileBox, 60, 30, Qt.RightButton);
            wait(100);
            verify(tileHold.holding);
            mouseMove(tileBox, 260, 30);
            verify(!tileHold.holding);
            mouseRelease(tileBox, 260, 30, Qt.RightButton);
            compare(tileBox.rightFires, 0);

            // Full right-click hold executes once
            mousePress(tileBox, 60, 30, Qt.RightButton);
            tryCompare(tileBox, "rightFires", 1, 900);
            mouseRelease(tileBox, 60, 30, Qt.RightButton);
            compare(tileBox.rightFires, 1);
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
