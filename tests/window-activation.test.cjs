const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const context = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../core/WindowActivation.js'), 'utf8').replace(/^\.pragma library\s*/, ''), context);
const hasLua = spawnSync('lua', ['-v']).status === 0;
const activate = (owner = 1, action = '') => `(${context.command(owner, '"address:0xabc"', action)})();`;
const cancel = owner => context.cancel(owner);
function check(body) {
    const result = spawnSync('lua', ['-'], {encoding: 'utf8', timeout: 3000, input: `
local window = {mapped = true, address = '0xabc'}
local layers, timers, focused, actions = {}, {}, 0, 0
hl = {
    get_window = function(selector) assert(selector == 'address:0xabc'); return window end,
    get_layers = function() return layers end,
    timer = function(callback, opts)
        assert(opts.timeout == 20 and opts.type == 'oneshot')
        table.insert(timers, callback)
    end,
    dsp = {focus = function(opts) assert(opts.window == window); return 'focus' end},
    dispatch = function(command) assert(command == 'focus'); focused = focused + 1 end,
}
local function tick()
    local callback = table.remove(timers, 1)
    assert(callback, 'no pending retry'); callback()
end
${body}
`});
    assert.equal(result.status, 0, result.stderr);
}
test('focus and menu action execute once after both exclusive surfaces release', {skip: !hasLua}, () => check(`
local bar = {mapped = true, interactivity = 1}
local module = {mapped = true, interactivity = 1}
layers = {bar, module}
${activate(1, 'actions = actions + 1;')}
for i = 1, 8 do tick(); assert(focused == 0 and actions == 0) end
module.mapped = false
tick(); assert(focused == 0)
bar.interactivity = 0
tick(); assert(focused == 1 and actions == 1 and #timers == 0)
`));
test('desktop activation does not wait on nonexclusive or unmapped layers', {skip: !hasLua}, () => check(`
layers = {{mapped = true, interactivity = 0}, {mapped = true, interactivity = 2}, {mapped = false, interactivity = 1}}
${activate()}
assert(focused == 1 and #timers == 0)
`));
test('a new panel cancels an old delayed activation and its window action', {skip: !hasLua}, () => check(`
layers = {{mapped = true, interactivity = 1}}
${activate(1, 'actions = actions + 1;')}
${cancel(1)}
layers = {}
tick(); assert(focused == 0 and actions == 0 and #timers == 0)
`));
test('a newer activation supersedes a pending retry', {skip: !hasLua}, () => check(`
layers = {{mapped = true, interactivity = 1}}
${activate(1, 'actions = actions + 10;')}
${activate(1, 'actions = actions + 1;')}
layers = {}
tick(); tick(); assert(focused == 1 and actions == 1 and #timers == 0)
`));
test('separate shell processes have independent cancellation tokens', {skip: !hasLua}, () => check(`
layers = {{mapped = true, interactivity = 1}}
${activate(1)}
${cancel(2)}
layers = {}
tick(); assert(focused == 1 and #timers == 0)
`));
test('closing the target window while waiting cancels the action', {skip: !hasLua}, () => check(`
layers = {{mapped = true, interactivity = 1}}
${activate(1, 'actions = actions + 1;')}
window.mapped = false
tick(); assert(focused == 0 and actions == 0 and #timers == 0)
`));
test('a persistent exclusive layer cannot leave timers running indefinitely', {skip: !hasLua}, () => check(`
layers = {{mapped = true, interactivity = 1}}
${activate()}
for i = 1, 49 do tick() end
assert(focused == 0 and #timers == 0)
`));
