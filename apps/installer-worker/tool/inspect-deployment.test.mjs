import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { inspectDeployment, summarize, reads } from './inspect-deployment.mjs';
import { failureDiagnostic } from './deploy-version.mjs';

test('inspection uses only fixed scoped GETs and refuses redirects', async () => {
  const calls = [];
  const reports = await inspectDeployment({ token: 'synthetic-secret', fetcher: async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ success: true, result: [] }), { status: 200 });
  } });
  assert.equal(calls.length, reads.length);
  assert.equal(reports.length, reads.length);
  for (const c of calls) {
    assert.equal(c.options.method, 'GET');
    assert.equal(c.options.redirect, 'error');
    assert.equal(c.options.headers.Authorization, 'Bearer synthetic-secret');
    assert.ok(c.url.startsWith('https://api.cloudflare.com/client/v4/accounts/4347dd6103310d9273ecca7f207a0f4b/workers/'));
    assert.ok(c.url.includes('vynic-installer-downloads'));
  }
  assert.ok(!JSON.stringify(reports).includes('synthetic-secret'));
});

test('API errors expose only status and numeric code, never messages or body', () => {
  const report = summarize('service', 403, { success: false,
    errors: [{ code: 10000, message: 'synthetic-secret' }, { code: 'synthetic-secret' }],
    result: { token: 'synthetic-secret' } });
  assert.deepEqual(report, { read: 'service', status: 403, success: false, codes: [10000] });
});

test('binding and environment inspection never emits values or arbitrary names', () => {
  const bindings = summarize('bindings', 200, { success: true, result: [
    { name: 'DOWNLOAD_GATEWAY_SECRET', type: 'secret_text', value: 'synthetic-secret' },
    { name: 'INSTALLERS', type: 'r2_bucket', bucket_name: 'vynic-installers' },
    { name: 'synthetic-secret', type: 'plain_text', text: 'synthetic-secret' },
  ] });
  assert.equal(bindings.expectedR2, true); assert.equal(bindings.expectedSecret, true);
  assert.equal(bindings.otherBindings, 1);
  assert.ok(!JSON.stringify(bindings).includes('synthetic-secret'));
  const environment = summarize('environment', 200, { success: true, result: { script: {
    secret: 'synthetic-secret', compatibility_date: '2026-06-16', observability: {
      enabled: true, logs: { enabled: true, invocation_logs: true, persist: true },
    },
  } } });
  assert.equal(environment.observabilityEnabled, true);
  assert.equal(environment.logsEnabled, true);
  assert.ok(!JSON.stringify(environment).includes('synthetic-secret'));
});

test('network, oversized and malformed responses produce fixed diagnostics with no retry', async () => {
  for (const response of [() => { throw new Error('synthetic-secret'); },
    () => new Response('synthetic-secret'), () => new Response('x'.repeat(262145))]) {
    let calls = 0;
    const reports = await inspectDeployment({ token: 'synthetic-secret', fetcher: async () => { calls++; return response(); } });
    assert.equal(calls, reads.length);
    assert.ok(reports.every(r => !r.success && r.status === null));
    assert.ok(!JSON.stringify(reports).includes('synthetic-secret'));
  }
});

test('Wrangler failure classifier preserves exact known cause without raw provider output', () => {
  for (const [text, expected] of [
    ['Aborting the upload operation because of conflicts', 'strict-config-conflict'],
    ['Unable to fetch bindings, routes, or services metadata', 'dashboard-config-read-failed'],
    ['The following required secrets have not been set', 'required-secret-unavailable'],
    ['[code: 10000]', 'provider-api-error'],
    ['other', 'provider-command-failed'],
  ]) {
    const r = failureDiagnostic('upload', { status: 1, stdout: text+' synthetic-secret', stderr: 'synthetic-secret' });
    assert.equal(r.diagnostic, expected); assert.equal(r.exit, 1);
    assert.ok(!JSON.stringify(r).includes('synthetic-secret'));
  }
});

test('classifier markers match the installed pinned Wrangler contract', () => {
  const wrangler = readFileSync(new URL('../node_modules/wrangler/wrangler-dist/cli.js', import.meta.url), 'utf8');
  assert.ok(wrangler.includes('Aborting the upload operation because of conflicts'));
  assert.ok(wrangler.includes('Unable to fetch bindings, routes, or services metadata'));
  assert.ok(wrangler.includes('required secrets have not been set'));
  assert.ok(wrangler.includes('script.last_deployed_from === "dash"'));
});

test('inspection handles the actual deployments object without exposing provider extras', () => {
  const id = '00000000-0000-4000-8000-000000000001';
  const result = summarize('deployments', 200, { success: true, result: {
    deployments: [{ id, secret: 'synthetic-secret', versions: [{ version_id: id, percentage: 100 }] }],
  } });
  assert.equal(result.deployments[0].id, id);
  assert.equal(result.deployments[0].versions[0].percentage, 100);
  assert.ok(!JSON.stringify(result).includes('synthetic-secret'));
});
