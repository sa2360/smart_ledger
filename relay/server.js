// ============================================================
// 一语记 · AI 中转服务（纯 Node.js，无任何第三方依赖）
//
// 作用：持有 Agnes / 百度的 API Key，替 App 转发请求，
//       APK 中不包含任何 Key。
//
// 部署：把本文件上传到 DomCloud 的 Node.js 应用，
//       启动命令 node relay.js（配置见下方 CONFIG 区，推荐用环境变量）
// ============================================================

const http = require('http');
const https = require('https');
const dns = require('dns');
const tls = require('tls');

// ---------------- CONFIG：至少改这里 ----------------
// 推荐在 DomCloud 面板/环境变量里设置，而不是写死在文件里：
//   AGNES_KEY, BAIDU_API_KEY, BAIDU_SECRET_KEY
// 若面板不支持环境变量，也可直接填在下面引号里。
const CONFIG = {
  AGNES_KEY: process.env.AGNES_KEY || '',
  AGNES_UPSTREAM: process.env.AGNES_UPSTREAM || 'https://apihub.agnes-ai.cn/v1',
  BAIDU_API_KEY: process.env.BAIDU_API_KEY || '',
  BAIDU_SECRET_KEY: process.env.BAIDU_SECRET_KEY || '',

  // 限流（每 IP 每天）：0 表示不限
  // AI 对话不限（上游免费）；语音识别限 100 次/人/天，防刷
  CHAT_DAILY_LIMIT_PER_IP: parseInt(process.env.CHAT_DAILY_LIMIT_PER_IP || '0', 10),
  ASR_DAILY_LIMIT_PER_IP: parseInt(process.env.ASR_DAILY_LIMIT_PER_IP || '100', 10),
  ASR_DAILY_LIMIT_GLOBAL: parseInt(process.env.ASR_DAILY_LIMIT_GLOBAL || '1000', 10),
};

// ---------------- 简易每日限流（内存版，重启清零） ----------------
const counters = {
  day: todayStr(),
  chat: { perIp: new Map(), global: 0 },
  asr: { perIp: new Map(), global: 0 },
};

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

function rollDay() {
  const d = todayStr();
  if (counters.day !== d) {
    counters.day = d;
    counters.chat.perIp.clear();
    counters.chat.global = 0;
    counters.asr.perIp.clear();
    counters.asr.global = 0;
  }
}

function clientIp(req) {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.length > 0) return xf.split(',')[0].trim();
  return req.socket.remoteAddress || 'unknown';
}

function overLimit(req, route) {
  const perIpMax = route === 'chat'
    ? CONFIG.CHAT_DAILY_LIMIT_PER_IP
    : CONFIG.ASR_DAILY_LIMIT_PER_IP;
  const globalMax = route === 'chat' ? 0 : CONFIG.ASR_DAILY_LIMIT_GLOBAL;
  if (perIpMax <= 0 && globalMax <= 0) return false;
  rollDay();
  const bucket = counters[route];
  const ip = clientIp(req);
  const ipCount = bucket.perIp.get(ip) || 0;
  if (perIpMax > 0 && ipCount >= perIpMax) return true;
  if (globalMax > 0 && bucket.global >= globalMax) return true;
  bucket.perIp.set(ip, ipCount + 1);
  bucket.global++;
  return false;
}

// ---------------- 小工具 ----------------

function readBody(req, limitBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limitBytes) {
        reject(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function sendJson(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

// HTTPS 请求（转发用），返回 { status, headers, body:Buffer }
function httpsRequest(urlStr, { method = 'POST', headers = {}, body = null, timeoutMs = 120000 } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(urlStr);
    const req = https.request(
      {
        hostname: u.hostname,
        port: 443,
        path: u.pathname + u.search,
        method,
        headers: { Host: u.hostname, ...headers },
        timeout: timeoutMs,
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () =>
          resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
      },
    );
    req.on('timeout', () => req.destroy(new Error('upstream timeout')));
    req.on('error', (e) => {
      const detail = Array.isArray(e.errors)
        ? e.errors.map((x) => `${x.code || x.name}:${x.message}`).join(' | ')
        : (e.code || e.name) + ':' + e.message;
      reject(new Error(`connect ${u.hostname} failed => ${detail}`));
    });
    if (body) req.write(body);
    req.end();
  });
}

// ---------------- 百度 access_token 缓存 ----------------
let baiduToken = { value: '', at: 0 };

async function getBaiduToken() {
  const ageSec = Math.floor(Date.now() / 1000) - baiduToken.at;
  if (baiduToken.value && ageSec < 29 * 86400) return baiduToken.value;
  const url =
    'https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials' +
    `&client_id=${encodeURIComponent(CONFIG.BAIDU_API_KEY)}` +
    `&client_secret=${encodeURIComponent(CONFIG.BAIDU_SECRET_KEY)}`;
  const res = await httpsRequest(url, { method: 'GET', timeoutMs: 20000 });
  const data = JSON.parse(res.body.toString('utf8'));
  if (!data.access_token) throw new Error('baidu token fetch failed');
  baiduToken = { value: data.access_token, at: Math.floor(Date.now() / 1000) };
  return baiduToken.value;
}

// ---------------- 路由 ----------------

// LLM 转发：POST /v1/chat/completions（/chat/completions 亦可）
async function handleChat(req, res, path) {
  if (!CONFIG.AGNES_KEY) return sendJson(res, 500, { error: 'server missing AGNES_KEY' });
  if (path !== '/v1/chat/completions' && path !== '/chat/completions') {
    return sendJson(res, 404, { error: 'not found' });
  }
  const raw = await readBody(req, 4 * 1024 * 1024);
  const upstream = await httpsRequest(`${CONFIG.AGNES_UPSTREAM}/chat/completions`, {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${CONFIG.AGNES_KEY}`,
      'Content-Length': raw.length,
    },
    body: raw,
    timeoutMs: 120000,
  });
  res.writeHead(upstream.status, {
    'Content-Type': upstream.headers['content-type'] || 'application/json',
    'Content-Length': upstream.body.length,
  });
  res.end(upstream.body);
}

// 语音识别转发：POST /asr  body: { speech: base64, len, cuid }
async function handleAsr(req, res) {
  if (!CONFIG.BAIDU_API_KEY || !CONFIG.BAIDU_SECRET_KEY) {
    return sendJson(res, 500, { err_no: -100, err_msg: 'server missing BAIDU keys' });
  }
  const raw = await readBody(req, 14 * 1024 * 1024); // 60s PCM ≈ 1.9MB，base64 后 ~2.6MB
  let payload;
  try {
    payload = JSON.parse(raw.toString('utf8'));
  } catch (_) {
    return sendJson(res, 400, { err_no: -101, err_msg: 'bad json' });
  }
  if (!payload.speech || !payload.len) {
    return sendJson(res, 400, { err_no: -102, err_msg: 'missing speech/len' });
  }
  const token = await getBaiduToken();
  const baiduBody = JSON.stringify({
    format: 'pcm',
    rate: 16000,
    channel: 1,
    cuid: payload.cuid || 'yiyuji_relay',
    token,
    len: payload.len,
    speech: payload.speech,
  });
  const upstream = await httpsRequest('https://vop.baidu.com/server_api', {
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(baiduBody),
    },
    body: baiduBody,
    timeoutMs: 60000,
  });
  res.writeHead(upstream.status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': upstream.body.length,
  });
  res.end(upstream.body);
}


// 网络自诊断：DNS 解析 + TLS 连接逐项报告
function probe(host) {
  return new Promise((resolve) => {
    dns.lookup(host, { all: true }, (err, addrs) => {
      if (err) return resolve({ host, dns: 'FAIL ' + err.code });
      const tryConn = (addr) =>
        new Promise((done) => {
          const t0 = Date.now();
          const sock = tls.connect(
            { host: addr.address, family: addr.family, servername: host, port: 443, timeout: 8000 },
            () => { sock.destroy(); done(`${addr.address} TLS-OK ${Date.now() - t0}ms`); },
          );
          sock.on('error', (e) => done(`${addr.address} FAIL ${e.code || e.message}`));
          sock.on('timeout', () => { sock.destroy(); done(`${addr.address} FAIL timeout`); });
        });
      Promise.all(addrs.slice(0, 2).map(tryConn)).then((results) =>
        resolve({ host, dns: 'OK', connect: results }));
    });
  });
}

// ---------------- HTTP 服务 ----------------

const server = http.createServer(async (req, res) => {
  const path = req.url || '/';
  try {
    // 健康检查（DomCloud 拉起探测也可以打这里）
    if (req.method === 'GET' && (path === '/' || path === '/health')) {
      return sendJson(res, 200, { ok: true, service: 'yiyuji-relay' });
    }
    if (req.method === 'GET' && path === '/debug-net') {
      const results = await Promise.all(
        ['apihub.agnes-ai.cn', 'vop.baidu.com', 'aip.baidubce.com'].map(probe),
      );
      return sendJson(res, 200, results);
    }

    if (req.method !== 'POST') {
      return sendJson(res, 405, { error: 'method not allowed' });
    }
    const isChat = path === '/v1/chat/completions' || path === '/chat/completions';
    const isAsr = path === '/asr';
    if (isChat && overLimit(req, 'chat')) {
      return sendJson(res, 429, { error: '今日请求次数已达上限' });
    }
    if (isAsr && overLimit(req, 'asr')) {
      return sendJson(res, 429, { err_no: -200, err_msg: '今日语音识别次数已达上限（100 次/天）' });
    }

    if (isChat) {
      return await handleChat(req, res, path);
    }
    if (isAsr) {
      return await handleAsr(req, res);
    }
    return sendJson(res, 404, { error: 'not found' });
  } catch (e) {
    console.error('[relay error]', path, e.message || e);
    if (!res.headersSent) {
      sendJson(res, 502, { error: `relay error: ${e.message || e}` });
    }
  }
});

const PORT = parseInt(process.env.PORT || '3000', 10);
server.listen(PORT, () => console.log(`[yiyuji-relay] listening on :${PORT}`));
