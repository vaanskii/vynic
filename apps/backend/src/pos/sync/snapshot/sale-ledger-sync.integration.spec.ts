import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Body, Controller, Post } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { PrismaService } from '../../../prisma.service';
import type { TenantContext } from '../../../tenancy/tenant-context';
import type { SaleLedgerSync } from '../sync-payload';
import { MobileSaleLedgerService } from '../../../mobile/services/mobile-sale-ledger.service';
import { SaleLedgerSyncService } from './sale-ledger-sync.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

function sale(
  id: string,
  overrides: Partial<SaleLedgerSync> = {},
): SaleLedgerSync {
  return {
    posSaleId: id,
    posOrderId: Number(id.replace(/\D/g, '')) || 1,
    closureId: `closure-${id}`,
    businessDate: '2026-09-04',
    createdAt: '2026-09-04T10:00:00.000Z',
    closedAt: '2026-09-04T10:30:00.000Z',
    gross: '100.00',
    subtotal: '90.91',
    serviceFee: '9.09',
    discount: '0.00',
    manualAdjustment: '0.00',
    advanceApplied: '0.00',
    amountDueNow: '100.00',
    collectedNow: '100.00',
    paymentMethod: 'cash',
    isFiscal: true,
    isCancelled: false,
    restoredToOrder: false,
    createdBy: 'waiter',
    closedById: 'manager-a',
    tableNumbers: ['1'],
    floor: 'first',
    revision: 1,
    sourceUpdatedAt: '2026-09-04T10:30:00.000Z',
    lines: [
      {
        lineSeq: 0,
        menuItemId: 'menu-stable',
        variantId: 'variant-stable',
        itemName: 'Original name',
        variantName: 'Large',
        quantity: 1,
        unitPrice: '100.00',
        lineTotal: '100.00',
      },
    ],
    payments: [{ method: 'cash', amount: '100.00' }],
    ...overrides,
  };
}

describeDatabase('Cloud Sale ledger (PostgreSQL)', () => {
  let prisma: PrismaService;
  let sync: SaleLedgerSyncService;
  let queries: MobileSaleLedgerService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `5a000000-0000-4000-8000-${suffix}`;
  const venueA: TenantContext = {
    venueId: `5a000001-0000-4000-8000-${suffix}`,
    organizationId,
  };
  const venueB: TenantContext = {
    venueId: `5a000002-0000-4000-8000-${suffix}`,
    organizationId,
  };

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Sale ledger fixture',
        venues: {
          create: [
            {
              id: venueA.venueId,
              name: 'Venue A',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
            {
              id: venueB.venueId,
              name: 'Venue B',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
          ],
        },
      },
    });
    sync = new SaleLedgerSyncService(prisma);
    queries = new MobileSaleLedgerService(prisma);
  });

  afterEach(async () => {
    const venueIds = [venueA.venueId, venueB.venueId];
    await prisma.cloudSale.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.saleLedgerDay.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.auditReport.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.setting.deleteMany({ where: { venueId: { in: venueIds } } });
  });

  afterAll(async () => {
    await prisma.venue.deleteMany({ where: { organizationId } });
    await prisma.organization.deleteMany({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  it.each([
    ['cash', [{ method: 'cash', amount: '100.00' }]],
    ['card-tbc', [{ method: 'card-tbc', amount: '100.00' }]],
    ['card-bog', [{ method: 'card-bog', amount: '100.00' }]],
    [
      'split',
      [
        { method: 'cash', amount: '40.00' },
        { method: 'card-tbc', amount: '60.00' },
      ],
    ],
  ])('creates an exact %s Sale', async (method, payments) => {
    await sync.sync(
      venueA,
      [sale(`sale-${method}`, { paymentMethod: method, payments })],
      [],
    );
    const stored = await prisma.cloudSale.findFirstOrThrow({
      where: { venueId: venueA.venueId },
      include: { payments: true, lines: true },
    });
    expect(stored.gross.toFixed(2)).toBe('100.00');
    expect(stored.payments).toHaveLength(payments.length);
    expect(stored.lines).toHaveLength(1);
  });

  it('persists advance plus final payment and exact decimal arithmetic', async () => {
    await sync.sync(
      venueA,
      [
        sale('sale-advance', {
          gross: '0.30',
          subtotal: '0.30',
          serviceFee: '0.00',
          advanceApplied: '0.10',
          amountDueNow: '0.20',
          collectedNow: '0.20',
          payments: [
            { method: 'cash', amount: '0.20' },
            { method: 'advance', amount: '0.10' },
          ],
          lines: [
            {
              lineSeq: 0,
              itemName: 'Exact',
              quantity: 3,
              unitPrice: '0.10',
              lineTotal: '0.30',
            },
          ],
        }),
      ],
      [],
    );
    const stored = await prisma.cloudSale.findFirstOrThrow({
      where: { venueId: venueA.venueId },
      include: { payments: true },
    });
    expect(stored.gross.toFixed(2)).toBe('0.30');
    expect(
      stored.payments
        .reduce(
          (sum, part) => sum.plus(part.amount),
          stored.gross.minus(stored.gross),
        )
        .toFixed(2),
    ).toBe('0.30');
  });

  it('rejects floating wire values and broken money equations', async () => {
    await expect(
      sync.sync(
        venueA,
        [sale('sale-float', { gross: '0.30000000000000004' })],
        [],
      ),
    ).rejects.toThrow('fixed two-decimal string');
    await expect(
      sync.sync(venueA, [sale('sale-mismatch', { gross: '100.01' })], []),
    ).rejects.toThrow('gross must equal');
    await expect(
      sync.sync(
        venueA,
        [
          sale('sale-payments', {
            payments: [{ method: 'cash', amount: '99.99' }],
          }),
        ],
        [],
      ),
    ).rejects.toThrow('Tender payment parts');
    expect(
      await prisma.cloudSale.count({ where: { venueId: venueA.venueId } }),
    ).toBe(0);
  });

  it('stores internal close history while excluding it from revenue', async () => {
    await sync.sync(
      venueA,
      [
        sale('sale-internal', {
          isFiscal: false,
          paymentMethod: 'non-fiscal',
          collectedNow: '0.00',
          payments: [],
        }),
      ],
      [],
    );
    const summary = await queries.getSummary(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(summary.revenue).toBe('0.00');
    expect(summary.internalCount).toBe(1);
    expect(summary.internalValue).toBe('100.00');
  });

  it('is idempotent for the Sale, lines, payments and repeated revision', async () => {
    const payload = sale('sale-idempotent');
    for (let attempt = 0; attempt < 10; attempt++) {
      await sync.sync(venueA, [payload], []);
    }
    expect(
      await prisma.cloudSale.count({ where: { venueId: venueA.venueId } }),
    ).toBe(1);
    expect(await prisma.saleLine.count()).toBe(1);
    expect(await prisma.salePayment.count()).toBe(1);
  });

  it('keeps frozen money/lines while applying restore and creates a new re-close', async () => {
    const original = sale('sale-a');
    await sync.sync(venueA, [original], []);
    await sync.sync(
      venueA,
      [
        {
          ...original,
          revision: 2,
          restoredToOrder: true,
          restoredAt: '2026-09-04T11:00:00.000Z',
          restoredBy: 'manager-a',
          sourceUpdatedAt: '2026-09-04T11:00:00.000Z',
          gross: '999.00',
          advanceApplied: '0.00',
          amountDueNow: '999.00',
          collectedNow: '999.00',
          payments: [{ method: 'cash', amount: '999.00' }],
          lines: [
            {
              ...original.lines[0],
              itemName: 'Mutated',
              unitPrice: '999.00',
              lineTotal: '999.00',
            },
          ],
        },
      ],
      [],
    );
    await sync.sync(venueA, [sale('sale-b', { closureId: 'closure-b' })], []);
    const rows = await prisma.cloudSale.findMany({
      where: { venueId: venueA.venueId },
      include: { lines: true },
      orderBy: { posSaleId: 'asc' },
    });
    expect(rows).toHaveLength(2);
    expect(rows[0].restoredToOrder).toBe(true);
    expect(rows[0].gross.toFixed(2)).toBe('100.00');
    expect(rows[0].lines[0].itemName).toBe('Original name');
    expect(rows[0].closureId).toBe('closure-sale-a');
    expect(rows[1].closureId).toBe('closure-b');
  });

  it('keeps void history and excludes it from revenue', async () => {
    const original = sale('sale-void');
    await sync.sync(venueA, [original], []);
    await sync.sync(
      venueA,
      [
        {
          ...original,
          revision: 2,
          isCancelled: true,
          cancelledAt: '2026-09-04T11:00:00.000Z',
          cancelledBy: 'manager-a',
          cancellationReason: 'mistake',
          sourceUpdatedAt: '2026-09-04T11:00:00.000Z',
        },
      ],
      [],
    );
    const summary = await queries.getSummary(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(
      await prisma.cloudSale.count({ where: { venueId: venueA.venueId } }),
    ).toBe(1);
    expect(summary.revenue).toBe('0.00');
    expect(summary.voidedCount).toBe(1);
  });

  /**
   * A cancelled Order's Sale as the POS now sends it after the legacy
   * normalization fix: durable history with no tender at all.
   */
  const cancelledSale = (id: string) =>
    sale(id, {
      // The sentinel the POS records instead of a tender name. It is header
      // context, not a payment, and Cloud stores it as written.
      paymentMethod: 'cancelled',
      isFiscal: false,
      isCancelled: true,
      cancelledAt: '2026-09-04T10:30:00.000Z',
      cancellationReason: 'guest left',
      collectedNow: '0.00',
      payments: [],
    });

  it('refuses a sentinel offered as a Sale payment method', async () => {
    // `cancelled` is not a tender and must never become one. This is the
    // guard that made the POS regression visible instead of silently booking
    // an untrue collection, and it stays strict on purpose.
    // The same document is accepted with no tender...
    await sync.sync(venueA, [cancelledSale('sale-sentinel-ok')], []);
    expect(
      await prisma.cloudSale.count({
        where: { venueId: venueA.venueId, posSaleId: 'sale-sentinel-ok' },
      }),
    ).toBe(1);

    // ...and refused the moment the sentinel is offered as one.
    await expect(
      sync.sync(
        venueA,
        [
          {
            ...cancelledSale('sale-sentinel-tender'),
            collectedNow: '100.00',
            payments: [{ method: 'cancelled', amount: '100.00' }],
          },
        ],
        [],
      ),
    ).rejects.toThrow(/Unsupported Sale payment method cancelled/);
    expect(
      await prisma.cloudSale.count({
        where: { venueId: venueA.venueId, posSaleId: 'sale-sentinel-tender' },
      }),
    ).toBe(0);
  });

  it('accepts a snapshot mixing ordinary Sales with a legacy cancellation', async () => {
    // The reproduced failure: one cancelled Order from an older POS build made
    // the whole snapshot 400, so orders, tables, menu and staff stopped
    // syncing too. The batch has to go through whole.
    await sync.sync(
      venueA,
      [
        sale('snapshot-cash'),
        cancelledSale('snapshot-legacy-cancelled'),
        sale('snapshot-card', {
          paymentMethod: 'card-tbc',
          payments: [{ method: 'card-tbc', amount: '100.00' }],
        }),
      ],
      [],
    );

    expect(
      await prisma.cloudSale.count({ where: { venueId: venueA.venueId } }),
    ).toBe(3);
    const stored = await prisma.cloudSale.findFirstOrThrow({
      where: {
        venueId: venueA.venueId,
        posSaleId: 'snapshot-legacy-cancelled',
      },
      include: { payments: true },
    });
    // Durable history, not revenue, and not a fabricated tender.
    expect(stored.gross.toFixed(2)).toBe('100.00');
    expect(stored.collectedNow.toFixed(2)).toBe('0.00');
    expect(stored.isFiscal).toBe(false);
    expect(stored.isCancelled).toBe(true);
    expect(stored.paymentMethod).toBe('cancelled');
    expect(stored.payments).toEqual([]);

    const summary = await queries.getSummary(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    // Only the two fiscal Sales are revenue; the cancellation is excluded.
    expect(summary.revenue).toBe('200.00');
  });

  const retainedSnapshotPath = process.env.POS_RETAINED_SALES_WIRE_OUTPUT;
  (retainedSnapshotPath ? it : it.skip)(
    'ingests every retained Dart Sale payload and acknowledges the complete history',
    async () => {
      const rows = JSON.parse(
        readFileSync(retainedSnapshotPath!, 'utf8'),
      ) as SaleLedgerSync[];
      const acknowledgements: string[] = [];
      for (let offset = 0; offset < rows.length; offset += 250) {
        const result = await sync.sync(
          venueA,
          rows.slice(offset, offset + 250),
          [],
        );
        acknowledgements.push(
          ...result.acknowledgements.map((row) => row.posSaleId),
        );
      }
      expect(acknowledgements).toEqual(rows.map((row) => row.posSaleId));
      expect(
        await prisma.cloudSale.count({ where: { venueId: venueA.venueId } }),
      ).toBe(rows.length);
      const invalidPayments = await prisma.salePayment.count({
        where: { sale: { venueId: venueA.venueId, isFiscal: false } },
      });
      expect(invalidPayments).toBe(0);
    },
  );

  it('preserves non-fiscal advance context without inventing payment rows', async () => {
    for (const isCancelled of [false, true]) {
      const row = sale(`internal-advance-${isCancelled}`, {
        isFiscal: false,
        isCancelled,
        paymentMethod: 'non-fiscal',
        advanceApplied: '40.00',
        amountDueNow: '60.00',
        collectedNow: '0.00',
        payments: [],
      });
      await sync.sync(venueA, [row], []);
      const stored = await prisma.cloudSale.findFirstOrThrow({
        where: { venueId: venueA.venueId, posSaleId: row.posSaleId },
        include: { payments: true },
      });
      expect(stored.gross.toFixed(2)).toBe('100.00');
      expect(stored.advanceApplied.toFixed(2)).toBe('40.00');
      expect(stored.amountDueNow.toFixed(2)).toBe('60.00');
      expect(stored.collectedNow.toFixed(2)).toBe('0.00');
      expect(stored.payments).toEqual([]);
      for (const payments of [
        [{ method: 'advance', amount: '40.00' }],
        [{ method: 'cash', amount: '10.00' }],
      ]) {
        await expect(
          sync.sync(venueA, [{ ...row, payments }], []),
        ).rejects.toThrow('Non-fiscal Sales cannot collect tender');
      }
    }
    await expect(
      sync.sync(
        venueA,
        [
          sale('bad-fiscal-advance', {
            advanceApplied: '40.00',
            amountDueNow: '60.00',
            collectedNow: '60.00',
            payments: [{ method: 'cash', amount: '60.00' }],
          }),
        ],
        [],
      ),
    ).rejects.toThrow('Advance payment part must equal advanceApplied');
    const summary = await queries.getSummary(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(summary.revenue).toBe('0.00');
  });

  it('rejects captured stale tender and ingests Dart-normalized mixed history over HTTP', async () => {
    const fixture = (name: string) =>
      JSON.parse(
        readFileSync(
          resolve(__dirname, '../../../../../operations/test/fixtures', name),
          'utf8',
        ),
      );
    const normalized = fixture(
      'retained_non_fiscal_wire.json',
    ) as SaleLedgerSync;
    const mixed = fixture('mixed_sale_ledger_wire.json') as SaleLedgerSync[];
    // HTTP harness around the real service and disposable PostgreSQL.
    // Tenant is fixed by the harness, never supplied by the request body.
    @Controller('snapshot')
    class SnapshotHarness {
      @Post()
      ingest(@Body() body: { sales: SaleLedgerSync[] }) {
        return sync.sync(venueA, body.sales, []);
      }
    }
    const module = await Test.createTestingModule({
      controllers: [SnapshotHarness],
    }).compile();
    const app = module.createNestApplication();
    await app.init();
    try {
      const before = {
        ...normalized,
        collectedNow: '176.00',
        payments: [{ method: 'cash', amount: '176.00' }],
      };
      const rejected = await request(app.getHttpServer())
        .post('/snapshot')
        .send({ sales: [before] })
        .expect(400);
      expect(rejected.body.message).toBe(
        'Non-fiscal Sales cannot collect tender',
      );
      await request(app.getHttpServer())
        .post('/snapshot')
        .send({
          sales: [
            {
              ...normalized,
              posSaleId: 'malformed-direct',
              collectedNow: '10.00',
              payments: [{ method: 'cash', amount: '10.00' }],
            },
          ],
        })
        .expect(400);
      expect(
        await prisma.cloudSale.count({ where: { venueId: venueA.venueId } }),
      ).toBe(0);
      await request(app.getHttpServer())
        .post('/snapshot')
        .send({ sales: [normalized, ...mixed] })
        .expect(201);
      const stored = await prisma.cloudSale.findFirstOrThrow({
        where: { venueId: venueA.venueId, posSaleId: normalized.posSaleId },
        include: { payments: true, lines: true },
      });
      expect(stored.gross.toFixed(2)).toBe('176.00');
      expect(stored.collectedNow.toFixed(2)).toBe('0.00');
      expect(stored.payments).toEqual([]);
      expect(stored.lines).toHaveLength(2);
      expect(stored.isFiscal).toBe(false);
      expect(stored.isCancelled).toBe(false);
      expect(stored.restoredToOrder).toBe(false);
      expect(stored.closureId).toBe(normalized.closureId);
      expect(stored.paymentMethod).toBe('non-fiscal');
      const history = await prisma.cloudSale.findMany({
        where: { venueId: venueA.venueId },
        include: { payments: true },
      });
      expect(history).toHaveLength(7);
      for (const row of history.filter(
        (row) => !row.isFiscal || row.isCancelled,
      )) {
        expect(row.collectedNow.toFixed(2)).toBe('0.00');
        expect(row.payments).toEqual([]);
      }
      const internalSummary = await queries.getSummary(venueA, {
        from: '2026-06-22',
        to: '2026-06-22',
      });
      expect(internalSummary.revenue).toBe('0.00');
      const mixedSummary = await queries.getSummary(venueA, {
        from: '2026-09-04',
        to: '2026-09-04',
      });
      expect(mixedSummary.revenue).toBe('36.00');
    } finally {
      await app.close();
    }
  });

  it('uses authenticated Venue authority and isolates list/detail/filters', async () => {
    await sync.sync(venueA, [sale('shared', { venueId: venueB.venueId })], []);
    await sync.sync(
      venueB,
      [
        sale('shared', {
          gross: '90.00',
          amountDueNow: '90.00',
          collectedNow: '90.00',
          payments: [{ method: 'cash', amount: '90.00' }],
        }),
      ],
      [],
    );
    const a = await prisma.cloudSale.findFirstOrThrow({
      where: { venueId: venueA.venueId },
    });
    const b = await prisma.cloudSale.findFirstOrThrow({
      where: { venueId: venueB.venueId },
    });
    expect(a.gross.toFixed(2)).toBe('100.00');
    expect(b.gross.toFixed(2)).toBe('90.00');
    await expect(queries.getSale(venueA, b.id)).rejects.toThrow(
      'Sale not found',
    );
    const menuFiltered = await queries.listSales(venueB, {
      from: '2026-09-04',
      to: '2026-09-04',
      menuItemId: 'menu-stable',
      staffId: 'manager-a',
    });
    expect(menuFiltered.sales).toHaveLength(1);
    expect(menuFiltered.sales[0].id).toBe(b.id);
  });

  it('keyset-paginates without loading or repeating the full history', async () => {
    await sync.sync(
      venueA,
      [
        sale('sale-page-1', { closedAt: '2026-09-04T10:00:00.000Z' }),
        sale('sale-page-2', { closedAt: '2026-09-04T11:00:00.000Z' }),
      ],
      [],
    );
    const first = await queries.listSales(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
      limit: 1,
    });
    const second = await queries.listSales(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
      limit: 1,
      cursor: first.nextCursor!,
    });
    expect(first.sales).toHaveLength(1);
    expect(second.sales).toHaveLength(1);
    expect(second.sales[0].id).not.toBe(first.sales[0].id);
  });

  it('proves complete/matched, mismatch, partial and legacy-only reconciliation', async () => {
    await sync.sync(
      venueA,
      [sale('sale-reconcile')],
      [
        {
          businessDate: '2026-09-04',
          expectedSaleCount: 1,
          expectedRevenue: '100.00',
          legacyRevenue: '100.00',
          uploadComplete: true,
        },
      ],
    );
    let day = await prisma.saleLedgerDay.findFirstOrThrow({
      where: { venueId: venueA.venueId },
    });
    expect([day.completeness, day.reconciliation]).toEqual([
      'COMPLETE',
      'MATCHED',
    ]);

    await sync.sync(
      venueA,
      [],
      [
        {
          businessDate: '2026-09-04',
          expectedSaleCount: 1,
          expectedRevenue: '100.00',
          legacyRevenue: '99.99',
          uploadComplete: true,
        },
      ],
    );
    day = await prisma.saleLedgerDay.findFirstOrThrow({
      where: { venueId: venueA.venueId },
    });
    expect(day.reconciliation).toBe('MISMATCH');

    await sync.sync(
      venueA,
      [],
      [
        {
          businessDate: '2026-09-04',
          expectedSaleCount: 2,
          expectedRevenue: '200.00',
          uploadComplete: false,
        },
        {
          businessDate: '2026-09-03',
          uploadComplete: false,
          legacySummaryOnly: true,
          legacyRevenue: '50.00',
        },
      ],
    );
    const days = await prisma.saleLedgerDay.findMany({
      where: { venueId: venueA.venueId },
    });
    expect(days).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          businessDate: '2026-09-04',
          reconciliation: 'INCOMPLETE',
        }),
        expect.objectContaining({
          businessDate: '2026-09-03',
          reconciliation: 'LEGACY_ONLY',
        }),
      ]),
    );
    expect(
      await prisma.cloudSale.count({
        where: { venueId: venueA.venueId, businessDate: '2026-09-03' },
      }),
    ).toBe(0);
  });

  it('uses legacy fallback only when no complete ledger exists and never double-counts partial history', async () => {
    await prisma.setting.create({
      data: {
        venueId: venueA.venueId,
        key: 'salesSummary:2026-09-04',
        value: JSON.stringify({
          totalRevenue: 999,
          orderCount: 9,
          cashRevenue: 399,
          cardRevenue: 600,
          paymentBreakdown: { cash: 399, 'card-tbc': 600 },
        }),
      },
    });

    let summary = await queries.getSummary(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(summary.provenance).toBe('LEGACY_FALLBACK');
    expect(summary.revenue).toBe('999.00');

    // A Sale can commit before a later day declaration fails. Its presence is
    // enough to prohibit adding the legacy aggregate on top.
    await sync.sync(venueA, [sale('sale-partial')], []);
    summary = await queries.getSummary(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(summary.provenance).toBe('PARTIAL');
    expect(summary.revenue).toBe('100.00');

    await sync.sync(
      venueA,
      [],
      [
        {
          businessDate: '2026-09-04',
          expectedSaleCount: 1,
          expectedRevenue: '100.00',
          legacyRevenue: '999.00',
          uploadComplete: false,
        },
      ],
    );

    await sync.sync(
      venueA,
      [],
      [
        {
          businessDate: '2026-09-04',
          expectedSaleCount: 1,
          expectedRevenue: '100.00',
          legacyRevenue: '999.00',
          uploadComplete: true,
        },
      ],
    );
    summary = await queries.getSummary(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(summary.provenance).toBe('LEDGER_COMPLETE');
    expect(summary.revenue).toBe('100.00');
    expect(summary.reconciliation).toEqual([
      { businessDate: '2026-09-04', result: 'MISMATCH' },
    ]);
  });

  it('links the Sale closure to the existing Order audit without rewriting it', async () => {
    await sync.sync(venueA, [sale('sale-audit')], []);
    await prisma.auditReport.create({
      data: {
        venueId: venueA.venueId,
        reportId: 'audit-report-1',
        posOrderId: sale('sale-audit').posOrderId,
        tableNumbers: ['1'],
        floor: 'first',
        openedById: 'waiter',
        openedByName: 'Waiter',
        openedAt: new Date('2026-09-04T10:00:00Z'),
        status: 'CLOSED',
        locked: true,
        events: {
          create: {
            venueId: venueA.venueId,
            type: 'CLOSE',
            itemName: 'ORDER',
            previousQty: 0,
            newQty: 0,
            waiterId: 'manager-a',
            waiterName: 'Manager A',
            eventTime: new Date('2026-09-04T10:30:00Z'),
            details: { closureId: 'closure-sale-audit' },
          },
        },
      },
    });
    const stored = await prisma.cloudSale.findFirstOrThrow({
      where: { venueId: venueA.venueId },
    });
    const detail = await queries.getSale(venueA, stored.id);
    expect(detail.closureId).toBe('closure-sale-audit');
    expect(detail.auditLink).toEqual(
      expect.objectContaining({
        reportId: 'audit-report-1',
        closureId: 'closure-sale-audit',
      }),
    );
  });

  it('groups renamed products by stable identity and reports honest staff attribution', async () => {
    await sync.sync(
      venueA,
      [
        sale('sale-product-1'),
        sale('sale-product-2', {
          closedAt: '2026-09-04T11:00:00.000Z',
          lines: [
            {
              ...sale('x').lines[0],
              itemName: 'Renamed product',
              quantity: 2,
              lineTotal: '200.00',
            },
          ],
        }),
        sale('sale-manual', {
          closedById: null,
          lines: [
            {
              ...sale('x').lines[0],
              menuItemId: null,
              variantId: null,
              itemName: 'Manual line',
            },
          ],
        }),
      ],
      [],
    );
    const products = await queries.getProducts(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(products.byRevenue).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          menuItemId: 'menu-stable',
          quantity: 3,
          revenue: '300.00',
        }),
        expect.objectContaining({ manual: true, name: 'Manual line' }),
      ]),
    );
    const staff = await queries.getStaff(venueA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(staff.staff).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ staffId: 'manager-a', saleCount: 2 }),
        expect.objectContaining({ staffId: null, attributionReliable: false }),
      ]),
    );
  });
});
