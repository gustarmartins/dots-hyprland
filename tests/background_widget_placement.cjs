// Run with node tests/background_widget_placement.cjs; no desktop IPC or writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname,
    '../dots/.config/quickshell/ii/modules/ii/background/WidgetPlacement.js'), 'utf8');
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma library\s*/, ''), context);
const { monitorObstacles, bestOpenSpot } = context;

// 1. Settings window on the left of 1920x1080 leaves the right strip open; clock centers there.
const leftWindow = [{ x: 50, y: 70, width: 1400, height: 850 }];
const rightSpot = bestOpenSpot(1920, 1080, [0, 0, 0, 0], leftWindow, 230, 230);
assert.ok(rightSpot, 'Expected open spot on right side');
assert.ok(rightSpot.x - 115 >= 1450, `Clock overlapped left window: x=${rightSpot.x}`);
assert.ok(rightSpot.x + 115 <= 1920 - 24, `Clock exceeded right margin: x=${rightSpot.x}`);
assert.ok(Math.abs(rightSpot.y - 540) < 5, `Clock not vertically centered: y=${rightSpot.y}`);

// 2. Sibling weather widget avoids both the Settings window and the placed clock.
const clockRect = { x: rightSpot.x - 115, y: rightSpot.y - 115, width: 230, height: 230 };
const weatherSpot = bestOpenSpot(1920, 1080, [0, 0, 0, 0], [...leftWindow, clockRect], 200, 200);
assert.ok(weatherSpot, 'Expected open spot for weather widget');
assert.ok(weatherSpot.x - 100 >= 1450, `Weather overlapped left window: x=${weatherSpot.x}`);
const weatherRect = { x: weatherSpot.x - 100, y: weatherSpot.y - 100, width: 200, height: 200 };
const overlapsClock = !(weatherRect.x + weatherRect.width <= clockRect.x
    || clockRect.x + clockRect.width <= weatherRect.x
    || weatherRect.y + weatherRect.height <= clockRect.y
    || clockRect.y + clockRect.height <= weatherRect.y);
assert.ok(!overlapsClock, 'Weather overlapped clock');

// 3. Empty workspace returns null so widget falls back to calmest wallpaper region.
assert.equal(bestOpenSpot(1920, 1080, [0, 0, 0, 0], [], 230, 230), null);

// 4. Fully covered tiled workspace returns null (no erratic jumping).
const fullTiled = [
    { x: 8, y: 8, width: 948, height: 1064 },
    { x: 964, y: 8, width: 948, height: 1064 },
];
assert.equal(bestOpenSpot(1920, 1080, [0, 0, 0, 0], fullTiled, 230, 230), null);

// 5. Multi-monitor obstacle filtering & coordinate translation (HDMI-A-1 at x=1920, y=500).
const clients = [
    { mapped: true, hidden: false, monitor: 0, workspace: { id: 5 }, at: [10, 10], size: [1000, 900] },
    { mapped: true, hidden: false, monitor: 1, workspace: { id: 6 }, at: [2000, 560], size: [1200, 960] },
    { mapped: false, hidden: false, monitor: 1, workspace: { id: 6 }, at: [3200, 560], size: [600, 960] },
    { mapped: true, hidden: true, monitor: 1, workspace: { id: 6 }, at: [3200, 560], size: [600, 960] },
    { mapped: true, hidden: false, monitor: 1, workspace: { name: 'special:mail' }, at: [1920, 500], size: [1920, 1080] },
];
const mon1Obs = monitorObstacles(clients, 1, 1920, 500, 6);
assert.equal(mon1Obs.length, 1);
assert.deepEqual(Object.assign({}, mon1Obs[0]), { x: 80, y: 60, width: 1200, height: 960 });
const mon1Spot = bestOpenSpot(1920, 1080, [0, 0, 0, 48], mon1Obs, 230, 230);
assert.ok(mon1Spot, 'Expected open spot on second monitor');
assert.ok(mon1Spot.x - 115 >= 1280, `Mon1 clock overlapped window: ${mon1Spot.x}`);
assert.ok(mon1Spot.y + 115 <= 1080 - 48 - 24, `Mon1 clock overlapped reserved bottom bar: ${mon1Spot.y}`);

// 6. Bottom-half window leaves open top banner; clock centers in open top area.
const bottomWin = [{ x: 20, y: 520, width: 1880, height: 540 }];
const topSpot = bestOpenSpot(1920, 1080, [0, 0, 0, 0], bottomWin, 230, 230);
assert.ok(topSpot && topSpot.y + 115 <= 520, `Clock did not move to top half: ${JSON.stringify(topSpot)}`);

console.log('PASS: background widget open-space placement assertions passed');
