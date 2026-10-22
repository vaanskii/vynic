// Only invoked by prove_mgr06_postgres.py against its newly-created cluster.
import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [mode, output] = process.argv.slice(2);
const url = new URL(process.env.DATABASE_URL);
assert.equal(url.hostname, '127.0.0.1');
assert.equal(url.pathname, '/disposable_mgr06_upgrade_20261007');
const db = new PrismaClient();
const tables = [
  'PayrollPeriod',
  'PayrollAccrual',
  'PayrollPayment',
  'FinancialObligation',
  'ObligationCycle',
  'ObligationReserveEntry',
  'ObligationPayment',
  'AuditEventLog',
];
async function snapshot() {
  const result = {};
  for (const table of tables) {
    result[table] = await db.$queryRawUnsafe(
      `SELECT to_jsonb(t) - 'reversalOfId' - 'correctionBusinessDate' AS row FROM pos."${table}" t ORDER BY id`,
    );
  }
  return result;
}
try {
  if (mode === 'before') {
    const org = await db.organization.create({
      data: { name: 'MGR06 synthetic pre-upgrade' },
    });
    const venue = await db.venue.create({
      data: {
        organizationId: org.id,
        name: 'Synthetic only',
        timezone: 'Asia/Tbilisi',
        currency: 'GEL',
      },
    });
    const staff = await db.staff.create({
      data: {
        venueId: venue.id,
        username: 'Synthetic historical employee',
        role: 'MANAGER',
        pinHash: 'synthetic-unused',
      },
    });
    const period = await db.payrollPeriod.create({
      data: {
        venueId: venue.id,
        staffId: staff.id,
        staffName: staff.username,
        periodMonth: '2026-09',
        compensationType: 'MONTHLY_FIXED',
        rate: '1500.00',
        targetAmount: '1500.00',
      },
    });
    await db.payrollAccrual.create({
      data: {
        id: randomUUID(),
        venueId: venue.id,
        payrollPeriodId: period.id,
        amount: '25.00',
        notes: 'Historical accrual unchanged',
        actorId: staff.id,
        actorName: staff.username,
      },
    });
    const obligation = await db.financialObligation.create({
      data: {
        venueId: venue.id,
        name: 'Synthetic rent',
        type: 'RENT',
        monthlyAmount: '3000.00',
        dueDay: 30,
        startsOn: '2026-09-01',
      },
    });
    const cycle = await db.obligationCycle.create({
      data: {
        venueId: venue.id,
        obligationId: obligation.id,
        name: obligation.name,
        type: obligation.type,
        periodMonth: '2026-09',
        targetAmount: '3000.00',
        dueDate: '2026-09-30',
      },
    });
    const payroll = randomUUID(),
      reserve = randomUUID(),
      payment = randomUUID(),
      zero = randomUUID();
    await db.$executeRaw`INSERT INTO pos."PayrollPayment" (id,"venueId","payrollPeriodId",amount,"businessDate","paymentDate",notes,"actorId","actorName") VALUES (${payroll},${venue.id},${period.id},120.34,'2026-09-15','2026-09-15','Historical payroll note',${staff.id},${staff.username}), (${zero},${venue.id},${period.id},0,'2026-09-15','2026-09-15',NULL,${staff.id},${staff.username})`;
    await db.$executeRaw`INSERT INTO pos."ObligationReserveEntry" (id,"venueId","obligationCycleId",amount,"businessDate",notes,"actorId","actorName") VALUES (${reserve},${venue.id},${cycle.id},100.00,'2026-09-15','Historical reserve note',${staff.id},${staff.username})`;
    await db.$executeRaw`INSERT INTO pos."ObligationPayment" (id,"venueId","obligationCycleId",amount,"reserveConsumed","businessDate","paymentDate",notes,"actorId","actorName") VALUES (${payment},${venue.id},${cycle.id},80.00,80.00,'2026-09-15','2026-09-15','Historical payment note',${staff.id},${staff.username})`;
    await db.auditEventLog.create({
      data: {
        venueId: venue.id,
        action: 'PAYROLL_PAYMENT_CREATED',
        entityType: 'PAYROLL_PAYMENT',
        entityId: payroll,
        userId: staff.id,
        deviceType: 'manager',
        data: {
          entryId: payroll,
          amount: '120.34',
          actorId: staff.id,
          reason: 'Historical audit unchanged',
        },
      },
    });
    fs.writeFileSync(
      output,
      JSON.stringify(
        {
          ids: {
            venue: venue.id,
            staff: staff.id,
            payroll,
            reserve,
            payment,
            zero,
            period: period.id,
            cycle: cycle.id,
          },
          snapshot: await snapshot(),
        },
        null,
        2,
      ) + '\n',
    );
    console.log(
      'PASS seeded representative pre-correction rows: positive/zero payroll, accrual, consumed reserve/payment, original audit',
    );
  } else if (mode === 'after') {
    const before = JSON.parse(fs.readFileSync(output, 'utf8'));
    assert.deepEqual(await snapshot(), before.snapshot);
    for (const table of [
      'PayrollPayment',
      'ObligationPayment',
      'ObligationReserveEntry',
    ]) {
      const rows = await db.$queryRawUnsafe(
        `SELECT "reversalOfId", "correctionBusinessDate" FROM pos."${table}"`,
      );
      assert(
        rows.every(
          (r) => r.reversalOfId === null && r.correctionBusinessDate === null,
        ),
      );
    }
    fs.writeFileSync(
      output.replace('.json', '-preserved.json'),
      JSON.stringify(
        {
          status: 'PASS',
          originalTables: tables.length,
          originalRows: Object.values(before.snapshot).reduce(
            (n, v) => n + v.length,
            0,
          ),
          allOriginalFieldsUnchanged: true,
          addedFieldsNull: true,
        },
        null,
        2,
      ) + '\n',
    );
    console.log(
      'PASS all original financial/audit fields unchanged after additive upgrade; added fields null',
    );
  } else throw Error('Invalid upgrade fixture mode');
} finally {
  await db.$disconnect();
}
