import 'reflect-metadata';
import { HttpException } from '@nestjs/common';
import type { PrismaClient } from '@prisma/client';
import { CustomerService } from './customer.service';
import { DeviceRuntimeConfigController } from './customer.controller';
import type { PrismaService } from '../prisma.service';
import type { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import type { PlatformCommercialService } from '../platform/platform-commercial.service';
import type { DeviceEnrollmentService } from '../edge/device-enrollment.service';
import {
  persistPreparedPrinterRuntimeConfig,
  printerRuntimeConfigForReader,
} from './printer-runtime-persistence';
import {
  MAX_PRINTER_RUNTIME_CONFIG_BYTES,
  MAX_PRINTER_RUNTIME_REVISION,
} from './printer-runtime-config';

const deviceId = '11111111-1111-4111-8111-111111111111';
const secondDeviceId = '22222222-2222-4222-8222-222222222222';
const venueId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const organizationId = '44444444-4444-4444-8444-444444444444';
const otherVenueId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const ownerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const platformId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const requestId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const laterRequestId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const thirdRequestId = '33333333-3333-4333-8333-333333333333';
const owner = { customerAccountId: ownerId };
const platform = { platformUserId: platformId };
const context = { deviceId, venueId };
type JsonObject = Record<string, any>;
const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value));

function route(overrides: JsonObject = {}): JsonObject {
  return {
    protocol: 1,
    id: 'kitchen',
    name: 'Kitchen',
    role: 'kitchen',
    revision: 1,
    enabled: true,
    destination: { kind: 'tcp', host: '192.168.1.50', port: 9100 },
    capabilityProfile: {
      protocol: 1,
      paperWidthMm: 80,
      rasterWidthDots: 576,
      language: 'escposRaster',
      cutter: 'partial',
      encoding: 'georgianViaRaster',
      beep: { capability: 'unknown', enabled: false },
    },
    ...overrides,
  };
}
function envelope(overrides: JsonObject = {}): JsonObject {
  return {
    version: 2,
    requestId,
    expectedRevision: 0,
    minimumReaderVersion: 2,
    routes: [route()],
    ...overrides,
  };
}
function legacy() {
  return {
    kitchen: { enabled: true, host: '192.168.1.71', port: 9100 },
    receipt: { enabled: false, host: '', port: 9100 },
  };
}
type State = {
  devices: Record<string, JsonObject>;
  journal: Record<string, JsonObject>;
  customerAudit: JsonObject[];
  platformAudit: JsonObject[];
};

/**
 * Explicit in-memory transaction fake: verifies orchestration, serialized fake
 * requests and rollback. It is not PostgreSQL row-lock/constraint/migration proof.
 */
class FakePrinterDatabase {
  state: State = {
    devices: {
      [deviceId]: {
        id: deviceId,
        venueId,
        runtimeConfig: null,
        status: 'REVOKED',
        credentialHash: 'unchanged-verifier',
      },
    },
    journal: {},
    customerAudit: [],
    platformAudit: [],
  };
  events: string[] = [];
  queries: { sql: string; parameters: unknown[] }[] = [];
  ownerAllowed = true;
  transactionOwnerAllowed = true;
  posAllowed = true;
  transactionPosAllowed = true;
  failAt: 'after-device' | 'after-journal' | 'after-audit' | null = null;
  missCas = false;
  private queue: Promise<void> = Promise.resolve();
  private commercialVenue(allowed: boolean) {
    return {
      id: venueId,
      legacyCommercialAccess: true,
      subscription: null,
      planAssignment: null,
      featureOverrides: allowed
        ? [{ feature: { key: 'POS' }, effect: 'ENABLED' }]
        : [],
      websiteConfig: null,
    };
  }
  venue = {
    findFirst: async () => (this.ownerAllowed ? { id: venueId } : null),
    findUnique: async () => this.commercialVenue(this.posAllowed),
  };
  async $transaction<T>(work: (tx: any) => Promise<T>): Promise<T> {
    const previous = this.queue;
    let release!: () => void;
    this.queue = new Promise<void>((resolve) => {
      release = resolve;
    });
    await previous;
    const pending = clone(this.state);
    this.events.push('begin');
    const sql = (strings: TemplateStringsArray, parameters: unknown[]) => {
      const text = strings.join('?').replace(/\s+/g, ' ').trim();
      this.queries.push({ sql: text, parameters: clone(parameters) });
      return text;
    };
    const tx = {
      $queryRaw: async (
        strings: TemplateStringsArray,
        ...parameters: unknown[]
      ) => {
        const query = sql(strings, parameters);
        if (
          query.includes('FROM "pos"."Venue"') &&
          query.endsWith('FOR UPDATE')
        ) {
          this.events.push('venue-lock');
          return parameters[0] === venueId
            ? [{ id: venueId, organizationId }]
            : [];
        }
        if (
          query.includes('FROM "pos"."Device"') &&
          query.endsWith('FOR UPDATE')
        ) {
          this.events.push('device-lock');
          const [id, tenant] = parameters;
          const device = pending.devices[String(id)];
          return device && device.venueId === tenant ? [clone(device)] : [];
        }
        if (
          query.includes('FROM "pos"."OrganizationMembership"') &&
          query.endsWith('FOR SHARE')
        ) {
          this.events.push('membership-lock');
          expect(parameters).toEqual([ownerId, organizationId]);
          return this.transactionOwnerAllowed
            ? [{ customerAccountId: ownerId, organizationId }]
            : [];
        }
        if (query.includes('FROM "pos"."DevicePrinterRuntimeRequest"')) {
          this.events.push('journal-read');
          const receipt = pending.journal[`${parameters[0]}/${parameters[1]}`];
          return receipt ? [clone(receipt)] : [];
        }
        throw new Error(`Unexpected fake query: ${query}`);
      },
      $executeRaw: async (
        strings: TemplateStringsArray,
        ...parameters: unknown[]
      ) => {
        const query = sql(strings, parameters);
        if (query.startsWith('UPDATE "pos"."Device"')) {
          this.events.push('device-cas');
          const [json, id, tenant, beforeJson] = parameters;
          const device = pending.devices[String(id)];
          if (
            this.missCas ||
            !device ||
            device.venueId !== tenant ||
            JSON.stringify(device.runtimeConfig) !== beforeJson
          )
            return 0;
          device.runtimeConfig = JSON.parse(String(json));
          if (this.failAt === 'after-device')
            throw new Error('Injected failure after Device write');
          return 1;
        }
        if (
          query.startsWith('INSERT INTO "pos"."DevicePrinterRuntimeRequest"')
        ) {
          this.events.push('journal-insert');
          const [
            id,
            key,
            tenant,
            actorType,
            actorId,
            inputSha256,
            expectedRevision,
            outcomeStatus,
            outcomeJson,
          ] = parameters;
          const scopedKey = `${id}/${key}`;
          if (pending.journal[scopedKey])
            throw new Error('Fake duplicate receipt');
          pending.journal[scopedKey] = {
            deviceId: id,
            requestId: key,
            venueId: tenant,
            actorType,
            actorId,
            inputSha256,
            expectedRevision,
            outcomeStatus,
            outcomeJson,
          };
          if (this.failAt === 'after-journal')
            throw new Error('Injected failure after journal insert');
          return 1;
        }
        throw new Error(`Unexpected fake mutation: ${query}`);
      },
      venue: {
        findFirst: async (query: JsonObject) => {
          this.events.push('owner-recheck');
          expect(query.where.id).toBe(venueId);
          expect(query.where.organizationId).toBe(organizationId);
          expect(query.where.organization.memberships.some).toEqual({
            customerAccountId: ownerId,
            role: 'OWNER',
          });
          return this.transactionOwnerAllowed ? { id: venueId } : null;
        },
        findUnique: async () => {
          this.events.push('pos-recheck');
          return this.commercialVenue(this.transactionPosAllowed);
        },
      },
      device: {
        update: async ({ where, data }: JsonObject) => {
          this.events.push('legacy-write');
          const device = pending.devices[where.id];
          Object.assign(device, clone(data));
          if (this.failAt === 'after-device')
            throw new Error('Injected failure after Device write');
          return clone(device);
        },
      },
      customerAuditEvent: {
        create: async ({ data }: JsonObject) => {
          this.events.push('customer-audit');
          pending.customerAudit.push(clone(data));
          if (this.failAt === 'after-audit')
            throw new Error('Injected failure after audit write');
          return data;
        },
      },
      platformAuditEvent: {
        create: async ({ data }: JsonObject) => {
          this.events.push('platform-audit');
          pending.platformAudit.push(clone(data));
          if (this.failAt === 'after-audit')
            throw new Error('Injected failure after audit write');
          return data;
        },
      },
    };
    try {
      const result = await work(tx);
      this.state = pending;
      this.events.push('commit');
      return result;
    } catch (error) {
      this.events.push('rollback');
      throw error;
    } finally {
      release();
    }
  }
  client(): Pick<PrismaClient, '$transaction'> {
    return this as unknown as Pick<PrismaClient, '$transaction'>;
  }
  service() {
    return new CustomerService(
      this as unknown as PrismaService,
      {} as VenueEntitlementsService,
      {} as PlatformCommercialService,
      {} as DeviceEnrollmentService,
    );
  }
  receipt(key = requestId, id = deviceId) {
    return this.state.journal[`${id}/${key}`];
  }
}

async function httpError(
  action: Promise<unknown>,
  status: number,
): Promise<HttpException> {
  try {
    await action;
    throw new Error('Expected HTTP rejection');
  } catch (error) {
    expect(error).toBeInstanceOf(HttpException);
    expect((error as HttpException).getStatus()).toBe(status);
    return error as HttpException;
  }
}

describe('printer PREPARED persistence — fake transactions, not PostgreSQL proof', () => {
  it('atomically prepares Owner config, immutable response and Customer audit using bound Device parameters', async () => {
    const db = new FakePrinterDatabase();
    const result = await db
      .service()
      .printers(owner, venueId, deviceId, envelope());
    expect(result).toMatchObject({
      version: 2,
      deviceId,
      venueId,
      revision: 1,
      phase: 'PREPARED',
      minimumReaderVersion: 2,
    });
    expect(result.printers).toEqual({
      kitchen: { enabled: false, host: '', port: 9100 },
      receipt: { enabled: false, host: '', port: 9100 },
    });
    expect(db.state.devices[deviceId].runtimeConfig).toEqual(result);
    expect(db.state.devices[deviceId]).toMatchObject({
      status: 'REVOKED',
      credentialHash: 'unchanged-verifier',
    });
    expect(db.receipt()).toMatchObject({
      deviceId,
      venueId,
      actorType: 'CUSTOMER',
      actorId: ownerId,
      expectedRevision: 0,
      outcomeStatus: 200,
    });
    expect(db.receipt().inputSha256).toMatch(/^[0-9a-f]{64}$/);
    expect(db.receipt().outcomeJson).toBe(JSON.stringify(result));
    expect(db.state.customerAudit).toHaveLength(1);
    expect(db.state.customerAudit[0]).toMatchObject({
      customerAccountId: ownerId,
      action: 'device.printers_prepared',
      targetId: deviceId,
      metadata: { requestId, from: null, to: result },
    });
    expect(db.state.platformAudit).toHaveLength(0);
    expect(db.events).toEqual([
      'begin',
      'venue-lock',
      'device-lock',
      'membership-lock',
      'owner-recheck',
      'pos-recheck',
      'journal-read',
      'device-cas',
      'journal-insert',
      'customer-audit',
      'commit',
    ]);
    expect(db.queries[0].parameters).toEqual([venueId]);
    expect(db.queries[1].parameters).toEqual([deviceId, venueId]);
    expect(db.queries[1].sql).toContain(
      'WHERE "id" = ? AND "venueId" = ? FOR UPDATE',
    );
    for (const query of db.queries) expect(query.sql).not.toContain(deviceId);
  });

  it('keeps Platform identity and audit separate without claiming Customer ownership', async () => {
    const db = new FakePrinterDatabase();
    await db.service().printers(platform, venueId, deviceId, envelope());
    expect(db.receipt()).toMatchObject({
      actorType: 'PLATFORM',
      actorId: platformId,
    });
    expect(db.state.platformAudit).toHaveLength(1);
    expect(db.state.platformAudit[0]).toMatchObject({
      platformUserId: platformId,
      action: 'device.printers_prepared',
    });
    expect(db.state.customerAudit).toHaveLength(0);
    expect(db.events).not.toContain('owner-recheck');
  });

  it('snapshots validated input, writer and context before asynchronous lock acquisition', async () => {
    const db = new FakePrinterDatabase();
    const input = envelope();
    const writer = { ...owner };
    const requestedContext = { ...context };
    const pending = persistPreparedPrinterRuntimeConfig(
      db.client(),
      writer,
      requestedContext,
      input,
    );
    input.routes[0].destination.host = '192.168.1.99';
    input.routes[0].capabilityProfile.beep.enabled = true;
    writer.customerAccountId = platformId;
    requestedContext.venueId = otherVenueId;
    const result = await pending;
    expect(result.routes[0].destination).toMatchObject({
      host: '192.168.1.50',
    });
    expect(db.receipt()).toMatchObject({ actorId: ownerId, venueId });
    expect(
      await persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
    ).toEqual(result);
  });

  it('rejects another Platform writer using the same requestId without replacing the result', async () => {
    const db = new FakePrinterDatabase();
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      platform,
      context,
      envelope(),
    );
    const before = clone(db.state);
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        { platformUserId: ownerId },
        context,
        envelope(),
      ),
      409,
    );
    expect(db.state).toEqual(before);
  });

  it('returns exact original response on an identical retry after a later revision without new writes/audit', async () => {
    const db = new FakePrinterDatabase();
    const initial = envelope();
    const first = await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      initial,
    );
    const firstText = JSON.stringify(first);
    const originalReceipt = clone(db.receipt());
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope({
        requestId: laterRequestId,
        expectedRevision: 1,
        routes: [route({ enabled: false, revision: 2 })],
      }),
    );
    const current = clone(db.state.devices[deviceId].runtimeConfig);
    const retried = await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      initial,
    );
    expect(JSON.stringify(retried)).toBe(firstText);
    expect(retried.revision).toBe(1);
    expect(db.state.devices[deviceId].runtimeConfig).toEqual(current);
    expect(db.receipt()).toEqual(originalReceipt);
    expect(Object.keys(db.state.journal)).toHaveLength(2);
    expect(db.state.customerAudit).toHaveLength(2);
    expect(db.events.slice(-8)).toEqual([
      'begin',
      'venue-lock',
      'device-lock',
      'membership-lock',
      'owner-recheck',
      'pos-recheck',
      'journal-read',
      'commit',
    ]);
  });

  it('canonicalizes object key order while preserving actual optional-beep input distinctions', async () => {
    const db = new FakePrinterDatabase();
    const input = envelope();
    input.routes[0].capabilityProfile.beep = {
      capability: 'future',
      arbitrary: [27, 65],
    };
    const first = await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      input,
    );
    expect(first.routes[0].capabilityProfile.beep).toEqual({
      capability: 'unknown',
      enabled: false,
    });
    const reverseKeys = (value: any): any =>
      Array.isArray(value)
        ? value.map(reverseKeys)
        : value && typeof value === 'object'
          ? Object.fromEntries(
              Object.entries(value)
                .reverse()
                .map(([key, item]) => [key, reverseKeys(item)]),
            )
          : value;
    expect(
      await persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        reverseKeys(input),
      ),
    ).toEqual(first);
    const changed = clone(input);
    changed.routes[0].capabilityProfile.beep.arbitrary = [27, 66];
    await httpError(
      persistPreparedPrinterRuntimeConfig(db.client(), owner, context, changed),
      409,
    );
    expect(Object.keys(db.state.journal)).toHaveLength(1);
    expect(db.state.customerAudit).toHaveLength(1);
  });

  it('rejects requestId reuse with changed input, actor type, or actor identity while retaining the original receipt', async () => {
    const db = new FakePrinterDatabase();
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
    const before = clone(db.state);
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope({ expectedRevision: 1 }),
      ),
      409,
    );
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        platform,
        context,
        envelope(),
      ),
      409,
    );
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        { platformUserId: ownerId },
        context,
        envelope(),
      ),
      409,
    );
    expect(db.state).toEqual(before);
  });

  it('persists a CAS conflict before throwing, and returns its exact immutable failure after later revisions', async () => {
    const db = new FakePrinterDatabase();
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
    const stale = envelope({ requestId: laterRequestId });
    const conflict = await httpError(
      persistPreparedPrinterRuntimeConfig(db.client(), owner, context, stale),
      409,
    );
    expect(db.events.at(-1)).toBe('commit');
    expect(db.receipt(laterRequestId)).toMatchObject({
      outcomeStatus: 409,
      expectedRevision: 0,
    });
    expect(db.receipt(laterRequestId).outcomeJson).toBe(
      JSON.stringify(conflict.getResponse()),
    );
    expect(db.state.customerAudit).toHaveLength(1);
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope({
        requestId: thirdRequestId,
        expectedRevision: 1,
        routes: [route({ enabled: false, revision: 2 })],
      }),
    );
    const retried = await httpError(
      persistPreparedPrinterRuntimeConfig(db.client(), owner, context, stale),
      409,
    );
    expect(JSON.stringify(retried.getResponse())).toBe(
      JSON.stringify(conflict.getResponse()),
    );
    expect(db.events.at(-1)).toBe('commit');
    expect(db.state.devices[deviceId].runtimeConfig.revision).toBe(2);
    expect(Object.keys(db.state.journal)).toHaveLength(3);
  });

  it('journals a missed database CAS as conflict without configuration or success audit', async () => {
    const db = new FakePrinterDatabase();
    db.missCas = true;
    const error = await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
      409,
    );
    expect(error.getResponse()).toMatchObject({
      code: 'PRINTER_REVISION_CONFLICT',
    });
    expect(db.state.devices[deviceId].runtimeConfig).toBeNull();
    expect(db.receipt().outcomeStatus).toBe(409);
    expect(db.state.customerAudit).toHaveLength(0);
    expect(db.events.at(-1)).toBe('commit');
  });

  it.each(['omitted-route', 'route-revision'] as const)(
    'journals immutable %s conflicts without changing accepted routes',
    async (change) => {
      const db = new FakePrinterDatabase();
      await persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      );
      const before = clone(db.state.devices[deviceId].runtimeConfig);
      const input = envelope({
        requestId: laterRequestId,
        expectedRevision: 1,
        routes:
          change === 'omitted-route'
            ? []
            : [route({ enabled: false, revision: 1 })],
      });
      const error = await httpError(
        persistPreparedPrinterRuntimeConfig(db.client(), owner, context, input),
        409,
      );
      expect(error.getResponse()).toMatchObject({
        code: 'PRINTER_REVISION_CONFLICT',
      });
      expect(db.receipt(laterRequestId).outcomeStatus).toBe(409);
      expect(db.state.devices[deviceId].runtimeConfig).toEqual(before);
      expect(db.state.customerAudit).toHaveLength(1);
      expect(db.events.at(-1)).toBe('commit');
    },
  );

  it('journals revision exhaustion without resetting identities or counters', async () => {
    const db = new FakePrinterDatabase();
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
    db.state.devices[deviceId].runtimeConfig.revision =
      MAX_PRINTER_RUNTIME_REVISION;
    const error = await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope({
          requestId: laterRequestId,
          expectedRevision: MAX_PRINTER_RUNTIME_REVISION,
        }),
      ),
      409,
    );
    expect(error.getResponse()).toMatchObject({
      code: 'PRINTER_REVISION_EXHAUSTED',
    });
    expect(db.receipt(laterRequestId).outcomeStatus).toBe(409);
    expect(db.state.devices[deviceId].runtimeConfig.revision).toBe(
      MAX_PRINTER_RUNTIME_REVISION,
    );
    expect(db.state.customerAudit).toHaveLength(1);
  });

  it.each(['after-device', 'after-journal', 'after-audit'] as const)(
    'rolls back config, receipt and audit after injected %s failure',
    async (failure) => {
      const db = new FakePrinterDatabase();
      const before = clone(db.state);
      db.failAt = failure;
      await expect(
        persistPreparedPrinterRuntimeConfig(
          db.client(),
          owner,
          context,
          envelope(),
        ),
      ).rejects.toThrow('Injected failure');
      expect(db.state).toEqual(before);
      expect(db.events.at(-1)).toBe('rollback');
      db.failAt = null;
      expect(
        (
          await persistPreparedPrinterRuntimeConfig(
            db.client(),
            owner,
            context,
            envelope(),
          )
        ).revision,
      ).toBe(1);
      expect(db.state.customerAudit).toHaveLength(1);
    },
  );

  it('serializes fake competing preparations and duplicate requests with one accepted change', async () => {
    const db = new FakePrinterDatabase();
    const results = await Promise.allSettled([
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope({ requestId: laterRequestId }),
      ),
    ]);
    expect(results[0].status).toBe('fulfilled');
    expect(results[1]).toEqual(results[0]);
    expect(results[2].status).toBe('rejected');
    expect(db.state.devices[deviceId].runtimeConfig.revision).toBe(1);
    expect(db.state.customerAudit).toHaveLength(1);
    expect(Object.keys(db.state.journal)).toHaveLength(2);
  });

  it('scopes request identity per Device and rejects a Device outside the authorized Venue', async () => {
    const db = new FakePrinterDatabase();
    db.state.devices[secondDeviceId] = {
      id: secondDeviceId,
      venueId,
      runtimeConfig: null,
    };
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      { deviceId: secondDeviceId, venueId },
      envelope(),
    );
    expect(Object.keys(db.state.journal)).toHaveLength(2);
    expect(db.receipt(requestId, secondDeviceId).deviceId).toBe(secondDeviceId);
    const before = clone(db.state);
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        platform,
        { deviceId, venueId: otherVenueId },
        envelope(),
      ),
      404,
    );
    expect(db.state).toEqual(before);
  });

  it('rechecks transaction ownership and commercial POS before journal lookup, including retries', async () => {
    const db = new FakePrinterDatabase();
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
    const before = clone(db.state);
    db.transactionOwnerAllowed = false;
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
      404,
    );
    expect(db.events.slice(-5)).toEqual([
      'begin',
      'venue-lock',
      'device-lock',
      'membership-lock',
      'rollback',
    ]);
    db.transactionOwnerAllowed = true;
    db.transactionPosAllowed = false;
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
      403,
    );
    expect(db.events.slice(-7)).toEqual([
      'begin',
      'venue-lock',
      'device-lock',
      'membership-lock',
      'owner-recheck',
      'pos-recheck',
      'rollback',
    ]);
    expect(db.state).toEqual(before);
  });

  it.each(['tenantId', 'deviceId', 'venueId', 'phase', 'printers', 'actor'])(
    'rejects extra envelope field %s before opening a transaction',
    async (key) => {
      const db = new FakePrinterDatabase();
      await httpError(
        persistPreparedPrinterRuntimeConfig(
          db.client(),
          owner,
          context,
          envelope({ [key]: deviceId }),
        ),
        400,
      );
      expect(db.events).toHaveLength(0);
    },
  );

  it.each([
    { requestId: 'garbage' },
    { expectedRevision: -1 },
    { expectedRevision: 0.1 },
    { expectedRevision: '0' },
    { minimumReaderVersion: 1 },
    { version: '2' },
    { routes: [route({ id: '../bad' })] },
  ])(
    'validates exact first/retry input before consulting a receipt: %j',
    async (overrides) => {
      const db = new FakePrinterDatabase();
      await persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      );
      const before = db.queries.length;
      await httpError(
        persistPreparedPrinterRuntimeConfig(
          db.client(),
          owner,
          context,
          envelope(overrides),
        ),
        400,
      );
      expect(db.queries).toHaveLength(before);
    },
  );

  it('bounds raw fingerprint complexity and rejects non-JSON misuse without invoking getters', async () => {
    const malformed: any[] = [
      NaN,
      Infinity,
      BigInt(1),
      new Date(),
      'x'.repeat(MAX_PRINTER_RUNTIME_CONFIG_BYTES + 1),
      new Array(2),
      Array(20000).fill(null),
    ];
    let nested: any = null;
    for (let index = 0; index < 40; index++) nested = { nested };
    malformed.push(nested);
    const cyclic: JsonObject = {};
    cyclic.self = cyclic;
    malformed.push(cyclic);
    let getterReads = 0;
    const accessor: JsonObject = {};
    Object.defineProperty(accessor, 'capability', {
      get() {
        getterReads++;
        return 'unknown';
      },
      enumerable: true,
    });
    malformed.push(accessor, Object.create({ enabled: true }));
    for (const beep of malformed) {
      const db = new FakePrinterDatabase();
      const input = envelope();
      input.routes[0].capabilityProfile.beep = beep;
      await httpError(
        persistPreparedPrinterRuntimeConfig(db.client(), owner, context, input),
        400,
      );
      expect(db.events).toHaveLength(0);
    }
    expect(getterReads).toBe(0);
  });

  it('treats UUID case variations as the same request identity while preserving exact submitted fingerprint', async () => {
    const db = new FakePrinterDatabase();
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope({ requestId: requestId.toUpperCase() }),
      ),
      409,
    );
    expect(Object.keys(db.state.journal)).toHaveLength(1);
  });

  it('fails visibly for a corrupt stored config/result rather than inventing an accepted write', async () => {
    const db = new FakePrinterDatabase();
    db.state.devices[deviceId].runtimeConfig = { version: 2 };
    const before = clone(db.state);
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
      503,
    );
    expect(db.state).toEqual(before);
    db.state.devices[deviceId].runtimeConfig = null;
    await persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
    db.receipt().outcomeJson = '{"version":2}';
    await httpError(
      persistPreparedPrinterRuntimeConfig(
        db.client(),
        owner,
        context,
        envelope(),
      ),
      503,
    );
    expect(db.events.at(-1)).toBe('rollback');
  });
});

describe('legacy printer writes share the lock and cannot overwrite v2 — fake transactions', () => {
  it('preserves accepted v1 behavior and audit while rechecking authority under the shared lock', async () => {
    const db = new FakePrinterDatabase();
    const result = await db
      .service()
      .printers(owner, venueId, deviceId, legacy());
    expect(result).toEqual({ version: 1, printers: legacy() });
    expect(db.events).toEqual([
      'begin',
      'venue-lock',
      'device-lock',
      'membership-lock',
      'owner-recheck',
      'pos-recheck',
      'legacy-write',
      'customer-audit',
      'commit',
    ]);
    expect(db.state.customerAudit[0].action).toBe('device.printers_changed');
    expect(Object.keys(db.state.journal)).toHaveLength(0);
  });
  it('blocks v1 overwrite after v2 preparation and keeps the original config/receipts/audit', async () => {
    const db = new FakePrinterDatabase();
    await db.service().printers(owner, venueId, deviceId, envelope());
    const before = clone(db.state);
    const error = await httpError(
      db.service().printers(owner, venueId, deviceId, legacy()),
      409,
    );
    expect(error.getResponse()).toMatchObject({
      code: 'LEGACY_PRINTER_WRITE_REJECTED',
    });
    expect(db.state).toEqual(before);
    expect(db.events.at(-1)).toBe('rollback');
  });
  it.each(['membership', 'commercial'] as const)(
    'blocks stale v1 authorization when transaction %s changes',
    async (change) => {
      const db = new FakePrinterDatabase();
      if (change === 'membership') db.transactionOwnerAllowed = false;
      else db.transactionPosAllowed = false;
      await httpError(
        db.service().printers(owner, venueId, deviceId, legacy()),
        change === 'membership' ? 404 : 403,
      );
      expect(db.state.devices[deviceId].runtimeConfig).toBeNull();
      expect(db.state.customerAudit).toHaveLength(0);
      expect(db.events.at(-1)).toBe('rollback');
      const lockBoundary = db.events.indexOf('venue-lock');
      expect(db.events[lockBoundary + 1]).toBe('device-lock');
      expect(db.events[lockBoundary + 2]).toBe('membership-lock');
      expect(db.events).not.toContain('legacy-write');
      if (change === 'commercial') expect(db.events).toContain('pos-recheck');
    },
  );
  it('allows explicit v1-to-PREPARED transition without granting activation', async () => {
    const db = new FakePrinterDatabase();
    await db.service().printers(owner, venueId, deviceId, legacy());
    expect(
      await db.service().printers(owner, venueId, deviceId, envelope()),
    ).toMatchObject({ phase: 'PREPARED' });
    expect(db.state.customerAudit.map((row) => row.action)).toEqual([
      'device.printers_changed',
      'device.printers_prepared',
    ]);
  });
});

describe('Device-authenticated runtime v2 GET compatibility — no database', () => {
  async function prepared() {
    const db = new FakePrinterDatabase();
    return persistPreparedPrinterRuntimeConfig(
      db.client(),
      owner,
      context,
      envelope(),
    );
  }
  it.each([undefined, '1', '3', '02', '2, 2', ['2']])(
    'requires exact current-request reader header: %j',
    async (header) => {
      const value = await prepared();
      try {
        printerRuntimeConfigForReader(value as any, context, header);
        throw new Error('Expected reader rejection');
      } catch (error) {
        expect(error).toBeInstanceOf(HttpException);
        expect((error as HttpException).getStatus()).toBe(426);
      }
    },
  );
  it('keeps outer response version one, Device scoping and explicitly PREPARED routes for an upgraded reader', async () => {
    const value = await prepared();
    const findFirstOrThrow = jest.fn().mockResolvedValue({
      id: deviceId,
      venueId,
      displayName: 'POS',
      runtimeConfig: value,
      venue: { id: venueId, name: 'Restaurant' },
    });
    const controller = new DeviceRuntimeConfigController(
      { device: { findFirstOrThrow } } as unknown as PrismaService,
      {
        effectiveFeatures: jest.fn().mockResolvedValue(['POS']),
      } as unknown as VenueEntitlementsService,
    );
    const edgeActor = { ...context, organizationId };
    const response = await controller.config(edgeActor, '2');
    expect(findFirstOrThrow.mock.calls[0][0].where).toEqual({
      id: deviceId,
      venueId,
    });
    expect(response.version).toBe(1);
    expect(response.device.runtimeConfig).toEqual(value);
    expect(response.device.runtimeConfig).toMatchObject({ phase: 'PREPARED' });
    await httpError(controller.config(edgeActor), 426);
  });
  it('preserves v1/null reads without a reader header, while invalid v2 binding is visibly held', async () => {
    expect(printerRuntimeConfigForReader(null, context, undefined)).toBeNull();
    const v1 = { version: 1, printers: legacy() };
    expect(printerRuntimeConfigForReader(v1, context, undefined)).toBe(v1);
    const v2 = await prepared();
    try {
      printerRuntimeConfigForReader(
        { ...v2, deviceId: secondDeviceId } as any,
        context,
        '2',
      );
      throw new Error('Expected stored binding rejection');
    } catch (error) {
      expect(error).toBeInstanceOf(HttpException);
      expect((error as HttpException).getStatus()).toBe(503);
    }
  });
});
