"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PrinterRuntimeConfigError = exports.MAX_PRINTER_RUNTIME_CONFIG_BYTES = exports.MAX_PRINTER_RUNTIME_ROUTES = exports.MAX_PRINTER_RUNTIME_REVISION = exports.PRINTER_RUNTIME_READER_VERSION = void 0;
exports.parsePrinterRuntimeConfigV2 = parsePrinterRuntimeConfigV2;
exports.preparePrinterRuntimeConfigV2 = preparePrinterRuntimeConfigV2;
exports.assertLegacyPrinterWriteAllowed = assertLegacyPrinterWriteAllowed;
/**
 * Printer configuration v2 is prepared by an authorized Owner/Platform writer.
 * Device/Venue identity and the current value must come from that writer's
 * server-owned Device read. This module performs no persistence, activation,
 * hardware discovery, printing, or durable compare-and-swap.
 */
exports.PRINTER_RUNTIME_READER_VERSION = 2;
exports.MAX_PRINTER_RUNTIME_REVISION = 0x7fffffff;
exports.MAX_PRINTER_RUNTIME_ROUTES = 64;
exports.MAX_PRINTER_RUNTIME_CONFIG_BYTES = 256 * 1024;
class PrinterRuntimeConfigError extends Error {
    code;
    constructor(code, message) {
        super(message);
        this.code = code;
        this.name = 'PrinterRuntimeConfigError';
    }
}
exports.PrinterRuntimeConfigError = PrinterRuntimeConfigError;
// Same UUID shape accepted by existing backend control-plane validation.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ROUTE_ID = /^[a-zA-Z0-9_-]{1,120}$/;
const CONTROL_CHARACTER = /[\x00-\x1f\x7f]/;
const roles = ['kitchen', 'bar', 'receipt', 'additional'];
const languages = ['escposRaster', 'windowsDriverRendered'];
const cutters = ['none', 'full', 'partial'];
const beepCapabilities = [
    'unknown',
    'unsupported',
    'epsonEscA97Pattern',
];
function invalid(path, rule) {
    throw new PrinterRuntimeConfigError('INVALID_PRINTER_RUNTIME_CONFIG', `${path}: ${rule}`);
}
function isDataRecord(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value))
        return false;
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null)
        return false;
    return Reflect.ownKeys(value).every((key) => {
        if (typeof key !== 'string')
            return false;
        const descriptor = Object.getOwnPropertyDescriptor(value, key);
        return descriptor !== undefined && 'value' in descriptor;
    });
}
function record(value, path) {
    if (!isDataRecord(value))
        invalid(path, 'a plain data object is required');
    return value;
}
function exactKeys(value, required, path, optional = []) {
    const allowed = new Set([...required, ...optional]);
    if (required.some((key) => !Object.prototype.hasOwnProperty.call(value, key)) ||
        Object.getOwnPropertyNames(value).some((key) => !allowed.has(key)))
        invalid(path, 'unexpected or missing fields');
}
function text(value, maximum, path) {
    if (typeof value !== 'string' ||
        value.length < 1 ||
        value.length > maximum ||
        value.trim() !== value ||
        CONTROL_CHARACTER.test(value))
        invalid(path, `trimmed control-free text of 1-${maximum} characters is required`);
    return value;
}
function uuid(value, path) {
    const id = text(value, 120, path);
    if (!UUID.test(id))
        invalid(path, 'a canonical UUID is required');
    return id;
}
function integer(value, minimum, maximum, path) {
    if (!Number.isSafeInteger(value) ||
        Number(value) < minimum ||
        Number(value) > maximum)
        invalid(path, `an integer between ${minimum} and ${maximum} is required`);
    return value;
}
function boolean(value, path) {
    if (typeof value !== 'boolean')
        invalid(path, 'a boolean is required');
    return value;
}
function choice(value, values, path) {
    if (typeof value !== 'string' || !values.includes(value))
        invalid(path, 'unsupported value');
    return value;
}
function contextIdentity(context) {
    const source = record(context, 'serverContext');
    return Object.freeze({
        deviceId: uuid(source.deviceId, 'serverContext.deviceId'),
        venueId: uuid(source.venueId, 'serverContext.venueId'),
    });
}
/** Optional sound never substitutes guessed commands or invalidates core output. */
function parseBeep(value, language) {
    const silent = () => Object.freeze({ capability: 'unknown', enabled: false });
    if (!isDataRecord(value))
        return silent();
    if (Object.getOwnPropertyNames(value).length !== 2 ||
        !Object.prototype.hasOwnProperty.call(value, 'capability') ||
        !Object.prototype.hasOwnProperty.call(value, 'enabled') ||
        typeof value.enabled !== 'boolean' ||
        !beepCapabilities.includes(value.capability))
        return silent();
    const capability = value.capability;
    return Object.freeze({
        capability,
        enabled: value.enabled &&
            capability === 'epsonEscA97Pattern' &&
            language === 'escposRaster',
    });
}
function parseProfile(value, path) {
    const source = record(value, path);
    exactKeys(source, [
        'protocol',
        'paperWidthMm',
        'rasterWidthDots',
        'language',
        'cutter',
        'encoding',
    ], path, ['beep']);
    integer(source.protocol, 1, 1, `${path}.protocol`);
    const rasterWidthDots = integer(source.rasterWidthDots, 64, 2048, `${path}.rasterWidthDots`);
    if (rasterWidthDots % 8 !== 0)
        invalid(`${path}.rasterWidthDots`, 'must be divisible by eight');
    const language = choice(source.language, languages, `${path}.language`);
    return Object.freeze({
        protocol: 1,
        paperWidthMm: integer(source.paperWidthMm, 40, 120, `${path}.paperWidthMm`),
        rasterWidthDots,
        language,
        cutter: choice(source.cutter, cutters, `${path}.cutter`),
        encoding: choice(source.encoding, ['georgianViaRaster'], `${path}.encoding`),
        beep: parseBeep(source.beep, language),
    });
}
function parseDestination(value, context, path) {
    const source = record(value, path);
    if (source.kind === 'tcp') {
        exactKeys(source, ['kind', 'host', 'port'], path);
        return Object.freeze({
            kind: 'tcp',
            host: text(source.host, 255, `${path}.host`),
            port: integer(source.port, 1, 65535, `${path}.port`),
        });
    }
    if (source.kind === 'windowsSpooler') {
        exactKeys(source, ['kind', 'ownerDeviceId', 'queueName', 'driverName', 'portName'], path);
        const ownerDeviceId = uuid(source.ownerDeviceId, `${path}.ownerDeviceId`);
        if (ownerDeviceId !== context.deviceId)
            throw new PrinterRuntimeConfigError('PRINTER_DEVICE_MISMATCH', 'Windows queue belongs to a different Device');
        return Object.freeze({
            kind: 'windowsSpooler',
            ownerDeviceId,
            queueName: text(source.queueName, 255, `${path}.queueName`),
            driverName: text(source.driverName, 1024, `${path}.driverName`),
            portName: text(source.portName, 1024, `${path}.portName`),
        });
    }
    return invalid(`${path}.kind`, 'unsupported transport');
}
function endpoint(destination) {
    return destination.kind === 'tcp'
        ? JSON.stringify(['tcp', destination.host.toLowerCase(), destination.port])
        : JSON.stringify([
            'windowsSpooler',
            destination.ownerDeviceId,
            destination.queueName.toLowerCase(),
        ]);
}
function parseRoutes(value, context) {
    if (!Array.isArray(value) || value.length > exports.MAX_PRINTER_RUNTIME_ROUTES)
        invalid('routes', `an array of at most ${exports.MAX_PRINTER_RUNTIME_ROUTES} routes is required`);
    if (Object.getPrototypeOf(value) !== Array.prototype ||
        Reflect.ownKeys(value).length !== value.length + 1)
        invalid('routes', 'a dense data array without additional fields is required');
    const ids = new Set(), names = new Set(), endpoints = new Set(), singletonRoles = new Set();
    const routes = [];
    for (let index = 0; index < value.length; index++) {
        const descriptor = Object.getOwnPropertyDescriptor(value, index);
        if (!descriptor || !('value' in descriptor))
            invalid('routes', 'sparse arrays and accessor entries are not accepted');
        const path = `routes[${index}]`;
        const source = record(descriptor.value, path);
        exactKeys(source, [
            'protocol',
            'id',
            'name',
            'role',
            'revision',
            'destination',
            'capabilityProfile',
            'enabled',
        ], path);
        integer(source.protocol, 1, 1, `${path}.protocol`);
        const id = text(source.id, 120, `${path}.id`);
        if (!ROUTE_ID.test(id))
            invalid(`${path}.id`, 'invalid route identity');
        const route = Object.freeze({
            protocol: 1,
            id,
            name: text(source.name, 80, `${path}.name`),
            role: choice(source.role, roles, `${path}.role`),
            revision: integer(source.revision, 1, exports.MAX_PRINTER_RUNTIME_REVISION, `${path}.revision`),
            destination: parseDestination(source.destination, context, `${path}.destination`),
            capabilityProfile: parseProfile(source.capabilityProfile, `${path}.capabilityProfile`),
            enabled: boolean(source.enabled, `${path}.enabled`),
        });
        const name = route.name.toLowerCase(), target = endpoint(route.destination);
        if (ids.has(route.id))
            invalid(path, 'duplicate route identity');
        if (names.has(name))
            invalid(path, 'duplicate route name');
        if (endpoints.has(target))
            invalid(path, 'duplicate physical endpoint');
        if (route.role !== 'additional' && singletonRoles.has(route.role))
            invalid(path, 'duplicate printer role');
        ids.add(route.id);
        names.add(name);
        endpoints.add(target);
        if (route.role !== 'additional')
            singletonRoles.add(route.role);
        routes.push(route);
    }
    return Object.freeze(routes);
}
function legacyDisabledPrinters() {
    const disabled = Object.freeze({
        enabled: false,
        host: '',
        port: 9100,
    });
    return Object.freeze({ kitchen: disabled, receipt: disabled });
}
function validateLegacyStubs(value) {
    const printers = record(value, 'printers');
    exactKeys(printers, ['kitchen', 'receipt'], 'printers');
    for (const role of ['kitchen', 'receipt']) {
        const row = record(printers[role], `printers.${role}`);
        exactKeys(row, ['enabled', 'host', 'port'], `printers.${role}`);
        if (row.enabled !== false || row.host !== '' || row.port !== 9100)
            invalid(`printers.${role}`, 'disabled legacy containment entry is required');
    }
}
function bounded(config) {
    if (Buffer.byteLength(JSON.stringify(config), 'utf8') >
        exports.MAX_PRINTER_RUNTIME_CONFIG_BYTES)
        invalid('runtimeConfig', `canonical JSON exceeds ${exports.MAX_PRINTER_RUNTIME_CONFIG_BYTES} bytes`);
    return Object.freeze(config);
}
/** Read a complete snapshot; accepting ACTIVE data does not activate anything. */
function parsePrinterRuntimeConfigV2(value, serverContext) {
    const context = contextIdentity(serverContext);
    const source = record(value, 'runtimeConfig');
    exactKeys(source, [
        'version',
        'deviceId',
        'venueId',
        'revision',
        'phase',
        'minimumReaderVersion',
        'printers',
        'routes',
    ], 'runtimeConfig');
    integer(source.version, 2, 2, 'runtimeConfig.version');
    const deviceId = uuid(source.deviceId, 'runtimeConfig.deviceId');
    const venueId = uuid(source.venueId, 'runtimeConfig.venueId');
    if (deviceId !== context.deviceId)
        throw new PrinterRuntimeConfigError('PRINTER_DEVICE_MISMATCH', 'Configuration belongs to a different Device');
    if (venueId !== context.venueId)
        throw new PrinterRuntimeConfigError('PRINTER_VENUE_MISMATCH', 'Configuration belongs to a different Venue');
    validateLegacyStubs(source.printers);
    integer(source.minimumReaderVersion, 2, 2, 'runtimeConfig.minimumReaderVersion');
    return bounded({
        version: 2,
        deviceId,
        venueId,
        revision: integer(source.revision, 1, exports.MAX_PRINTER_RUNTIME_REVISION, 'runtimeConfig.revision'),
        phase: choice(source.phase, ['PREPARED', 'ACTIVE'], 'runtimeConfig.phase'),
        minimumReaderVersion: 2,
        printers: legacyDisabledPrinters(),
        routes: parseRoutes(source.routes, context),
    });
}
function revisionConflict(message) {
    throw new PrinterRuntimeConfigError('PRINTER_REVISION_CONFLICT', message);
}
/**
 * Draft keys: version, expectedRevision, minimumReaderVersion, routes.
 * Client Device/Venue, phase and compatibility entries are never accepted.
 * Supply currentConfig from the trusted locked Device read (null is explicit).
 * V1 remains authoritative until a separate authorized persistence transition.
 */
function preparePrinterRuntimeConfigV2(draft, serverContext, currentConfig) {
    const context = contextIdentity(serverContext);
    const source = record(draft, 'draft');
    exactKeys(source, ['version', 'expectedRevision', 'minimumReaderVersion', 'routes'], 'draft');
    integer(source.version, 2, 2, 'draft.version');
    integer(source.minimumReaderVersion, 2, 2, 'draft.minimumReaderVersion');
    const expectedRevision = integer(source.expectedRevision, 0, exports.MAX_PRINTER_RUNTIME_REVISION, 'draft.expectedRevision');
    let previous = null;
    if (currentConfig !== null) {
        const current = record(currentConfig, 'currentConfig');
        // Do not reinterpret or mutate the established v1 printer representation.
        if (current.version !== 1)
            previous = parsePrinterRuntimeConfigV2(current, context);
    }
    const revision = previous?.revision ?? 0;
    if (expectedRevision !== revision)
        revisionConflict('Printer configuration revision changed');
    if (revision === exports.MAX_PRINTER_RUNTIME_REVISION)
        throw new PrinterRuntimeConfigError('PRINTER_REVISION_EXHAUSTED', 'Printer configuration revision is exhausted');
    const routes = parseRoutes(source.routes, context);
    const previousRoutes = new Map(previous?.routes.map((route) => [route.id, route]) ?? []);
    const nextIds = new Set(routes.map((route) => route.id));
    if ([...previousRoutes.keys()].some((id) => !nextIds.has(id)))
        revisionConflict('Existing route identities must be retained; disable routes instead of deleting them');
    for (const route of routes) {
        const before = previousRoutes.get(route.id);
        if (!before) {
            if (route.revision !== 1)
                revisionConflict('New printer routes must start at revision one');
            continue;
        }
        const { revision: _beforeRevision, ...beforeBody } = before;
        const { revision: _nextRevision, ...nextBody } = route;
        const changed = JSON.stringify(beforeBody) !== JSON.stringify(nextBody);
        if (changed && before.revision === exports.MAX_PRINTER_RUNTIME_REVISION)
            throw new PrinterRuntimeConfigError('PRINTER_REVISION_EXHAUSTED', 'Printer route revision is exhausted');
        if (route.revision !== before.revision + (changed ? 1 : 0))
            revisionConflict('Printer route revision does not match its accepted change');
    }
    return bounded({
        version: 2,
        deviceId: context.deviceId,
        venueId: context.venueId,
        revision: revision + 1,
        phase: 'PREPARED',
        minimumReaderVersion: 2,
        printers: legacyDisabledPrinters(),
        routes,
    });
}
/** Later v1 writers must invoke this before changing the stored Device value. */
function assertLegacyPrinterWriteAllowed(currentConfig) {
    if (currentConfig === null)
        return;
    const current = record(currentConfig, 'currentConfig');
    if (current.version === 1)
        return;
    throw new PrinterRuntimeConfigError('LEGACY_PRINTER_WRITE_REJECTED', 'Legacy printer writes cannot overwrite a versioned printer configuration');
}
