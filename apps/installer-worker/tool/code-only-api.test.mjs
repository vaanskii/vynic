import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { deployCodeOnly, deployments } from './code-only-api.mjs';

const config = JSON.parse(readFileSync(new URL('../wrangler.json', import.meta.url)));
const oldVersion = '00000000-0000-4000-8000-000000000001';
const newVersion = '00000000-0000-4000-8000-000000000002';
const oldDeployment = '00000000-0000-4000-8000-000000000003';
const newDeployment = '00000000-0000-4000-8000-000000000004';
const sha = 'a'.repeat(40);
const bindings = [{ name: 'INSTALLERS', type: 'r2_bucket', bucket_name: 'vynic-installers' },
  { name: 'DOWNLOAD_GATEWAY_SECRET', type: 'secret_text' }];
const runtime = { compatibility_date: config.compatibility_date, compatibility_flags: [],
  observability: { enabled: true, logs: { enabled: true, invocation_logs: true, persist: true } } };
const row = (active = false) => ({ id: active ? newDeployment : oldDeployment,
  created_on: active ? '2026-10-31T12:30:00Z' : '2026-10-31T12:00:00Z',
  versions: [{ version_id: active ? newVersion : oldVersion, percentage: 100 }] });

function fixture(change = () => undefined, input = {}) {
  const calls = [], progress = [];
  let uploaded = false, activated = false;
  const fetcher = async (url, options) => {
    const path = new URL(url).pathname, method = options.method;
    assert.equal(new URL(url).host, 'api.cloudflare.com');
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, 'Bearer synthetic-token');
    calls.push({ path, method, body: options.body });
    // Permissions intentionally refuse route/domain/R2 management. Successful
    // deployment must never attempt these unrelated operations.
    if (/\/routes|\/domains|\/r2\//.test(path)) return new Response(JSON.stringify({
      success: false, errors: [{ code: 10000, message: 'synthetic-secret' }] }), { status: 403 });
    let result;
    if (method === 'POST' && path.endsWith('/versions')) {
      assert.equal(new URL(url).search, '?bindings_inherit=strict');
      uploaded = true; result = { id: newVersion };
    } else if (method === 'POST' && path.endsWith('/deployments')) {
      activated = true; result = row(true);
    } else if (path.endsWith('/deployments')) result = { deployments: [row(activated)] };
    else if (path.endsWith('/versions')) result = { items: [{ id: uploaded ? newVersion : oldVersion }] };
    else if (path.endsWith(`/versions/${newVersion}`)) result = { id: newVersion,
      annotations: { 'workers/tag': sha }, resources: { bindings, script_runtime: runtime } };
    else if (path.endsWith('/bindings')) result = bindings;
    else if (path.endsWith('/subdomain')) result = { enabled: false, previews_enabled: false };
    else if (path.endsWith('/environments/production')) result = { script: runtime };
    else assert.fail('unexpected API endpoint');
    const override = await change({ path, method, uploaded, activated, result, options, calls });
    if (override instanceof Response) return override;
    return new Response(JSON.stringify({ success: true, result: override === undefined ? result : override }));
  };
  return { calls, progress, run: () => deployCodeOnly({ config, sha, branch: 'main', enabled: 'true',
    token: 'synthetic-token', code: 'export default {fetch(){return new Response("test")}}',
    unchanged: () => true, fetcher, progress: event => progress.push(event), ...input }) };
}

test('code-only API succeeds with route/domain reads forbidden and preserves exact binding inheritance', async () => {
  const f = fixture();
  assert.deepEqual(await f.run(), { worker: config.name, source: sha, versionId: newVersion,
    deploymentId: newDeployment, traffic: 100 });
  const writes = f.calls.filter(c => c.method === 'POST');
  assert.equal(writes.length, 2);
  const metadata = JSON.parse(await writes[0].body.get('metadata').text());
  assert.deepEqual(metadata.bindings, [{ name: 'INSTALLERS', type: 'inherit' },
    { name: 'DOWNLOAD_GATEWAY_SECRET', type: 'inherit' }]);
  assert.equal(metadata.annotations['workers/commit_sha'], sha);
  assert.equal(metadata.observability, undefined, 'non-versioned settings stay untouched');
  assert.equal(metadata.routes, undefined);
  assert.deepEqual(JSON.parse(writes[1].body).versions, [{ version_id: newVersion, percentage: 100 }]);
  assert.equal(JSON.parse(writes[1].body).force, undefined);
  assert.ok(f.calls.every(c => !/\/routes|\/domains|\/r2\/|\/secrets/.test(c.path)));
  assert.ok(!JSON.stringify(f.progress).includes('synthetic-token'));
});

test('invalid source, gate, token or target fails before any network request', async () => {
  for (const input of [{ sha: 'latest' }, { enabled: 'false' }, { branch: 'feature' },
    { token: '' }, { unchanged: () => false }, { code: '' },
    { config: { ...config, name: 'other' } }, { config: { ...config, preview_urls: true } },
    { config: { ...config, assets: { directory: 'public' } } },
    { config: { ...config, main: 'other.mjs' } },
    { config: { ...config, compatibility_date: '2026-10-31' } }]) {
    const f = fixture(undefined, input); await assert.rejects(f.run); assert.equal(f.calls.length, 0);
  }
});

test('missing permission is sanitized and fails before upload, with no retry or broader path', async () => {
  const f = fixture(() => new Response(JSON.stringify({ success: false,
    errors: [{ code: 10000, message: 'synthetic-secret' }] }), { status: 403 }));
  await assert.rejects(f.run, error => error.message === 'preflight: API HTTP 403; codes 10000; no automatic retry');
  assert.equal(f.calls.length, 1);
});

test('unreviewed inactive version, wrong binding and public preview stop before upload', async () => {
  for (const mutate of [
    c => c.path.endsWith('/versions') ? { items: [{ id: newVersion }] } : undefined,
    c => c.path.endsWith('/bindings') ? [...bindings, { name: 'EXTRA', type: 'plain_text' }] : undefined,
    c => c.path.endsWith('/bindings') ? [{ ...bindings[0], bucket_name: 'other' }, bindings[1]] : undefined,
    c => c.path.endsWith('/subdomain') ? { enabled: true, previews_enabled: false } : undefined,
    c => c.path.endsWith('/environments/production') ? { script: { ...runtime, observability: { enabled: false } } } : undefined,
  ]) {
    const f = fixture(mutate); await assert.rejects(f.run);
    assert.equal(f.calls.filter(c => c.method === 'POST').length, 0);
  }
});

test('ambiguous upload errors, malformed response and 403 stop without activation or retry', async () => {
  for (const failure of [() => { throw new Error('synthetic-secret'); },
    () => new Response('synthetic-secret'), () => new Response('x'.repeat(1024 * 1024 + 1)),
    () => new Response(JSON.stringify({ success: false, errors: [{ code: 10000, message: 'synthetic-secret' }] }), { status: 403 })]) {
    const f = fixture(c => c.method === 'POST' ? failure() : undefined);
    await assert.rejects(f.run, e => !e.message.includes('synthetic-secret'));
    assert.equal(f.calls.filter(c => c.method === 'POST').length, 1);
    assert.equal(f.progress.length, 0);
  }
});

test('wrong upload identity, tag, runtime or inherited bindings never activates', async () => {
  for (const change of [v => ({ ...v, id: oldVersion }),
    v => ({ ...v, annotations: { 'workers/tag': 'b'.repeat(40) } }),
    v => ({ ...v, resources: { ...v.resources, bindings: [] } }),
    v => ({ ...v, resources: { ...v.resources, script_runtime: { ...runtime, compatibility_flags: ['other'] } } }),
  ]) {
    const f = fixture(c => c.path.endsWith(`/versions/${newVersion}`) ? change(c.result) : undefined);
    await assert.rejects(f.run); assert.equal(f.calls.filter(c => c.method === 'POST').length, 1);
  }
});

test('concurrent version, deployment, settings or source change stops activation', async () => {
  const changes = [
    c => c.uploaded && c.path.endsWith('/versions') && c.method === 'GET' ? { items: [{ id: oldVersion }] } : undefined,
    c => c.uploaded && c.path.endsWith('/deployments') ? { deployments: [row(true)] } : undefined,
    c => c.uploaded && c.path.endsWith('/environments/production') ?
      { script: { ...runtime, observability: { enabled: true, logs: { enabled: false } } } } : undefined,
  ];
  for (const change of changes) {
    const f = fixture(change); await assert.rejects(f.run);
    assert.equal(f.calls.filter(c => c.method === 'POST').length, 1);
  }
  let checks = 0;
  const f = fixture(undefined, { unchanged: () => ++checks < 3 });
  await assert.rejects(f.run); assert.equal(f.calls.filter(c => c.method === 'POST').length, 1);
});

test('activation ambiguity or wrong traffic never retries or claims success', async () => {
  for (const change of [
    c => { if (c.method === 'POST' && c.path.endsWith('/deployments')) throw new Error('synthetic-secret'); },
    c => c.activated && c.method === 'GET' && c.path.endsWith('/deployments') ? { deployments: [row(false)] } : undefined,
  ]) {
    const f = fixture(change); await assert.rejects(f.run, e => !e.message.includes('synthetic-secret'));
    assert.equal(f.calls.filter(c => c.method === 'POST').length, 2);
  }
});

test('deployment API object contract and array contract normalize identically', () => {
  assert.deepEqual(deployments({ deployments: [row()] }), deployments([row()]));
  for (const value of [null, {}, [], { deployments: [{ ...row(), created_on: 'unknown' }] }]) {
    assert.throws(() => deployments(value));
  }
});
