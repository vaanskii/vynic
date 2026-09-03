jest.mock('../../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { IngestAuditReportsService } from './ingest-audit-reports.service';

const TENANT = { venueId: 'venue-a', organizationId: 'organization-a' };

/** A Prisma double whose auditReport table behaves like an empty one. */
function auditReportDouble(existing: unknown = null) {
  return {
    findUnique: jest.fn<Promise<unknown>, [unknown]>(() =>
      Promise.resolve(existing),
    ),
    upsert: jest.fn<Promise<{ id: string }>, [unknown]>(() =>
      Promise.resolve({ id: 'db-report' }),
    ),
    findMany: jest.fn<Promise<Array<{ id: string }>>, [unknown]>(() =>
      Promise.resolve([]),
    ),
    deleteMany: jest.fn<Promise<{ count: number }>, [unknown]>(() =>
      Promise.resolve({ count: 0 }),
    ),
  };
}

function auditEventDouble() {
  return {
    deleteMany: jest.fn<Promise<{ count: number }>, [unknown]>(() =>
      Promise.resolve({ count: 0 }),
    ),
    createMany: jest.fn<Promise<{ count: number }>, [unknown]>(() =>
      Promise.resolve({ count: 0 }),
    ),
  };
}

describe('IngestAuditReportsService tenant scoping', () => {
  it('scopes report identity and full reconciliation to the authenticated Venue', async () => {
    const auditReport = auditReportDouble();
    const auditEvent = auditEventDouble();
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    await service.ingestReports(
      { reports: [{ reportId: 'report-1', orderId: 7 }], fullSync: true },
      TENANT,
    );

    expect(auditReport.upsert.mock.calls[0][0]).toMatchObject({
      where: {
        venueId_reportId: { venueId: 'venue-a', reportId: 'report-1' },
      },
      create: { venueId: 'venue-a' },
    });
    expect(auditReport.findMany.mock.calls[0][0]).toMatchObject({
      where: { venueId: 'venue-a' },
    });
  });

  it('checks and creates immutable event logs only inside the authenticated Venue', async () => {
    const auditEventLog = {
      findFirst: jest.fn<Promise<null>, [unknown]>(() => Promise.resolve(null)),
      create: jest.fn<Promise<{ id: string }>, [unknown]>(() =>
        Promise.resolve({ id: 'log-1' }),
      ),
    };
    const service = new IngestAuditReportsService(
      { auditEventLog } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    await service.ingestEventLogs(
      {
        logs: [
          {
            id: 'log-1',
            action: 'opened',
            userId: 'staff-1',
            data: {},
            deviceType: 'pos',
            createdAt: '2026-08-31T10:00:00.000Z',
          },
        ],
      },
      TENANT,
    );

    expect(auditEventLog.findFirst).toHaveBeenCalledWith({
      where: { id: 'log-1', venueId: 'venue-a' },
      select: { id: true },
    });
    expect(auditEventLog.create.mock.calls[0][0]).toMatchObject({
      data: { id: 'log-1', venueId: 'venue-a' },
    });
  });
});

describe('IngestAuditReportsService incremental acknowledgment', () => {
  it('acknowledges the exact revision it was offered', async () => {
    const auditReport = auditReportDouble();
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent: auditEventDouble() } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    const result = await service.ingestReports(
      {
        reports: [
          { reportId: 'report-1', revision: 'rev-a' },
          { reportId: 'report-2', revision: 'rev-b' },
        ],
      },
      TENANT,
    );

    expect(result.acknowledged).toEqual([
      { reportId: 'report-1', revision: 'rev-a' },
      { reportId: 'report-2', revision: 'rev-b' },
    ]);
    expect(result.upserted).toBe(2);
  });

  it('does not acknowledge a report whose write failed', async () => {
    const auditReport = auditReportDouble();
    auditReport.upsert.mockRejectedValueOnce(new Error('constraint'));
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent: auditEventDouble() } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    const result = await service.ingestReports(
      {
        reports: [
          { reportId: 'broken', revision: 'rev-a' },
          { reportId: 'fine', revision: 'rev-b' },
        ],
      },
      TENANT,
    );

    // The failed report stays unacknowledged, so the POS keeps it dirty and
    // offers it again. One bad report does not cost the rest of the batch.
    expect(result.acknowledged).toEqual([
      { reportId: 'fine', revision: 'rev-b' },
    ]);
  });

  it('skips rewriting a report whose stored revision already matches', async () => {
    const auditReport = auditReportDouble({
      id: 'db-report',
      syncRevision: 'rev-a',
    });
    const auditEvent = auditEventDouble();
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    const result = await service.ingestReports(
      { reports: [{ reportId: 'report-1', revision: 'rev-a' }] },
      TENANT,
    );

    expect(auditReport.upsert).not.toHaveBeenCalled();
    expect(auditEvent.deleteMany).not.toHaveBeenCalled();
    // Still acknowledged: the server holds this revision, which is exactly what
    // the POS is asking about.
    expect(result.acknowledged).toEqual([
      { reportId: 'report-1', revision: 'rev-a' },
    ]);
    expect(result.unchanged).toBe(1);
  });

  it('rewrites a report whose stored revision differs', async () => {
    const auditReport = auditReportDouble({
      id: 'db-report',
      syncRevision: 'rev-a',
    });
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent: auditEventDouble() } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    await service.ingestReports(
      { reports: [{ reportId: 'report-1', revision: 'rev-b' }] },
      TENANT,
    );

    expect(auditReport.upsert).toHaveBeenCalled();
    expect(auditReport.upsert.mock.calls[0][0]).toMatchObject({
      update: { syncRevision: 'rev-b' },
    });
  });

  it('rewrites a report offered without a revision', async () => {
    // An old POS build sends no revision. "Revision unknown" must mean write,
    // never skip, or an upgraded backend would silently stop ingesting from it.
    const auditReport = auditReportDouble({
      id: 'db-report',
      syncRevision: null,
    });
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent: auditEventDouble() } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    const result = await service.ingestReports(
      { reports: [{ reportId: 'report-1' }] },
      TENANT,
    );

    expect(auditReport.upsert).toHaveBeenCalled();
    expect(result.acknowledged).toEqual([
      { reportId: 'report-1', revision: null },
    ]);
  });
});

describe('IngestAuditReportsService reconciliation', () => {
  it('deletes reports absent from knownReportIds without any contents being sent', async () => {
    const auditReport = auditReportDouble();
    auditReport.findMany.mockResolvedValueOnce([{ id: 'stale-row' }]);
    const auditEvent = auditEventDouble();
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    await service.ingestReports(
      { knownReportIds: ['report-1', 'report-2'] },
      TENANT,
    );

    expect(auditReport.findMany).toHaveBeenCalledWith({
      where: {
        venueId: 'venue-a',
        reportId: { notIn: ['report-1', 'report-2'] },
      },
      select: { id: true },
    });
    expect(auditReport.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: ['stale-row'] } },
    });
    expect(auditEvent.deleteMany).toHaveBeenCalledWith({
      where: { reportId: { in: ['stale-row'] } },
    });
  });

  it('refuses to empty a Venue when the POS reports no reports at all', async () => {
    const auditReport = auditReportDouble();
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent: auditEventDouble() } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    await service.ingestReports({ knownReportIds: [] }, TENANT);
    await service.ingestReports({ reports: [], fullSync: true }, TENANT);

    expect(auditReport.findMany).not.toHaveBeenCalled();
    expect(auditReport.deleteMany).not.toHaveBeenCalled();
  });

  it('does not reconcile an ordinary incremental batch', async () => {
    // The batch is not the complete set. Treating it as one would delete every
    // report that simply had not changed.
    const auditReport = auditReportDouble();
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent: auditEventDouble() } as never,
      { broadcastUpdate: jest.fn() } as never,
    );

    await service.ingestReports(
      { reports: [{ reportId: 'report-1', revision: 'rev-a' }] },
      TENANT,
    );

    expect(auditReport.findMany).not.toHaveBeenCalled();
    expect(auditReport.deleteMany).not.toHaveBeenCalled();
  });
});
