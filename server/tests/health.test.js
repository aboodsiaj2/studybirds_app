const { test } = require('node:test');
const assert = require('node:assert/strict');

test('liveness stays available while readiness reports a disconnected database', async () => {
  let server;
  try {
    server = await new Promise(resolve => {
      const running = require('../src/app').listen(0, '127.0.0.1', () => resolve(running));
    });
    const origin = `http://127.0.0.1:${server.address().port}`;
    const ping = await fetch(`${origin}/ping`);
    assert.equal(ping.status, 200);
    assert.equal(await ping.text(), 'OK');

    const health = await fetch(`${origin}/api/health`);
    assert.equal(health.status, 503);
    assert.deepEqual(await health.json(), {
      status: 'degraded', service: 'study-birds-api', database: 'disconnected',
    });
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
  }
});
