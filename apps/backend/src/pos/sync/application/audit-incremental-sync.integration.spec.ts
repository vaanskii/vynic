jest.mock('../../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { PrismaService } from '../../../prisma.service';
import { DeviceCredentialService } from '../../../auth/device-credential.service';
import { IngestAuditReportsService } from './ingest-audit-reports.service';
import type { TenantContext } from '../../../auth/pos-auth-context';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * Incremental AuditReport synchronization, against real PostgreSQL.
 *
 * The properties here are the ones a mocked Prisma cannot prove: that a
 * redelivered batch leaves one logical history rather than two, that the
 * `(venueId, reportId)` key really does keep one restaurant's `reportId` out of
 * another's rows, and that a revision the server already stores is
 * acknowledged without its events being rewritten.
 */
describeDatabase('Incremental audit sync (PostgreSQL)', () => {
  let prisma: PrismaService;
  let ingest: IngestAuditReportsService;
  let credentials: DeviceCredentialService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `90000000-0000-4000-8000-${suffix}`;
  const venueAId = `91000000-0000-4000-8000-${suffix}`;
  const venueBId = `92000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];

  const tenantA: TenantContext = { venueId: venueAId, organizationId };
  const tenantB: TenantContext = { venueId: venueBId, organizationId };

  const broadcasts: unknown[] = [];

  function report(
    reportId: string,
    revision: string,
    events: Array<{ itemName: string; newQty: number }> = [],
  ) {
    return {
      reportId,
      revision,
      orderId: 42,
      tableNumbers: ['5'],
      floor: 'first',
      openedById: 'staff-1',
      openedByName: 'Nino',
      openedAt: '2026-09-01T18:00:00.000Z',
      status: 'OPEN',
      updatedAt: '2026-09-01T18:05:00.000Z',
      locked: false,
      events: events.map((e) => ({
        type: 'ADD_ITEM',
        itemName: e.itemName,
        previousQty: 0,
        newQty: e.newQty,
        waiterId: 'staff-1',
        waiterName: 'Nino',
        timestamp: '2026-09-01T18:01:00.000Z',
      })),
    };
  }

  async function rowsFor(venueId: string) {
    return prisma.auditReport.findMany({
      where: { venueId },
      select: {
        id: true,
        reportId: true,
        syncRevision: true,
        openedByName: true,
        _count: { select: { events: true } },
      },
      orderBy: { reportId: 'asc' },
    });
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    credentials = new DeviceCredentialService(prisma);
    ingest = new IngestAuditReportsService(prisma, {
      broadcastUpdate: (...args: unknown[]) => broadcasts.push(args),
    } as never);

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Audit sync fixture',
        venues: {
          create: [venue(venueAId, 'Venue A'), venue(venueBId, 'Venue B')],
        },
      },
    });
  });

  afterAll(async () => {
    await prisma.auditEvent.deleteMany({
      where: { report: { venueId: { in: venueIds } } },
    });
    await prisma.auditReport.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.device.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  afterEach(async () => {
    await prisma.auditEvent.deleteMany({
      where: { report: { venueId: { in: venueIds } } },
    });
    await prisma.auditReport.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    broadcasts.length = 0;
  });

  it('leaves one logical history when the same revision is delivered twice', async () => {
    const batch = {
      reports: [
        report('audit_report_order_1', 'rev-1', [
          { itemName: 'Khachapuri', newQty: 2 },
          { itemName: 'Lobio', newQty: 1 },
        ]),
      ],
    };

    const first = await ingest.ingestReports(batch, tenantA);
    const second = await ingest.ingestReports(batch, tenantA);

    expect(first.acknowledged).toEqual([
      { reportId: 'audit_report_order_1', revision: 'rev-1' },
    ]);
    // Redelivery is still acknowledged — that is what lets the POS mark it
    // synced after a lost response — but nothing is written a second time.
    expect(second.acknowledged).toEqual(first.acknowledged);
    expect(second.unchanged).toBe(1);
    expect(second.upserted).toBe(0);

    const rows = await rowsFor(venueAId);
    expect(rows).toHaveLength(1);
    expect(rows[0]._count.events).toBe(2);
    expect(rows[0].syncRevision).toBe('rev-1');
  });

  it('replaces the report when a new revision arrives', async () => {
    await ingest.ingestReports(
      {
        reports: [
          report('audit_report_order_2', 'rev-1', [
            { itemName: 'Khachapuri', newQty: 2 },
          ]),
        ],
      },
      tenantA,
    );
    await ingest.ingestReports(
      {
        reports: [
          {
            ...report('audit_report_order_2', 'rev-2', [
              { itemName: 'Khachapuri', newQty: 2 },
              { itemName: 'Wine', newQty: 1 },
            ]),
            openedByName: 'Giorgi',
          },
        ],
      },
      tenantA,
    );

    const rows = await rowsFor(venueAId);
    expect(rows).toHaveLength(1);
    expect(rows[0].syncRevision).toBe('rev-2');
    expect(rows[0].openedByName).toBe('Giorgi');
    expect(rows[0]._count.events).toBe(2);
  });

  it('keeps the same reportId in two Venues as two separate reports', async () => {
    await ingest.ingestReports(
      { reports: [report('audit_report_order_9', 'rev-a')] },
      tenantA,
    );
    await ingest.ingestReports(
      {
        reports: [
          { ...report('audit_report_order_9', 'rev-b'), openedByName: 'Other' },
        ],
      },
      tenantB,
    );

    const a = await rowsFor(venueAId);
    const b = await rowsFor(venueBId);
    expect(a).toHaveLength(1);
    expect(b).toHaveLength(1);
    // Venue B addressing the same reportId wrote its own row, not Venue A's.
    expect(a[0].id).not.toBe(b[0].id);
    expect(a[0].openedByName).toBe('Nino');
    expect(a[0].syncRevision).toBe('rev-a');
    expect(b[0].openedByName).toBe('Other');
  });

  it("never lets one Venue reconcile away another Venue's reports", async () => {
    await ingest.ingestReports(
      { reports: [report('audit_report_order_10', 'rev-a')] },
      tenantA,
    );
    await ingest.ingestReports(
      { reports: [report('audit_report_order_11', 'rev-a')] },
      tenantB,
    );

    // Venue B claims to hold only its own report. Venue A's must survive.
    await ingest.ingestReports(
      { knownReportIds: ['audit_report_order_11'] },
      tenantB,
    );

    expect(await rowsFor(venueAId)).toHaveLength(1);
    expect(await rowsFor(venueBId)).toHaveLength(1);
  });

  it('drops a report the POS no longer holds, and only that one', async () => {
    await ingest.ingestReports(
      {
        reports: [
          report('audit_report_order_20', 'rev-a', [
            { itemName: 'Kept', newQty: 1 },
          ]),
          report('audit_report_order_21', 'rev-a', [
            { itemName: 'Dropped', newQty: 1 },
          ]),
        ],
      },
      tenantA,
    );

    await ingest.ingestReports(
      { knownReportIds: ['audit_report_order_20'] },
      tenantA,
    );

    const rows = await rowsFor(venueAId);
    expect(rows.map((r) => r.reportId)).toEqual(['audit_report_order_20']);
    // The dropped report's events went with it rather than being orphaned.
    const remaining = await prisma.auditEvent.count({
      where: { report: { venueId: venueAId } },
    });
    expect(remaining).toBe(1);
  });

  it('re-ingests reports carrying no revision, so an unupgraded POS still syncs', async () => {
    const legacy = report('audit_report_order_30', '');
    delete (legacy as { revision?: string }).revision;

    const first = await ingest.ingestReports(
      { reports: [legacy], fullSync: true },
      tenantA,
    );
    const second = await ingest.ingestReports(
      { reports: [legacy], fullSync: true },
      tenantA,
    );

    expect(first.acknowledged).toEqual([
      { reportId: 'audit_report_order_30', revision: null },
    ]);
    // No revision means "unknown", which must mean write rather than skip.
    expect(second.unchanged).toBe(0);
    expect(second.upserted).toBe(1);
    expect(await rowsFor(venueAId)).toHaveLength(1);
  });

  it('the steady state: a backfilled history plus one change writes one report', async () => {
    // The property the whole mechanism exists for, proved on the server's half:
    // 60 reports already acknowledged at their current revisions, one of them
    // edited. Only the edited one is written; the rest are left alone.
    const history = Array.from({ length: 60 }, (_, i) =>
      report(`audit_report_order_1${i}`, `rev-${i}`, [
        { itemName: 'Item', newQty: 1 },
      ]),
    );
    await ingest.ingestReports({ reports: history }, tenantA);

    const changed = { ...history[7], revision: 'rev-7-edited' };
    const result = await ingest.ingestReports({ reports: [changed] }, tenantA);

    expect(result.upserted).toBe(1);
    expect(result.acknowledged).toEqual([
      { reportId: 'audit_report_order_17', revision: 'rev-7-edited' },
    ]);
    expect(await rowsFor(venueAId)).toHaveLength(60);
  });

  it('resolves the Venue from the Device credential, not from the payload', async () => {
    const issued = await credentials.issueCredential({
      venueId: venueAId,
      installationId: `93000000-0000-4000-8000-${suffix}`,
      displayName: 'Venue A POS',
      platform: 'windows',
    });
    const verified = await credentials.verifyCredential(issued.credential);
    expect(verified?.venueId).toBe(venueAId);

    // Whatever a report claims about itself, ownership comes from the verified
    // Device. There is no field in the payload that names a Venue.
    await ingest.ingestReports(
      {
        reports: [
          {
            ...report('audit_report_order_40', 'rev-a'),
            venueId: venueBId,
          },
        ],
      },
      { venueId: verified!.venueId, organizationId: verified!.organizationId },
    );

    expect(await rowsFor(venueAId)).toHaveLength(1);
    expect(await rowsFor(venueBId)).toHaveLength(0);
  });
});
