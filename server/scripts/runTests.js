const { readdirSync } = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const serverRoot = path.resolve(__dirname, '..');
process.env.STUDY_BIRDS_TEST_TOOLS ||= serverRoot;

const tests = readdirSync(path.join(serverRoot, 'tests'))
  .filter(name => name.endsWith('.test.js'))
  .sort()
  .map(name => path.join(serverRoot, 'tests', name));

const result = spawnSync(process.execPath, ['--test', ...tests], {
  cwd: serverRoot,
  env: process.env,
  stdio: 'inherit',
});

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
