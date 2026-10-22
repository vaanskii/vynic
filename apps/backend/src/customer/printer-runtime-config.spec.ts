import {
  assertLegacyPrinterWriteAllowed,
  MAX_PRINTER_RUNTIME_CONFIG_BYTES,
  MAX_PRINTER_RUNTIME_REVISION,
  MAX_PRINTER_RUNTIME_ROUTES,
  parsePrinterRuntimeConfigV2,
  preparePrinterRuntimeConfigV2,
  PrinterRuntimeConfigError,
  type PrinterRuntimeConfigErrorCode,
} from './printer-runtime-config';

type WireObject = Record<string, any>;
const deviceId = '11111111-1111-4111-8111-111111111111';
const venueId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const otherDeviceId = '22222222-2222-4222-8222-222222222222';
const otherVenueId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const context = { deviceId, venueId };
const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value));

function profile(): WireObject {
  return {
    protocol: 1,
    paperWidthMm: 80,
    rasterWidthDots: 576,
    language: 'escposRaster',
    cutter: 'partial',
    encoding: 'georgianViaRaster',
    beep: { capability: 'unknown', enabled: false },
  };
}
function route(overrides: WireObject = {}): WireObject {
  return {
    protocol: 1,
    id: 'kitchen-route',
    name: 'Kitchen',
    role: 'kitchen',
    revision: 1,
    destination: { kind: 'tcp', host: '192.168.1.50', port: 9100 },
    capabilityProfile: profile(),
    enabled: true,
    ...overrides,
  };
}
function windowsRoute(overrides: WireObject = {}): WireObject {
  return route({
    id: 'usb-route',
    name: 'USB Kitchen',
    destination: {
      kind: 'windowsSpooler',
      ownerDeviceId: deviceId,
      queueName: 'Kitchen queue',
      driverName: 'Configured RAW driver',
      portName: 'USB001',
    },
    ...overrides,
  });
}
function disabledLegacy(): WireObject {
  return {
    kitchen: { enabled: false, host: '', port: 9100 },
    receipt: { enabled: false, host: '', port: 9100 },
  };
}
function snapshot(routes = [route()], overrides: WireObject = {}): WireObject {
  return {
    version: 2,
    deviceId,
    venueId,
    revision: 1,
    phase: 'PREPARED',
    minimumReaderVersion: 2,
    printers: disabledLegacy(),
    routes,
    ...overrides,
  };
}
function draft(routes = [route()], overrides: WireObject = {}): WireObject {
  return {
    version: 2,
    expectedRevision: 0,
    minimumReaderVersion: 2,
    routes,
    ...overrides,
  };
}
function errorCode(
  action: () => unknown,
  code: PrinterRuntimeConfigErrorCode,
): void {
  try {
    action();
    throw new Error('Expected printer configuration rejection');
  } catch (error) {
    expect(error).toBeInstanceOf(PrinterRuntimeConfigError);
    expect((error as PrinterRuntimeConfigError).code).toBe(code);
  }
}
const invalid = (action: () => unknown) =>
  errorCode(action, 'INVALID_PRINTER_RUNTIME_CONFIG');

describe('printer runtime v2 preparation and ownership', () => {
  it('derives Device/Venue, first revision, reader floor and disabled legacy entries without activation', () => {
    const prepared = preparePrinterRuntimeConfigV2(draft(), context, null);
    expect(prepared).toEqual(snapshot());
    expect(prepared.phase).toBe('PREPARED');
    expect(prepared.printers).toEqual(disabledLegacy());
    expect(prepared.minimumReaderVersion).toBe(2);
    expect(parsePrinterRuntimeConfigV2(prepared, context)).toEqual(prepared);
  });

  it('prepares from a trusted v1 value without mutating or activating its established authority', () => {
    const legacy = {
      version: 1,
      printers: {
        kitchen: { enabled: true, host: '192.168.1.70', port: 9100 },
        receipt: { enabled: false, host: '', port: 9100 },
      },
    };
    const before = clone(legacy);
    expect(
      preparePrinterRuntimeConfigV2(draft(), context, legacy),
    ).toMatchObject({
      revision: 1,
      phase: 'PREPARED',
    });
    expect(legacy).toEqual(before);
    expect(() => assertLegacyPrinterWriteAllowed(legacy)).not.toThrow();
    invalid(() => parsePrinterRuntimeConfigV2(legacy, context));
  });

  it('parses explicitly stored ACTIVE fixtures but exposes no default promotion', () => {
    expect(
      parsePrinterRuntimeConfigV2(snapshot([], { phase: 'ACTIVE' }), context)
        .phase,
    ).toBe('ACTIVE');
    expect(
      preparePrinterRuntimeConfigV2(
        draft([], { expectedRevision: 1 }),
        context,
        snapshot([], { phase: 'ACTIVE' }),
      ).phase,
    ).toBe('PREPARED');
    const missingPhase = snapshot();
    delete missingPhase.phase;
    invalid(() => parsePrinterRuntimeConfigV2(missingPhase, context));
  });

  it.each([
    'deviceId',
    'venueId',
    'tenantId',
    'organizationId',
    'ownerDeviceId',
    'phase',
    'printers',
    'revision',
    'actor',
  ])('rejects client authority or server-managed draft field %s', (key) => {
    invalid(() =>
      preparePrinterRuntimeConfigV2(
        draft(undefined, { [key]: deviceId }),
        context,
        null,
      ),
    );
  });

  it('rejects wrong Device/Venue and a Windows queue bound to another Device', () => {
    errorCode(
      () =>
        parsePrinterRuntimeConfigV2(
          snapshot(undefined, { deviceId: otherDeviceId }),
          context,
        ),
      'PRINTER_DEVICE_MISMATCH',
    );
    errorCode(
      () =>
        parsePrinterRuntimeConfigV2(
          snapshot(undefined, { venueId: otherVenueId }),
          context,
        ),
      'PRINTER_VENUE_MISMATCH',
    );
    const windows = windowsRoute();
    windows.destination.ownerDeviceId = otherDeviceId;
    errorCode(
      () => preparePrinterRuntimeConfigV2(draft([windows]), context, null),
      'PRINTER_DEVICE_MISMATCH',
    );
  });

  it.each([
    '',
    ' device-a',
    'device-a',
    '../device',
    '00000000-0000-0000-0000-000000000000',
  ])('rejects malformed server/root UUID %j', (id) => {
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft(), { deviceId: id, venueId }, null),
    );
    invalid(() =>
      parsePrinterRuntimeConfigV2(
        snapshot(undefined, { venueId: id }),
        context,
      ),
    );
    const windows = windowsRoute();
    windows.destination.ownerDeviceId = id;
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft([windows]), context, null),
    );
  });

  it('requires complete disabled kitchen/receipt entries for old lookup containment', () => {
    for (const mutate of [
      (s: WireObject) => delete s.printers,
      (s: WireObject) => delete s.printers.receipt,
      (s: WireObject) => {
        s.printers.kitchen.enabled = true;
      },
      (s: WireObject) => {
        s.printers.receipt.host = '192.168.1.80';
      },
      (s: WireObject) => {
        s.printers.kitchen.port = 9200;
      },
      (s: WireObject) => {
        s.printers.receipt.transport = 'tcp';
      },
    ]) {
      const value = snapshot();
      mutate(value);
      invalid(() => parsePrinterRuntimeConfigV2(value, context));
    }
    const prepared = preparePrinterRuntimeConfigV2(draft([]), context, null);
    // This proves explicit disabled entries, not fencing of an old offline v1 cache.
    expect(
      prepared.printers.kitchen.enabled ? prepared.printers.kitchen.host : '',
    ).toBe('');
    expect(
      prepared.printers.receipt.enabled ? prepared.printers.receipt.host : '',
    ).toBe('');
  });

  it('returns independent frozen profiles/destinations, including Windows driver and port', () => {
    const input = draft([windowsRoute()]);
    const accepted = preparePrinterRuntimeConfigV2(input, context, null);
    input.routes[0].destination.driverName = 'replacement driver';
    input.routes[0].destination.portName = 'USB099';
    input.routes[0].capabilityProfile.rasterWidthDots = 384;
    expect(accepted.routes[0].destination).toMatchObject({
      driverName: 'Configured RAW driver',
      portName: 'USB001',
    });
    expect(accepted.routes[0].capabilityProfile.rasterWidthDots).toBe(576);
    expect(Object.isFrozen(accepted)).toBe(true);
    expect(Object.isFrozen(accepted.routes)).toBe(true);
    expect(Object.isFrozen(accepted.routes[0].destination)).toBe(true);
    expect(Object.isFrozen(accepted.routes[0].capabilityProfile.beep)).toBe(
      true,
    );
  });
});

describe('printer runtime v2 complete route/capability validation', () => {
  it.each([
    ['version', 1],
    ['version', '2'],
    ['revision', 0],
    ['revision', 1.1],
    ['revision', MAX_PRINTER_RUNTIME_REVISION + 1],
    ['minimumReaderVersion', 1],
    ['minimumReaderVersion', '2'],
    ['minimumReaderVersion', 3],
    ['phase', 'READY'],
  ])('rejects invalid root %s=%j', (key, value) => {
    invalid(() =>
      parsePrinterRuntimeConfigV2(
        snapshot(undefined, { [key]: value }),
        context,
      ),
    );
  });

  it.each([
    'protocol',
    'id',
    'name',
    'role',
    'revision',
    'destination',
    'capabilityProfile',
    'enabled',
  ])('requires route field %s without defaults', (key) => {
    const value = route();
    delete value[key];
    invalid(() => preparePrinterRuntimeConfigV2(draft([value]), context, null));
  });

  it.each([
    ['protocol', true],
    ['protocol', 2],
    ['id', 'with space'],
    ['id', '../route'],
    ['id', 'x'.repeat(121)],
    ['name', ' Kitchen'],
    ['name', 'a\nb'],
    ['name', 'x'.repeat(81)],
    ['role', 'unknown'],
    ['revision', 0],
    ['revision', '1'],
    ['revision', Number.NaN],
    ['enabled', 'true'],
    ['venueId', venueId],
  ])('rejects invalid/foreign route %s=%j', (key, value) => {
    invalid(() =>
      preparePrinterRuntimeConfigV2(
        draft([route({ [key]: value })]),
        context,
        null,
      ),
    );
  });

  it('accepts literal boundary values and hostname TCP destinations', () => {
    const value = route({ id: 'x'.repeat(120), name: 'x'.repeat(80) });
    value.destination = { kind: 'tcp', host: 'printer.local', port: 1 };
    value.capabilityProfile.paperWidthMm = 40;
    value.capabilityProfile.rasterWidthDots = 64;
    expect(
      preparePrinterRuntimeConfigV2(draft([value]), context, null).routes[0]
        .destination,
    ).toEqual(value.destination);
    value.destination = { kind: 'tcp', host: 'h'.repeat(255), port: 65535 };
    value.capabilityProfile.paperWidthMm = 120;
    value.capabilityProfile.rasterWidthDots = 2048;
    expect(() =>
      preparePrinterRuntimeConfigV2(draft([value]), context, null),
    ).not.toThrow();
  });

  it.each([
    { kind: 'usb', host: '192.168.1.50', port: 9100 },
    { kind: 'tcp', host: '', port: 9100 },
    { kind: 'tcp', host: ' host', port: 9100 },
    { kind: 'tcp', host: 'a\u0000b', port: 9100 },
    { kind: 'tcp', host: 'h'.repeat(256), port: 9100 },
    { kind: 'tcp', host: 'printer.local', port: 0 },
    { kind: 'tcp', host: 'printer.local', port: 65536 },
    { kind: 'tcp', host: 'printer.local', port: '9100' },
    { kind: 'tcp', host: 'printer.local', port: 9100, queueName: 'extra' },
  ])('rejects malformed TCP/unknown destination %j', (destination) => {
    invalid(() =>
      preparePrinterRuntimeConfigV2(
        draft([route({ destination })]),
        context,
        null,
      ),
    );
  });

  it.each([
    ['queueName', ''],
    ['queueName', 'q'.repeat(256)],
    ['driverName', 'd'.repeat(1025)],
    ['portName', 'p'.repeat(1025)],
    ['portName', ' USB001'],
    ['driverName', 'a\rb'],
    ['host', '192.168.1.9'],
  ])('rejects malformed/foreign Windows field %s=%j', (key, value) => {
    const windows = windowsRoute();
    windows.destination[key] = value;
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft([windows]), context, null),
    );
  });

  it.each([
    'protocol',
    'paperWidthMm',
    'rasterWidthDots',
    'language',
    'cutter',
    'encoding',
  ])('requires core capability %s', (key) => {
    const value = route();
    delete value.capabilityProfile[key];
    invalid(() => preparePrinterRuntimeConfigV2(draft([value]), context, null));
  });

  it.each([
    ['protocol', '1'],
    ['paperWidthMm', 39],
    ['paperWidthMm', 121],
    ['rasterWidthDots', 63],
    ['rasterWidthDots', 2056],
    ['rasterWidthDots', 65],
    ['language', 'vendorGuess'],
    ['language', 'cp866'],
    ['cutter', 'automatic'],
    ['encoding', 'CP857'],
    ['vendorName', 'Epson'],
    ['commandBytes', [27, 40, 65]],
  ])(
    'holds malformed/unknown core capability %s=%j without guessing',
    (key, value) => {
      const valueRoute = route();
      valueRoute.capabilityProfile[key] = value;
      invalid(() =>
        preparePrinterRuntimeConfigV2(draft([valueRoute]), context, null),
      );
    },
  );

  it('retains recognized unimplemented driver rendering for review, never promotes it', () => {
    const value = windowsRoute();
    value.capabilityProfile.language = 'windowsDriverRendered';
    const prepared = preparePrinterRuntimeConfigV2(
      draft([value]),
      context,
      null,
    );
    expect(prepared.phase).toBe('PREPARED');
    expect(prepared.routes[0].capabilityProfile.language).toBe(
      'windowsDriverRendered',
    );
  });

  it.each([
    undefined,
    null,
    [],
    'beep',
    {},
    { capability: 'futureVendor', enabled: true },
    { capability: 'epsonEscA97Pattern', enabled: 'true' },
    { capability: 'epsonEscA97Pattern', enabled: true, bytes: [27, 40, 65] },
  ])(
    'normalizes absent/malformed optional beep %j without losing valid primary output',
    (beep) => {
      const value = route();
      value.capabilityProfile.beep = beep;
      const accepted = preparePrinterRuntimeConfigV2(
        draft([value]),
        context,
        null,
      ).routes[0].capabilityProfile;
      expect(accepted).toEqual(profile());
      expect(JSON.stringify(accepted)).not.toContain('bytes');
    },
  );

  it('accepts a missing beep field and emits a complete silent canonical profile', () => {
    const value = route();
    delete value.capabilityProfile.beep;
    expect(
      preparePrinterRuntimeConfigV2(draft([value]), context, null).routes[0]
        .capabilityProfile,
    ).toEqual(profile());
  });

  it.each(['unknown', 'unsupported'])(
    'disables enabled optional %s sound',
    (capability) => {
      const value = route();
      value.capabilityProfile.beep = { capability, enabled: true };
      expect(
        preparePrinterRuntimeConfigV2(draft([value]), context, null).routes[0]
          .capabilityProfile.beep,
      ).toEqual({ capability, enabled: false });
    },
  );

  it('enables only explicit compatible Epson raster sound and disables it for driver rendering', () => {
    const value = route();
    value.capabilityProfile.beep = {
      capability: 'epsonEscA97Pattern',
      enabled: true,
    };
    expect(
      preparePrinterRuntimeConfigV2(draft([value]), context, null).routes[0]
        .capabilityProfile.beep.enabled,
    ).toBe(true);
    value.capabilityProfile.language = 'windowsDriverRendered';
    expect(
      preparePrinterRuntimeConfigV2(draft([value]), context, null).routes[0]
        .capabilityProfile.beep,
    ).toEqual({ capability: 'epsonEscA97Pattern', enabled: false });
  });

  it('rejects inherited/accessor inputs without evaluating getters or returning partial configuration', () => {
    const inherited = Object.create({ routes: [] });
    invalid(() => preparePrinterRuntimeConfigV2(inherited, context, null));
    let getterReads = 0;
    const accessor = { ...draft() };
    Object.defineProperty(accessor, 'routes', {
      get: () => {
        getterReads++;
        return [];
      },
      enumerable: true,
    });
    invalid(() => preparePrinterRuntimeConfigV2(accessor, context, null));
    expect(getterReads).toBe(0);
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft(new Array(1)), context, null),
    );
  });

  it('rejects hidden authority fields and route-array metadata without invoking entry getters', () => {
    const hiddenAuthority = draft();
    Object.defineProperty(hiddenAuthority, 'tenantId', { value: venueId });
    invalid(() =>
      preparePrinterRuntimeConfigV2(hiddenAuthority, context, null),
    );

    const arrayWithMetadata = [route()];
    Object.defineProperty(arrayWithMetadata, 'deviceId', { value: deviceId });
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft(arrayWithMetadata), context, null),
    );

    let evaluated = false;
    const arrayWithAccessor = [route()];
    Object.defineProperty(arrayWithAccessor, 0, {
      get() {
        evaluated = true;
        return route();
      },
    });
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft(arrayWithAccessor), context, null),
    );
    expect(evaluated).toBe(false);
  });
});

describe('printer runtime v2 uniqueness and bounds', () => {
  it('rejects duplicate identities, names and singleton roles even if disabled', () => {
    const first = route();
    const second = route({
      id: 'second',
      name: 'Second',
      role: 'additional',
      destination: { kind: 'tcp', host: '192.168.1.51', port: 9100 },
    });
    for (const overrides of [
      { id: first.id },
      { name: 'KITCHEN' },
      { role: 'kitchen', enabled: false },
    ]) {
      invalid(() =>
        preparePrinterRuntimeConfigV2(
          draft([first, { ...second, ...overrides }]),
          context,
          null,
        ),
      );
    }
    expect(() =>
      preparePrinterRuntimeConfigV2(
        draft([route({ role: 'additional' }), second]),
        context,
        null,
      ),
    ).not.toThrow();
  });

  it('rejects a shared TCP endpoint regardless of hostname case or disabled state', () => {
    const first = route({
      destination: { kind: 'tcp', host: 'PRINTER.local', port: 9100 },
    });
    const second = route({
      id: 'second',
      name: 'Second',
      role: 'additional',
      enabled: false,
      destination: { kind: 'tcp', host: 'printer.LOCAL', port: 9100 },
    });
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft([first, second]), context, null),
    );
  });

  it('rejects the same Windows queue even with another role/driver/port and case spelling', () => {
    const first = windowsRoute();
    const second = windowsRoute({
      id: 'second',
      name: 'Second',
      role: 'additional',
      enabled: false,
    });
    second.destination.queueName = 'KITCHEN QUEUE';
    second.destination.driverName = 'A different driver snapshot';
    second.destination.portName = 'USB099';
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft([first, second]), context, null),
    );
  });

  it('accepts empty configuration and 64 distinct routes; rejects 65', () => {
    expect(
      preparePrinterRuntimeConfigV2(draft([]), context, null).routes,
    ).toEqual([]);
    const routes = Array.from(
      { length: MAX_PRINTER_RUNTIME_ROUTES },
      (_, index) =>
        route({
          id: `r-${index}`,
          name: `Printer ${index}`,
          role: 'additional',
          destination: {
            kind: 'tcp',
            host: `printer-${index}.local`,
            port: 9100,
          },
        }),
    );
    expect(
      preparePrinterRuntimeConfigV2(draft(routes), context, null).routes,
    ).toHaveLength(64);
    routes.push(
      route({ id: 'overflow', name: 'Overflow', role: 'additional' }),
    );
    invalid(() => preparePrinterRuntimeConfigV2(draft(routes), context, null));
  });

  it('enforces the canonical UTF-8 byte limit at its exact boundary with valid bounded fields', () => {
    const routes = Array.from({ length: 64 }, (_, index) => {
      const value = windowsRoute({
        id: `r-${index}`,
        name: `Printer ${index}`,
        role: 'additional',
      });
      value.destination.queueName = `Queue ${index}`;
      value.destination.driverName = '界'.repeat(1024);
      value.destination.portName = 'P';
      return value;
    });
    const value = snapshot(routes);
    let remaining =
      MAX_PRINTER_RUNTIME_CONFIG_BYTES -
      Buffer.byteLength(JSON.stringify(value), 'utf8');
    expect(remaining).toBeGreaterThan(0);
    for (const valueRoute of routes) {
      const add = Math.min(remaining, 1023);
      valueRoute.destination.portName += 'P'.repeat(add);
      remaining -= add;
    }
    expect(remaining).toBe(0);
    const accepted = parsePrinterRuntimeConfigV2(value, context);
    expect(Buffer.byteLength(JSON.stringify(accepted), 'utf8')).toBe(
      MAX_PRINTER_RUNTIME_CONFIG_BYTES,
    );
    expect(() =>
      preparePrinterRuntimeConfigV2(draft(routes), context, null),
    ).not.toThrow();
    routes.find(
      (valueRoute) => valueRoute.destination.portName.length < 1024,
    )!.destination.portName += 'P';
    invalid(() => parsePrinterRuntimeConfigV2(value, context));
    invalid(() => preparePrinterRuntimeConfigV2(draft(routes), context, null));
  });
});

describe('printer runtime v2 revision preparation and legacy write containment', () => {
  it('increments the config revision while retaining unchanged route revisions independent of input key order', () => {
    const current = snapshot([route({ revision: 8 })], {
      revision: 23,
      phase: 'ACTIVE',
    });
    const reordered = Object.fromEntries(
      Object.entries(route({ revision: 8 })).reverse(),
    );
    const prepared = preparePrinterRuntimeConfigV2(
      draft([reordered], { expectedRevision: 23 }),
      context,
      current,
    );
    expect(prepared).toMatchObject({ revision: 24, phase: 'PREPARED' });
    expect(prepared.routes[0].revision).toBe(8);
    expect(current.phase).toBe('ACTIVE');
  });

  it('rejects stale config revision and new route revision jumps', () => {
    errorCode(
      () => preparePrinterRuntimeConfigV2(draft(), context, snapshot()),
      'PRINTER_REVISION_CONFLICT',
    );
    errorCode(
      () =>
        preparePrinterRuntimeConfigV2(
          draft([route({ revision: 2 })]),
          context,
          null,
        ),
      'PRINTER_REVISION_CONFLICT',
    );
    invalid(() =>
      preparePrinterRuntimeConfigV2(
        draft(undefined, { expectedRevision: -1 }),
        context,
        null,
      ),
    );
  });

  it('requires exactly the next revision for changes and forbids bumped unchanged records', () => {
    const current = snapshot();
    for (const mutate of [
      (r: WireObject) => {
        r.name = 'New name';
      },
      (r: WireObject) => {
        r.role = 'bar';
      },
      (r: WireObject) => {
        r.enabled = false;
      },
      (r: WireObject) => {
        r.destination.host = '192.168.1.99';
      },
      (r: WireObject) => {
        r.capabilityProfile.rasterWidthDots = 384;
      },
    ]) {
      const changed = route();
      mutate(changed);
      errorCode(
        () =>
          preparePrinterRuntimeConfigV2(
            draft([changed], { expectedRevision: 1 }),
            context,
            current,
          ),
        'PRINTER_REVISION_CONFLICT',
      );
      changed.revision = 2;
      expect(
        preparePrinterRuntimeConfigV2(
          draft([changed], { expectedRevision: 1 }),
          context,
          current,
        ).routes[0].revision,
      ).toBe(2);
      changed.revision = 3;
      errorCode(
        () =>
          preparePrinterRuntimeConfigV2(
            draft([changed], { expectedRevision: 1 }),
            context,
            current,
          ),
        'PRINTER_REVISION_CONFLICT',
      );
    }
    errorCode(
      () =>
        preparePrinterRuntimeConfigV2(
          draft([route({ revision: 2 })], { expectedRevision: 1 }),
          context,
          current,
        ),
      'PRINTER_REVISION_CONFLICT',
    );
  });

  it('requires a route revision when the frozen Windows driver or port changes', () => {
    const current = snapshot([windowsRoute()]);
    for (const field of ['driverName', 'portName']) {
      const changed = windowsRoute();
      changed.destination[field] += ' changed';
      errorCode(
        () =>
          preparePrinterRuntimeConfigV2(
            draft([changed], { expectedRevision: 1 }),
            context,
            current,
          ),
        'PRINTER_REVISION_CONFLICT',
      );
      changed.revision = 2;
      expect(() =>
        preparePrinterRuntimeConfigV2(
          draft([changed], { expectedRevision: 1 }),
          context,
          current,
        ),
      ).not.toThrow();
    }
  });

  it('retains IDs using disabled records and admits new IDs only at revision one', () => {
    const current = snapshot();
    errorCode(
      () =>
        preparePrinterRuntimeConfigV2(
          draft([], { expectedRevision: 1 }),
          context,
          current,
        ),
      'PRINTER_REVISION_CONFLICT',
    );
    const retained = route({ enabled: false, revision: 2 });
    const added = windowsRoute({ role: 'additional' });
    const prepared = preparePrinterRuntimeConfigV2(
      draft([retained, added], { expectedRevision: 1 }),
      context,
      current,
    );
    expect(prepared.routes.map((r) => [r.id, r.revision, r.enabled])).toEqual([
      ['kitchen-route', 2, false],
      ['usb-route', 1, true],
    ]);
  });

  it('rejects counter exhaustion and unrecognized/missing current state', () => {
    errorCode(
      () =>
        preparePrinterRuntimeConfigV2(
          draft(undefined, { expectedRevision: MAX_PRINTER_RUNTIME_REVISION }),
          context,
          snapshot(undefined, { revision: MAX_PRINTER_RUNTIME_REVISION }),
        ),
      'PRINTER_REVISION_EXHAUSTED',
    );
    const current = snapshot([
      route({ revision: MAX_PRINTER_RUNTIME_REVISION }),
    ]);
    const changed = route({
      revision: MAX_PRINTER_RUNTIME_REVISION,
      enabled: false,
    });
    errorCode(
      () =>
        preparePrinterRuntimeConfigV2(
          draft([changed], { expectedRevision: 1 }),
          context,
          current,
        ),
      'PRINTER_REVISION_EXHAUSTED',
    );
    invalid(() => preparePrinterRuntimeConfigV2(draft(), context, undefined));
    invalid(() =>
      preparePrinterRuntimeConfigV2(draft(), context, { version: 3 }),
    );
    errorCode(
      () =>
        preparePrinterRuntimeConfigV2(
          draft(undefined, { expectedRevision: 1 }),
          context,
          snapshot(undefined, { deviceId: otherDeviceId }),
        ),
      'PRINTER_DEVICE_MISMATCH',
    );
  });

  it('provides a separate v1 overwrite guard, including malformed/future versioned values', () => {
    expect(() => assertLegacyPrinterWriteAllowed(null)).not.toThrow();
    expect(() =>
      assertLegacyPrinterWriteAllowed({ version: 1, printers: {} }),
    ).not.toThrow();
    for (const current of [
      snapshot(),
      snapshot(undefined, { phase: 'ACTIVE' }),
      { version: 2 },
      { version: 3 },
    ]) {
      errorCode(
        () => assertLegacyPrinterWriteAllowed(current),
        'LEGACY_PRINTER_WRITE_REJECTED',
      );
    }
  });
});
