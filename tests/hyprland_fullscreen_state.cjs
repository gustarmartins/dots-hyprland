// Run with node tests/hyprland_fullscreen_state.cjs. No desktop IPC or writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname,
    '../dots/.config/quickshell/ii/services/HyprlandData.qml'), 'utf8');
const root = {
    monitorsReady: true,
    workspacesReady: true,
    monitors: [{id: 0, name: 'left', activeWorkspace: {id: 2}},
               {id: 1, name: 'right', activeWorkspace: {id: 6}}],
    workspaceById: {2: {hasfullscreen: false}, 6: {hasfullscreen: true}},
    windowList: [],
};
const context = vm.createContext({root});
// Execute the production function, supplying only its service state.
vm.runInContext(source.slice(source.indexOf('function monitorHasFullscreen('),
    source.indexOf('function preferredNotificationMonitorName(')), context);
const fullscreen = context.monitorHasFullscreen;
assert.equal(fullscreen('left'), false);
assert.equal(fullscreen('right'), true);
// A placeholder workspace or monitor elsewhere must not hide an existing screen.
root.workspacesReady = false;
root.monitorsReady = false;
assert.equal(fullscreen('left'), false);
assert.equal(fullscreen('right'), true);
// A new active workspace can precede its JSON snapshot.
root.monitors[0].activeWorkspace.id = 11;
assert.equal(fullscreen('left'), false);
// Client fullscreen details still protect the correct monitor/workspace.
root.windowList = [{monitor: 0, workspace: {id: 11}, fullscreen: 2}];
assert.equal(fullscreen('left'), true);
root.windowList[0].workspace.id = 2;
assert.equal(fullscreen('left'), false);
root.windowList[0] = {monitor: 1, workspace: {id: 11}, fullscreenClient: 2};
assert.equal(fullscreen('left'), false);
assert.equal(fullscreen('missing'), true);
assert.equal(fullscreen(''), true);
console.log('10 fullscreen state assertions passed');
