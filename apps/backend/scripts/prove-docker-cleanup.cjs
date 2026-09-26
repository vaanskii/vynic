/** Explicit destructive proof, only inside isolated Docker. Run after consent:
 * ./scripts/docker.sh exec -T backend node - --confirm-local < apps/backend/scripts/prove-docker-cleanup.cjs
 * Deletes ALL customer test data, preserves existing admins, and reseeds samples.
 */
const assert = require('node:assert/strict');
const { randomUUID: uuid } = require('node:crypto');
const fs = require('node:fs/promises');
const { spawnSync } = require('node:child_process');
const { PrismaClient } = require('@prisma/client');
const argon2 = require('argon2');
const {
  requireLocalDocker,
} = require('./dist/src/local-tools/local-docker-guard');
const {
  cleanupCustomers,
  cleanupMedia,
} = require('./dist/src/local-tools/customer-cleanup');
const {
  preservedModels,
  delegate,
  venueModels,
} = require('./dist/src/local-tools/deletion-matrix');
requireLocalDocker();
if (process.argv[2] !== '--confirm-local')
  throw new Error('Destructive proof requires --confirm-local');
const db = new PrismaClient();
const check = (m) => console.log('PASS', m);
async function api(path, token, body) {
  const r = await fetch('http://127.0.0.1:3000/platform/' + path, {
    method: body ? 'POST' : 'GET',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { status: r.status, body: await r.json() };
}
async function snapshot() {
  const result = {};
  for (const m of preservedModels) {
    if (m === 'PlatformAuditEvent') continue;
    result[m] = await db[m[0].toLowerCase() + m.slice(1)].findMany({
      orderBy:
        m === 'PlanFeature'
          ? [{ planId: 'asc' }, { featureId: 'asc' }]
          : { id: 'asc' },
    });
  }
  result.migrations = await db.$queryRawUnsafe(
    'SELECT migration_name, checksum, finished_at FROM "public"."_prisma_migrations" ORDER BY migration_name',
  );
  return JSON.stringify(result);
}
async function venue(org, name) {
  return db.venue.create({
    data: {
      organizationId: org.id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    },
  });
}
function cli(script, ...args) {
  const r = spawnSync('node', [`dist/scripts/${script}.js`, ...args], {
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(script === 'reset-docker-customers' ? r.stdout : '{}');
}
async function run() {
  const password = uuid() + uuid();
  const admin = await db.platformUser.create({
    data: {
      email: `cleanup-proof-${uuid()}@example.invalid`,
      displayName: 'Temporary cleanup proof',
      passwordHash: await argon2.hash(password),
    },
  });
  try {
    const login = await api('auth/login', null, {
      email: admin.email,
      password,
    });
    assert.equal(login.status, 201);
    const token = login.body.access_token;
    const a = await db.organization.create({
      data: { name: 'Cleanup proof A' },
    });
    const b = await db.organization.create({
      data: { name: 'Cleanup proof B' },
    });
    const av = await venue(a, 'Cleanup proof A1'),
      av2 = await venue(a, 'Cleanup proof A2'),
      bv = await venue(b, 'Cleanup proof B1');
    const account = (name, organizations) =>
      db.customerAccount.create({
        data: {
          organizationId: a.id,
          email: `${uuid()}@example.invalid`,
          displayName: name,
          passwordHash: 'disabled-proof',
          memberships: {
            create: organizations.map((organizationId) => ({ organizationId })),
          },
        },
      });
    const shared = await account('Shared owner', [a.id, b.id]),
      only = await account('Only A', [a.id]);
    const web = await db.websiteUser.create({
      data: { phone: uuid(), password: 'disabled-proof', adminVenueId: av.id },
    });
    for (const v of [av, bv])
      await db.websiteReservation.create({
        data: {
          venueId: v.id,
          userId: web.id,
          date: new Date(),
          timeSlot: '12:00',
        },
      });
    const keys = [uuid() + '.webp', uuid() + '.webp'];
    for (const [i, v] of [av, bv].entries()) {
      await db.websiteMediaAsset.create({
        data: {
          venueId: v.id,
          storageKey: keys[i],
          purpose: 'proof',
          byteSize: 4,
        },
      });
      await fs.writeFile('/var/lib/vynic/media/' + keys[i], 'test');
    }
    const unrelated = '/var/lib/vynic/media/cleanup-proof-unrelated.txt';
    await fs.writeFile(unrelated, 'unrelated');
    const staff = await db.staff.create({
      data: { venueId: av.id, username: uuid(), pinHash: 'proof' },
    });
    const period = await db.payrollPeriod.create({
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
    const accrualData = {
      venueId: av.id,
      payrollPeriodId: period.id,
      amount: 10,
      actorId: staff.id,
      actorName: 'Proof',
    };
    const accrual = await db.payrollAccrual.create({
      data: { id: uuid(), ...accrualData, payableDate: '2026-09-26' },
    });
    await db.payrollAccrual.create({
      data: { id: uuid(), ...accrualData, dayEntryId: accrual.id, amount: -1 },
    });
    const stock = await db.stockItem.create({
      data: { venueId: av.id, name: 'Proof stock', baseUnit: 'kg' },
    });
    const receipt = async (v) =>
      db.receiving.create({
        data: {
          venueId: v.id,
          supplierNameSnapshot: 'Proof',
          sourceType: 'SELF_PURCHASE',
          documentDate: '2026-09-26',
          businessDate: '2026-09-26',
          receivedAt: new Date(),
          createdById: staff.id,
          createdByName: 'Proof',
        },
      });
    const receiving = await receipt(av),
      foreign = await receipt(bv);
    const paymentData = {
      venueId: av.id,
      receivingId: receiving.id,
      amount: 1,
      paymentDate: '2026-09-26',
      businessDate: '2026-09-26',
      method: 'CASH',
      actorId: staff.id,
      actorName: 'Proof',
    };
    const payment = await db.supplierPayment.create({
      data: { ...paymentData, requestId: uuid() },
    });
    await db.supplierPayment.create({
      data: {
        ...paymentData,
        requestId: uuid(),
        amount: -1,
        reversalOfId: payment.id,
      },
    });
    const foreignLine = await db.receivingLine.create({
      data: {
        receivingId: foreign.id,
        lineSequence: 1,
        stockItemId: stock.id,
        stockItemNameSnapshot: 'Proof',
        enteredQuantity: 1,
        enteredUnit: 'kg',
        baseQuantity: 1,
        baseUnit: 'kg',
        unitPurchaseCost: 1,
        lineTotal: 1,
        effectiveBaseUnitCost: 1,
      },
    });
    const before = await snapshot();
    const dry = cli('reset-docker-customers', '--dry-run');
    assert(dry.deleted.Venue >= 3);
    assert.equal(await snapshot(), before);
    check('dry-run reports fixtures and leaves control-plane rows identical');
    assert.equal(
      (
        await api(`developer-tools/venues/${av.id}/delete`, null, {
          confirmation: `DELETE ${av.name}`,
        })
      ).status,
      401,
    );
    assert.equal(
      (
        await api(`developer-tools/venues/${av.id}/delete`, token, {
          confirmation: 'DELETE Wrong',
        })
      ).status,
      400,
    );
    await assert.rejects(
      cleanupCustomers(db, {
        kind: 'venue',
        id: av.id,
        confirmation: `DELETE ${av.name}`,
        actorId: admin.id,
      }),
    );
    assert.equal(
      await db.supplierPayment.count({ where: { venueId: av.id } }),
      2,
    );
    assert.equal(
      await db.payrollAccrual.count({ where: { venueId: av.id } }),
      2,
    );
    assert.equal((await cleanupMedia(db)).removed, 0);
    await fs.stat('/var/lib/vynic/media/' + keys[0]);
    check('late FK failure rolls back previous deletes and retains media');
    await db.receivingLine.delete({ where: { id: foreignLine.id } });
    const result = await api(`developer-tools/venues/${av.id}/delete`, token, {
      confirmation: `DELETE ${av.name}`,
    });
    assert.equal(result.status, 201, JSON.stringify(result.body));
    assert.equal(result.body.mediaCleanup.failures.length, 0);
    assert.equal(await db.venue.findUnique({ where: { id: av.id } }), null);
    for (const v of [av2, bv])
      assert(await db.venue.findUnique({ where: { id: v.id } }));
    assert(await db.organization.findUnique({ where: { id: a.id } }));
    assert(await db.customerAccount.findUnique({ where: { id: only.id } }));
    assert(await db.websiteUser.findUnique({ where: { id: web.id } }));
    assert.equal(
      await db.websiteReservation.count({ where: { venueId: bv.id } }),
      1,
    );
    await assert.rejects(fs.stat('/var/lib/vynic/media/' + keys[0]));
    await fs.stat('/var/lib/vynic/media/' + keys[1]);
    await fs.stat(unrelated);
    check(
      'venue-only deletion isolates other venues and preserves shared identities and unrelated media',
    );
    const org = await api(
      `developer-tools/organizations/${a.id}/delete`,
      token,
      { confirmation: `DELETE ${a.name}` },
    );
    assert.equal(org.status, 201, JSON.stringify(org.body));
    assert.equal(
      await db.customerAccount.findUnique({ where: { id: only.id } }),
      null,
    );
    assert.equal(
      (await db.customerAccount.findUnique({ where: { id: shared.id } }))
        .organizationId,
      null,
    );
    assert.equal(
      await db.organizationMembership.count({
        where: { customerAccountId: shared.id, organizationId: b.id },
      }),
      1,
    );
    assert.equal(
      await db.platformAuditEvent.count({
        where: { platformUserId: admin.id, action: 'LOCAL_TEST_DATA_DELETED' },
      }),
      2,
    );
    check(
      'organization deletion preserves multi-organization owner and writes durable Platform audit',
    );
    const control = await snapshot();
    cli('reset-docker-customers', '--confirm-local');
    for (const m of [
      ...venueModels,
      'Venue',
      'Organization',
      'CustomerAccount',
      'WebsiteUser',
      'OnboardingRequest',
      'CustomerAuditEvent',
      'OwnerInvitation',
      'OrganizationMembership',
    ])
      assert.equal(await delegate(db, m).count(), 0, m);
    assert.equal(await snapshot(), control);
    assert.equal((await api('auth/me', token)).status, 200);
    assert.equal(
      (await api('auth/login', null, { email: admin.email, password })).status,
      201,
    );
    await assert.rejects(fs.stat('/var/lib/vynic/media/' + keys[1]));
    await fs.stat(unrelated);
    check(
      'full reset deletes customer state, preserves exact admin/catalog/config/migrations and permits admin login',
    );
    cli('seed-docker-local', '--confirm-local');
    assert.equal(await db.venue.count(), 2);
    check('explicit reseed recreates samples');
    await fs.unlink(unrelated);
    assert.equal((await cleanupMedia(db)).failures.length, 0);
    check('cleanup retry safely resolves earlier rollback manifest');
  } finally {
    await db.platformAuditEvent.updateMany({
      where: { platformUserId: admin.id },
      data: { platformUserId: null },
    });
    await db.platformUser.delete({ where: { id: admin.id } });
  }
}
run()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());
