const { test } = require('node:test');
const assert = require('node:assert/strict');
const https = require('node:https');
const { EventEmitter } = require('node:events');
const { PassThrough } = require('node:stream');

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

test('invalid audio payloads are rejected before contacting Baidu', () => {
  const { validAudioPayload } = require('./server');
  for (const payload of [null, [], {}, { speech: '!!!!', len: 2 },
    { speech: 'AAAA', len: 2 }, { speech: 'AAA=', len: -2 },
    { speech: 'AAA=', len: 2, cuid: {} }, { speech: 'AAA=', len: 1920002 }]) {
    assert.equal(validAudioPayload(payload), false);
  }
  assert.equal(validAudioPayload({ speech: 'AAA=', len: 2, cuid: 'test-device' }), true);
});

test('body overflow rejects with 413 without destroying the response socket', async () => {
  const { readBody } = require('./server');
  const request = new PassThrough();
  const result = readBody(request, 4);
  request.write(Buffer.alloc(5));
  await assert.rejects(result, { status: 413 });
  assert.equal(request.destroyed, false);
  request.end();
});

test('upstream abort, size limit and total timeout reject; custom HTTPS port is retained', async (t) => {
  const { httpsRequest } = require('./server');
  let captured;
  let respond;
  let request;
  t.mock.method(https, 'request', (options, callback) => {
    captured = options;
    respond = callback;
    request = new EventEmitter();
    request.write = () => {};
    request.end = () => {};
    request.destroy = error => request.emit('error', error);
    return request;
  });
  const pending = httpsRequest('https://example.test:8443/v1');
  assert.equal(captured.port, '8443');
  assert.equal(captured.headers.Host, 'example.test:8443');
  const aborted = new PassThrough();
  respond(aborted);
  aborted.emit('aborted');
  await assert.rejects(pending, /aborted/);

  const oversized = httpsRequest('https://example.test', { maxResponseBytes: 4 });
  const large = new PassThrough();
  respond(large);
  large.write(Buffer.alloc(5));
  await assert.rejects(oversized, /too large/);
  const timed = httpsRequest('https://example.test', { timeoutMs: 10 });
  const keepAlive = setTimeout(() => {}, 1000);
  try { await assert.rejects(timed, /timeout/); } finally { clearTimeout(keepAlive); }
  await assert.rejects(httpsRequest('http://example.test'), /HTTPS/);
});

test('invalid limit configuration fails closed', () => {
  const { dailyLimit } = require('./server');
  process.env.TEST_RELAY_LIMIT = 'garbage';
  assert.throws(() => dailyLimit('TEST_RELAY_LIMIT', 200), /invalid/);
  process.env.TEST_RELAY_LIMIT = '-1';
  assert.throws(() => dailyLimit('TEST_RELAY_LIMIT', 200), /invalid/);
  process.env.TEST_RELAY_LIMIT = '0';
  assert.equal(dailyLimit('TEST_RELAY_LIMIT', 200), 0);
  delete process.env.TEST_RELAY_LIMIT;
});
