// Exercise current server authority code with a synthetic transaction only.
// No Prisma client, HTTP endpoint, or database connection is constructed.
const path = require('node:path');
const assert = require('node:assert/strict');
const backend = path.resolve(__dirname, '../../backend');
require(path.join(backend, 'node_modules/ts-node')).register({
  transpileOnly: true, project: path.join(backend, 'tsconfig.json'),
});
const { assertOperationalAuthority, replaceOperationalDevice } = require(
  path.join(backend, 'src/edge/operational-authority.ts'),
);
(async () => {
  const venue = { id: 'synthetic-venue-a', activeOperationalDeviceId: 'old-pos' };
  const devices = [
    { id: 'old-pos', venueId: venue.id, status: 'ACTIVE' },
    { id: 'fresh-pos', venueId: venue.id, status: 'ACTIVE' },
    { id: 'other-venue-pos', venueId: 'synthetic-venue-b', status: 'ACTIVE' },
  ];
  const audits = [], held = [];
  const matches = (d, where) => Object.entries(where).every(([k, v]) => d[k] === v);
  const tx = {
    $queryRaw: async () => [],
    venue: { findUnique: async () => venue, update: async ({ data }) => Object.assign(venue, data) },
    device: { count: async ({ where }) => devices.filter(d => matches(d, where)).length,
      findFirst: async ({ where }) => devices.find(d => matches(d, where)) },
    edgeCommand: { updateMany: async (args) => { held.push(args); return { count: 1 }; } },
    platformAuditEvent: { create: async (args) => { audits.push(args); } },
  };
  const db = { $transaction: work => work(tx) };
  const auth = id => ({ deviceId: id, venueId: venue.id });
  async function denied(id) {
    await assert.rejects(() => assertOperationalAuthority(tx, auth(id)),
      error => error.getStatus() === 403 && error.getResponse().code === 'PRIMARY_POS_REQUIRED');
  }
  await assertOperationalAuthority(tx, auth('old-pos'));
  await denied('fresh-pos');
  await replaceOperationalDevice(db, { platformUserId: 'synthetic-operator' },
    venue.id, 'fresh-pos', 'old-pos', 'MENU-01 isolated replacement proof');
  await denied('old-pos');
  await assertOperationalAuthority(tx, auth('fresh-pos'));
  await denied('other-venue-pos');
  await denied(undefined);
  assert.equal(held[0].data.resultCode, 'primary_replaced_outcome_unknown');
  assert.equal(audits.length, 1);
  console.log(JSON.stringify({ status: 'PASS', productionModule: 'apps/backend/src/edge/operational-authority.ts',
    boundary: 'Current server functions; synthetic transaction state, not PostgreSQL integration',
    oldPrimaryBefore: 'allowed', freshSecondaryBefore: 'PRIMARY_POS_REQUIRED',
    oldPrimaryAfter: 'PRIMARY_POS_REQUIRED', freshPrimaryAfter: 'allowed',
    otherVenueDevice: 'PRIMARY_POS_REQUIRED', legacyCredentialAfter: 'PRIMARY_POS_REQUIRED',
    uncertainCommandReplacement: held[0].data.resultCode, auditCount: audits.length }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
