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

describe('IngestAuditReportsService event ordering and tenancy', () => {
  /** A creation event and the lines written with it, all at one instant. */
  function creationBatch(instant = '2026-09-05T10:00:00.000Z') {
    return [
      {
        type: 'CREATE_WALKIN',
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: 'nino',
        waiterName: 'Nino',
        timestamp: instant,
        sequence: 0,
        details: { orderId: 12, orderKind: 'WALK_IN' },
      },
      ...Array.from({ length: 40 }, (_unused, index) => ({
        type: 'ADD_ITEM',
        itemName: `Item ${index}`,
        previousQty: 0,
        newQty: 1,
        waiterId: 'nino',
        waiterName: 'Nino',
        timestamp: instant,
        sequence: index + 1,
      })),
    ];
  }

  async function ingest(report: Record<string, unknown>) {
    const auditReport = auditReportDouble();
    const auditEvent = auditEventDouble();
    const service = new IngestAuditReportsService(
      { auditReport, auditEvent } as never,
      { broadcastUpdate: jest.fn() } as never,
    );
    await service.ingestReports({ reports: [report] }, TENANT);
    return { auditReport, auditEvent };
  }

  it("writes the POS's own sequence into seq rather than arrival position", async () => {
    // Offered out of order on purpose: arrival position would number the
    // close as 0, and the timeline would open with it.
    const { auditEvent } = await ingest({
      reportId: 'report-1',
      orderId: 12,
      events: [
        {
          type: 'CLOSE',
          itemName: 'ORDER',
          previousQty: 0,
          newQty: 0,
          timestamp: '2026-09-05T12:00:00.000Z',
          sequence: 2,
        },
        {
          type: 'CREATE_WALKIN',
          itemName: 'ORDER',
          previousQty: 0,
          newQty: 0,
          timestamp: '2026-09-05T10:00:00.000Z',
          sequence: 0,
        },
        {
          type: 'ADD_ITEM',
          itemName: 'Khinkali',
          previousQty: 0,
          newQty: 3,
          timestamp: '2026-09-05T10:00:00.000Z',
          sequence: 1,
        },
      ],
    });

    const written = auditEvent.createMany.mock.calls[0][0] as {
      data: Array<{ type: string; seq: number }>;
    };
    expect(
      written.data.map((event) => [event.type, event.seq]),
    ).toEqual([
      ['CLOSE', 2],
      ['CREATE_WALKIN', 0],
      ['ADD_ITEM', 1],
    ]);
  });

  it('keeps a 41-event same-instant batch in the order the POS numbered', async () => {
    const { auditEvent } = await ingest({
      reportId: 'report-1',
      orderId: 12,
      events: creationBatch(),
    });

    const written = auditEvent.createMany.mock.calls[0][0] as {
      data: Array<{ type: string; seq: number }>;
    };
    expect(written.data).toHaveLength(41);
    expect(written.data.map((event) => event.seq)).toEqual(
      Array.from({ length: 41 }, (_unused, index) => index),
    );
    expect(written.data[0].type).toBe('CREATE_WALKIN');
  });

  it('falls back to array position for a POS that sends no sequence', async () => {
    const { auditEvent } = await ingest({
      reportId: 'report-1',
      orderId: 12,
      events: [
        { type: 'ADD_ITEM', previousQty: 0, newQty: 1 },
        { type: 'CLOSE' },
      ],
    });

    const written = auditEvent.createMany.mock.calls[0][0] as {
      data: Array<{ seq: number }>;
    };
    expect(written.data.map((event) => event.seq)).toEqual([0, 1]);
  });

  it('numbers by position when only some events carry a sequence', async () => {
    // Two numbering schemes in one report would interleave; it is all or
    // nothing.
    const { auditEvent } = await ingest({
      reportId: 'report-1',
      orderId: 12,
      events: [
        { type: 'CREATE_WALKIN', sequence: 5 },
        { type: 'ADD_ITEM', previousQty: 0, newQty: 1 },
      ],
    });

    const written = auditEvent.createMany.mock.calls[0][0] as {
      data: Array<{ seq: number }>;
    };
    expect(written.data.map((event) => event.seq)).toEqual([0, 1]);
  });

  it('stamps every event with the authenticated Venue, never the payload', async () => {
    const { auditEvent } = await ingest({
      reportId: 'report-1',
      orderId: 12,
      // A payload claiming another Venue must change nothing.
      venueId: 'venue-somebody-else',
      events: [
        {
          type: 'CREATE_WALKIN',
          sequence: 0,
          details: { venueId: 'venue-somebody-else' },
        },
      ],
    });

    const written = auditEvent.createMany.mock.calls[0][0] as {
      data: Array<{ venueId: string }>;
    };
    expect(written.data.map((event) => event.venueId)).toEqual(['venue-a']);
  });

  it('derives the report Order kind from its own creation event', async () => {
    const { auditReport } = await ingest({
      reportId: 'report-1',
      orderId: 12,
      events: creationBatch(),
    });

    expect(auditReport.upsert.mock.calls[0][0]).toMatchObject({
      create: { orderKind: 'WALK_IN' },
      update: { orderKind: 'WALK_IN' },
    });
  });

  it('leaves orderKind null for a report with no creation event', async () => {
    const { auditReport } = await ingest({
      reportId: 'legacy_report_order_9',
      orderId: 9,
      floor: 'takeaway',
      events: [{ type: 'ADD_ITEM', previousQty: 0, newQty: 1 }],
    });

    // `floor` says takeaway, and is still not evidence.
    expect(auditReport.upsert.mock.calls[0][0]).toMatchObject({
      create: { orderKind: null },
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
