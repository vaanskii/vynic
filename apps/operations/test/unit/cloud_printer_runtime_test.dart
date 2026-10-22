import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/cloud_printer_runtime.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';

const _device = '10000000-0000-4000-8000-000000000001';
const _venue = '20000000-0000-4000-8000-000000000001';
const _foreignDevice = '10000000-0000-4000-8000-000000000002';
const _foreignVenue = '20000000-0000-4000-8000-000000000002';

Map<String, dynamic> _profile({
  PrinterCommandLanguage language = PrinterCommandLanguage.escposRaster,
}) => PrinterCapabilityProfile(
  paperWidthMm: 58,
  rasterWidthDots: 384,
  language: language,
  cutter: PrinterCutter.partial,
).toMap();

Map<String, dynamic> _route({
  String id = 'kitchen-route',
  String name = 'სამზარეულო',
  PrinterRole role = PrinterRole.kitchen,
  bool enabled = true,
  int revision = 3,
  Map<String, dynamic>? destination,
  Map<String, dynamic>? profile,
}) => {
  'protocol': 1,
  'id': id,
  'name': name,
  'role': role.name,
  'revision': revision,
  'destination':
      destination ??
      PrinterDestination.tcp(host: 'kitchen.local', port: 9100).toMap(),
  'capabilityProfile': profile ?? _profile(),
  'enabled': enabled,
};

Map<String, dynamic> _runtime({
  String phase = 'ACTIVE',
  List<Map<String, dynamic>>? routes,
}) => {
  'version': 2,
  'deviceId': _device,
  'venueId': _venue,
  'revision': 7,
  'phase': phase,
  'minimumReaderVersion': 2,
  'printers': {
    'kitchen': {'enabled': false, 'host': '', 'port': 9100},
    'receipt': {'enabled': false, 'host': '', 'port': 9100},
  },
  'routes': routes ?? [_route()],
};

CloudPrinterRuntime _decode(dynamic raw) => CloudPrinterRuntime.decode(
  raw,
  boundDeviceId: _device,
  boundVenueId: _venue,
);

Matcher _held(CloudPrinterDispatchHoldKind kind) => throwsA(
  isA<CloudPrinterDispatchHold>().having((hold) => hold.kind, 'kind', kind),
);

void main() {
  test(
    'valid active TCP and owned Windows routes resolve complete frozen profiles',
    () {
      final spooler = PrinterDestination.windowsSpooler(
        ownerDeviceId: _device,
        queueName: 'Synthetic RAW',
        driverName: 'Synthetic raster driver',
        portName: 'USB001',
      );
      final body = _runtime(
        routes: [
          _route(),
          _route(
            id: 'receipt-route',
            name: 'Receipt',
            role: PrinterRole.receipt,
            destination: spooler.toMap(),
          ),
        ],
      );
      final runtime = _decode(body);
      expect(runtime.deviceId, _device);
      expect(runtime.venueId, _venue);
      expect(runtime.revision, 7);
      expect(runtime.phase, CloudPrinterRuntimePhase.active);
      final kitchen = runtime.resolveForDispatch(role: PrinterRole.kitchen);
      expect(kitchen.id, 'kitchen-route');
      expect(kitchen.revision, 3);
      expect(kitchen.destination.host, 'kitchen.local');
      expect(kitchen.capabilityProfile.paperWidthMm, 58);
      expect(kitchen.capabilityProfile.rasterWidthDots, 384);
      expect(kitchen.capabilityProfile.cutter, PrinterCutter.partial);
      final receipt = runtime.resolveForDispatch(role: PrinterRole.receipt);
      expect(receipt.destination.toMap(), spooler.toMap());
      expect(runtime.toMap(), body);
      for (final role in PrinterRole.values) {
        expect(runtime.ownsRole(role), true);
      }
    },
  );

  test(
    'PREPARED holds enabled and absent roles without any auto-promotion',
    () {
      final runtime = _decode(_runtime(phase: 'PREPARED'));
      for (final role in PrinterRole.values) {
        expect(
          () => runtime.resolveForDispatch(role: role),
          _held(CloudPrinterDispatchHoldKind.prepared),
        );
      }
      expect(runtime.phase, CloudPrinterRuntimePhase.prepared);
      expect(runtime.toMap()['phase'], 'PREPARED');
    },
  );

  test(
    'disabled and missing active roles explicitly refuse local fallback',
    () {
      final runtime = _decode(_runtime(routes: [_route(enabled: false)]));
      expect(runtime.routes.single.enabled, false);
      expect(
        () => runtime.resolveForDispatch(role: PrinterRole.kitchen),
        _held(CloudPrinterDispatchHoldKind.disabled),
      );
      expect(
        () => runtime.resolveForDispatch(role: PrinterRole.receipt),
        _held(CloudPrinterDispatchHoldKind.notConfigured),
      );
      final empty = _decode(_runtime(routes: []));
      expect(empty.ownsRole(PrinterRole.bar), true);
      expect(
        () => empty.resolveForDispatch(role: PrinterRole.bar),
        _held(CloudPrinterDispatchHoldKind.notConfigured),
      );
    },
  );

  test(
    'additional stations need one explicit id and never substitute another role',
    () {
      final runtime = _decode(
        _runtime(
          routes: [
            _route(
              id: 'station-a',
              name: 'Station A',
              role: PrinterRole.additional,
            ),
            _route(
              id: 'station-b',
              name: 'Station B',
              role: PrinterRole.additional,
              destination: PrinterDestination.tcp(
                host: 'station-b.local',
                port: 9200,
              ).toMap(),
            ),
          ],
        ),
      );
      expect(
        () => runtime.resolveForDispatch(role: PrinterRole.additional),
        _held(CloudPrinterDispatchHoldKind.ambiguousSelection),
      );
      expect(
        runtime
            .resolveForDispatch(
              role: PrinterRole.additional,
              routeId: 'station-b',
            )
            .destination
            .host,
        'station-b.local',
      );
      expect(
        () => runtime.resolveForDispatch(
          role: PrinterRole.kitchen,
          routeId: 'station-b',
        ),
        _held(CloudPrinterDispatchHoldKind.notConfigured),
      );
      expect(
        () => runtime.resolveForDispatch(
          role: PrinterRole.additional,
          routeId: 'not-present',
        ),
        _held(CloudPrinterDispatchHoldKind.notConfigured),
      );
      expect(
        () => runtime.resolveForDispatch(
          role: PrinterRole.additional,
          routeId: '',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'recognized driver-rendered station holds without blocking unrelated raster role',
    () {
      final runtime = _decode(
        _runtime(
          routes: [
            _route(),
            _route(
              id: 'held-station',
              name: 'Driver station',
              role: PrinterRole.additional,
              destination: PrinterDestination.tcp(
                host: 'held.local',
                port: 9100,
              ).toMap(),
              profile: _profile(
                language: PrinterCommandLanguage.windowsDriverRendered,
              ),
            ),
          ],
        ),
      );
      expect(
        runtime.resolveForDispatch(role: PrinterRole.kitchen).id,
        'kitchen-route',
      );
      expect(
        () => runtime.resolveForDispatch(role: PrinterRole.additional),
        _held(CloudPrinterDispatchHoldKind.rendererUnavailable),
      );
    },
  );

  test(
    'decoded objects and emitted maps stay detached from source mutation',
    () {
      final body = _runtime();
      final runtime = _decode(body);
      final frozen = runtime.toMap();
      final source = (body['routes'] as List).single as Map;
      (source['destination'] as Map)['host'] = 'changed.local';
      (source['capabilityProfile'] as Map)['paperWidthMm'] = 80;
      (source['capabilityProfile']['beep'] as Map)['enabled'] = true;
      source['revision'] = 99;
      source['enabled'] = false;
      body['phase'] = 'PREPARED';
      final exported = runtime.toMap();
      (exported['printers']['kitchen'] as Map)['enabled'] = true;
      ((exported['routes'] as List).single['destination'] as Map)['port'] =
          9200;
      expect(runtime.toMap(), frozen);
      expect(runtime.resolveForDispatch(role: PrinterRole.kitchen).revision, 3);
      expect(() => runtime.routes.clear(), throwsUnsupportedError);
    },
  );

  for (final field in ['deviceId', 'venueId']) {
    test('foreign $field is rejected against the enrolled binding', () {
      final body = _runtime()
        ..[field] = field == 'deviceId' ? _foreignDevice : _foreignVenue;
      expect(() => _decode(body), throwsFormatException);
    });
  }

  test('malformed or missing trusted bindings cannot grant v2 authority', () {
    for (final device in [
      '',
      'device-a',
      '10000000-0000-7000-8000-000000000001',
    ]) {
      final body = _runtime()..['deviceId'] = device;
      expect(
        () => CloudPrinterRuntime.decode(
          body,
          boundDeviceId: device,
          boundVenueId: _venue,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => CloudPrinterRuntime.decode(
        _runtime(),
        boundDeviceId: _device,
        boundVenueId: '',
      ),
      throwsFormatException,
    );
  });

  test(
    'foreign Windows owner is rejected even under a valid outer binding',
    () {
      final destination = PrinterDestination.windowsSpooler(
        ownerDeviceId: _foreignDevice,
        queueName: 'Other RAW',
        driverName: 'Other driver',
        portName: 'USB001',
      );
      expect(
        () => _decode(
          _runtime(routes: [_route(destination: destination.toMap())]),
        ),
        throwsFormatException,
      );
    },
  );

  for (final mutation in <String, dynamic>{
    'version': 1,
    'minimumReaderVersion': 1,
    'revision': 0,
    'phase': 'prepared',
    'routes': 'not-a-list',
  }.entries) {
    test('invalid required ${mutation.key} is rejected', () {
      expect(
        () => _decode(_runtime()..[mutation.key] = mutation.value),
        throwsFormatException,
      );
    });
  }

  test(
    'version, reader floor and revisions require bounded actual integers',
    () {
      for (final body in [
        _runtime()..['version'] = 2.0,
        _runtime()..['minimumReaderVersion'] = 2.0,
        _runtime()..['minimumReaderVersion'] = 3,
        _runtime()..['revision'] = 7.0,
        _runtime()..['revision'] = 0x80000000,
        _runtime(routes: [_route()..['protocol'] = 1.0]),
        _runtime(routes: [_route()..['revision'] = 0x80000000]),
      ]) {
        expect(() => _decode(body), throwsFormatException);
      }
    },
  );

  test('root, route, destination and core profile keys are exact', () {
    for (final body in [
      _runtime()..['extra'] = true,
      _runtime()..remove('minimumReaderVersion'),
      _runtime(routes: [_route()..['extra'] = true]),
      _runtime(routes: [_route()..remove('capabilityProfile')]),
      _runtime(
        routes: [
          _route(
            destination: {
              ...PrinterDestination.tcp(
                host: 'printer.local',
                port: 9100,
              ).toMap(),
              'serial': 'COM1',
            },
          ),
        ],
      ),
      _runtime(
        routes: [
          _route(
            profile: {
              ..._profile(),
              'rawCommands': [7],
            },
          ),
        ],
      ),
      _runtime(routes: [_route(profile: _profile()..remove('paperWidthMm'))]),
      _runtime(
        routes: [
          _route(profile: {..._profile(), 'language': 'vendorGuessed'}),
        ],
      ),
      _runtime(
        routes: [
          _route(profile: {..._profile(), 'rasterWidthDots': 385}),
        ],
      ),
      _runtime(routes: [_route()..['name'] = 'Printer\n']),
    ]) {
      expect(() => _decode(body), throwsFormatException);
    }
  });

  test('both exact disabled legacy stubs prevent old settings fallback', () {
    final valid = _runtime();
    for (final role in ['kitchen', 'receipt']) {
      for (final mutation in [
        {'enabled': true, 'host': '', 'port': 9100},
        {'enabled': false, 'host': 'old.local', 'port': 9100},
        {'enabled': false, 'host': '', 'port': 9200},
        {'enabled': false, 'host': '', 'port': 9100.0},
        {'enabled': false, 'host': '', 'port': 9100, 'extra': true},
      ]) {
        final body = jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;
        (body['printers'] as Map)[role] = mutation;
        expect(() => _decode(body), throwsFormatException);
      }
      final missing = jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;
      (missing['printers'] as Map).remove(role);
      expect(() => _decode(missing), throwsFormatException);
    }
    final extra = _runtime();
    (extra['printers'] as Map)['bar'] = {
      'enabled': false,
      'host': '',
      'port': 9100,
    };
    expect(() => _decode(extra), throwsFormatException);
  });

  test(
    'duplicate route ids, names, endpoints and singleton roles reject whole snapshots',
    () {
      for (final other in [
        _route(
          id: 'kitchen-route',
          name: 'Other',
          role: PrinterRole.additional,
          destination: PrinterDestination.tcp(
            host: 'other.local',
            port: 9100,
          ).toMap(),
        ),
        _route(
          id: 'other',
          name: 'სამზარეულო',
          role: PrinterRole.additional,
          destination: PrinterDestination.tcp(
            host: 'other.local',
            port: 9100,
          ).toMap(),
        ),
        _route(
          id: 'other',
          name: 'Other',
          role: PrinterRole.additional,
          enabled: false,
          destination: PrinterDestination.tcp(
            host: 'KITCHEN.LOCAL',
            port: 9100,
          ).toMap(),
        ),
        _route(
          id: 'other',
          name: 'Other',
          role: PrinterRole.kitchen,
          destination: PrinterDestination.tcp(
            host: 'other.local',
            port: 9100,
          ).toMap(),
        ),
      ]) {
        expect(
          () => _decode(_runtime(routes: [_route(), other])),
          throwsFormatException,
        );
      }
      final first = PrinterDestination.windowsSpooler(
        ownerDeviceId: _device,
        queueName: 'POS RAW',
        driverName: 'Driver A',
        portName: 'USB001',
      );
      final sameQueue = PrinterDestination.windowsSpooler(
        ownerDeviceId: _device,
        queueName: 'pos raw',
        driverName: 'Driver B',
        portName: 'USB002',
      );
      expect(
        () => _decode(
          _runtime(
            routes: [
              _route(destination: first.toMap()),
              _route(
                id: 'other',
                name: 'Other',
                role: PrinterRole.bar,
                destination: sameQueue.toMap(),
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test('bounded route count accepts64 and rejects65 before any dispatch', () {
    List<Map<String, dynamic>> stations(int count) => [
      for (var n = 1; n <= count; n++)
        _route(
          id: 'station-$n',
          name: 'Station $n',
          role: PrinterRole.additional,
          destination: PrinterDestination.tcp(
            host: 'station-$n.local',
            port: 9100,
          ).toMap(),
        ),
    ];
    expect(_decode(_runtime(routes: stations(64))).routes, hasLength(64));
    expect(
      () => _decode(_runtime(routes: stations(65))),
      throwsFormatException,
    );
  });

  test('canonical UTF-8 size limit covers multibyte Windows descriptors', () {
    List<Map<String, dynamic>> stations(int descriptorLength) => [
      for (var n = 1; n <= 64; n++)
        _route(
          id: 'station-$n',
          name: 'Station $n',
          role: PrinterRole.additional,
          destination: PrinterDestination.windowsSpooler(
            ownerDeviceId: _device,
            queueName: 'Queue $n',
            driverName: 'ა' * descriptorLength,
            portName: 'ბ' * descriptorLength,
          ).toMap(),
        ),
    ];
    final under = _runtime(routes: stations(128));
    expect(
      utf8.encode(jsonEncode(under)).length,
      lessThanOrEqualTo(CloudPrinterRuntime.maxEncodedBytes),
    );
    expect(_decode(under).routes, hasLength(64));
    final over = _runtime(routes: stations(1024));
    expect(
      utf8.encode(jsonEncode(over)).length,
      greaterThan(CloudPrinterRuntime.maxEncodedBytes),
    );
    expect(() => _decode(over), throwsFormatException);
  });

  for (final beep in <dynamic>[
    null,
    false,
    'vendor-siren',
    {'capability': 'vendorGuessed', 'enabled': true},
    {'capability': 'epsonEscA97Pattern', 'enabled': 'true'},
    {
      'capability': 'epsonEscA97Pattern',
      'enabled': true,
      'bytes': [27, 7],
    },
    {
      'bytes': [7],
    },
  ]) {
    test(
      'malformed optional beep $beep normalizes silent without blocking primary print',
      () {
        final profile = _profile()..['beep'] = beep;
        final runtime = _decode(_runtime(routes: [_route(profile: profile)]));
        final route = runtime.resolveForDispatch(role: PrinterRole.kitchen);
        expect(
          route.capabilityProfile.beep.capability,
          PrinterBeepCapability.unknown,
        );
        expect(route.capabilityProfile.beep.enabled, false);
        expect(route.capabilityProfile.toMap()['beep'], {
          'capability': 'unknown',
          'enabled': false,
        });
      },
    );
  }

  test('missing and recognized unsupported optional beep stay silent', () {
    for (final profile in [
      _profile()..remove('beep'),
      _profile()..['beep'] = {'capability': 'unknown', 'enabled': true},
      _profile()..['beep'] = {'capability': 'unsupported', 'enabled': true},
    ]) {
      final runtime = _decode(_runtime(routes: [_route(profile: profile)]));
      final route = runtime.resolveForDispatch(role: PrinterRole.kitchen);
      expect(route.capabilityProfile.beep.enabled, false);
      expect(
        (runtime.toMap()['routes'] as List)
            .single['capabilityProfile']['beep']['enabled'],
        false,
      );
    }
  });

  test(
    'Epson sound requires the exact capability and implemented command language',
    () {
      final beep = {'capability': 'epsonEscA97Pattern', 'enabled': true};
      final raster = _decode(
        _runtime(routes: [_route(profile: _profile()..['beep'] = beep)]),
      );
      expect(
        raster
            .resolveForDispatch(role: PrinterRole.kitchen)
            .capabilityProfile
            .beep
            .enabled,
        true,
      );
      final driver = _decode(
        _runtime(
          routes: [
            _route(
              profile: _profile(
                language: PrinterCommandLanguage.windowsDriverRendered,
              )..['beep'] = beep,
            ),
          ],
        ),
      );
      expect(driver.routes.single.route.capabilityProfile.beep.enabled, false);
      expect(
        () => driver.resolveForDispatch(role: PrinterRole.kitchen),
        _held(CloudPrinterDispatchHoldKind.rendererUnavailable),
      );
    },
  );
}
