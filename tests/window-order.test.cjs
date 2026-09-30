const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const context = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../core/WindowOrder.js'), 'utf8').replace(/^\.pragma library\s*/, ''), context);
const client = (wayland, x, options = {}) => ({wayland, lastIpcObject: {
    at: [x, 80], monitor: 0, workspace: {id: 1}, floating: false, ...options
}});
const order = (windows, clients) => Array.from(context.ordered(windows, clients));

test('opening 3 after focusing 1 follows the actual 1,3,2 column order', () => {
    const windows = [{id: 1}, {id: 2}, {id: 3}];
    const result = order(windows, [client(windows[0], 0), client(windows[1], 1000), client(windows[2], 500)]);
    assert.deepEqual(result, [windows[0], windows[2], windows[1]]);
    assert.deepEqual(windows.map(w => w.id), [1, 2, 3]);
});
test('scroll offsets, focus and maximized width do not change column order', () => {
    const windows = ['first', 'second', 'third'];
    const clients = [client('third', 1000), client('first', -1000), client('second', 0, {fullscreen: 1, size: [2000, 1000], focusHistoryID: 0})];
    assert.deepEqual(order(windows, clients), windows);
    for (const c of clients) c.lastIpcObject.at[0] -= 1800;
    assert.deepEqual(order(windows, clients), windows);
});
test('reordering existing columns updates order without replacing handles', () => {
    const windows = [{id: 1}, {id: 2}];
    const clients = windows.map((w, i) => client(w, i * 500));
    assert.deepEqual(order(windows, clients), windows);
    clients[0].lastIpcObject.at[0] = 1000;
    assert.deepEqual(order(windows, clients), [windows[1], windows[0]]);
});
test('workspace and monitor geometry stays separate; floating entries stay reachable', () => {
    const windows = ['float1', 'other-workspace', 'right', 'other-monitor', 'left', 'float2'];
    const clients = [client('float1', -300, {floating: true}), client('other-workspace', -2000, {workspace: {id: 2}}),
        client('right', 500), client('other-monitor', -4000, {monitor: 1}), client('left', 0), client('float2', -500, {floating: true})];
    assert.deepEqual(order(windows, clients), ['left', 'right', 'float1', 'float2', 'other-workspace', 'other-monitor']);
});
test('missing IPC metadata and non-Hyprland sessions retain all windows', () => {
    const windows = ['one', 'two', 'three'];
    assert.deepEqual(order(windows, []), windows);
    assert.deepEqual(order(windows, [client('two', 0), {wayland: 'three', lastIpcObject: {}}]), ['two', 'one', 'three']);
});

test('QML IPC coordinate sequences work without being JavaScript arrays', () => {
    const windows = ['right', 'left'];
    const clients = [client('right', 500), client('left', 0)];
    for (const c of clients) {
        const at = c.lastIpcObject.at;
        c.lastIpcObject.at = {0: at[0], 1: at[1], length: 2};
    }
    assert.deepEqual(order(windows, clients), ['left', 'right']);
});
