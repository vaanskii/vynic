import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validateTarget, verifyActivation } from './deploy-version.mjs';
const config = JSON.parse(readFileSync(new URL('../wrangler.json', import.meta.url)));
const versionId = '00000000-0000-4000-8000-000000000001';
const deploymentId = '00000000-0000-4000-8000-000000000002';
const latest = { id: deploymentId, created_on: '2026-10-31T10:00:00.000Z', versions: [{ version_id: versionId, percentage: 100 }] };

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
