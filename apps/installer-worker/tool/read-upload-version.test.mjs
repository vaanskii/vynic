import { test } from 'node:test';
import assert from 'node:assert/strict';
import { uploadedVersion } from './read-upload-version.mjs';
const receipt = { type: 'version-upload', version: 1, worker_name: 'vynic-installer-downloads', worker_name_overridden: false, version_id: '00000000-0000-4000-8000-000000000001' };
test('activation consumes the exact typed Worker upload receipt, not latest', () => {
  assert.equal(uploadedVersion(JSON.stringify(receipt)), receipt.version_id);
});
test('ambiguous, wrong-target, invalid and command-injection receipts stop activation', () => {
  for (const text of [
    '', 'invalid JSON', JSON.stringify(receipt)+'\n'+JSON.stringify(receipt),
    ...[
      { worker_name: 'another-worker' }, { worker_name_overridden: true },
      { wrangler_environment: 'preview' }, { version: 2 },
      { version_id: 'id;echo unsafe' }, { version_id: undefined },
    ].map(delta => JSON.stringify({ ...receipt, ...delta })),
  ]) assert.throws(() => uploadedVersion(text));
});
