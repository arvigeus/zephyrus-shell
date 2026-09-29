const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const context = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../settings/AudioNames.js'), 'utf8'), context);
const rules = ['10-laptop.json', '20-dell-s2722dc.json'].flatMap(file => JSON.parse(fs.readFileSync(path.join(__dirname, '../config/audio', file))));
test('laptop route labels track speakers and headphones independently', () => {
  const node = {name:'alsa_output.pci-0000_07_00.6.analog-stereo', description:'Generic audio'};
  for (const [port,label] of [['analog-output-speaker','Laptop speakers'],['analog-output-headphones','Headphones · laptop jack']]) {
    const snapshot = {rules, devices:{[node.name]:{properties:{'port.name':port}, available:true}}};
    assert.equal(context.describe(node,snapshot).label,label);
  }
});
test('a different monitor on the same connector never inherits the Dell label', () => {
  const node = {name:'alsa_output.pci-0000_07_00.1.hdmi-stereo', description:'HDMI [DELL S2722DC]'};
  assert.equal(context.describe(node,{rules}).label,'Dell S2722DC · monitor audio');
  node.description = 'HDMI [Other display]';
  assert.equal(context.describe(node,{rules}).label,node.description);
});
test('missing and unplugged devices are represented honestly', () => {
  assert.equal(context.describe(null,{}).available,false);
  const node = {name:'monitor',description:'Monitor'};
  assert.equal(context.describe(node,{devices:{monitor:{properties:{},available:false}}}).available,false);
});
test('the two unused Navi outputs are hidden by stable node identity', () => {
  const navi = JSON.parse(fs.readFileSync(path.join(__dirname, '../config/audio/05-navi-hdmi.json')));
  for (const suffix of ['3', '7']) {
    const node = {name: `alsa_output.pci-0000_03_00.1.pro-output-${suffix}`, description: 'Navi HDMI audio'};
    assert.equal(context.describe(node, {rules: [...navi, ...rules]}).hidden, true);
  }
  const other = {name: 'alsa_output.another-gpu.pro-output-3', description: 'Another HDMI audio'};
  assert.equal(context.describe(other, {rules: [...navi, ...rules]}).hidden, false);
});
