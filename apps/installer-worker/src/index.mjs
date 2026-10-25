// Only this Worker streams the private bucket. Backend decisions stay authoritative.
const ORIGIN = 'https://releases.vynic.ge';
const AUTHORITY = 'https://api.vynic.ge/customer/downloads/worker/authorize';
const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const KEY = /^windows\/beta\/(\d+\.\d+\.\d+)\/build([1-9]\d*)\/Vynic-Windows-(\d+\.\d+\.\d+)-build([1-9]\d*)-beta-offline\.zip$/;
const safeHeaders = {
  'Cache-Control': 'private, no-store',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
  'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
};
class Denial extends Error {
  constructor(status, bytes) { super('Download unavailable'); this.status = status; this.bytes = bytes; }
}
const errorResponse = (error) => new Response('Download unavailable. Request a new link or try again later.', {
  status: error instanceof Denial ? error.status : 503,
  headers: { ...safeHeaders, 'Content-Type': 'text/plain; charset=utf-8',
    ...(error instanceof Denial && error.status === 416 && Number.isSafeInteger(error.bytes)
      ? { 'Content-Range': `bytes */${error.bytes}` } : {}) },
});
async function boundedJson(response, limit) {
  if (!response.body) throw new Denial(503);
  const reader = response.body.getReader(); let size = 0; const chunks = [];
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new Denial(503);
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  const data = new Uint8Array(size); let offset = 0;
  for (const c of chunks) { data.set(c, offset); offset += c.byteLength; }
  return JSON.parse(new TextDecoder().decode(data));
}
async function decision(env, input) {
  if (!TOKEN.test(env.DOWNLOAD_GATEWAY_SECRET ?? '')) throw new Denial(503);
  const response = await fetch(AUTHORITY, {
    method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(10000),
    headers: { Authorization: `Bearer ${env.DOWNLOAD_GATEWAY_SECRET}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (response.status >= 300 && response.status < 400) { await response.body?.cancel(); throw new Denial(503); }
  const data = await boundedJson(response, 4096);
  if (!response.ok) {
    throw new Denial([400, 403, 404, 416, 429].includes(response.status) ? response.status : 503,
      response.status === 416 && Number.isSafeInteger(data.bytes) && data.bytes > 0 && data.bytes <= 512 * 1024 * 1024 ? data.bytes : undefined);
  }
  if (input.operation !== 'outcome' && (!Number.isFinite(Date.parse(data.expiresAt)) || Date.parse(data.expiresAt) <= Date.now()))
    throw new Denial(404);
  return data;
}
function cookieToken(request) {
  const values = (request.headers.get('Cookie') ?? '').split(';').map(s => s.trim()).filter(s => s.startsWith('__Secure-vynic-download='));
  if (values.length !== 1) throw new Denial(404);
  const token = values[0].slice('__Secure-vynic-download='.length);
  if (!TOKEN.test(token)) throw new Denial(404);
  return token;
}
function bridge() {
  const nonce = crypto.randomUUID().replaceAll('-', '');
  // Fragment capability never enters a URL query or referrer. Clear it before requests.
  return new Response(`<!doctype html><html lang="ka"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Vynic installer</title><body><main><h1>Vynic Windows</h1><p id="status" role="status">ინსტალერის წვდომა მოწმდება…</p><a id="download" hidden>ინსტალერის ჩამოტვირთვა</a></main><script nonce="${nonce}">
(async()=>{const p=location.pathname;const t=new URLSearchParams(location.hash.slice(1)).get('token');history.replaceState(null,'',p);try{if(t){const s=await fetch(p+'/session',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':'vynic-download'},body:JSON.stringify({token:t})});if(!s.ok)throw Error();}const h=await fetch(p+'/file',{method:'HEAD'});if(!h.ok||h.headers.get('content-type')!=='application/zip'||!h.headers.get('content-disposition')?.startsWith('attachment;')||Number(h.headers.get('content-length'))<=0)throw Error();const a=document.getElementById('download');a.href=p+'/file';a.hidden=false;document.getElementById('status').textContent='ინსტალერი მზადაა ჩამოსატვირთად.';}catch{document.getElementById('status').textContent='ბმული მიუწვდომელია ან ვადა გაუვიდა. მოითხოვეთ ახალი ბმული.'}})();
</script></body></html>`, { headers: { ...safeHeaders, 'Content-Type': 'text/html; charset=utf-8',
    'Content-Security-Policy': `default-src 'none'; script-src 'nonce-${nonce}'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'` } });
}
function validateArtifact(data, range) {
  const key = typeof data.key === 'string' && data.key.length < 240 ? KEY.exec(data.key) : null;
  if (!key || key[1] !== key[3] || key[2] !== key[4]
    || !Number.isSafeInteger(data.bytes) || data.bytes <= 0 || data.bytes > 512 * 1024 * 1024
    || !/^[a-f0-9]{64}$/.test(data.sha256 ?? '')
    || !Number.isSafeInteger(data.start) || !Number.isSafeInteger(data.end)
    || data.start < 0 || data.end < data.start || data.end >= data.bytes
    || data.partial !== (range !== undefined)) throw new Denial(503);
  if (range === undefined) {
    if (data.start !== 0 || data.end !== data.bytes - 1) throw new Denial(503);
  } else {
    const [start, end] = range.slice(6).split('-');
    if (data.start !== Number(start) || data.end !== (end ? Math.min(Number(end), data.bytes - 1) : data.bytes - 1)) throw new Denial(503);
  }
}
export default {
  async fetch(request, env, ctx) {
    let audit;
    try {
      const url = new URL(request.url);
      const route = /^\/windows\/access\/([a-f0-9-]{36})(\/session|\/file)?$/.exec(url.pathname);
      if (url.origin !== ORIGIN || url.search || !route) throw new Denial(404);
      // This header is populated by Cloudflare on ingress. Never trust X-Forwarded-For.
      const clientIp = request.headers.get('CF-Connecting-IP');
      if (!clientIp || clientIp.length > 45 || !/^[a-fA-F0-9:.]+$/.test(clientIp)) throw new Denial(404);
      const base = { id: route[1], clientIp };
      if (!route[2] && request.method === 'GET') {
        await decision(env, { ...base, operation: 'context' }); return bridge();
      }
      if (route[2] === '/session' && request.method === 'POST') {
        if (request.headers.get('Origin') !== ORIGIN || request.headers.get('X-CSRF-Token') !== 'vynic-download'
          || request.headers.get('Content-Type') !== 'application/json') throw new Denial(403);
        let body; try { body = await boundedJson(request, 256); } catch { throw new Denial(400); }
        if (!body || Object.keys(body).length !== 1 || !TOKEN.test(body.token ?? '')) throw new Denial(400);
        const data = await decision(env, { ...base, operation: 'session', token: body.token });
        const seconds = Math.min(900, Math.floor((Date.parse(data.expiresAt) - Date.now()) / 1000));
        if (seconds <= 0) throw new Denial(404);
        return new Response(null, { status: 204, headers: { ...safeHeaders,
          'Set-Cookie': `__Secure-vynic-download=${body.token}; Path=/windows/access/${base.id}; Secure; HttpOnly; SameSite=Strict; Max-Age=${seconds}` } });
      }
      if (route[2] !== '/file' || !['GET', 'HEAD'].includes(request.method)) throw new Denial(404);
      const token = cookieToken(request);
      const range = request.headers.get('Range') ?? undefined;
      if (range !== undefined && (range.length > 64 || !/^bytes=\d+-\d*$/.test(range))) throw new Denial(400);
      const data = await decision(env, { ...base, operation: 'file', token, method: request.method, ...(range === undefined ? {} : { range }) });
      if (request.method === 'GET') audit = outcome => ctx.waitUntil(decision(env, { ...base, token, operation: 'outcome', outcome }).catch(() => { console.error('installer_audit_unavailable'); }));
      validateArtifact(data, range);
      const head = await env.INSTALLERS.head(data.key);
      if (!head || head.size !== data.bytes || head.customMetadata?.sha256 !== data.sha256) throw new Denial(503);
      const length = data.end - data.start + 1;
      const headers = { ...safeHeaders, 'Content-Type': 'application/zip',
        'Content-Disposition': 'attachment; filename="Vynic-Windows-beta-offline.zip"',
        'Content-Length': String(length), 'Accept-Ranges': 'bytes',
        ...(data.partial ? { 'Content-Range': `bytes ${data.start}-${data.end}/${data.bytes}` } : {}) };
      if (request.method === 'HEAD') return new Response(null, { status: data.partial ? 206 : 200, headers });
      const object = await env.INSTALLERS.get(data.key, { onlyIf: { etagMatches: head.etag }, range: { offset: data.start, length } });
      if (!object?.body || object.size !== data.bytes || object.customMetadata?.sha256 !== data.sha256) {
        await object?.body?.cancel(); throw new Denial(503);
      }
      const reader = object.body.getReader(); let received = 0, finished = false;
      const finish = outcome => { if (!finished) { finished = true; audit(outcome); } };
      const stream = new ReadableStream({
        async pull(controller) {
          try {
            const { done, value } = await reader.read();
            if (done) {
              if (received !== length) throw new Error('Incomplete object');
              controller.close(); finish('completed'); return;
            }
            received += value.byteLength;
            if (received > length) throw new Error('Excess object');
            controller.enqueue(value);
          } catch {
            try { await reader.cancel(); } finally { finish('failed'); controller.error(new Error('Private storage stream failed')); }
          }
        },
        async cancel() { try { await reader.cancel(); } finally { finish('failed'); } },
      });
      // workerd derives Content-Length from a fixed length stream, not a header on an arbitrary stream.
      if (typeof FixedLengthStream !== 'undefined') {
        const fixed = new FixedLengthStream(length);
        ctx.waitUntil(stream.pipeTo(fixed.writable).catch(() => { finish('failed'); }));
        return new Response(fixed.readable, { status: data.partial ? 206 : 200, headers });
      }
      return new Response(stream, { status: data.partial ? 206 : 200, headers });
    } catch (error) { audit?.('failed'); return errorResponse(error); }
  },
};
