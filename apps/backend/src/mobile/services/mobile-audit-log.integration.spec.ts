import { PrismaService } from '../../prisma.service';
import { MobileAuditLogService } from './mobile-audit-log.service';
import type { TenantContext } from '../../tenancy/tenant-context';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * The venue-wide audit reader, against real PostgreSQL.
 *
 * These are the properties a mocked Prisma cannot prove: that one restaurant
 * cannot read another's history, that the keyset cursor really does walk every
 * row exactly once when timestamps tie, and that a row written before
 * `entityType` existed is still found by the entity it is about — which is a
 * JSON path match the query planner has to actually run.
 */
describeDatabase('Global audit log reader (PostgreSQL)', () => {
  let prisma: PrismaService;
  let service: MobileAuditLogService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `a0000000-0000-4000-8000-${suffix}`;
  const venueAId = `a1000000-0000-4000-8000-${suffix}`;
  const venueBId = `a2000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];

  const tenantA: TenantContext = { venueId: venueAId, organizationId };
  const tenantB: TenantContext = { venueId: venueBId, organizationId };

  let seq = 0;

  function row(params: {
    venueId: string;
    action: string;
    userId?: string;
    entityType?: string | null;
    entityId?: string | null;
    data?: Record<string, unknown>;
    createdAt: string;
  }) {
    seq += 1;
    return {
      id: `${venueAId.slice(0, 24)}${`${seq}`.padStart(12, '0')}`,
      venueId: params.venueId,
      action: params.action,
      userId: params.userId ?? 'nino',
      entityType: params.entityType ?? null,
      entityId: params.entityId ?? null,
      data: (params.data ?? {}) as never,
      deviceType: 'windows',
      createdAt: new Date(params.createdAt),
    };
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    service = new MobileAuditLogService(prisma);

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Audit reader fixture',
        venues: {
          create: [venue(venueAId, 'Venue A'), venue(venueBId, 'Venue B')],
        },
      },
    });
  });

  afterAll(async () => {
    await prisma.auditEventLog.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  afterEach(async () => {
    await prisma.auditEventLog.deleteMany({
      where: { venueId: { in: venueIds } },
    });
  });

  it('never returns another Venue’s history', async () => {
    await prisma.auditEventLog.createMany({
      data: [
        row({
          venueId: venueAId,
          action: 'STAFF_ROLE_CHANGED',
          entityType: 'STAFF',
          entityId: 'nika',
          data: { staffName: 'nika' },
          createdAt: '2026-09-05T10:00:00.000Z',
        }),
        row({
          venueId: venueBId,
          action: 'STAFF_ROLE_CHANGED',
          entityType: 'STAFF',
          entityId: 'other-venue-staff',
          data: { staffName: 'other-venue-staff' },
          createdAt: '2026-09-05T10:00:00.000Z',
        }),
      ],
    });

    const a = await service.getAuditLog(tenantA, {});
    const b = await service.getAuditLog(tenantB, {});

    expect(a.items.map((i) => i.entityId)).toEqual(['nika']);
    expect(b.items.map((i) => i.entityId)).toEqual(['other-venue-staff']);

    // And asking for the other Venue's subject by name finds nothing, rather
    // than reaching across the boundary.
    const crossed = await service.getAuditLog(tenantA, {
      entityType: 'STAFF',
      entityId: 'other-venue-staff',
    });
    expect(crossed.items).toEqual([]);
  });

  it('filters by date, action, entity and actor', async () => {
    await prisma.auditEventLog.createMany({
      data: [
        row({
          venueId: venueAId,
          action: 'MENU_ITEM_UPDATED',
          userId: 'nino',
          entityType: 'MENU_ITEM',
          entityId: 'hot/Khinkali',
          data: {
            itemName: 'ხინკალი',
            changes: [
              { field: 'price', previousValue: 2, newValue: 2.5 },
            ],
          },
          createdAt: '2026-09-05T09:00:00.000Z',
        }),
        row({
          venueId: venueAId,
          action: 'EXPENSE_CREATED',
          userId: 'avtandil',
          entityType: 'EXPENSE',
          entityId: 'exp-1',
          data: { amount: 120, category: 'Supplies' },
          createdAt: '2026-09-04T09:00:00.000Z',
        }),
        row({
          venueId: venueAId,
          action: 'CLOSE_DAY_COMPLETED',
          userId: 'nino',
          entityType: 'CLOSE_DAY',
          entityId: '2026-09-03',
          data: { businessDateClosed: '2026-09-03' },
          createdAt: '2026-09-03T22:00:00.000Z',
        }),
      ],
    });

    const byAction = await service.getAuditLog(tenantA, {
      action: 'EXPENSE_CREATED',
    });
    expect(byAction.items.map((i) => i.entityId)).toEqual(['exp-1']);

    const byEntity = await service.getAuditLog(tenantA, {
      entityType: 'MENU_ITEM',
    });
    expect(byEntity.items.map((i) => i.entityId)).toEqual(['hot/Khinkali']);
    // The price move survives as a structured pair, not as prose.
    expect(byEntity.items[0].changes).toEqual([
      { field: 'price', previousValue: 2, newValue: 2.5 },
    ]);
    expect(byEntity.items[0].entityLabel).toBe('ხინკალი');

    const byActor = await service.getAuditLog(tenantA, { actor: 'avtandil' });
    expect(byActor.items.map((i) => i.action)).toEqual(['EXPENSE_CREATED']);

    // A bare `to` date names the whole day, so the 4th is included by it.
    const byDate = await service.getAuditLog(tenantA, {
      from: '2026-09-04',
      to: '2026-09-04',
    });
    expect(byDate.items.map((i) => i.action)).toEqual(['EXPENSE_CREATED']);
  });

  it('walks every row exactly once when the timestamps all tie', async () => {
    const sameInstant = '2026-09-05T12:00:00.000Z';
    await prisma.auditEventLog.createMany({
      data: Array.from({ length: 25 }, () =>
        row({
          venueId: venueAId,
          action: 'STAFF_PIN_CHANGED',
          entityType: 'STAFF',
          entityId: 'nika',
          data: { staffName: 'nika', field: 'pin', changed: true },
          createdAt: sameInstant,
        }),
      ),
    });

    const seen: string[] = [];
    let cursor: string | null | undefined;
    let pages = 0;
    do {
      const page = await service.getAuditLog(tenantA, {
        limit: '10',
        cursor: cursor ?? undefined,
      });
      seen.push(...page.items.map((i) => i.id));
      cursor = page.nextCursor;
      pages += 1;
      expect(pages).toBeLessThan(10); // a cursor that never advances would hang
    } while (cursor);

    expect(seen).toHaveLength(25);
    expect(new Set(seen).size).toBe(25);
  });

  it('finds a row written before entity identity existed', async () => {
    await prisma.auditEventLog.createMany({
      data: [
        // Exactly the shape history holds: no entityType, no entityId, the
        // subject only inside the details.
        row({
          venueId: venueAId,
          action: 'reservation_cancelled',
          data: { reservationId: 'res-legacy-1', customerName: 'Tamar' },
          createdAt: '2026-08-01T10:00:00.000Z',
        }),
        row({
          venueId: venueAId,
          action: 'ADVANCE_RECORDED',
          data: { orderId: 512, newAmount: 40 },
          createdAt: '2026-08-01T11:00:00.000Z',
        }),
      ],
    });

    const reservations = await service.getAuditLog(tenantA, {
      entityType: 'RESERVATION',
    });
    expect(reservations.items).toHaveLength(1);
    // Derived on read; the stored row is untouched.
    expect(reservations.items[0].entityType).toBe('RESERVATION');
    expect(reservations.items[0].entityId).toBe('res-legacy-1');

    const oneBooking = await service.getAuditLog(tenantA, {
      entityType: 'RESERVATION',
      entityId: 'res-legacy-1',
    });
    expect(oneBooking.items).toHaveLength(1);

    // An id stored as a number is still matched from a string query.
    const oneOrder = await service.getAuditLog(tenantA, {
      entityType: 'ORDER',
      entityId: '512',
    });
    expect(oneOrder.items.map((i) => i.action)).toEqual(['ADVANCE_RECORDED']);

    const stored = await prisma.auditEventLog.findMany({
      where: { venueId: venueAId },
      select: { entityType: true, entityId: true },
    });
    expect(stored.every((r) => r.entityType === null)).toBe(true);
  });

  it('reports the actions this Venue has actually recorded', async () => {
    await prisma.auditEventLog.createMany({
      data: [
        row({
          venueId: venueAId,
          action: 'PACKAGE_UPDATED',
          entityType: 'PACKAGE',
          entityId: 'pkg-1',
          createdAt: '2026-09-05T08:00:00.000Z',
        }),
        row({
          venueId: venueBId,
          action: 'BACKUP_RESTORED',
          entityType: 'BACKUP',
          createdAt: '2026-09-05T08:00:00.000Z',
        }),
      ],
    });

    const facets = await service.getAuditLogFacets(tenantA);
    expect(facets.actions.map((a) => a.action)).toEqual(['PACKAGE_UPDATED']);
    expect(facets.entityTypes).toEqual(['PACKAGE']);
  });

  it('rejects a filter it cannot honour instead of ignoring it', async () => {
    await expect(
      service.getAuditLog(tenantA, { entityType: 'TABLE' }),
    ).rejects.toThrow(/unknown entityType/);
    await expect(
      service.getAuditLog(tenantA, { from: 'not-a-date' }),
    ).rejects.toThrow(/from must be a date/);
    await expect(
      service.getAuditLog(tenantA, { cursor: 'nonsense' }),
    ).rejects.toThrow(/invalid cursor/);
  });
});
