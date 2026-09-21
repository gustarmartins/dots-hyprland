// Run with node tests/background_workspace_placement.cjs; no desktop IPC or writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname,
    '../dots/.config/quickshell/ii/modules/ii/background/WorkspacePlacement.js'), 'utf8');
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma library\s*/, ''), context);
const fraction = context.fraction;
const rules = [];
for (const [monitor, start] of [['left', 1], ['right', 6], ['third', 41]]) {
    for (const group of [0, 10, 20]) {
        for (let slot = 0; slot < 5; ++slot) {
            rules.push({monitor, workspaceString: String(start + group + slot), enabled: true});
        }
    }
}
let checks = 0;
for (const group of [0, 10, 20]) {
    for (let slot = 0; slot < 5; ++slot) {
        for (const [monitor, start] of [['left', 1], ['right', 6], ['third', 41]]) {
            assert.equal(fraction(rules, monitor, start + group + slot, 20), slot / 4);
            ++checks;
        }
    }
}
// Native list order, duplicate and unrelated rules cannot shift an existing range.
const noisy = [...rules].reverse().concat(rules, [
    {monitor: 'left', workspaceString: 'special:special'},
    {monitor: 'left', workspaceString: '0', enabled: false},
    {monitor: 'another', workspaceString: '6'},
]);
assert.equal(fraction(noisy, 'left', 5, 20), 1);
assert.equal(fraction([{monitor: 'only', workspaceString: '42'}], 'only', 42, 20), 0.5);
assert.equal(fraction([], 'unassigned', 1, 20), 0);
assert.equal(fraction([], 'unassigned', 20, 20), 1);
assert.equal(fraction([], 'unassigned', 21, 20), 0);
assert.equal(fraction([], 'unassigned', 1, 1), 0.5);
console.log(`${checks + 6} workspace placement assertions passed`);
