import 'reflect-metadata';

// Named stubs: the guard assertions below compare class names, and the real
// modules drag in the firebase-admin / uuid (ESM) chain ts-jest can't load.
// The gateway is stubbed because the audit use case imported here pulls it in.
jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class MonitoringGateway {},
}));
jest.mock('../../auth/pos-sync.guard', () => ({
  PosSyncGuard: class PosSyncGuard {},
}));
jest.mock('../../auth/jwt-auth.guard', () => ({
  JwtAuthGuard: class JwtAuthGuard {},
}));
jest.mock('../../auth/roles.guard', () => ({
  RolesGuard: class RolesGuard {},
}));

import { RequestMethod } from '@nestjs/common';
import { SyncController } from './sync.controller';

/**
 * The controller is now transport only, so these tests pin the transport: the
 * route table the Flutter POS calls, the guards on each route, and the fact
 * that `manager-data` hands its body to the ingestion use case untouched and
 * returns that result unchanged.
 *
 * Route paths, methods and guards here are the POS's contract. A failure in
 * this file means an existing client stopped working.
 */

type CtorArgs = ConstructorParameters<typeof SyncController>;

interface Stubs {
  controller: SyncController;
  execute: jest.Mock;
  ingestReports: jest.Mock;
  ingestEventLogs: jest.Mock;
  restore: jest.Mock;
}

function makeController(): Stubs {
  const execute = jest.fn(() =>
    Promise.resolve({ success: true, syncedAt: 'stamped' }),
  );
  const ingestReports = jest.fn(() =>
    Promise.resolve({ success: true, upserted: 3 }),
  );
  const ingestEventLogs = jest.fn(() =>
    Promise.resolve({ success: true, count: 2 }),
  );
  const restore = jest.fn(() => Promise.resolve());
  const controller = new SyncController(
    {} as unknown as CtorArgs[0],
    { execute } as unknown as CtorArgs[1],
    { ingestReports, ingestEventLogs } as unknown as CtorArgs[2],
    { restore } as unknown as CtorArgs[3],
  );
  return { controller, execute, ingestReports, ingestEventLogs, restore };
}

function routeOf(method: keyof SyncController): {
  path: unknown;
  verb: unknown;
  guards: string[];
} {
  const handler = SyncController.prototype[method] as unknown as object;
  const guards =
    (Reflect.getMetadata('__guards__', handler) as
      | Array<new (...args: never[]) => unknown>
      | undefined) ?? [];
  return {
    path: Reflect.getMetadata('path', handler),
    verb: Reflect.getMetadata('method', handler),
    guards: guards.map((g) => g.name),
  };
}

describe('SyncController — route table', () => {
  it('is still mounted at /sync', () => {
    expect(Reflect.getMetadata('path', SyncController)).toBe('sync');
  });

  it('exposes GET /sync/ping unguarded', () => {
    expect(routeOf('ping')).toEqual({
      path: 'ping',
      verb: RequestMethod.GET,
      guards: [],
    });
  });

  it('exposes GET /sync/diff behind the manager JWT guards', () => {
    expect(routeOf('getDiff')).toEqual({
      path: 'diff',
      verb: RequestMethod.GET,
      guards: ['JwtAuthGuard', 'RolesGuard'],
    });
  });

  it('exposes POST /sync/manager-data behind the POS sync guard', () => {
    expect(routeOf('syncManagerData')).toEqual({
      path: 'manager-data',
      verb: RequestMethod.POST,
      guards: ['PosSyncGuard'],
    });
  });

  it('exposes POST /sync/audit-reports behind the POS sync guard', () => {
    expect(routeOf('syncAuditReports')).toEqual({
      path: 'audit-reports',
      verb: RequestMethod.POST,
      guards: ['PosSyncGuard'],
    });
  });

  it('exposes POST /sync/audit-logs behind the POS sync guard', () => {
    expect(routeOf('syncAuditEventLogs')).toEqual({
      path: 'audit-logs',
      verb: RequestMethod.POST,
      guards: ['PosSyncGuard'],
    });
  });
});

describe('SyncController — delegation', () => {
  it('hands the request body to the ingestion use case untouched', async () => {
    const { controller, execute } = makeController();
    const body = { businessDate: '2026-06-27', orders: [] };

    await controller.syncManagerData(body);

    expect(execute).toHaveBeenCalledTimes(1);
    expect(execute).toHaveBeenCalledWith(body);
    expect((execute.mock.calls as unknown[][])[0][0]).toBe(body);
  });

  it('returns the use case result unchanged', async () => {
    const { controller } = makeController();

    await expect(controller.syncManagerData({})).resolves.toEqual({
      success: true,
      syncedAt: 'stamped',
    });
  });

  it('hands audit reports to the audit use case and returns its result', async () => {
    const { controller, ingestReports } = makeController();
    const body = { reports: [{ reportId: 'r-1' }], fullSync: true };

    await expect(controller.syncAuditReports(body)).resolves.toEqual({
      success: true,
      upserted: 3,
    });
    expect(ingestReports).toHaveBeenCalledWith(body);
  });

  it('hands audit event logs to the audit use case and returns its result', async () => {
    const { controller, ingestEventLogs } = makeController();
    const body = { logs: [] };

    await expect(controller.syncAuditEventLogs(body)).resolves.toEqual({
      success: true,
      count: 2,
    });
    expect(ingestEventLogs).toHaveBeenCalledWith(body);
  });

  it('restores the POS callback registration on module init', async () => {
    const { controller, restore } = makeController();

    await controller.onModuleInit();

    expect(restore).toHaveBeenCalledTimes(1);
  });

  it('answers ping without touching any collaborator', () => {
    const { controller, execute, restore } = makeController();

    const result = controller.ping();

    expect(result.ok).toBe(true);
    expect(new Date(result.serverTime).toString()).not.toBe('Invalid Date');
    expect(execute).not.toHaveBeenCalled();
    expect(restore).not.toHaveBeenCalled();
  });
});
