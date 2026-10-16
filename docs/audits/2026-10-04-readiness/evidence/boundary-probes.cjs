// Read-only audit probes: actual service methods, in-memory fakes, no DB/network.
// Run from repo root: node docs/audits/2026-10-04-readiness/evidence/boundary-probes.cjs
const path = require('node:path');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const backend = path.resolve(__dirname, '../../../../apps/backend');
const req = createRequire(path.join(backend, 'package.json'));
req('ts-node').register({ project: path.join(backend, 'tsconfig.json'), transpileOnly: true });
req('reflect-metadata');
const { MobileDashboardService } = req('./src/mobile/services/mobile-dashboard.service.ts');
const { MobileOrdersService } = req('./src/mobile/services/mobile-orders.service.ts');
const { ReservationService } = req('./src/website/reservation/reservation.service.ts');
const tenant = { venueId: 'audit-venue', organizationId: 'audit-org' };
const results = [];
(async () => {
  let dispatches = 0;
  const table = { isReserved: true, activeOrderId: 42, currentBill: 17 };
  const cloud = { table: { updateMany: async ({ data }) => { Object.assign(table, data); return { count: 1 }; } } };
  const service = new MobileDashboardService(cloud, { broadcastUpdate() {} }, { dispatch() { dispatches++; } }, { registerMobileMutationEchoGuard() {}, wsExcludeOpts() {} });
  assert.deepEqual(await service.freeTable(tenant, '1', 'first'), { success: true });
  assert.equal(dispatches, 0);
  assert.equal(table.activeOrderId, null);
  results.push({ id: 'MGR-02', reproduced: true, result: 'Cloud table cleared and success returned; zero POS dispatches.' });

  const rows = [{ name: 'Existing', quantity: 2, price: 10 }];
  let deletes = 0;
  const db = {
    order: { findUnique: async () => ({ id: 'audit-order', posOrderId: 42 }) },
    orderItem: {
      findMany: async () => [...rows],
      deleteMany: async () => { deletes++; rows.splice(0); },
      create: async () => { throw new Error('synthetic create failure'); },
    },
  };
  const orders = new MobileOrdersService(db, {}, {}, {});
  await assert.rejects(orders.updateOrder(tenant, '42', undefined, { items: [{ name: 'Replacement' }] }), /synthetic create failure/);
  assert.equal(deletes, 1); assert.equal(rows.length, 0);
  results.push({ id: 'MGR-05', reproduced: true, result: 'Failure creating replacement leaves the previously deleted lines absent; no transaction boundary requested.' });

  let pushes = 0;
  const booking = { id: 'audit-booking', venueId: tenant.venueId, venue: { organizationId: tenant.organizationId }, paymentIntegrationId: 'audit-integration', paymentId: 'audit-payment', status: 'PENDING', posReservationId: null, tables: [] };
  const reservations = new ReservationService({ websiteReservation: {
    findUnique: async () => structuredClone(booking),
    update: async ({ data }) => { Object.assign(booking, data); return structuredClone(booking); },
  } }, {}, { pushConfirmedReservationToPos: async () => {
    pushes++;
    // Matches bridge source ordering: persist link first, then enqueue command.
    booking.posReservationId = 'audit-pos-reservation';
    throw new Error('synthetic enqueue failure after link persisted');
  } });
  reservations.logger = { error() {} };
  await reservations.updateReservationPaymentStatus(booking.id, 'completed', 'synthetic', booking.paymentId);
  await reservations.updateReservationPaymentStatus(booking.id, 'completed', 'synthetic retry', booking.paymentId);
  assert.equal(booking.status, 'CONFIRMED'); assert.equal(pushes, 1);
  results.push({ id: 'WEB-03', reproduced: true, result: 'Persisted link plus enqueue failure leaves confirmed booking; duplicate outcome does not retry bridge.' });
  await reservations.updateReservationPaymentStatus(booking.id, 'pending', 'synthetic delayed status', booking.paymentId);
  assert.equal(booking.status, 'PENDING');
  results.push({ id: 'WEB-04', reproduced: true, result: 'Delayed pending outcome overwrites CONFIRMED; service has no monotonic transition check.' });
  console.log(JSON.stringify({ scope: 'Actual current service code with in-memory fakes; not PostgreSQL/provider/HTTP proof', results }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
