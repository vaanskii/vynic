import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { deployVersion, validateTarget, verifyActivation } from './deploy-version.mjs';

const config = JSON.parse(readFileSync(new URL('../wrangler.json', import.meta.url), 'utf8'));
const versionId = '00000000-0000-4000-8000-000000000001';
const deploymentId = '00000000-0000-4000-8000-000000000002';
const upload = JSON.stringify({ type: 'version-upload', version: 1,
  worker_name: config.name, worker_name_overridden: false, version_id: versionId });
const activated = JSON.stringify({ type: 'version-deploy', version: 1,
  worker_name: config.name, deployment_id: deploymentId });
const latest = { id: deploymentId, created_on: '2026-10-31T10:00:00.000Z',
  versions: [{ version_id: versionId, percentage: 100 }] };

function fixture(overrides = {}) {
  const calls = [];
  const options = { config, sha: 'a'.repeat(40), branch: 'main', enabled: 'true',
    unchanged: () => true,
    receipt: stage => stage === 'upload' ? upload : activated,
    run: (args, stage) => { calls.push({ args, stage }); return JSON.stringify([latest]); },
    ...overrides };
  return { calls, run: () => deployVersion(options) };
}

test('version publication activates only the returned ID and verifies latest traffic', () => {
  const f = fixture();
  assert.deepEqual(f.run(), { worker: config.name, source: 'a'.repeat(40), versionId, deploymentId, traffic: 100 });
  assert.equal(f.calls.length, 5);
  assert.deepEqual(f.calls[3].args.slice(0, 3), ['versions', 'deploy', `${versionId}@100%`]);
  assert.ok(f.calls.every(c => !c.args.includes('triggers') && !c.args.includes('secret') && !c.args.includes('r2')));
  assert.notEqual(f.calls[0].args[0], 'deploy');
});

test('preview, missing gate, invalid SHA and wrong target fail before remote work', () => {
  for (const override of [{ branch: 'feature' }, { branch: undefined }, { enabled: undefined },
    { enabled: 'false' }, { sha: 'latest' }, { config: { ...config, name: 'other' } },
    { config: { ...config, workers_dev: true } }, { config: { ...config, preview_urls: true } },
    { config: { ...config, r2_buckets: [{ binding: 'INSTALLERS', bucket_name: 'other' }] } }]) {
    const f = fixture(override); assert.throws(f.run); assert.equal(f.calls.length, 0);
  }
});

test('upload errors, invalid receipts and changed source never activate', () => {
  for (const override of [{ receipt: () => '' }, { receipt: () => upload + '\n' + upload },
    { receipt: () => upload.replace(config.name, 'other') }, { unchanged: () => false }]) {
    const f = fixture(override); assert.throws(f.run); assert.equal(f.calls.length, 2);
  }
  const stages = [];
  const f = fixture({ run: (_args, stage) => {
    stages.push(stage);
    if (stage === 'upload') throw new Error('synthetic upload failure');
    return JSON.stringify([latest]);
  } });
  assert.throws(f.run, /upload failure/);
  assert.deepEqual(stages, ['preflight', 'upload']);
});

test('activation/verification failures never retry, roll back or claim success', () => {
  const calls = [];
  const f = fixture({ run: (args, stage) => {
    calls.push(stage); if (stage === 'activate') throw new Error('synthetic ambiguous timeout');
    return JSON.stringify([latest]);
  } });
  assert.throws(f.run, /ambiguous/); assert.deepEqual(calls, ['preflight', 'upload', 'compare', 'activate']);
  const wrong = fixture({ run: () => JSON.stringify([{ ...latest, versions: [{ version_id: versionId, percentage: 50 }] }]) });
  assert.throws(wrong.run, /Latest deployment/);
});

test('wrong version, newer concurrent deploy, duplicate newest, invalid time fail readback', () => {
  for (const rows of [[], [{ ...latest, created_on: 'invalid' }], [latest, latest],
    [{ ...latest, versions: [{ version_id: deploymentId, percentage: 100 }] }],
    [latest, { ...latest, id: versionId, created_on: '2026-10-31T11:00:00.000Z' }]]) {
    assert.throws(() => verifyActivation(JSON.stringify(rows), deploymentId, versionId));
  }
  verifyActivation(JSON.stringify([{ ...latest, id: versionId, created_on: '2026-10-30T00:00:00Z' }, latest]), deploymentId, versionId);
});

test('actual config retains the private target and rejects custom build/environment hooks', () => {
  validateTarget(config);
  assert.throws(() => validateTarget({ ...config, build: { command: 'anything' } }));
  assert.throws(() => validateTarget({ ...config, env: { preview: {} } }));
});

test('missing deployment read scope stops before upload; concurrent deployment stops activation', () => {
  for (const response of ['', '[]', '{}']) {
    const f = fixture({ run: () => response });
    assert.throws(f.run);
  }
  const stages = [];
  const f = fixture({ run: (_args, stage) => {
    stages.push(stage);
    return JSON.stringify([{ ...latest, id: stage === 'compare' ? versionId : deploymentId }]);
  } });
  assert.throws(f.run, /changed during upload/);
  assert.deepEqual(stages, ['preflight', 'upload', 'compare']);
});
