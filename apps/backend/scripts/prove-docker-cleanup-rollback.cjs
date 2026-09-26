/** Non-persistent DB proof. Every write runs inside one transaction which always
 * throws; no fixtures, deletions, accounts or audit rows are committed. No files
 * are written: fail before the reset if any owned/legacy media exists. */
const assert = require('node:assert/strict');
const { randomUUID: uuid } = require('node:crypto');
const { PrismaClient } = require('@prisma/client');
const {
  requireLocalDocker,
} = require('./dist/src/local-tools/local-docker-guard');
const { cleanupCustomers } = require('./dist/src/local-tools/customer-cleanup');
const {
  delegate,
  preservedModels,
  venueModels,
} = require('./dist/src/local-tools/deletion-matrix');
requireLocalDocker();
const db = new PrismaClient();
const ROLLBACK = new Error('EXPECTED_PROOF_ROLLBACK');
async function main() {
  const original = [
    await db.venue.count(),
    await db.organization.count(),
    await db.platformUser.count(),
  ];
  try {
    await db.$transaction(
      async (tx) => {
        // cleanupCustomers uses the enclosing transaction: its apparent inner
        // commit cannot commit this transaction, which unconditionally rolls back.
        const enclosed = { $transaction: (callback) => callback(tx) };
        const preview = await cleanupCustomers(enclosed, { kind: 'all' }, true);
        assert.equal(
          preview.mediaFiles.length,
          0,
          'This no-files proof needs no existing owned/legacy media',
        );
        const admin = await tx.platformUser.findFirst();
        assert(
          admin,
          'An existing admin is needed for transactional audit FK proof',
        );
        const a = await tx.organization.create({
          data: { name: 'Rollback proof A' },
        });
        const b = await tx.organization.create({
          data: { name: 'Rollback proof B' },
        });
        const venue = (org, name) =>
          tx.venue.create({
            data: {
              organizationId: org.id,
              name,
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
          });
        const av = await venue(a, 'Rollback venue A1'),
          av2 = await venue(a, 'Rollback venue A2'),
          bv = await venue(b, 'Rollback venue B');
        const account = (name, orgs) =>
          tx.customerAccount.create({
            data: {
              organizationId: a.id,
              email: `${uuid()}@example.invalid`,
              displayName: name,
              passwordHash: 'not-a-credential',
              memberships: {
                create: orgs.map((organizationId) => ({ organizationId })),
              },
            },
          });
        const shared = await account('Shared', [a.id, b.id]),
          only = await account('Only A', [a.id]);
        const websiteUser = await tx.websiteUser.create({
          data: {
            phone: uuid(),
            password: 'not-a-credential',
            adminVenueId: av.id,
          },
        });
        for (const v of [av, bv])
          await tx.websiteReservation.create({
            data: {
              venueId: v.id,
              userId: websiteUser.id,
              date: new Date(),
              timeSlot: '12:00',
            },
          });
        const staff = await tx.staff.create({
          data: { venueId: av.id, username: uuid(), pinHash: 'proof' },
        });
        const period = await tx.payrollPeriod.create({
          data: {
            venueId: av.id,
            staffId: staff.id,
            staffName: 'Proof',
            periodMonth: '2026-09',
            compensationType: 'DAILY_FIXED',
            rate: 10,
            targetAmount: 10,
          },
        });
        const accrual = {
          venueId: av.id,
          payrollPeriodId: period.id,
          amount: 10,
          actorId: staff.id,
          actorName: 'Proof',
        };
        const base = await tx.payrollAccrual.create({
          data: { id: uuid(), ...accrual, payableDate: '2026-09-26' },
        });
        await tx.payrollAccrual.create({
          data: { id: uuid(), ...accrual, dayEntryId: base.id, amount: -1 },
        });
        const receipt = await tx.receiving.create({
          data: {
            venueId: av.id,
            supplierNameSnapshot: 'Proof',
            sourceType: 'SELF_PURCHASE',
            documentDate: '2026-09-26',
            businessDate: '2026-09-26',
            receivedAt: new Date(),
            createdById: staff.id,
            createdByName: 'Proof',
          },
        });
        const pay = {
          venueId: av.id,
          receivingId: receipt.id,
          amount: 1,
          paymentDate: '2026-09-26',
          businessDate: '2026-09-26',
          method: 'CASH',
          actorId: staff.id,
          actorName: 'Proof',
        };
        const payment = await tx.supplierPayment.create({
          data: { ...pay, requestId: uuid() },
        });
        await tx.supplierPayment.create({
          data: {
            ...pay,
            requestId: uuid(),
            amount: -1,
            reversalOfId: payment.id,
          },
        });
        const target = {
          kind: 'venue',
          id: av.id,
          confirmation: `DELETE ${av.name}`,
          actorId: admin.id,
        };
        await assert.rejects(
          cleanupCustomers(enclosed, { ...target, confirmation: 'Wrong' }),
        );
        const dry = await cleanupCustomers(enclosed, { kind: 'all' }, true);
        assert(dry.deleted.Venue >= 3);
        assert.equal(
          await tx.payrollAccrual.count({ where: { venueId: av.id } }),
          2,
        );
        await cleanupCustomers(enclosed, target);
        assert.equal(await tx.venue.findUnique({ where: { id: av.id } }), null);
        assert(await tx.venue.findUnique({ where: { id: av2.id } }));
        assert(await tx.venue.findUnique({ where: { id: bv.id } }));
        assert(await tx.organization.findUnique({ where: { id: a.id } }));
        assert(await tx.customerAccount.findUnique({ where: { id: only.id } }));
        assert(
          await tx.websiteUser.findUnique({ where: { id: websiteUser.id } }),
        );
        assert.equal(
          await tx.websiteReservation.count({ where: { venueId: bv.id } }),
          1,
        );
        console.log(
          'PASS transactional venue isolation, shared WebsiteUser, payroll adjustments and supplier reversal chains',
        );
        await cleanupCustomers(enclosed, {
          kind: 'organization',
          id: a.id,
          confirmation: `DELETE ${a.name}`,
          actorId: admin.id,
        });
        assert.equal(
          await tx.customerAccount.findUnique({ where: { id: only.id } }),
          null,
        );
        assert.equal(
          (await tx.customerAccount.findUnique({ where: { id: shared.id } }))
            .organizationId,
          null,
        );
        assert.equal(
          await tx.organizationMembership.count({
            where: { customerAccountId: shared.id, organizationId: b.id },
          }),
          1,
        );
        assert.equal(
          await tx.platformAuditEvent.count({
            where: {
              action: 'LOCAL_TEST_DATA_DELETED',
              targetId: { in: [av.id, a.id] },
            },
          }),
          2,
        );
        console.log(
          'PASS transactional organization ownership, shared account, retained audit',
        );
        const snapshot = async () => {
          const out = {};
          for (const m of preservedModels)
            out[m] = await tx[m[0].toLowerCase() + m.slice(1)].findMany();
          return JSON.stringify(out);
        };
        const control = await snapshot();
        await cleanupCustomers(enclosed, { kind: 'all' });
        for (const m of [
          ...venueModels,
          'Venue',
          'Organization',
          'CustomerAccount',
          'WebsiteUser',
        ])
          assert.equal(await delegate(tx, m).count(), 0, m);
        assert.equal(await snapshot(), control);
        console.log(
          'PASS full deletion inside rollback transaction preserves all control-plane rows',
        );
        throw ROLLBACK;
      },
      { timeout: 60000 },
    );
  } catch (error) {
    if (error !== ROLLBACK) throw error;
  }
  assert.deepEqual(
    [
      await db.venue.count(),
      await db.organization.count(),
      await db.platformUser.count(),
    ],
    original,
  );
  console.log(
    'PASS outer transaction rolled back; original local data preserved',
  );
}
main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());
