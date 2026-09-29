const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const context = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../settings/HomeUsage.js'), 'utf8'), context);

test('small folders and files directly in home become Others', () => {
  const gib = 1073741824;
  const output = [
    (2 * gib) + '\t/home/example/Games',
    '1024\t/home/example/Notes',
    (2 * gib + 2048) + '\t/home/example',
  ].join('\0') + '\0';
  const result = context.summarize(output, '/home/example');
  assert.equal(result.total, 2 * gib + 2048);
  assert.equal(result.entries[0].name, 'Games');
  assert.equal(result.entries[1].name, 'Other folders & files');
  assert.equal(result.entries[1].bytes, 2048);
});

test('only immediate home folders are shown', () => {
  const gib = 1073741824;
  const output = [
    gib + '\t/home/example/Projects/one',
    (2 * gib) + '\t/home/example/Projects',
    (2 * gib) + '\t/home/example',
  ].join('\0') + '\0';
  const result = context.summarize(output, '/home/example');
  assert.equal(result.entries.length, 1);
  assert.equal(result.entries[0].name, 'Projects');
});

test('all folders above the relative cutoff stay visible', () => {
  const gib = 1073741824;
  const records = Array.from({length: 14}, (_, index) => `${gib}\t/home/example/Folder${index}`);
  records.push(`${14 * gib}\t/home/example`);
  const result = context.summarize(records.join('\0') + '\0', '/home/example');
  assert.equal(result.entries.length, 14);
  assert.equal(result.threshold, 0.14 * gib);
});
