import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import {
  menu09App,
  seedMenu09,
  menu09Http,
  menu09Snapshot,
} from '../../test/menu09.fixture';
import { DeviceEnrollmentService } from '../edge/device-enrollment.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { MENU_CLIENT_CAPABILITY } from './menu-client-policy';

export const currentMenuClient = {
  version: 1,
  capabilities: [MENU_CLIENT_CAPABILITY],
  appVersion: 'synthetic-current+9',
  buildNumber: 9,
};
const old = {
  version: 1,
  capabilities: [],
  appVersion: 'synthetic-old',
  buildNumber: 1,
};
describe('MENU09 real HTTP/PostgreSQL compatibility matrix', () => {
  let live: Awaited<ReturnType<typeof menu09App>>;
  let venues: Awaited<ReturnType<typeof seedMenu09>>['venues'];
  const evidence: unknown[] = [];
  const rolloutPath = (v: (typeof venues)[number]) =>
    `/customer/venues/${v.venueId}/menu-rollout`;
  const http = (
    v: (typeof venues)[number],
    path: string,
    body?: unknown,
    client: unknown = currentMenuClient,
  ) => menu09Http(live.base, path, v.credential, body, false, client);
  const owner = (v: (typeof venues)[number], path: string, body?: unknown) =>
    menu09Http(live.base, path, v.ownerToken, body, true);
  const record = (name: string, value: unknown) =>
    evidence.push({ name, value });
  async function enroll(v: (typeof venues)[number], client: unknown) {
    const code = await live.app
      .get(DeviceEnrollmentService)
      .create({ customerAccountId: v.ownerId }, v.venueId, {
        displayName: 'Synthetic enrollment',
        platform: 'WINDOWS',
      });
    return menu09Http(live.base, '/edge/enroll', undefined, {
      enrollmentCode: code.code,
      installationId: randomUUID(),
      platform: 'WINDOWS',
      ...(client ? { menuClient: client } : {}),
    });
  }
  async function ready(v: (typeof venues)[number]) {
    expect(
      (
        await http(v, '/edge/menu-client/check-in', {
          menuClient: currentMenuClient,
        })
      ).status,
    ).toBe(201);
    const snapshot = menu09Snapshot();
    expect(
      (
        await http(v, '/sync/manager-data', {
          menu: snapshot,
          menuIdentityVersion: 1,
        })
      ).status,
    ).toBe(201);
    const r = await owner(v, rolloutPath(v));
    expect(r.status).toBe(200);
    return r;
  }
  const confirmation = (r: { body: Record<string, unknown> }) => ({
    readinessToken: r.body.readinessToken,
    allPosOnline: true,
    finalLegacySyncConfirmed: true,
    noPendingLocalMenuEdits: true,
    reason: 'Synthetic operator reconciliation',
  });
  beforeAll(async () => {
    const url = process.env.MENU09_TEST_DATABASE_URL;
    if (!url)
      throw Error(
        'MENU09_TEST_DATABASE_URL must name an owned disposable database; acceptance cannot be skipped',
      );
    live = await menu09App(url);
  });
  beforeEach(async () => {
    ({ venues } = await seedMenu09(live));
  });
  afterAll(async () => {
    if (process.env.MENU09_HTTP_PROOF)
      writeFileSync(
        process.env.MENU09_HTTP_PROOF,
        JSON.stringify(evidence, null, 2),
      );
    if (live) {
      await live.app.close();
      await live.db.$disconnect();
    }
  });

  it('1 canonical Venue rejects old enrollment without redeeming its invitation', async () => {
    const a = venues[0];
    const before = await live.db.device.count({
      where: { venueId: a.venueId },
    });
    const r = await enroll(a, old);
    expect(r.status).toBe(426);
    expect(r.body.code).toBe('MENU_UPDATE_REQUIRED');
    expect(await live.db.device.count({ where: { venueId: a.venueId } })).toBe(
      before,
    );
    expect(
      await live.db.deviceEnrollment.count({
        where: { venueId: a.venueId, redeemedAt: { not: null } },
      }),
    ).toBe(0);
    record('oldEnrollment', {
      status: r.status,
      body: r.body,
      businessRowsUnchanged: true,
    });
  });
  it('2 canonical Venue admits current enrollment and canonical bootstrap', async () => {
    const a = venues[0];
    const r = await enroll(a, currentMenuClient);
    expect(r.status).toBe(201);
    const v = { ...a, credential: r.body.credential as string };
    expect((await http(v, '/edge/runtime-config')).status).toBe(200);
    expect(
      (await http(v, '/edge/restaurant-foundation/bootstrap', {})).status,
    ).toBe(201);
    const catalog = await http(v, '/edge/menu/catalog');
    expect(catalog.status).toBe(200);
    expect(catalog.body.authority).toBe('CLOUD');
    record('currentEnrollment', { status: r.status, catalog: catalog.body });
  });
  it('3 legacy Venue admits old client and applies its snapshot', async () => {
    const b = venues[1];
    expect((await enroll(b, null)).status).toBe(201);
    const menu = menu09Snapshot(13);
    const r = await http(
      b,
      '/sync/manager-data',
      { menu, menuIdentityVersion: 1 },
      null,
    );
    expect(r.status).toBe(201);
    expect(r.body.menu).toEqual({ outcome: 'LEGACY_APPLIED' });
    expect(
      (
        await live.db.menuItem.findFirstOrThrow({
          where: { venueId: b.venueId },
        })
      ).price,
    ).toBe(13);
    expect(
      (await live.db.venue.findUniqueOrThrow({ where: { id: b.venueId } }))
        .menuAuthority,
    ).toBe('POS');
    record('legacyOld', r);
  });
  it('4 current client remains legacy without silently converting its Venue', async () => {
    const b = venues[1];
    expect((await enroll(b, currentMenuClient)).status).toBe(201);
    const r = await http(b, '/edge/menu/catalog');
    expect(r.status).toBe(200);
    expect(r.body.authority).toBe('POS');
    expect(
      (await live.db.venue.findUniqueOrThrow({ where: { id: b.venueId } }))
        .menuAuthority,
    ).toBe('POS');
    record('legacyCurrent', r);
  });
  it('5 enrolled old canonical device cannot receive false full-sync success; safe recovery remains', async () => {
    const a = venues[0];
    for (const path of [
      '/edge/menu/catalog',
      '/edge/menu/changes?since=0',
      '/edge/menu/retired',
      '/edge/runtime-config',
    ])
      expect((await http(a, path, undefined, null)).status).toBe(426);
    expect(
      (await http(a, '/edge/restaurant-foundation/bootstrap', {}, null)).status,
    ).toBe(426);
    const input = {
      menu: menu09Snapshot(777),
      tables: [
        { tableNumber: 'blocked', floor: 'synthetic', isReserved: true },
      ],
    };
    const r = await http(a, '/sync/manager-data', input, null);
    expect(r.status).toBe(426);
    expect(
      (
        await http(
          a,
          '/sync/manager-data',
          { ...input, realtimeOnly: true },
          null,
        )
      ).status,
    ).toBe(426);
    expect(await live.db.table.count({ where: { venueId: a.venueId } })).toBe(
      0,
    );
    expect(
      await live.db.menuItem.count({ where: { venueId: a.venueId } }),
    ).toBe(0);
    expect(
      (
        await http(
          a,
          '/sync/manager-data',
          { realtimeOnly: true, tables: [] },
          null,
        )
      ).status,
    ).toBe(201);
    expect((await http(a, '/sync/audit-logs', { logs: [] }, null)).status).toBe(
      201,
    );
    record('enrolledOld', {
      rejection: r,
      noPartialRows: true,
      safeRecovery: true,
    });
  });
  it('6 cutover detects every incompatible ACTIVE device, including non-primary', async () => {
    const b = venues[1];
    await ready(b);
    const extra = await live.app.get(DeviceCredentialService).issueCredential({
      venueId: b.venueId,
      installationId: randomUUID(),
      displayName: 'Forgotten old POS',
      platform: 'WINDOWS',
    });
    const r = await owner(b, rolloutPath(b));
    expect(r.body.verdict).toBe('BLOCKED');
    expect(
      (r.body.blockers as string[]).some((x) => x.includes(extra.deviceId)),
    ).toBe(true);
    expect(
      (await owner(b, rolloutPath(b) + '/cutover', confirmation(r))).status,
    ).toBe(409);
    record('incompatibleFleet', r);
  });
  it('7 stale compatibility blocks cutover even when credential lastSeen is fresh', async () => {
    const b = venues[1];
    await ready(b);
    await live.db.device.updateMany({
      where: { venueId: b.venueId },
      data: {
        menuClientObservedAt: new Date(Date.now() - 16 * 60_000),
        lastSeenAt: new Date(),
      },
    });
    const r = await owner(b, rolloutPath(b));
    expect(r.body.verdict).toBe('BLOCKED');
    expect(
      (r.body.blockers as string[]).some((x) =>
        x.startsWith('DEVICE_REPORT_STALE'),
      ),
    ).toBe(true);
    expect(
      (await owner(b, rolloutPath(b) + '/cutover', confirmation(r))).status,
    ).toBe(409);
    record('staleFleet', r);
  });
  it('8 existing disable/revoke lifecycle excludes an incompatible device from readiness', async () => {
    const b = venues[1];
    await ready(b);
    const extra = await live.app.get(DeviceCredentialService).issueCredential({
      venueId: b.venueId,
      installationId: randomUUID(),
      displayName: 'Old secondary',
      platform: 'WINDOWS',
    });
    expect((await owner(b, rolloutPath(b))).body.verdict).toBe('BLOCKED');
    await live.db.device.update({
      where: { id: extra.deviceId },
      data: { status: 'REVOKED' },
    });
    const r = await owner(b, rolloutPath(b));
    expect(r.body.verdict).toBe('READY_FOR_CUTOVER');
    expect(
      (await menu09Http(live.base, '/edge/menu/catalog', extra.credential))
        .status,
    ).toBe(401);
    record('revokedExcluded', r);
  });
  it('9 explicit controlled cutover preserves node identities and audit, rejecting changed readiness', async () => {
    const b = venues[1];
    const r = await ready(b);
    expect(r.body.verdict).toBe('READY_FOR_CUTOVER');
    expect(
      (
        await owner(b, rolloutPath(b) + '/cutover', {
          ...confirmation(r),
          readinessToken: 'old',
        })
      ).status,
    ).toBe(409);
    expect(
      (
        await owner(b, rolloutPath(b) + '/cutover', {
          ...confirmation(r),
          noPendingLocalMenuEdits: false,
        })
      ).status,
    ).toBe(400);
    const before = await live.db.menuItem.findMany({
      where: { venueId: b.venueId },
    });
    const cutover = await owner(
      b,
      rolloutPath(b) + '/cutover',
      confirmation(r),
    );
    expect(cutover.status).toBe(201);
    expect(
      await live.db.menuItem.findMany({ where: { venueId: b.venueId } }),
    ).toEqual(before);
    expect(
      await live.db.customerAuditEvent.count({
        where: { targetId: b.venueId, action: 'venue.menu_cutover' },
      }),
    ).toBe(1);
    record('controlledCutover', cutover);
  });
  it('10 old binary reconnect after cutover is rejected despite prior stored compatible report', async () => {
    const b = venues[1];
    const r = await ready(b);
    expect(
      (await owner(b, rolloutPath(b) + '/cutover', confirmation(r))).status,
    ).toBe(201);
    const before = await live.db.menuItem.findMany({
      where: { venueId: b.venueId },
    });
    const rejection = await http(
      b,
      '/sync/manager-data',
      { menu: menu09Snapshot(999) },
      null,
    );
    expect(rejection.status).toBe(426);
    expect(
      (await http(b, '/edge/runtime-config', undefined, null)).status,
    ).toBe(426);
    expect(
      await live.db.menuItem.findMany({ where: { venueId: b.venueId } }),
    ).toEqual(before);
    record('oldAfterCutover', rejection);
  });
  it('11 current client bootstrap after cutover succeeds', async () => {
    const b = venues[1];
    const r = await ready(b);
    await owner(b, rolloutPath(b) + '/cutover', confirmation(r));
    const catalog = await http(b, '/edge/menu/catalog');
    expect(catalog.status).toBe(200);
    expect(catalog.body.authority).toBe('CLOUD');
    expect((await http(b, '/edge/runtime-config')).status).toBe(200);
    record('bootstrapAfterCutover', catalog);
  });
  it('12 canonical mutation/retry/retirement/restore after cutover preserves existing protocols', async () => {
    const b = venues[1];
    const r = await ready(b);
    await owner(b, rolloutPath(b) + '/cutover', confirmation(r));
    const item = await live.db.menuItem.findFirstOrThrow({
      where: { venueId: b.venueId },
    });
    const mutation = {
      mutationId: randomUUID(),
      entityType: 'ITEM',
      entityId: item.posMenuItemId,
      operation: 'UPSERT',
      expectedRevision: item.revision,
      patch: { price: 21 },
    };
    const edit = await http(b, '/edge/menu/mutations', mutation);
    expect(edit.status).toBe(200);
    const removal = await http(b, '/edge/menu/mutations', {
      ...mutation,
      mutationId: randomUUID(),
      operation: 'DELETE',
      expectedRevision: edit.body.revision,
      patch: undefined,
    });
    expect(removal.status).toBe(200);
    expect((await http(b, '/edge/menu/mutations', mutation)).body).toEqual({
      ...edit.body,
      duplicate: true,
    });
    const restore = await http(b, '/edge/menu/mutations', {
      ...mutation,
      mutationId: randomUUID(),
      expectedRevision: removal.body.revision,
      patch: { restore: true },
    });
    expect(restore.status).toBe(200);
    record('canonicalAfterCutover', { edit, removal, restore });
  });
  it('13 fake Venue selectors cannot bypass server mode and build policy', async () => {
    const a = venues[0];
    const r = await http(
      a,
      '/sync/manager-data',
      { venueId: venues[1].venueId, menuAuthority: 'POS', menu: [] },
      null,
    );
    expect(r.status).toBe(426);
    process.env.MENU_CANONICAL_MIN_BUILD_WINDOWS = '10';
    try {
      expect((await http(a, '/edge/menu/catalog')).status).toBe(426);
      expect((await http(venues[1], '/edge/menu/catalog')).status).toBe(200);
    } finally {
      delete process.env.MENU_CANONICAL_MIN_BUILD_WINDOWS;
    }
    expect((await http(a, '/sync/manager-data', { menu: [] })).body.code).toBe(
      'CANONICAL_MENU_SNAPSHOT_UNSUPPORTED',
    );
    record('serverOwnedPolicy', r);
  });
  it('14 cross-Venue owners/devices and unauthenticated metadata writes fail closed', async () => {
    const [a, b] = venues;
    const before = await live.db.device.findFirstOrThrow({
      where: { venueId: b.venueId },
    });
    expect((await owner(a, rolloutPath(b))).status).toBe(404);
    expect(
      (
        await owner(a, rolloutPath(b) + '/cutover', {
          allPosOnline: true,
          finalLegacySyncConfirmed: true,
          noPendingLocalMenuEdits: true,
          reason: 'foreign',
        })
      ).status,
    ).toBe(404);
    expect(
      (
        await http(a, '/edge/menu-client/check-in', {
          menuClient: currentMenuClient,
          deviceId: before.id,
          venueId: b.venueId,
        })
      ).status,
    ).toBe(400);
    expect(
      (
        await menu09Http(live.base, '/edge/menu-client/check-in', undefined, {
          menuClient: currentMenuClient,
        })
      ).status,
    ).toBe(401);
    expect(
      (await live.db.device.findUniqueOrThrow({ where: { id: before.id } }))
        .menuClientReport,
    ).toEqual(before.menuClientReport);
    expect(
      (await live.db.venue.findUniqueOrThrow({ where: { id: b.venueId } }))
        .menuAuthority,
    ).toBe('POS');
    record('tenantMatrix', {
      foreignOwner: 404,
      foreignMetadata: 400,
      unauthenticated: 401,
      otherVenueUnchanged: true,
    });
  });
  it('16 invalid or cross-kind duplicate legacy identities block canonical adoption', async () => {
    const b = venues[1];
    await ready(b);
    const item = await live.db.menuItem.findFirstOrThrow({
      where: { venueId: b.venueId },
    });
    const category = await live.db.menuCategory.findFirstOrThrow({
      where: { venueId: b.venueId },
    });
    for (const id of ['legacy-name', category.posMenuCategoryId]) {
      await live.db.menuItem.update({
        where: { id: item.id },
        data: { posMenuItemId: id },
      });
      const r = await owner(b, rolloutPath(b));
      expect(r.body.verdict).toBe('BLOCKED');
      expect(
        (r.body.blockers as string[]).some((x) =>
          x.startsWith('MENU_IDENTITY_'),
        ),
      ).toBe(true);
      expect(
        (await owner(b, rolloutPath(b) + '/cutover', confirmation(r))).status,
      ).toBe(409);
    }
    record('invalidIdentity', {
      invalidUuidBlocked: true,
      crossKindCollisionBlocked: true,
    });
  });
  it('17 a changed legacy snapshot invalidates the preview token', async () => {
    const b = venues[1];
    const r = await ready(b);
    await live.db.menuItem.updateMany({
      where: { venueId: b.venueId },
      data: { price: 33 },
    });
    const result = await owner(b, rolloutPath(b) + '/cutover', confirmation(r));
    expect(result.status).toBe(409);
    expect(result.body.code).toBe('MENU_READINESS_CHANGED');
    record('changedSnapshot', result);
  });
  it('15 backend restart retains report/cutover and rollback never invents merge semantics', async () => {
    const b = venues[1];
    const r = await ready(b);
    await owner(b, rolloutPath(b) + '/cutover', confirmation(r));
    const before = await live.db.venue.findUniqueOrThrow({
      where: { id: b.venueId },
    });
    const url = process.env.MENU09_TEST_DATABASE_URL!;
    await live.app.close();
    await live.db.$disconnect();
    live = await menu09App(url);
    expect((await http(b, '/edge/menu/catalog')).status).toBe(200);
    expect((await http(b, '/edge/menu/catalog', undefined, null)).status).toBe(
      426,
    );
    expect(
      (await live.db.venue.findUniqueOrThrow({ where: { id: b.venueId } }))
        .menuCutover,
    ).toEqual(before.menuCutover);
    expect((await owner(b, rolloutPath(b) + '/rollback', {})).body.code).toBe(
      'MENU_ROLLBACK_UNSUPPORTED',
    );
    record('restart', {
      cutoverRetained: true,
      compatibilityEnforced: true,
      rollbackRejected: true,
    });
  });
});
