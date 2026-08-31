jest.mock('../../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { IngestAuditReportsService } from './ingest-audit-reports.service';

const TENANT = { venueId: 'venue-a', organizationId: 'organization-a' };

describe('IngestAuditReportsService tenant scoping', () => {
  it('scopes report identity and full reconciliation to the authenticated Venue', async () => {
    const auditReport = {
      upsert: jest.fn(() => Promise.resolve({ id: 'db-report' })),
      findMany: jest.fn(() => Promise.resolve([])),
      deleteMany: jest.fn(() => Promise.resolve({ count: 0 })),
    };
    const auditEvent = {
      deleteMany: jest.fn(() => Promise.resolve({ count: 0 })),
      createMany: jest.fn(() => Promise.resolve({ count: 0 })),
    };
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
      findFirst: jest.fn(() => Promise.resolve(null)),
      create: jest.fn(() => Promise.resolve({ id: 'log-1' })),
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
