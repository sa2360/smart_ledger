const { test } = require('node:test');
const assert = require('node:assert/strict');

test('health, disabled diagnostics, and rate limits with spoofed proxy headers', async () => {
  process.env.AGNES_KEY = '';
  process.env.CHAT_DAILY_LIMIT_PER_IP = '1';
  process.env.CHAT_DAILY_LIMIT_GLOBAL = '2';
  process.env.TRUST_PROXY = 'false';
  process.env.ENABLE_NETWORK_DIAGNOSTICS = 'false';
  const { server } = require('./server');
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.deepEqual(await (await fetch(`${base}/health`)).json(), { ok: true, service: 'yiyuji-relay' });
    assert.notEqual((await fetch(`${base}/debug-net`)).status, 200);
    assert.equal((await fetch(`${base}/v1/chat/completions`, { method: 'POST', headers: { 'x-forwarded-for': '1.2.3.4' }, body: '{}' })).status, 500);
    assert.equal((await fetch(`${base}/v1/chat/completions`, { method: 'POST', headers: { 'x-forwarded-for': '4.3.2.1' }, body: '{}' })).status, 429);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
