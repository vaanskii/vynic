import { createHash } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { Prisma, PrismaClient } from '@prisma/client';
import { requireCommercialFeature } from '../entitlements/commercial-state';
import type { ControlActor } from '../platform/control-actor';
import {
  MAX_PRINTER_RUNTIME_CONFIG_BYTES,
  MAX_PRINTER_RUNTIME_REVISION,
  parsePrinterRuntimeConfigV2,
  preparePrinterRuntimeConfigV2,
  PrinterRuntimeConfigError,
  type PrinterRuntimeConfigV2,
  type PrinterRuntimeContext,
} from './printer-runtime-config';

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_JSON_DEPTH = 32;
const MAX_JSON_NODES = 16384;
const envelopeKeys = [
  'version',
  'requestId',
  'expectedRevision',
  'minimumReaderVersion',
  'routes',
] as const;
type WriterIdentity = Readonly<{
  actorType: 'CUSTOMER' | 'PLATFORM';
  actorId: string;
}>;
type JournalRow = WriterIdentity & {
  venueId: string;
  inputSha256: string;
  outcomeStatus: number;
  outcomeJson: string;
};
type PersistedOutcome = { status: 200 | 409; json: string };
export type LockedPrinterRuntimeDevice = {
  id: string;
  venueId: string;
  runtimeConfig: Prisma.JsonValue | null;
};

function badInput(message: string): never {
  throw new BadRequestException(message);
}
function dataRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return badInput('Printer request must contain plain JSON data');
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null)
    return badInput('Printer request must contain plain JSON data');
  const keys = Reflect.ownKeys(value);
  if (keys.length > MAX_JSON_NODES)
    badInput('Printer request exceeds the JSON complexity limit');
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (typeof key !== 'string' || !descriptor || !('value' in descriptor))
      return badInput('Printer request accessors and symbols are not accepted');
  }
  return value as Record<string, unknown>;
}

/**
 * First inspect iteratively, with byte/node/depth budgets. Only then sort and
 * recurse over the bounded plain JSON tree. Unknown optional beep JSON is part
 * of the fingerprint even when the domain normalizes it to silent output.
 */
function canonicalJson(value: unknown): string {
  const stack: { value: unknown; depth: number; leave?: boolean }[] = [
    { value, depth: 0 },
  ];
  const seen = new Set<object>();
  let bytes = 0,
    nodes = 0;
  const addBytes = (count: number) => {
    bytes += count;
    if (bytes > MAX_PRINTER_RUNTIME_CONFIG_BYTES)
      badInput('Printer request exceeds the JSON byte limit');
  };
  while (stack.length) {
    const item = stack.pop()!;
    if (item.leave) {
      seen.delete(item.value as object);
      continue;
    }
    if (++nodes > MAX_JSON_NODES || item.depth > MAX_JSON_DEPTH)
      badInput('Printer request exceeds the JSON complexity limit');
    const current = item.value;
    if (current === null || typeof current === 'boolean') {
      addBytes(Buffer.byteLength(JSON.stringify(current), 'utf8'));
    } else if (typeof current === 'string') {
      // Reject oversized text before allocating its escaped JSON form.
      if (Buffer.byteLength(current, 'utf8') > MAX_PRINTER_RUNTIME_CONFIG_BYTES)
        badInput('Printer request exceeds the JSON byte limit');
      addBytes(Buffer.byteLength(JSON.stringify(current), 'utf8'));
    } else if (typeof current === 'number') {
      if (!Number.isFinite(current))
        badInput('Printer request numbers must be finite');
      addBytes(Buffer.byteLength(JSON.stringify(current), 'utf8'));
    } else if (typeof current === 'object') {
      if (seen.has(current)) badInput('Printer request must be a JSON tree');
      seen.add(current);
      stack.push({ value: current, depth: item.depth, leave: true });
      if (Array.isArray(current)) {
        if (
          Object.getPrototypeOf(current) !== Array.prototype ||
          current.length > MAX_JSON_NODES ||
          Reflect.ownKeys(current).length !== current.length + 1
        )
          badInput('Printer request arrays must be dense plain JSON arrays');
        addBytes(2 + Math.max(0, current.length - 1));
        for (let index = 0; index < current.length; index++) {
          const descriptor = Object.getOwnPropertyDescriptor(current, index);
          if (!descriptor || !('value' in descriptor))
            badInput('Printer request array accessors are not accepted');
          stack.push({ value: descriptor.value, depth: item.depth + 1 });
        }
      } else {
        const row = dataRecord(current);
        const keys = Object.getOwnPropertyNames(row);
        if (keys.length > MAX_JSON_NODES)
          badInput('Printer request exceeds the JSON complexity limit');
        addBytes(2 + Math.max(0, keys.length - 1));
        for (const key of keys) {
          if (Buffer.byteLength(key, 'utf8') > MAX_PRINTER_RUNTIME_CONFIG_BYTES)
            badInput('Printer request exceeds the JSON byte limit');
          addBytes(Buffer.byteLength(JSON.stringify(key), 'utf8') + 1);
          stack.push({ value: row[key], depth: item.depth + 1 });
        }
      }
    } else badInput('Printer request must contain JSON values');
  }
  const encode = (item: unknown): string => {
    if (Array.isArray(item)) return `[${item.map(encode).join(',')}]`;
    if (item !== null && typeof item === 'object') {
      const row = item as Record<string, unknown>;
      return `{${Object.getOwnPropertyNames(row)
        .sort()
        .map((key) => `${JSON.stringify(key)}:${encode(row[key])}`)
        .join(',')}}`;
    }
    return JSON.stringify(item);
  };
  return encode(value);
}

function writerIdentity(actor: ControlActor): WriterIdentity {
  if (!actor || typeof actor !== 'object')
    throw new ForbiddenException(
      'A single Owner or Platform writer is required',
    );
  const customer = actor.customerAccountId;
  const platform = actor.platformUserId;
  if ((customer !== undefined) === (platform !== undefined))
    throw new ForbiddenException(
      'A single Owner or Platform writer is required',
    );
  const actorId = customer ?? platform;
  if (typeof actorId !== 'string' || !UUID.test(actorId))
    throw new ForbiddenException('Invalid printer writer identity');
  return {
    actorType: customer !== undefined ? 'CUSTOMER' : 'PLATFORM',
    actorId,
  };
}

function requestEnvelope(body: unknown, context: PrinterRuntimeContext) {
  const source = dataRecord(body);
  if (
    Object.getOwnPropertyNames(source).length !== envelopeKeys.length ||
    envelopeKeys.some(
      (key) => !Object.prototype.hasOwnProperty.call(source, key),
    )
  )
    badInput('Unexpected or missing printer request fields');
  // This bounded preflight also rejects accessors/prototypes in optional JSON.
  const canonical = canonicalJson(source);
  if (typeof source.requestId !== 'string' || !UUID.test(source.requestId))
    badInput('Printer requestId must be a UUID');
  if (
    !Number.isSafeInteger(source.expectedRevision) ||
    Number(source.expectedRevision) < 0 ||
    Number(source.expectedRevision) > MAX_PRINTER_RUNTIME_REVISION
  )
    badInput('Invalid expected printer configuration revision');
  if (source.version !== 2 || source.minimumReaderVersion !== 2)
    badInput('Printer request version and reader floor must be two');
  // Validate every first request and retry before consulting the journal.
  let validated: PrinterRuntimeConfigV2;
  try {
    validated = parsePrinterRuntimeConfigV2(
      {
        version: 2,
        deviceId: context.deviceId,
        venueId: context.venueId,
        revision: 1,
        phase: 'PREPARED',
        minimumReaderVersion: 2,
        printers: {
          kitchen: { enabled: false, host: '', port: 9100 },
          receipt: { enabled: false, host: '', port: 9100 },
        },
        routes: source.routes,
      },
      context,
    );
  } catch (error) {
    throwPrinterRuntimeHttpError(error);
  }
  return {
    requestId: source.requestId.toLowerCase(),
    inputSha256: createHash('sha256').update(canonical).digest('hex'),
    draft: {
      version: 2,
      expectedRevision: source.expectedRevision,
      minimumReaderVersion: 2,
      routes: validated.routes,
    },
  };
}

/** Shared by v1 and v2. The locked server row supplies the Device/Venue binding. */
export async function lockPrinterRuntimeDevice(
  tx: Prisma.TransactionClient,
  context: PrinterRuntimeContext,
  actor: ControlActor,
): Promise<LockedPrinterRuntimeDevice> {
  const writer = writerIdentity(actor);
  // Commercial writers already serialize on Venue before Device. Keep that
  // order, and pin the actual Organization used for the Owner membership check.
  const venues = await tx.$queryRaw<{ id: string; organizationId: string }[]>`
    SELECT "id", "organizationId" FROM "pos"."Venue"
    WHERE "id" = ${context.venueId} FOR UPDATE
  `;
  const venue = venues[0];
  if (!venue) throw new NotFoundException('Restaurant not found');
  const rows = await tx.$queryRaw<LockedPrinterRuntimeDevice[]>`
    SELECT "id", "venueId", "runtimeConfig"
    FROM "pos"."Device"
    WHERE "id" = ${context.deviceId} AND "venueId" = ${context.venueId}
    FOR UPDATE
  `;
  const device = rows[0];
  if (!device) throw new NotFoundException('Device not found');
  if (writer.actorType === 'CUSTOMER') {
    // The composite Owner row stays present/OWNER until this transaction ends;
    // removal or demotion must wait, rather than racing a one-time membership read.
    const memberships = await tx.$queryRaw<
      { customerAccountId: string; organizationId: string }[]
    >`
      SELECT "customerAccountId", "organizationId" FROM "pos"."OrganizationMembership"
      WHERE "customerAccountId" = ${writer.actorId}
        AND "organizationId" = ${venue.organizationId} AND "role" = 'OWNER'
      FOR SHARE
    `;
    if (!memberships.length)
      throw new NotFoundException('Restaurant not found');
    const owned = await tx.venue.findFirst({
      where: {
        id: device.venueId,
        organizationId: venue.organizationId,
        organization: {
          memberships: {
            some: { customerAccountId: writer.actorId, role: 'OWNER' },
          },
        },
      },
      select: { id: true },
    });
    if (!owned) throw new NotFoundException('Restaurant not found');
  }
  await requireCommercialFeature(tx, device.venueId, 'POS');
  return device;
}

export function throwPrinterRuntimeHttpError(error: unknown): never {
  if (!(error instanceof PrinterRuntimeConfigError)) throw error;
  const body = { code: error.code, message: error.message };
  if (
    error.code === 'INVALID_PRINTER_RUNTIME_CONFIG' ||
    error.code === 'PRINTER_DEVICE_MISMATCH' ||
    error.code === 'PRINTER_VENUE_MISMATCH'
  )
    throw new BadRequestException(body);
  throw new ConflictException(body);
}

function conflictOutcome(error: PrinterRuntimeConfigError): PersistedOutcome {
  return {
    status: 409,
    json: canonicalJson({
      statusCode: 409,
      error: 'Conflict',
      code: error.code,
      message: error.message,
    }),
  };
}

function storedOutcome(
  row: JournalRow,
  context: PrinterRuntimeContext,
): PersistedOutcome {
  try {
    if (
      typeof row.outcomeJson !== 'string' ||
      Buffer.byteLength(row.outcomeJson, 'utf8') >
        MAX_PRINTER_RUNTIME_CONFIG_BYTES
    )
      throw new Error('Invalid journal JSON size');
    const value: unknown = JSON.parse(row.outcomeJson);
    canonicalJson(value);
    if (row.outcomeStatus === 200) {
      const result = parsePrinterRuntimeConfigV2(value, context);
      if (
        result.phase !== 'PREPARED' ||
        canonicalJson(result) !== canonicalJson(value)
      )
        throw new Error('Invalid journal prepared result');
      return { status: 200, json: row.outcomeJson };
    }
    const result = dataRecord(value);
    if (
      row.outcomeStatus !== 409 ||
      result.statusCode !== 409 ||
      result.error !== 'Conflict' ||
      typeof result.message !== 'string' ||
      !['PRINTER_REVISION_CONFLICT', 'PRINTER_REVISION_EXHAUSTED'].includes(
        String(result.code),
      ) ||
      Object.getOwnPropertyNames(result).length !== 4
    )
      throw new Error('Invalid journal conflict');
    return { status: 409, json: row.outcomeJson };
  } catch {
    throw new ServiceUnavailableException(
      'Stored printer request result requires repair',
    );
  }
}

/**
 * Commit immutable success/conflict receipts before responding. This endpoint
 * prepares configuration only: it cannot activate routes or prove fleet rollout.
 */
export async function persistPreparedPrinterRuntimeConfig(
  db: Pick<PrismaClient, '$transaction'>,
  actor: ControlActor,
  context: PrinterRuntimeContext,
  body: unknown,
): Promise<PrinterRuntimeConfigV2> {
  const writer = writerIdentity(actor);
  const requestedContext = {
    deviceId: context.deviceId,
    venueId: context.venueId,
  };
  const boundActor: ControlActor =
    writer.actorType === 'CUSTOMER'
      ? { customerAccountId: writer.actorId }
      : { platformUserId: writer.actorId };
  const request = requestEnvelope(body, requestedContext);
  const result = await db.$transaction(
    async (tx): Promise<PersistedOutcome> => {
      const device = await lockPrinterRuntimeDevice(
        tx,
        requestedContext,
        boundActor,
      );
      const bound = { deviceId: device.id, venueId: device.venueId };
      const prior = await tx.$queryRaw<JournalRow[]>`
      SELECT "venueId", "actorType", "actorId", "inputSha256", "outcomeStatus",
             "outcome"::text AS "outcomeJson"
      FROM "pos"."DevicePrinterRuntimeRequest"
      WHERE "deviceId" = ${device.id} AND "requestId" = ${request.requestId}
    `;
      if (prior.length) {
        const receipt = prior[0];
        if (
          receipt.venueId !== device.venueId ||
          receipt.actorType !== writer.actorType ||
          receipt.actorId !== writer.actorId ||
          receipt.inputSha256 !== request.inputSha256
        )
          throw new ConflictException(
            'Printer requestId is already bound to another input or actor',
          );
        return storedOutcome(receipt, bound);
      }
      let outcome: PersistedOutcome;
      try {
        const prepared = preparePrinterRuntimeConfigV2(
          request.draft,
          bound,
          device.runtimeConfig,
        );
        const json = canonicalJson(prepared);
        const updated = await tx.$executeRaw`
        UPDATE "pos"."Device"
        SET "runtimeConfig" = ${json}::jsonb, "updatedAt" = CURRENT_TIMESTAMP
        WHERE "id" = ${device.id} AND "venueId" = ${device.venueId}
          AND COALESCE("runtimeConfig", 'null'::jsonb) = ${JSON.stringify(device.runtimeConfig)}::jsonb
      `;
        if (updated !== 1)
          throw new PrinterRuntimeConfigError(
            'PRINTER_REVISION_CONFLICT',
            'Printer configuration changed during preparation',
          );
        outcome = { status: 200, json };
      } catch (error) {
        if (!(error instanceof PrinterRuntimeConfigError)) throw error;
        if (
          error.code !== 'PRINTER_REVISION_CONFLICT' &&
          error.code !== 'PRINTER_REVISION_EXHAUSTED'
        )
          throw new ServiceUnavailableException(
            'Stored printer configuration requires repair',
          );
        outcome = conflictOutcome(error);
      }
      const inserted = await tx.$executeRaw`
      INSERT INTO "pos"."DevicePrinterRuntimeRequest"
        ("deviceId", "requestId", "venueId", "actorType", "actorId", "inputSha256",
         "expectedRevision", "outcomeStatus", "outcome")
      VALUES (${device.id}, ${request.requestId}, ${device.venueId}, ${writer.actorType},
              ${writer.actorId}, ${request.inputSha256}, ${request.draft.expectedRevision},
              ${outcome.status}, ${outcome.json}::json)
    `;
      if (inserted !== 1)
        throw new ServiceUnavailableException(
          'Printer request result was not saved',
        );
      if (outcome.status === 200) {
        const data = {
          action: 'device.printers_prepared',
          targetType: 'Device',
          targetId: device.id,
          metadata: {
            requestId: request.requestId,
            from: device.runtimeConfig,
            to: JSON.parse(outcome.json),
          } as Prisma.InputJsonObject,
        };
        if (writer.actorType === 'CUSTOMER')
          await tx.customerAuditEvent.create({
            data: { ...data, customerAccountId: writer.actorId },
          });
        else
          await tx.platformAuditEvent.create({
            data: { ...data, platformUserId: writer.actorId },
          });
      }
      return outcome;
    },
  );
  // Throwing inside the transaction would erase the immutable conflict receipt.
  const response: unknown = JSON.parse(result.json);
  if (result.status === 409)
    throw new HttpException(response as Record<string, unknown>, 409);
  return response as PrinterRuntimeConfigV2;
}

/** Current authenticated request compatibility only; old offline v1 is not fenced. */
export function printerRuntimeConfigForReader(
  value: Prisma.JsonValue | null,
  context: PrinterRuntimeContext,
  readerVersion: unknown,
): Prisma.JsonValue | PrinterRuntimeConfigV2 | null {
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    value.version !== 2
  )
    return value;
  if (readerVersion !== '2')
    throw new HttpException(
      {
        statusCode: 426,
        error: 'Upgrade Required',
        message: 'Printer runtime reader version 2 is required',
        minimumReaderVersion: 2,
      },
      426,
    );
  try {
    return parsePrinterRuntimeConfigV2(value, context);
  } catch {
    throw new ServiceUnavailableException(
      'Stored printer configuration requires repair',
    );
  }
}
