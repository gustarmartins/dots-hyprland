// Test the production lock handlers with inert dispatchers and quoted selectors.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');
const base = path.join(__dirname, '../dots/.config/quickshell/ii');
const source = fs.readFileSync(path.join(base, 'modules/ii/lock/Lock.qml'), 'utf8');
const identity = fs.readFileSync(path.join(base, 'modules/common/functions/WorkspaceIdentity.js'), 'utf8');
function body(marker) {
    const start = source.indexOf(marker) + marker.length;
    assert(start >= marker.length);
    let depth = 1;
    for (let i = start; i < source.length; i++) {
        if (source[i] === '{') depth++;
        else if (source[i] === '}' && --depth === 0) return source.slice(start, i);
    }
    throw Error('Unclosed handler');
}
const commands = [];
const monitor = 'TEST-MONITOR';
const selector = 'name:work "quote"; $(touch NEVER)';
const context = vm.createContext({
    root: {savedWorkspaces: {}},
    GlobalStates: {screenLocked: true},
    HyprlandData: {monitors: [{name: monitor, activeWorkspace: {address: selector}}]},
    Quickshell: {screens: [{name: monitor}], execDetached: args => commands.push(args)},
    restoreTimer: {start: () => commands.push('timer')},
});
vm.runInContext(identity.replace(/^\.pragma library\s*/, '') + '\nWorkspaceIdentity={address};', context);
vm.runInContext('(function(){' + body('function onScreenLockedChanged() {') + '})()', context);
assert.equal(context.root.savedWorkspaces[monitor], selector);
assert.equal(commands.length, 1);
assert.equal(commands[0][0], 'hyprctl');
assert.equal(commands[0][1], 'eval');
assert(!commands[0][2].includes('keyword'));
// Parsing/execution uses Lua stubs; no compositor, shell or real window exists.
function checkLua(code, expected) {
    const stub = 'local calls={}\nhl={dsp={focus=function(x) return x end},dispatch=function(x) calls[#calls+1]=x end}\n';
    execFileSync('lua', ['-'], {input: stub + code + '\nassert(#calls==2)\nassert(calls[2].workspace==' + expected + ')\n'});
}
checkLua(commands[0][2], '2147483647');
commands.length = 0;
vm.runInContext('(function(){' + body('onTriggered: {') + '})()', context);
assert.equal(commands[0][0], 'hyprctl');
checkLua(commands[0][2], JSON.stringify(selector));
context.GlobalStates.screenLocked = false;
commands.length = 0;
vm.runInContext('(function(){' + body('function onScreenLockedChanged() {') + '})()', context);
assert.deepEqual(commands, ['timer']);
console.log('PASS: lock/unlock selectors, named workspace restoration, Lua quoting, no shell execution');
