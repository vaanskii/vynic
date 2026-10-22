'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { setTimeout: delay } = require('node:timers/promises');

// This script cannot use a host .env, default datasource, arbitrary URL, or
// application bootstrap. Its only supported target is the root-owned fixture.
assert.equal(__dirname, '/app/readiness-proof');
assert.equal(process.env.VYNIC_READINESS_DISPOSABLE_FIXTURE, 'vynic-readiness-20261006-a2nbcprb');
const marker = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-marker.json'), 'utf8'));
assert.deepEqual(marker, {
  kind: 'vynic-printer-runtime-disposable-proof', task: 'vynic-readiness-20261006-a2nbcprb',
  database: 'vynic_readiness', postgresContainer: 'vynic-readiness-20261006-pg',
  network: 'none', syntheticRowsOnly: true, noApplicationStartup: true,
});
const provenance = JSON.parse(fs.readFileSync(path.join(__dirname, 'provenance.json'), 'utf8'));
for (const [relative, expected] of Object.entries(provenance.compiledHashes)) {
  const actual = createHash('sha256').update(fs.readFileSync(path.join(__dirname, relative))).digest('hex');
  assert.equal(actual, expected, `Compiled source mismatch: ${relative}`);
}
const { PrismaClient } = require('@prisma/client');
const domain = require('./compiled/customer/printer-runtime-config.js');
const persistence = require('./compiled/customer/printer-runtime-persistence.js');
const fixtureUrl = 'postgresql://postgres:vynic-synthetic-readiness-only@127.0.0.1:5432/vynic_readiness?schema=pos';
const db = new PrismaClient({ datasources: { db: { url: fixtureUrl } } });
const ids = Object.fromEntries(['organization', 'venue', 'otherOrganization', 'otherVenue', 'owner', 'otherOwner', 'platform', 'device', 'legacyDevice', 'plan'].map((key) => [key, randomUUID()]));
const context = { deviceId: ids.device, venueId: ids.venue };
const owner = { customerAccountId: ids.owner };
const platform = { platformUserId: ids.platform };
const checks = [];
let featureId;

const report = {
  kind: 'REAL_POSTGRESQL_SYNTHETIC_PRINTER_RUNTIME_PROOF', status: 'RUNNING',
  sourceHashes: provenance.sourceHashes, compiledHashes: provenance.compiledHashes,
  compiler: provenance.compiler, syntheticIds: ids, checks,
  fixture: { ...marker, publishedPorts: [], fixtureMountReadOnly: true, cachedImagesOnly: true },
  runtime: { node: process.version, prisma: require('@prisma/client/package.json').version,
    nestCommon: require('@nestjs/common/package.json').version },
  limitations: ['Cached container dependencies; no fresh locked install', 'No HTTP authentication/token acceptance',
    'No activation, fleet fencing, hardware printing or production rollout', 'No deployment or original-workspace changes'],
};
function pass(name, details = {}) { checks.push({ name, passed: true, ...details }); console.log(`PASS ${name}`); }
async function rejected(action, status) {
  try { await action; throw new Error('Expected rejection'); }
  catch (error) { assert.equal(typeof error.getStatus, 'function'); assert.equal(error.getStatus(), status); return error; }
}
async function settled(action) {
  try { return { status: 'fulfilled', value: await action }; }
  catch (error) { return { status: 'rejected', error }; }
}
function route(overrides = {}) {
  return { protocol: 1, id: 'kitchen', name: 'Synthetic kitchen', role: 'kitchen', revision: 1,
    enabled: true, destination: { kind: 'tcp', host: 'synthetic-printer.local', port: 9100 },
    capabilityProfile: { protocol: 1, paperWidthMm: 80, rasterWidthDots: 576, language: 'escposRaster',
      cutter: 'partial', encoding: 'georgianViaRaster', beep: { capability: 'unknown', enabled: false } }, ...overrides };
}
function envelope(overrides = {}) {
  return { version: 2, requestId: randomUUID(), expectedRevision: 0, minimumReaderVersion: 2, routes: [route()], ...overrides };
}
async function receipt(requestId, deviceId = ids.device) {
  const rows = await db.$queryRaw`
    SELECT "venueId", "actorType", "actorId", "inputSha256", "expectedRevision", "outcomeStatus",
      "outcome"::text AS "outcomeJson"
    FROM "pos"."DevicePrinterRuntimeRequest" WHERE "deviceId"=${deviceId} AND "requestId"=${requestId}
  `;
  return rows[0] ?? null;
}
async function deviceConfig(deviceId = ids.device) {
  return (await db.device.findUniqueOrThrow({ where: { id: deviceId }, select: { runtimeConfig: true } })).runtimeConfig;
}
async function counts(deviceId = ids.device) {
  const rows = await db.$queryRaw`SELECT count(*)::integer AS count FROM "pos"."DevicePrinterRuntimeRequest" WHERE "deviceId"=${deviceId}`;
  return { journal: rows[0].count,
    customerAudit: await db.customerAuditEvent.count({ where: { targetId: deviceId } }),
    platformAudit: await db.platformAuditEvent.count({ where: { targetId: deviceId } }) };
}
async function nextEnvelope(overrides = {}, deviceId = ids.device) {
  const config = await deviceConfig(deviceId);
  return envelope({ expectedRevision: config.revision, routes: config.routes, ...overrides });
}
async function seed() {
  await db.organization.create({ data: { id: ids.organization, name: `Synthetic printer proof ${ids.organization}` } });
  await db.organization.create({ data: { id: ids.otherOrganization, name: `Synthetic scope proof ${ids.otherOrganization}` } });
  await db.venue.create({ data: { id: ids.otherVenue, organizationId: ids.otherOrganization, name: 'Synthetic scope proof', timezone: 'Asia/Tbilisi', currency: 'GEL' } });
  for (const id of [ids.owner, ids.otherOwner]) {
    await db.customerAccount.create({ data: { id, email: `synthetic-${id}@invalid.example`, displayName: 'Synthetic owner',
      passwordHash: 'synthetic-only-no-login', organizationId: ids.organization } });
    await db.organizationMembership.create({ data: { customerAccountId: id, organizationId: ids.organization, role: 'OWNER' } });
  }
  await db.platformUser.create({ data: { id: ids.platform, email: `synthetic-${ids.platform}@invalid.example`,
    displayName: 'Synthetic platform writer', passwordHash: 'synthetic-only-no-login' } });
  const feature = await db.feature.findUnique({ where: { key: 'POS' } }) ?? await db.feature.create({
    data: { id: randomUUID(), key: 'POS', name: 'Synthetic fixture POS' },
  });
  featureId = feature.id;
  await db.plan.create({ data: { id: ids.plan, key: `synthetic-printer-${ids.plan}`, name: 'Synthetic printer proof',
    features: { create: { featureId } } } });
  await db.venue.create({ data: { id: ids.venue, organizationId: ids.organization, name: 'Synthetic printer proof',
    timezone: 'Asia/Tbilisi', currency: 'GEL', legacyCommercialAccess: false,
    planAssignment: { create: { planId: ids.plan } },
    subscription: { create: { status: 'ACTIVE', billingManaged: true, currentPeriodStart: new Date(Date.now() - 10000),
      currentPeriodEndsAt: new Date(Date.now() + 86400000) } },
  } });
  await db.venueFeatureOverride.create({ data: { venueId: ids.venue, featureId, effect: 'ENABLED', note: 'Synthetic printer proof only' } });
  for (const id of [ids.device, ids.legacyDevice]) await db.device.create({ data: {
    id, venueId: ids.venue, installationId: `synthetic-printer-${id}`, displayName: 'Synthetic POS', platform: 'WINDOWS',
    credentialHash: 'synthetic-only-not-an-enrollment-credential', status: 'REVOKED',
  } });
}
async function actualLegacyWrite(deviceId, printers) {
  return db.$transaction(async (tx) => {
    const device = await persistence.lockPrinterRuntimeDevice(tx, { deviceId, venueId: ids.venue }, owner);
    try { domain.assertLegacyPrinterWriteAllowed(device.runtimeConfig); }
    catch (error) { persistence.throwPrinterRuntimeHttpError(error); }
    const runtimeConfig = { version: 1, printers };
    await tx.device.update({ where: { id: device.id }, data: { runtimeConfig } });
    await tx.customerAuditEvent.create({ data: { customerAccountId: ids.owner, action: 'device.printers_changed',
      targetType: 'Device', targetId: device.id, metadata: { from: device.runtimeConfig, to: runtimeConfig } } });
    return runtimeConfig;
  });
}
function rollbackDatabase(after) {
  return { $transaction: (work) => db.$transaction(async (tx) => {
    const proxy = new Proxy(tx, { get(target, key) {
      if (key === '$executeRaw') return async (strings, ...values) => {
        const result = await target.$executeRaw(strings, ...values);
        const sql = strings.join('?').trim();
        if ((after === 'config' && sql.startsWith('UPDATE "pos"."Device"')) ||
            (after === 'journal' && sql.startsWith('INSERT INTO "pos"."DevicePrinterRuntimeRequest"')))
          throw new Error(`Synthetic rollback injection after ${after}`);
        return result;
      };
      if (key === 'customerAuditEvent' && after === 'audit') return { create: async (args) => {
        await target.customerAuditEvent.create(args); throw new Error('Synthetic rollback injection after audit');
      } };
      const value = Reflect.get(target, key);
      return typeof value === 'function' ? value.bind(target) : value;
    } });
    return work(proxy);
  }) };
}
async function sqlFailure(name, action, sqlState) {
  try { await action(); throw new Error(`Expected SQL failure ${name}`); }
  catch (error) { assert.equal(error.meta?.code, sqlState, `${name}: ${error.message}`); }
  pass(name, { sqlState });
}
async function insertJournal(options = {}) {
  const deviceId = options.deviceId ?? ids.device;
  const requestId = options.requestId ?? randomUUID();
  const venueId = options.venueId ?? ids.venue;
  const outcome = options.outcome ?? { ...(await deviceConfig()), deviceId, venueId };
  return db.$executeRaw`
    INSERT INTO "pos"."DevicePrinterRuntimeRequest"
      ("deviceId","requestId","venueId","actorType","actorId","inputSha256","expectedRevision","outcomeStatus","outcome")
    VALUES (${deviceId},${requestId},${venueId},${options.actorType ?? 'CUSTOMER'},${ids.owner},
      ${options.inputSha256 ?? 'a'.repeat(64)},${options.expectedRevision ?? 0},${options.outcomeStatus ?? 200},
      ${options.outcomeJson ?? JSON.stringify(outcome)}::json)
  `;
}
function deferred() { let resolve; const promise = new Promise((done) => { resolve = done; }); return { promise, resolve }; }
async function assertSqlBlocked(blockingPid, table) {
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    const rows = await db.$queryRaw`
      SELECT pid, wait_event_type AS "waitEventType", pg_blocking_pids(pid) AS blockers
      FROM pg_stat_activity
      WHERE datname = current_database() AND wait_event_type='Lock'
        AND position(${table} in query) > 0 AND pid <> pg_backend_pid()
    `;
    const blocked = rows.find((row) => row.blockers.includes(blockingPid));
    if (blocked) return { waitingPid: blocked.pid, blockingPid, waitEventType: blocked.waitEventType };
    await delay(40);
  }
  throw new Error(`No PostgreSQL lock wait observed for ${table}`);
}
async function holdTransaction(work) {
  const ready = deferred(), release = deferred();
  const completion = db.$transaction(async (tx) => {
    const details = await work(tx);
    ready.resolve(details);
    await release.promise;
  }, { timeout: 15000, maxWait: 5000 });
  // Avoid hanging if the setup failed before publishing readiness.
  const details = await Promise.race([ready.promise, completion.then(() => { throw new Error('Fixture lock setup ended early'); })]);
  return { details, completion, release: release.resolve };
}

async function main() {
  const identity = await db.$queryRaw`SELECT current_database() AS name, current_user AS username, version() AS version,
    host(inet_server_addr()) AS address, inet_server_port() AS port`;
  assert.equal(identity[0].name, 'vynic_readiness');
  assert.equal(identity[0].username, 'postgres');
  assert.equal(identity[0].address, '127.0.0.1');
  assert.equal(identity[0].port, 5432);
  assert.match(identity[0].version, /^PostgreSQL 17\./);
  report.database = identity[0];
  const journalTable = await db.$queryRaw`SELECT to_regclass('pos."DevicePrinterRuntimeRequest"')::text AS table`;
  assert.ok(journalTable[0].table);
  pass('fixture-identity-before-any-write');
  await seed();
  pass('synthetic-bound-owner-platform-device-and-active-subscription-fixtures');

  await rejected(persistence.persistPreparedPrinterRuntimeConfig(db, platform, { deviceId: ids.device, venueId: ids.otherVenue }, envelope()), 404);
  assert.equal(await deviceConfig(), null);
  assert.deepEqual(await counts(), { journal: 0, customerAudit: 0, platformAudit: 0 });
  pass('real-device-venue-row-scope-refuses-cross-venue-device');

  const inputs = [envelope(), envelope(), envelope()];
  const parallel = await Promise.all(inputs.map((input) => settled(persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, input))));
  const successes = parallel.flatMap((row, index) => row.status === 'fulfilled' ? [index] : []);
  assert.equal(successes.length, 1);
  const winnerIndex = successes[0], winner = inputs[winnerIndex], winnerText = JSON.stringify(parallel[winnerIndex].value);
  const conflictIndex = parallel.findIndex((row) => row.status === 'rejected');
  for (const row of parallel.filter((result) => result.status === 'rejected')) assert.equal(row.error.getStatus(), 409);
  assert.deepEqual(await counts(), { journal: 3, customerAudit: 1, platformAudit: 0 });
  assert.equal((await deviceConfig()).revision, 1);
  assert.equal((await receipt(winner.requestId)).outcomeJson, winnerText);
  pass('real-parallel-three-distinct-requests-one-config-and-audit-winner', { accepted: 1, conflicts: 2 });

  const changed = envelope({ expectedRevision: 1, routes: [route({ revision: 2, enabled: false })] });
  await persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, changed);
  assert.equal(JSON.stringify(await persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, winner)), winnerText);
  assert.equal((await deviceConfig()).revision, 2);
  const frozenConflictText = (await receipt(inputs[conflictIndex].requestId)).outcomeJson;
  const retryConflict = await rejected(persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, inputs[conflictIndex]), 409);
  assert.equal(JSON.stringify(retryConflict.getResponse()), frozenConflictText);
  assert.deepEqual(await counts(), { journal: 4, customerAudit: 2, platformAudit: 0 });
  pass('exact-success-and-conflict-retries-after-later-revision');

  const beforeReuse = { config: await deviceConfig(), counts: await counts(), original: await receipt(winner.requestId) };
  await rejected(persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, { ...winner, expectedRevision: 2 }), 409);
  await rejected(persistence.persistPreparedPrinterRuntimeConfig(db, platform, context, winner), 409);
  await rejected(persistence.persistPreparedPrinterRuntimeConfig(db, { customerAccountId: ids.otherOwner }, context, winner), 409);
  assert.deepEqual({ config: await deviceConfig(), counts: await counts(), original: await receipt(winner.requestId) }, beforeReuse);
  pass('changed-input-or-bound-actor-reuse-cannot-change-immutable-receipt');

  const platformInput = await nextEnvelope();
  await persistence.persistPreparedPrinterRuntimeConfig(db, platform, context, platformInput);
  const platformReceipt = await receipt(platformInput.requestId);
  assert.equal(platformReceipt.actorType, 'PLATFORM'); assert.equal(platformReceipt.actorId, ids.platform);
  assert.equal((await counts()).platformAudit, 1);
  pass('separate-platform-identity-and-audit');

  const printers = { kitchen: { enabled: true, host: 'synthetic-legacy.local', port: 9100 }, receipt: { enabled: false, host: '', port: 9100 } };
  const legacyValue = await actualLegacyWrite(ids.legacyDevice, printers);
  assert.deepEqual(legacyValue, { version: 1, printers });
  const legacyContext = { deviceId: ids.legacyDevice, venueId: ids.venue };
  const legacyV2 = await persistence.persistPreparedPrinterRuntimeConfig(db, owner, legacyContext, envelope());
  assert.equal(legacyV2.phase, 'PREPARED');
  const beforeLegacyOverwrite = { config: await deviceConfig(ids.legacyDevice), counts: await counts(ids.legacyDevice) };
  const legacyError = await rejected(actualLegacyWrite(ids.legacyDevice, printers), 409);
  assert.equal(legacyError.getResponse().code, 'LEGACY_PRINTER_WRITE_REJECTED');
  assert.deepEqual({ config: await deviceConfig(ids.legacyDevice), counts: await counts(ids.legacyDevice) }, beforeLegacyOverwrite);
  pass('actual-v1-lock-and-guard-transition-then-overwrite-refusal');

  for (const after of ['config', 'journal', 'audit']) {
    const input = await nextEnvelope();
    const before = { config: await deviceConfig(), counts: await counts() };
    await assert.rejects(persistence.persistPreparedPrinterRuntimeConfig(rollbackDatabase(after), owner, context, input), new RegExp(`injection after ${after}`));
    assert.deepEqual({ config: await deviceConfig(), counts: await counts() }, before);
    assert.equal(await receipt(input.requestId), null);
    await persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, input);
    assert.equal((await receipt(input.requestId)).outcomeStatus, 200);
    pass(`real-atomic-rollback-after-${after}-and-clean-retry`);
  }

  const immutableKey = winner.requestId;
  await sqlFailure('journal-update-trigger', () => db.$executeRaw`UPDATE "pos"."DevicePrinterRuntimeRequest" SET "outcomeStatus"="outcomeStatus" WHERE "deviceId"=${ids.device} AND "requestId"=${immutableKey}`, '55000');
  await sqlFailure('journal-delete-trigger', () => db.$executeRaw`DELETE FROM "pos"."DevicePrinterRuntimeRequest" WHERE "deviceId"=${ids.device} AND "requestId"=${immutableKey}`, '55000');
  await sqlFailure('journal-truncate-trigger', () => db.$executeRaw`TRUNCATE "pos"."DevicePrinterRuntimeRequest"`, '55000');
  await sqlFailure('journal-status-constraint', () => insertJournal({ outcomeStatus: 201 }), '23514');
  await sqlFailure('journal-actor-type-constraint', () => insertJournal({ actorType: 'DEVICE' }), '23514');
  await sqlFailure('journal-sha256-constraint', () => insertJournal({ inputSha256: 'g'.repeat(64) }), '23514');
  await sqlFailure('journal-uuid-constraint', () => insertJournal({ requestId: 'not-a-request-id' }), '23514');
  await sqlFailure('journal-expected-revision-constraint', () => insertJournal({ expectedRevision: -1 }), '23514');
  await sqlFailure('journal-success-identity-constraint', async () => insertJournal({ outcome: { ...(await deviceConfig()), deviceId: randomUUID() } }), '23514');
  await sqlFailure('journal-prepared-only-constraint', async () => insertJournal({ outcome: { ...(await deviceConfig()), phase: 'ACTIVE' } }), '23514');
  await sqlFailure('journal-required-outcome-field-constraint', () => insertJournal({ outcome: {} }), '23514');
  await sqlFailure('journal-json-byte-limit-constraint', async () => insertJournal({ outcome: { ...(await deviceConfig()), padding: 'x'.repeat(262144) } }), '23514');
  await sqlFailure('journal-device-foreign-key', () => insertJournal({ deviceId: randomUUID() }), '23503');
  await sqlFailure('journal-venue-foreign-key', () => insertJournal({ venueId: randomUUID() }), '23503');
  await sqlFailure('journal-device-request-unique-key', () => insertJournal({ requestId: immutableKey }), '23505');
  await sqlFailure('journal-restricts-device-deletion-without-cascade', () => db.$executeRaw`DELETE FROM "pos"."Device" WHERE "id"=${ids.device}`, '23503');
  assert.equal((await receipt(winner.requestId)).outcomeJson, winnerText);

  const heldSubscription = await holdTransaction(async (tx) => {
    await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${ids.venue} FOR UPDATE`;
    const pid = (await tx.$queryRaw`SELECT pg_backend_pid() AS pid`)[0].pid;
    await tx.venueSubscription.update({ where: { venueId: ids.venue }, data: { status: 'SUSPENDED' } });
    return { pid };
  });
  let commercialBlocked;
  const commercialInput = await nextEnvelope();
  const commercialAttempt = settled(persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, commercialInput));
  try {
    commercialBlocked = await assertSqlBlocked(heldSubscription.details.pid, 'Venue');
    assert.equal(await receipt(commercialInput.requestId), null);
  } finally { heldSubscription.release(); await heldSubscription.completion; }
  const commercialResult = await commercialAttempt;
  assert.equal(commercialResult.status, 'rejected'); assert.equal(commercialResult.error.getStatus(), 403);
  assert.equal(await receipt(commercialInput.requestId), null);
  pass('real-venue-subscription-lock-blocks-then-commercial-downgrade-denies', commercialBlocked);
  await db.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${ids.venue} FOR UPDATE`;
    await tx.venueSubscription.update({ where: { venueId: ids.venue }, data: { status: 'ACTIVE' } });
  });

  const heldMembership = await holdTransaction(async (tx) => {
    await tx.$queryRaw`SELECT "customerAccountId", "organizationId" FROM "pos"."OrganizationMembership"
      WHERE "customerAccountId"=${ids.owner} AND "organizationId"=${ids.organization} FOR UPDATE`;
    const pid = (await tx.$queryRaw`SELECT pg_backend_pid() AS pid`)[0].pid;
    await tx.organizationMembership.delete({ where: { customerAccountId_organizationId: { customerAccountId: ids.owner, organizationId: ids.organization } } });
    return { pid };
  });
  let membershipBlocked;
  const membershipInput = await nextEnvelope();
  const membershipAttempt = settled(persistence.persistPreparedPrinterRuntimeConfig(db, owner, context, membershipInput));
  try {
    membershipBlocked = await assertSqlBlocked(heldMembership.details.pid, 'OrganizationMembership');
    assert.equal(await receipt(membershipInput.requestId), null);
  } finally { heldMembership.release(); await heldMembership.completion; }
  const membershipResult = await membershipAttempt;
  assert.equal(membershipResult.status, 'rejected'); assert.equal(membershipResult.error.getStatus(), 404);
  assert.equal(await receipt(membershipInput.requestId), null);
  pass('real-owner-membership-lock-blocks-then-revocation-denies', membershipBlocked);
  await db.organizationMembership.create({ data: { customerAccountId: ids.owner, organizationId: ids.organization, role: 'OWNER' } });

  const current = await deviceConfig();
  for (const header of [undefined, '1', '3', '02', ['2']]) {
    assert.throws(() => persistence.printerRuntimeConfigForReader(current, context, header), (error) => error.getStatus() === 426);
  }
  const read = persistence.printerRuntimeConfigForReader(current, context, '2');
  assert.equal(read.phase, 'PREPARED'); assert.equal(read.deviceId, ids.device);
  assert.throws(() => persistence.printerRuntimeConfigForReader(current, { deviceId: ids.legacyDevice, venueId: ids.venue }, '2'), (error) => error.getStatus() === 503);
  assert.equal(persistence.printerRuntimeConfigForReader(null, context, undefined), null);
  const v1Read = { version: 1, printers }; assert.equal(persistence.printerRuntimeConfigForReader(v1Read, context, undefined), v1Read);
  pass('bound-reader-header-compatibility-with-prepared-hold-and-v1-read-preservation');
  const lifecycle = await db.device.findUniqueOrThrow({ where: { id: ids.device }, select: { status: true, credentialHash: true } });
  assert.deepEqual(lifecycle, { status: 'REVOKED', credentialHash: 'synthetic-only-not-an-enrollment-credential' });
  pass('no-device-credential-lifecycle-or-activation-mutation');

  report.final = { revision: current.revision, phase: current.phase, counts: await counts(), legacyCounts: await counts(ids.legacyDevice) };
  report.status = 'PASS';
}

main().catch((error) => {
  report.status = 'FAIL'; report.error = { name: error.name, message: error.message, code: error.code, meta: error.meta };
  console.error(error.stack); process.exitCode = 1;
}).finally(async () => {
  await db.$disconnect();
  console.log(`PROOF_RESULT_JSON=${JSON.stringify(report)}`);
});
