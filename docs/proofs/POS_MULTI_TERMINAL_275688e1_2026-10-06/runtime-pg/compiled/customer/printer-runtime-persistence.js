"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lockPrinterRuntimeDevice = lockPrinterRuntimeDevice;
exports.throwPrinterRuntimeHttpError = throwPrinterRuntimeHttpError;
exports.persistPreparedPrinterRuntimeConfig = persistPreparedPrinterRuntimeConfig;
exports.printerRuntimeConfigForReader = printerRuntimeConfigForReader;
const node_crypto_1 = require("node:crypto");
const common_1 = require("@nestjs/common");
const commercial_state_1 = require("../entitlements/commercial-state");
const printer_runtime_config_1 = require("./printer-runtime-config");
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_JSON_DEPTH = 32;
const MAX_JSON_NODES = 16384;
const envelopeKeys = [
    'version',
    'requestId',
    'expectedRevision',
    'minimumReaderVersion',
    'routes',
];
function badInput(message) {
    throw new common_1.BadRequestException(message);
}
function dataRecord(value) {
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
    return value;
}
/**
 * First inspect iteratively, with byte/node/depth budgets. Only then sort and
 * recurse over the bounded plain JSON tree. Unknown optional beep JSON is part
 * of the fingerprint even when the domain normalizes it to silent output.
 */
function canonicalJson(value) {
    const stack = [
        { value, depth: 0 },
    ];
    const seen = new Set();
    let bytes = 0, nodes = 0;
    const addBytes = (count) => {
        bytes += count;
        if (bytes > printer_runtime_config_1.MAX_PRINTER_RUNTIME_CONFIG_BYTES)
            badInput('Printer request exceeds the JSON byte limit');
    };
    while (stack.length) {
        const item = stack.pop();
        if (item.leave) {
            seen.delete(item.value);
            continue;
        }
        if (++nodes > MAX_JSON_NODES || item.depth > MAX_JSON_DEPTH)
            badInput('Printer request exceeds the JSON complexity limit');
        const current = item.value;
        if (current === null || typeof current === 'boolean') {
            addBytes(Buffer.byteLength(JSON.stringify(current), 'utf8'));
        }
        else if (typeof current === 'string') {
            // Reject oversized text before allocating its escaped JSON form.
            if (Buffer.byteLength(current, 'utf8') > printer_runtime_config_1.MAX_PRINTER_RUNTIME_CONFIG_BYTES)
                badInput('Printer request exceeds the JSON byte limit');
            addBytes(Buffer.byteLength(JSON.stringify(current), 'utf8'));
        }
        else if (typeof current === 'number') {
            if (!Number.isFinite(current))
                badInput('Printer request numbers must be finite');
            addBytes(Buffer.byteLength(JSON.stringify(current), 'utf8'));
        }
        else if (typeof current === 'object') {
            if (seen.has(current))
                badInput('Printer request must be a JSON tree');
            seen.add(current);
            stack.push({ value: current, depth: item.depth, leave: true });
            if (Array.isArray(current)) {
                if (Object.getPrototypeOf(current) !== Array.prototype ||
                    current.length > MAX_JSON_NODES ||
                    Reflect.ownKeys(current).length !== current.length + 1)
                    badInput('Printer request arrays must be dense plain JSON arrays');
                addBytes(2 + Math.max(0, current.length - 1));
                for (let index = 0; index < current.length; index++) {
                    const descriptor = Object.getOwnPropertyDescriptor(current, index);
                    if (!descriptor || !('value' in descriptor))
                        badInput('Printer request array accessors are not accepted');
                    stack.push({ value: descriptor.value, depth: item.depth + 1 });
                }
            }
            else {
                const row = dataRecord(current);
                const keys = Object.getOwnPropertyNames(row);
                if (keys.length > MAX_JSON_NODES)
                    badInput('Printer request exceeds the JSON complexity limit');
                addBytes(2 + Math.max(0, keys.length - 1));
                for (const key of keys) {
                    if (Buffer.byteLength(key, 'utf8') > printer_runtime_config_1.MAX_PRINTER_RUNTIME_CONFIG_BYTES)
                        badInput('Printer request exceeds the JSON byte limit');
                    addBytes(Buffer.byteLength(JSON.stringify(key), 'utf8') + 1);
                    stack.push({ value: row[key], depth: item.depth + 1 });
                }
            }
        }
        else
            badInput('Printer request must contain JSON values');
    }
    const encode = (item) => {
        if (Array.isArray(item))
            return `[${item.map(encode).join(',')}]`;
        if (item !== null && typeof item === 'object') {
            const row = item;
            return `{${Object.getOwnPropertyNames(row)
                .sort()
                .map((key) => `${JSON.stringify(key)}:${encode(row[key])}`)
                .join(',')}}`;
        }
        return JSON.stringify(item);
    };
    return encode(value);
}
function writerIdentity(actor) {
    if (!actor || typeof actor !== 'object')
        throw new common_1.ForbiddenException('A single Owner or Platform writer is required');
    const customer = actor.customerAccountId;
    const platform = actor.platformUserId;
    if ((customer !== undefined) === (platform !== undefined))
        throw new common_1.ForbiddenException('A single Owner or Platform writer is required');
    const actorId = customer ?? platform;
    if (typeof actorId !== 'string' || !UUID.test(actorId))
        throw new common_1.ForbiddenException('Invalid printer writer identity');
    return {
        actorType: customer !== undefined ? 'CUSTOMER' : 'PLATFORM',
        actorId,
    };
}
function requestEnvelope(body, context) {
    const source = dataRecord(body);
    if (Object.getOwnPropertyNames(source).length !== envelopeKeys.length ||
        envelopeKeys.some((key) => !Object.prototype.hasOwnProperty.call(source, key)))
        badInput('Unexpected or missing printer request fields');
    // This bounded preflight also rejects accessors/prototypes in optional JSON.
    const canonical = canonicalJson(source);
    if (typeof source.requestId !== 'string' || !UUID.test(source.requestId))
        badInput('Printer requestId must be a UUID');
    if (!Number.isSafeInteger(source.expectedRevision) ||
        Number(source.expectedRevision) < 0 ||
        Number(source.expectedRevision) > printer_runtime_config_1.MAX_PRINTER_RUNTIME_REVISION)
        badInput('Invalid expected printer configuration revision');
    if (source.version !== 2 || source.minimumReaderVersion !== 2)
        badInput('Printer request version and reader floor must be two');
    // Validate every first request and retry before consulting the journal.
    let validated;
    try {
        validated = (0, printer_runtime_config_1.parsePrinterRuntimeConfigV2)({
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
        }, context);
    }
    catch (error) {
        throwPrinterRuntimeHttpError(error);
    }
    return {
        requestId: source.requestId.toLowerCase(),
        inputSha256: (0, node_crypto_1.createHash)('sha256').update(canonical).digest('hex'),
        draft: {
            version: 2,
            expectedRevision: source.expectedRevision,
            minimumReaderVersion: 2,
            routes: validated.routes,
        },
    };
}
/** Shared by v1 and v2. The locked server row supplies the Device/Venue binding. */
async function lockPrinterRuntimeDevice(tx, context, actor) {
    const writer = writerIdentity(actor);
    // Commercial writers already serialize on Venue before Device. Keep that
    // order, and pin the actual Organization used for the Owner membership check.
    const venues = await tx.$queryRaw `
    SELECT "id", "organizationId" FROM "pos"."Venue"
    WHERE "id" = ${context.venueId} FOR UPDATE
  `;
    const venue = venues[0];
    if (!venue)
        throw new common_1.NotFoundException('Restaurant not found');
    const rows = await tx.$queryRaw `
    SELECT "id", "venueId", "runtimeConfig"
    FROM "pos"."Device"
    WHERE "id" = ${context.deviceId} AND "venueId" = ${context.venueId}
    FOR UPDATE
  `;
    const device = rows[0];
    if (!device)
        throw new common_1.NotFoundException('Device not found');
    if (writer.actorType === 'CUSTOMER') {
        // The composite Owner row stays present/OWNER until this transaction ends;
        // removal or demotion must wait, rather than racing a one-time membership read.
        const memberships = await tx.$queryRaw `
      SELECT "customerAccountId", "organizationId" FROM "pos"."OrganizationMembership"
      WHERE "customerAccountId" = ${writer.actorId}
        AND "organizationId" = ${venue.organizationId} AND "role" = 'OWNER'
      FOR SHARE
    `;
        if (!memberships.length)
            throw new common_1.NotFoundException('Restaurant not found');
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
        if (!owned)
            throw new common_1.NotFoundException('Restaurant not found');
    }
    await (0, commercial_state_1.requireCommercialFeature)(tx, device.venueId, 'POS');
    return device;
}
function throwPrinterRuntimeHttpError(error) {
    if (!(error instanceof printer_runtime_config_1.PrinterRuntimeConfigError))
        throw error;
    const body = { code: error.code, message: error.message };
    if (error.code === 'INVALID_PRINTER_RUNTIME_CONFIG' ||
        error.code === 'PRINTER_DEVICE_MISMATCH' ||
        error.code === 'PRINTER_VENUE_MISMATCH')
        throw new common_1.BadRequestException(body);
    throw new common_1.ConflictException(body);
}
function conflictOutcome(error) {
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
function storedOutcome(row, context) {
    try {
        if (typeof row.outcomeJson !== 'string' ||
            Buffer.byteLength(row.outcomeJson, 'utf8') >
                printer_runtime_config_1.MAX_PRINTER_RUNTIME_CONFIG_BYTES)
            throw new Error('Invalid journal JSON size');
        const value = JSON.parse(row.outcomeJson);
        canonicalJson(value);
        if (row.outcomeStatus === 200) {
            const result = (0, printer_runtime_config_1.parsePrinterRuntimeConfigV2)(value, context);
            if (result.phase !== 'PREPARED' ||
                canonicalJson(result) !== canonicalJson(value))
                throw new Error('Invalid journal prepared result');
            return { status: 200, json: row.outcomeJson };
        }
        const result = dataRecord(value);
        if (row.outcomeStatus !== 409 ||
            result.statusCode !== 409 ||
            result.error !== 'Conflict' ||
            typeof result.message !== 'string' ||
            !['PRINTER_REVISION_CONFLICT', 'PRINTER_REVISION_EXHAUSTED'].includes(String(result.code)) ||
            Object.getOwnPropertyNames(result).length !== 4)
            throw new Error('Invalid journal conflict');
        return { status: 409, json: row.outcomeJson };
    }
    catch {
        throw new common_1.ServiceUnavailableException('Stored printer request result requires repair');
    }
}
/**
 * Commit immutable success/conflict receipts before responding. This endpoint
 * prepares configuration only: it cannot activate routes or prove fleet rollout.
 */
async function persistPreparedPrinterRuntimeConfig(db, actor, context, body) {
    const writer = writerIdentity(actor);
    const requestedContext = {
        deviceId: context.deviceId,
        venueId: context.venueId,
    };
    const boundActor = writer.actorType === 'CUSTOMER'
        ? { customerAccountId: writer.actorId }
        : { platformUserId: writer.actorId };
    const request = requestEnvelope(body, requestedContext);
    const result = await db.$transaction(async (tx) => {
        const device = await lockPrinterRuntimeDevice(tx, requestedContext, boundActor);
        const bound = { deviceId: device.id, venueId: device.venueId };
        const prior = await tx.$queryRaw `
      SELECT "venueId", "actorType", "actorId", "inputSha256", "outcomeStatus",
             "outcome"::text AS "outcomeJson"
      FROM "pos"."DevicePrinterRuntimeRequest"
      WHERE "deviceId" = ${device.id} AND "requestId" = ${request.requestId}
    `;
        if (prior.length) {
            const receipt = prior[0];
            if (receipt.venueId !== device.venueId ||
                receipt.actorType !== writer.actorType ||
                receipt.actorId !== writer.actorId ||
                receipt.inputSha256 !== request.inputSha256)
                throw new common_1.ConflictException('Printer requestId is already bound to another input or actor');
            return storedOutcome(receipt, bound);
        }
        let outcome;
        try {
            const prepared = (0, printer_runtime_config_1.preparePrinterRuntimeConfigV2)(request.draft, bound, device.runtimeConfig);
            const json = canonicalJson(prepared);
            const updated = await tx.$executeRaw `
        UPDATE "pos"."Device"
        SET "runtimeConfig" = ${json}::jsonb, "updatedAt" = CURRENT_TIMESTAMP
        WHERE "id" = ${device.id} AND "venueId" = ${device.venueId}
          AND COALESCE("runtimeConfig", 'null'::jsonb) = ${JSON.stringify(device.runtimeConfig)}::jsonb
      `;
            if (updated !== 1)
                throw new printer_runtime_config_1.PrinterRuntimeConfigError('PRINTER_REVISION_CONFLICT', 'Printer configuration changed during preparation');
            outcome = { status: 200, json };
        }
        catch (error) {
            if (!(error instanceof printer_runtime_config_1.PrinterRuntimeConfigError))
                throw error;
            if (error.code !== 'PRINTER_REVISION_CONFLICT' &&
                error.code !== 'PRINTER_REVISION_EXHAUSTED')
                throw new common_1.ServiceUnavailableException('Stored printer configuration requires repair');
            outcome = conflictOutcome(error);
        }
        const inserted = await tx.$executeRaw `
      INSERT INTO "pos"."DevicePrinterRuntimeRequest"
        ("deviceId", "requestId", "venueId", "actorType", "actorId", "inputSha256",
         "expectedRevision", "outcomeStatus", "outcome")
      VALUES (${device.id}, ${request.requestId}, ${device.venueId}, ${writer.actorType},
              ${writer.actorId}, ${request.inputSha256}, ${request.draft.expectedRevision},
              ${outcome.status}, ${outcome.json}::json)
    `;
        if (inserted !== 1)
            throw new common_1.ServiceUnavailableException('Printer request result was not saved');
        if (outcome.status === 200) {
            const data = {
                action: 'device.printers_prepared',
                targetType: 'Device',
                targetId: device.id,
                metadata: {
                    requestId: request.requestId,
                    from: device.runtimeConfig,
                    to: JSON.parse(outcome.json),
                },
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
    });
    // Throwing inside the transaction would erase the immutable conflict receipt.
    const response = JSON.parse(result.json);
    if (result.status === 409)
        throw new common_1.HttpException(response, 409);
    return response;
}
/** Current authenticated request compatibility only; old offline v1 is not fenced. */
function printerRuntimeConfigForReader(value, context, readerVersion) {
    if (!value ||
        typeof value !== 'object' ||
        Array.isArray(value) ||
        value.version !== 2)
        return value;
    if (readerVersion !== '2')
        throw new common_1.HttpException({
            statusCode: 426,
            error: 'Upgrade Required',
            message: 'Printer runtime reader version 2 is required',
            minimumReaderVersion: 2,
        }, 426);
    try {
        return (0, printer_runtime_config_1.parsePrinterRuntimeConfigV2)(value, context);
    }
    catch {
        throw new common_1.ServiceUnavailableException('Stored printer configuration requires repair');
    }
}
