/**
 * Printer configuration v2 is prepared by an authorized Owner/Platform writer.
 * Device/Venue identity and the current value must come from that writer's
 * server-owned Device read. This module performs no persistence, activation,
 * hardware discovery, printing, or durable compare-and-swap.
 */
export const PRINTER_RUNTIME_READER_VERSION = 2;
export const MAX_PRINTER_RUNTIME_REVISION = 0x7fffffff;
export const MAX_PRINTER_RUNTIME_ROUTES = 64;
export const MAX_PRINTER_RUNTIME_CONFIG_BYTES = 256 * 1024;

export type PrinterRuntimeConfigErrorCode =
  | 'INVALID_PRINTER_RUNTIME_CONFIG'
  | 'PRINTER_DEVICE_MISMATCH'
  | 'PRINTER_VENUE_MISMATCH'
  | 'PRINTER_REVISION_CONFLICT'
  | 'PRINTER_REVISION_EXHAUSTED'
  | 'LEGACY_PRINTER_WRITE_REJECTED';

export class PrinterRuntimeConfigError extends Error {
  constructor(
    readonly code: PrinterRuntimeConfigErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'PrinterRuntimeConfigError';
  }
}

export type PrinterRuntimeContext = Readonly<{
  deviceId: string;
  venueId: string;
}>;
export type PrinterRuntimeRole = 'kitchen' | 'bar' | 'receipt' | 'additional';
export type PrinterCommandLanguage = 'escposRaster' | 'windowsDriverRendered';
export type PrinterBeepCapability =
  | 'unknown'
  | 'unsupported'
  | 'epsonEscA97Pattern';
export type PrinterBeepSettings = Readonly<{
  capability: PrinterBeepCapability;
  enabled: boolean;
}>;
export type PrinterCapabilityProfile = Readonly<{
  protocol: 1;
  paperWidthMm: number;
  rasterWidthDots: number;
  language: PrinterCommandLanguage;
  cutter: 'none' | 'full' | 'partial';
  encoding: 'georgianViaRaster';
  beep: PrinterBeepSettings;
}>;
export type PrinterRuntimeDestination =
  | Readonly<{ kind: 'tcp'; host: string; port: number }>
  | Readonly<{
      kind: 'windowsSpooler';
      ownerDeviceId: string;
      queueName: string;
      driverName: string;
      portName: string;
    }>;
export type PrinterRuntimeRoute = Readonly<{
  protocol: 1;
  id: string;
  name: string;
  role: PrinterRuntimeRole;
  revision: number;
  destination: PrinterRuntimeDestination;
  capabilityProfile: PrinterCapabilityProfile;
  enabled: boolean;
}>;
type DisabledLegacyPrinter = Readonly<{
  enabled: false;
  host: '';
  port: 9100;
}>;
export type PrinterRuntimeConfigV2 = Readonly<{
  version: 2;
  deviceId: string;
  venueId: string;
  revision: number;
  phase: 'PREPARED' | 'ACTIVE';
  minimumReaderVersion: 2;
  printers: Readonly<{
    kitchen: DisabledLegacyPrinter;
    receipt: DisabledLegacyPrinter;
  }>;
  routes: readonly PrinterRuntimeRoute[];
}>;

// Same UUID shape accepted by existing backend control-plane validation.
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ROUTE_ID = /^[a-zA-Z0-9_-]{1,120}$/;
const CONTROL_CHARACTER = /[\x00-\x1f\x7f]/;
const roles = ['kitchen', 'bar', 'receipt', 'additional'] as const;
const languages = ['escposRaster', 'windowsDriverRendered'] as const;
const cutters = ['none', 'full', 'partial'] as const;
const beepCapabilities = [
  'unknown',
  'unsupported',
  'epsonEscA97Pattern',
] as const;

function invalid(path: string, rule: string): never {
  throw new PrinterRuntimeConfigError(
    'INVALID_PRINTER_RUNTIME_CONFIG',
    `${path}: ${rule}`,
  );
}

function isDataRecord(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) return false;
  return Reflect.ownKeys(value).every((key) => {
    if (typeof key !== 'string') return false;
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    return descriptor !== undefined && 'value' in descriptor;
  });
}

function record(value: unknown, path: string): Record<string, unknown> {
  if (!isDataRecord(value)) invalid(path, 'a plain data object is required');
  return value;
}

function exactKeys(
  value: Record<string, unknown>,
  required: readonly string[],
  path: string,
  optional: readonly string[] = [],
): void {
  const allowed = new Set([...required, ...optional]);
  if (
    required.some((key) => !Object.prototype.hasOwnProperty.call(value, key)) ||
    Object.getOwnPropertyNames(value).some((key) => !allowed.has(key))
  )
    invalid(path, 'unexpected or missing fields');
}

function text(value: unknown, maximum: number, path: string): string {
  if (
    typeof value !== 'string' ||
    value.length < 1 ||
    value.length > maximum ||
    value.trim() !== value ||
    CONTROL_CHARACTER.test(value)
  )
    invalid(
      path,
      `trimmed control-free text of 1-${maximum} characters is required`,
    );
  return value;
}

function uuid(value: unknown, path: string): string {
  const id = text(value, 120, path);
  if (!UUID.test(id)) invalid(path, 'a canonical UUID is required');
  return id;
}

function integer(
  value: unknown,
  minimum: number,
  maximum: number,
  path: string,
): number {
  if (
    !Number.isSafeInteger(value) ||
    Number(value) < minimum ||
    Number(value) > maximum
  )
    invalid(path, `an integer between ${minimum} and ${maximum} is required`);
  return value as number;
}

function boolean(value: unknown, path: string): boolean {
  if (typeof value !== 'boolean') invalid(path, 'a boolean is required');
  return value;
}

function choice<T extends string>(
  value: unknown,
  values: readonly T[],
  path: string,
): T {
  if (typeof value !== 'string' || !values.includes(value as T))
    invalid(path, 'unsupported value');
  return value as T;
}

function contextIdentity(
  context: PrinterRuntimeContext,
): PrinterRuntimeContext {
  const source = record(context, 'serverContext');
  return Object.freeze({
    deviceId: uuid(source.deviceId, 'serverContext.deviceId'),
    venueId: uuid(source.venueId, 'serverContext.venueId'),
  });
}

/** Optional sound never substitutes guessed commands or invalidates core output. */
function parseBeep(
  value: unknown,
  language: PrinterCommandLanguage,
): PrinterBeepSettings {
  const silent = (): PrinterBeepSettings =>
    Object.freeze({ capability: 'unknown', enabled: false });
  if (!isDataRecord(value)) return silent();
  if (
    Object.getOwnPropertyNames(value).length !== 2 ||
    !Object.prototype.hasOwnProperty.call(value, 'capability') ||
    !Object.prototype.hasOwnProperty.call(value, 'enabled') ||
    typeof value.enabled !== 'boolean' ||
    !beepCapabilities.includes(value.capability as PrinterBeepCapability)
  )
    return silent();
  const capability = value.capability as PrinterBeepCapability;
  return Object.freeze({
    capability,
    enabled:
      value.enabled &&
      capability === 'epsonEscA97Pattern' &&
      language === 'escposRaster',
  });
}

function parseProfile(value: unknown, path: string): PrinterCapabilityProfile {
  const source = record(value, path);
  exactKeys(
    source,
    [
      'protocol',
      'paperWidthMm',
      'rasterWidthDots',
      'language',
      'cutter',
      'encoding',
    ],
    path,
    ['beep'],
  );
  integer(source.protocol, 1, 1, `${path}.protocol`);
  const rasterWidthDots = integer(
    source.rasterWidthDots,
    64,
    2048,
    `${path}.rasterWidthDots`,
  );
  if (rasterWidthDots % 8 !== 0)
    invalid(`${path}.rasterWidthDots`, 'must be divisible by eight');
  const language = choice(source.language, languages, `${path}.language`);
  return Object.freeze({
    protocol: 1,
    paperWidthMm: integer(source.paperWidthMm, 40, 120, `${path}.paperWidthMm`),
    rasterWidthDots,
    language,
    cutter: choice(source.cutter, cutters, `${path}.cutter`),
    encoding: choice(
      source.encoding,
      ['georgianViaRaster'],
      `${path}.encoding`,
    ),
    beep: parseBeep(source.beep, language),
  });
}

function parseDestination(
  value: unknown,
  context: PrinterRuntimeContext,
  path: string,
): PrinterRuntimeDestination {
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
    exactKeys(
      source,
      ['kind', 'ownerDeviceId', 'queueName', 'driverName', 'portName'],
      path,
    );
    const ownerDeviceId = uuid(source.ownerDeviceId, `${path}.ownerDeviceId`);
    if (ownerDeviceId !== context.deviceId)
      throw new PrinterRuntimeConfigError(
        'PRINTER_DEVICE_MISMATCH',
        'Windows queue belongs to a different Device',
      );
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

function endpoint(destination: PrinterRuntimeDestination): string {
  return destination.kind === 'tcp'
    ? JSON.stringify(['tcp', destination.host.toLowerCase(), destination.port])
    : JSON.stringify([
        'windowsSpooler',
        destination.ownerDeviceId,
        destination.queueName.toLowerCase(),
      ]);
}

function parseRoutes(
  value: unknown,
  context: PrinterRuntimeContext,
): readonly PrinterRuntimeRoute[] {
  if (!Array.isArray(value) || value.length > MAX_PRINTER_RUNTIME_ROUTES)
    invalid(
      'routes',
      `an array of at most ${MAX_PRINTER_RUNTIME_ROUTES} routes is required`,
    );
  if (
    Object.getPrototypeOf(value) !== Array.prototype ||
    Reflect.ownKeys(value).length !== value.length + 1
  )
    invalid(
      'routes',
      'a dense data array without additional fields is required',
    );
  const ids = new Set<string>(),
    names = new Set<string>(),
    endpoints = new Set<string>(),
    singletonRoles = new Set<string>();
  const routes: PrinterRuntimeRoute[] = [];
  for (let index = 0; index < value.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, index);
    if (!descriptor || !('value' in descriptor))
      invalid('routes', 'sparse arrays and accessor entries are not accepted');
    const path = `routes[${index}]`;
    const source = record(descriptor.value, path);
    exactKeys(
      source,
      [
        'protocol',
        'id',
        'name',
        'role',
        'revision',
        'destination',
        'capabilityProfile',
        'enabled',
      ],
      path,
    );
    integer(source.protocol, 1, 1, `${path}.protocol`);
    const id = text(source.id, 120, `${path}.id`);
    if (!ROUTE_ID.test(id)) invalid(`${path}.id`, 'invalid route identity');
    const route: PrinterRuntimeRoute = Object.freeze({
      protocol: 1,
      id,
      name: text(source.name, 80, `${path}.name`),
      role: choice(source.role, roles, `${path}.role`),
      revision: integer(
        source.revision,
        1,
        MAX_PRINTER_RUNTIME_REVISION,
        `${path}.revision`,
      ),
      destination: parseDestination(
        source.destination,
        context,
        `${path}.destination`,
      ),
      capabilityProfile: parseProfile(
        source.capabilityProfile,
        `${path}.capabilityProfile`,
      ),
      enabled: boolean(source.enabled, `${path}.enabled`),
    });
    const name = route.name.toLowerCase(),
      target = endpoint(route.destination);
    if (ids.has(route.id)) invalid(path, 'duplicate route identity');
    if (names.has(name)) invalid(path, 'duplicate route name');
    if (endpoints.has(target)) invalid(path, 'duplicate physical endpoint');
    if (route.role !== 'additional' && singletonRoles.has(route.role))
      invalid(path, 'duplicate printer role');
    ids.add(route.id);
    names.add(name);
    endpoints.add(target);
    if (route.role !== 'additional') singletonRoles.add(route.role);
    routes.push(route);
  }
  return Object.freeze(routes);
}

function legacyDisabledPrinters(): PrinterRuntimeConfigV2['printers'] {
  const disabled: DisabledLegacyPrinter = Object.freeze({
    enabled: false,
    host: '',
    port: 9100,
  });
  return Object.freeze({ kitchen: disabled, receipt: disabled });
}

function validateLegacyStubs(value: unknown): void {
  const printers = record(value, 'printers');
  exactKeys(printers, ['kitchen', 'receipt'], 'printers');
  for (const role of ['kitchen', 'receipt']) {
    const row = record(printers[role], `printers.${role}`);
    exactKeys(row, ['enabled', 'host', 'port'], `printers.${role}`);
    if (row.enabled !== false || row.host !== '' || row.port !== 9100)
      invalid(
        `printers.${role}`,
        'disabled legacy containment entry is required',
      );
  }
}

function bounded(config: PrinterRuntimeConfigV2): PrinterRuntimeConfigV2 {
  if (
    Buffer.byteLength(JSON.stringify(config), 'utf8') >
    MAX_PRINTER_RUNTIME_CONFIG_BYTES
  )
    invalid(
      'runtimeConfig',
      `canonical JSON exceeds ${MAX_PRINTER_RUNTIME_CONFIG_BYTES} bytes`,
    );
  return Object.freeze(config);
}

/** Read a complete snapshot; accepting ACTIVE data does not activate anything. */
export function parsePrinterRuntimeConfigV2(
  value: unknown,
  serverContext: PrinterRuntimeContext,
): PrinterRuntimeConfigV2 {
  const context = contextIdentity(serverContext);
  const source = record(value, 'runtimeConfig');
  exactKeys(
    source,
    [
      'version',
      'deviceId',
      'venueId',
      'revision',
      'phase',
      'minimumReaderVersion',
      'printers',
      'routes',
    ],
    'runtimeConfig',
  );
  integer(source.version, 2, 2, 'runtimeConfig.version');
  const deviceId = uuid(source.deviceId, 'runtimeConfig.deviceId');
  const venueId = uuid(source.venueId, 'runtimeConfig.venueId');
  if (deviceId !== context.deviceId)
    throw new PrinterRuntimeConfigError(
      'PRINTER_DEVICE_MISMATCH',
      'Configuration belongs to a different Device',
    );
  if (venueId !== context.venueId)
    throw new PrinterRuntimeConfigError(
      'PRINTER_VENUE_MISMATCH',
      'Configuration belongs to a different Venue',
    );
  validateLegacyStubs(source.printers);
  integer(
    source.minimumReaderVersion,
    2,
    2,
    'runtimeConfig.minimumReaderVersion',
  );
  return bounded({
    version: 2,
    deviceId,
    venueId,
    revision: integer(
      source.revision,
      1,
      MAX_PRINTER_RUNTIME_REVISION,
      'runtimeConfig.revision',
    ),
    phase: choice(source.phase, ['PREPARED', 'ACTIVE'], 'runtimeConfig.phase'),
    minimumReaderVersion: 2,
    printers: legacyDisabledPrinters(),
    routes: parseRoutes(source.routes, context),
  });
}

function revisionConflict(message: string): never {
  throw new PrinterRuntimeConfigError('PRINTER_REVISION_CONFLICT', message);
}

/**
 * Draft keys: version, expectedRevision, minimumReaderVersion, routes.
 * Client Device/Venue, phase and compatibility entries are never accepted.
 * Supply currentConfig from the trusted locked Device read (null is explicit).
 * V1 remains authoritative until a separate authorized persistence transition.
 */
export function preparePrinterRuntimeConfigV2(
  draft: unknown,
  serverContext: PrinterRuntimeContext,
  currentConfig: unknown,
): PrinterRuntimeConfigV2 {
  const context = contextIdentity(serverContext);
  const source = record(draft, 'draft');
  exactKeys(
    source,
    ['version', 'expectedRevision', 'minimumReaderVersion', 'routes'],
    'draft',
  );
  integer(source.version, 2, 2, 'draft.version');
  integer(source.minimumReaderVersion, 2, 2, 'draft.minimumReaderVersion');
  const expectedRevision = integer(
    source.expectedRevision,
    0,
    MAX_PRINTER_RUNTIME_REVISION,
    'draft.expectedRevision',
  );
  let previous: PrinterRuntimeConfigV2 | null = null;
  if (currentConfig !== null) {
    const current = record(currentConfig, 'currentConfig');
    // Do not reinterpret or mutate the established v1 printer representation.
    if (current.version !== 1)
      previous = parsePrinterRuntimeConfigV2(current, context);
  }
  const revision = previous?.revision ?? 0;
  if (expectedRevision !== revision)
    revisionConflict('Printer configuration revision changed');
  if (revision === MAX_PRINTER_RUNTIME_REVISION)
    throw new PrinterRuntimeConfigError(
      'PRINTER_REVISION_EXHAUSTED',
      'Printer configuration revision is exhausted',
    );
  const routes = parseRoutes(source.routes, context);
  const previousRoutes = new Map(
    previous?.routes.map((route) => [route.id, route]) ?? [],
  );
  const nextIds = new Set(routes.map((route) => route.id));
  if ([...previousRoutes.keys()].some((id) => !nextIds.has(id)))
    revisionConflict(
      'Existing route identities must be retained; disable routes instead of deleting them',
    );
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
    if (changed && before.revision === MAX_PRINTER_RUNTIME_REVISION)
      throw new PrinterRuntimeConfigError(
        'PRINTER_REVISION_EXHAUSTED',
        'Printer route revision is exhausted',
      );
    if (route.revision !== before.revision + (changed ? 1 : 0))
      revisionConflict(
        'Printer route revision does not match its accepted change',
      );
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
export function assertLegacyPrinterWriteAllowed(currentConfig: unknown): void {
  if (currentConfig === null) return;
  const current = record(currentConfig, 'currentConfig');
  if (current.version === 1) return;
  throw new PrinterRuntimeConfigError(
    'LEGACY_PRINTER_WRITE_REJECTED',
    'Legacy printer writes cannot overwrite a versioned printer configuration',
  );
}
