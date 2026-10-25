import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/windows_spooler_transport.dart';
import 'package:vynic/core/services/security/developer_access.dart';

import '../support/pos02_developer_fixture.dart';
import '../support/pos02_fixture.dart';

const _device = '00000000-0000-4000-8000-000000000001';
const _otherDevice = '00000000-0000-4000-8000-000000000002';
const _channel = MethodChannel('vynic/synthetic_catalog_spooler');

class _RouteSettingsBox extends UpdateTrackedBox<dynamic> {
  _RouteSettingsBox(super.inner);
  final trace = <String>[];
  Completer<void>? flushEntered;
  Completer<void>? releaseFlush;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (key == LocalPrinterCatalog.routesSettingKey) {
      expect(LocalDataAdmission.insideMutation, true);
      trace.add('routes.put');
    }
    await super.put(key, value);
  }

  @override
  Future<void> flush() async {
    expect(LocalDataAdmission.insideMutation, true);
    trace.add('settings.flush');
    flushEntered?.complete();
    flushEntered = null;
    await releaseFlush?.future;
    await super.flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos02Fixture fixture;
  late _RouteSettingsBox settings;
  late List<Map<String, String>> inventory;
  late List<String> nativeCalls;

  Future<void> enroll([String id = _device]) async {
    expect(
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: 'vynic-device-v1.$id.${'x' * 40}',
        venueId: 'synthetic-venue',
        venueName: 'Synthetic route fixture',
      ),
      true,
    );
  }

  PrinterDestination tcp(String ip, [int port = 9100]) =>
      PrinterDestination.tcp(host: ip, port: port);
  PrinterDestination windows({
    String owner = _device,
    String name = 'Synthetic RAW',
    String driver = 'Synthetic ESC/POS',
    String port = 'USB001',
  }) => PrinterDestination.windowsSpooler(
    ownerDeviceId: owner,
    queueName: name,
    driverName: driver,
    portName: port,
  );
  Future<PrinterRoute> create({
    String name = 'Bar',
    PrinterRole role = PrinterRole.bar,
    PrinterDestination? destination,
    PrinterCapabilityProfile? capabilityProfile,
  }) => LocalPrinterCatalog.saveRoute(
    name: name,
    role: role,
    destination: destination ?? tcp('10.20.0.1'),
    expectedRevision: 0,
    capabilityProfile: capabilityProfile,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'vynic_printer_route_catalog_',
    );
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed(venueId: 'synthetic-venue');
    await DatabaseCore.settingsBox!.delete('deviceRuntimeConfig');
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = root.path;
    await unlockSyntheticPrinterDeveloper();
    settings = _RouteSettingsBox(DatabaseCore.settingsBox!);
    DatabaseCore.settingsBox = settings;
    nativeCalls = [];
    inventory = [
      {
        'name': 'Synthetic RAW',
        'driver': 'Synthetic ESC/POS',
        'port': 'USB001',
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          nativeCalls.add(call.method);
          expect(call.method, 'listQueues');
          return inventory;
        });
    LocalPrinterCatalog.windowsTransportOverride = WindowsSpoolerTransport(
      channel: _channel,
      isWindows: () => true,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    LocalPrinterCatalog.windowsTransportOverride = null;
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    DeveloperAccess.resetForTest();
    DeveloperAccess.publicKeyOverride = null;
    await fixture.close();
    await root.delete(recursive: true);
  });

  test(
    'explicit routes survive reopen and dispatch reads without developer scope',
    () async {
      await LocalPrinterCatalog.add('Unassigned', '10.20.0.7');
      final route = await create(name: ' ბარი ');
      expect(route.name, 'ბარი');
      expect(route.revision, 1);
      expect(LocalPrinterCatalog.read(), hasLength(1));
      expect(LocalPrinterCatalog.read().single['routing'], 'unassigned');
      expect(settings.trace.sublist(settings.trace.length - 2), [
        'routes.put',
        'settings.flush',
      ]);
      final boxName = settings.name;
      await settings.close();
      DatabaseCore.settingsBox = await Hive.openBox(boxName);
      DeveloperAccess.lock();
      expect(
        LocalPrinterCatalog.readRoutesForDispatch().single.toMap(),
        route.toMap(),
      );
      expect(LocalPrinterCatalog.readRoutesForAdministration, throwsStateError);
      await expectLater(create(), throwsStateError);
      expect(fixture.connections, 0);
      expect(nativeCalls, isEmpty);
    },
  );

  test(
    'an unrelated developer scope cannot administer or enumerate routes',
    () async {
      await unlockSyntheticPrinterDeveloper(
        scopes: [DeveloperScope.diagnostics],
      );
      expect(LocalPrinterCatalog.readRoutesForAdministration, throwsStateError);
      await expectLater(create(), throwsStateError);
      await expectLater(
        LocalPrinterCatalog.listWindowsQueuesForAdministration(),
        throwsStateError,
      );
      expect(LocalPrinterCatalog.readRoutesForDispatch(), isEmpty);
      expect(nativeCalls, isEmpty);
    },
  );

  test(
    'edit retains id, increments revision and freezes previously accepted destination',
    () async {
      final previous = await create();
      final edited = await LocalPrinterCatalog.saveRoute(
        id: previous.id,
        name: previous.name,
        role: previous.role,
        destination: tcp('10.20.0.2', 9200),
        expectedRevision: previous.revision,
      );
      expect(edited.id, previous.id);
      expect(edited.revision, 2);
      expect(previous.destination.host, '10.20.0.1');
      await expectLater(
        LocalPrinterCatalog.saveRoute(
          id: previous.id,
          name: 'Stale',
          role: previous.role,
          destination: tcp('10.20.0.3'),
          expectedRevision: previous.revision,
        ),
        throwsA(isA<PrinterRouteRevisionConflict>()),
      );
      expect(
        LocalPrinterCatalog.readRoutesForDispatch().single.toMap(),
        edited.toMap(),
      );
    },
  );

  test(
    'concurrent edits admit one current revision and reject the stale writer',
    () async {
      final route = await create();
      Future<Object> edit(String ip) => LocalPrinterCatalog.saveRoute(
        id: route.id,
        name: route.name,
        role: route.role,
        destination: tcp(ip),
        expectedRevision: route.revision,
      ).then<Object>((value) => value, onError: (Object error) => error);
      final results = await Future.wait([edit('10.20.0.2'), edit('10.20.0.3')]);
      expect(results.whereType<PrinterRoute>(), hasLength(1));
      expect(results.whereType<PrinterRouteRevisionConflict>(), hasLength(1));
      expect(LocalPrinterCatalog.readRoutesForDispatch().single.revision, 2);
    },
  );

  test(
    'save completes only after settings flush and keeps admission through it',
    () async {
      settings.flushEntered = Completer<void>();
      settings.releaseFlush = Completer<void>();
      var completed = false;
      final first = create().then((value) {
        completed = true;
        return value;
      });
      await settings.flushEntered!.future;
      expect(completed, false);
      final second = create(
        name: 'Other',
        role: PrinterRole.additional,
        destination: tcp('10.20.0.2'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(settings.trace, ['routes.put', 'settings.flush']);
      settings.releaseFlush!.complete();
      await Future.wait([first, second]);
      expect(completed, true);
      expect(settings.trace, [
        'routes.put',
        'settings.flush',
        'routes.put',
        'settings.flush',
      ]);
    },
  );

  for (final malformed in <dynamic>[
    null,
    'legacy',
    42,
    {'unexpected': 'map'},
    [
      {'protocol': 99},
    ],
  ]) {
    test(
      'malformed route value $malformed is visible and never replaced',
      () async {
        await settings.inner.put(
          LocalPrinterCatalog.routesSettingKey,
          malformed,
        );
        expect(
          LocalPrinterCatalog.readRoutesForAdministration,
          throwsA(anything),
        );
        await expectLater(create(), throwsA(anything));
        expect(settings.get(LocalPrinterCatalog.routesSettingKey), malformed);
      },
    );
  }

  test(
    'malformed legacy records block new route writes without adopting them',
    () async {
      await settings.put('printersList', ['legacy-record']);
      await expectLater(create(), throwsA(anything));
      expect(settings.get('printersList'), ['legacy-record']);
      expect(settings.containsKey(LocalPrinterCatalog.routesSettingKey), false);
    },
  );

  test(
    'duplicate endpoints, names and singleton roles refuse writes',
    () async {
      final route = await create();
      await expectLater(
        create(
          name: 'bar',
          role: PrinterRole.additional,
          destination: tcp('10.20.0.2'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        create(name: 'Other', role: PrinterRole.additional),
        throwsArgumentError,
      );
      await expectLater(
        create(name: 'Other', destination: tcp('10.20.0.2')),
        throwsArgumentError,
      );
      await LocalPrinterCatalog.add('Legacy', '10.20.0.7');
      await expectLater(
        create(
          name: 'Other',
          role: PrinterRole.additional,
          destination: tcp('10.20.0.7'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        create(
          name: 'legacy',
          role: PrinterRole.additional,
          destination: tcp('10.20.0.8'),
        ),
        throwsArgumentError,
      );
      expect(LocalPrinterCatalog.readRoutesForDispatch().single.id, route.id);
      final duplicate = {...route.toMap(), 'id': 'duplicate', 'name': 'Other'};
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [
        route.toMap(),
        duplicate,
      ]);
      expect(LocalPrinterCatalog.readRoutesForDispatch, throwsStateError);
      await expectLater(create(), throwsStateError);
      expect(settings.get(LocalPrinterCatalog.routesSettingKey), [
        route.toMap(),
        duplicate,
      ]);
    },
  );

  test(
    'Cloud primary roles remain authoritative including disabled configuration',
    () async {
      final config = {
        'version': 1,
        'printers': {
          'kitchen': {'enabled': true, 'host': '10.20.0.8', 'port': 9200},
          'receipt': {'enabled': false, 'host': '', 'port': 9100},
        },
      };
      await settings.put('deviceRuntimeConfig', config);
      for (final role in [PrinterRole.kitchen, PrinterRole.receipt]) {
        await expectLater(create(role: role), throwsStateError);
      }
      await create();
      expect(DatabaseService.getKitchenPrinterIp(), '10.20.0.8');
      expect(DatabaseService.getKitchenPrinterPort(), 9200);
      expect(DatabaseService.getReceiptPrinterIp(), '');
      expect(settings.get('deviceRuntimeConfig'), config);
    },
  );

  test(
    'a later Cloud primary claim holds existing local configuration for review',
    () async {
      final route = await create(role: PrinterRole.kitchen);
      await settings.put('deviceRuntimeConfig', {'version': 1, 'printers': {}});
      expect(
        LocalPrinterCatalog.readRoutesForAdministration().single.id,
        route.id,
      );
      expect(
        LocalPrinterCatalog.routeHoldReason(route),
        contains('Cloud owns'),
      );
      expect(LocalPrinterCatalog.readRoutesForDispatch, throwsStateError);
      expect(settings.get(LocalPrinterCatalog.routesSettingKey), [
        route.toMap(),
      ]);
    },
  );

  test(
    'Windows route accepts only an enumerated exact queue tied to this enrolled Device',
    () async {
      await enroll();
      final route = await create(destination: windows());
      expect(route.destination.ownerDeviceId, _device);
      expect(route.destination.queueName, 'Synthetic RAW');
      expect(route.destination.driverName, 'Synthetic ESC/POS');
      expect(route.destination.portName, 'USB001');
      expect(nativeCalls, ['listQueues']);
      DeveloperAccess.lock();
      expect(
        LocalPrinterCatalog.readRoutesForDispatch().single.toMap(),
        route.toMap(),
      );
      expect(fixture.connections, 0);
    },
  );

  test(
    'unenrolled and foreign-device Windows choices fail before enumeration',
    () async {
      await expectLater(create(destination: windows()), throwsStateError);
      await enroll();
      await expectLater(
        create(destination: windows(owner: _otherDevice)),
        throwsStateError,
      );
      expect(nativeCalls, isEmpty);
      expect(settings.containsKey(LocalPrinterCatalog.routesSettingKey), false);
    },
  );

  for (final destination in [
    windows(name: 'Guessed'),
    windows(driver: 'Changed'),
    windows(port: 'COM1'),
  ]) {
    test(
      'untrusted Windows descriptor ${destination.display} never persists',
      () async {
        await enroll();
        await expectLater(create(destination: destination), throwsStateError);
        expect(
          settings.containsKey(LocalPrinterCatalog.routesSettingKey),
          false,
        );
        expect(nativeCalls, ['listQueues']);
      },
    );
  }

  test(
    'blank inventory descriptors and inventory failures remain explicit failures',
    () async {
      await enroll();
      inventory.single['driver'] = '';
      await expectLater(create(destination: windows()), throwsFormatException);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _channel,
            (_) async => throw PlatformException(code: 'inventory_failed'),
          );
      await expectLater(
        create(destination: windows()),
        throwsA(isA<WindowsSpoolerException>()),
      );
      expect(settings.containsKey(LocalPrinterCatalog.routesSettingKey), false);
    },
  );

  test(
    'permission revoked during enumeration cannot authorize a later write',
    () async {
      await enroll();
      final entered = Completer<void>();
      final release = Completer<dynamic>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (_) {
            entered.complete();
            return release.future;
          });
      final saved = create(destination: windows());
      final failure = expectLater(saved, throwsStateError);
      await entered.future;
      DeveloperAccess.lock();
      release.complete(inventory);
      await failure;
      expect(settings.containsKey(LocalPrinterCatalog.routesSettingKey), false);
    },
  );

  test(
    'a different enrollment holds restored Windows routes without rewriting them',
    () async {
      await enroll();
      final route = await create(destination: windows());
      await enroll(_otherDevice);
      expect(
        LocalPrinterCatalog.readRoutesForAdministration().single.toMap(),
        route.toMap(),
      );
      expect(LocalPrinterCatalog.readRoutesForDispatch, throwsStateError);
      expect(
        LocalPrinterCatalog.routeHoldReason(route),
        contains('different enrolled Device'),
      );
      expect(settings.get(LocalPrinterCatalog.routesSettingKey), [
        route.toMap(),
      ]);
    },
  );

  test(
    'capability revisions freeze accepted dimensions, cutter and optional beep',
    () async {
      final profile = PrinterCapabilityProfile.genericEscposRaster(
        paperWidthMm: 58,
        rasterWidthDots: 384,
        cutter: PrinterCutter.partial,
        beep: const PrinterBeepSettings(
          capability: PrinterBeepCapability.epsonEscA97Pattern,
          enabled: true,
        ),
      );
      final accepted = await create(capabilityProfile: profile);
      final frozen = accepted.toMap();
      final nextProfile = PrinterCapabilityProfile.genericEscposRaster(
        paperWidthMm: 80,
        rasterWidthDots: 512,
        cutter: PrinterCutter.full,
        beep: const PrinterBeepSettings(
          capability: PrinterBeepCapability.unsupported,
        ),
      );
      final edited = await LocalPrinterCatalog.saveRoute(
        id: accepted.id,
        name: accepted.name,
        role: accepted.role,
        destination: accepted.destination,
        expectedRevision: accepted.revision,
        capabilityProfile: nextProfile,
      );
      expect(accepted.toMap(), frozen);
      expect(accepted.capabilityProfile.toMap(), profile.toMap());
      expect(accepted.capabilityProfile.beep.enabled, true);
      expect(edited.id, accepted.id);
      expect(edited.revision, 2);
      expect(edited.capabilityProfile.toMap(), nextProfile.toMap());
      final renamed = await LocalPrinterCatalog.saveRoute(
        id: edited.id,
        name: 'Renamed bar',
        role: edited.role,
        destination: tcp('10.20.0.2'),
        expectedRevision: edited.revision,
      );
      expect(renamed.capabilityProfile.toMap(), nextProfile.toMap());
      expect(renamed.revision, 3);
      expect(
        LocalPrinterCatalog.readRoutesForDispatch().single.toMap(),
        renamed.toMap(),
      );
      expect(fixture.connections, 0);
    },
  );

  test(
    'legacy candidate routes and absent beep remain conservative and silent',
    () async {
      final route = await create();
      expect(route.capabilityProfile.cutter, PrinterCutter.none);
      expect(
        route.capabilityProfile.beep.capability,
        PrinterBeepCapability.unknown,
      );
      expect(route.capabilityProfile.beep.enabled, false);
      final legacyCandidate = route.toMap()..remove('capabilityProfile');
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [
        legacyCandidate,
      ]);
      final legacy = LocalPrinterCatalog.readRoutesForAdministration().single;
      expect(
        legacy.capabilityProfile.toMap(),
        PrinterCapabilityProfile.genericEscposRaster().toMap(),
      );
      final profileWithoutBeep = legacy.capabilityProfile.toMap()
        ..remove('beep');
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [
        {...legacyCandidate, 'capabilityProfile': profileWithoutBeep},
      ]);
      final noBeep = LocalPrinterCatalog.readRoutesForDispatch().single;
      expect(noBeep.capabilityProfile.beep.enabled, false);
      expect(
        noBeep.capabilityProfile.beep.capability,
        PrinterBeepCapability.unknown,
      );
      final normalized = await LocalPrinterCatalog.saveRoute(
        id: noBeep.id,
        name: noBeep.name,
        role: noBeep.role,
        destination: noBeep.destination,
        expectedRevision: noBeep.revision,
      );
      expect(normalized.capabilityProfile.beep.enabled, false);
      expect(
        (settings.get(LocalPrinterCatalog.routesSettingKey) as List).single,
        normalized.toMap(),
      );
    },
  );

  test(
    'driver-rendered profile is saved for administration and held from dispatch',
    () async {
      final driverProfile = PrinterCapabilityProfile(
        paperWidthMm: 80,
        rasterWidthDots: 576,
        language: PrinterCommandLanguage.windowsDriverRendered,
        cutter: PrinterCutter.none,
      );
      final held = await create(capabilityProfile: driverProfile);
      expect(
        LocalPrinterCatalog.readRoutesForAdministration().single.toMap(),
        held.toMap(),
      );
      expect(
        LocalPrinterCatalog.routeHoldReason(held),
        contains('renderer is not implemented'),
      );
      expect(LocalPrinterCatalog.readRoutesForDispatch, throwsStateError);
      final active = await LocalPrinterCatalog.saveRoute(
        id: held.id,
        name: held.name,
        role: held.role,
        destination: held.destination,
        expectedRevision: held.revision,
        capabilityProfile: PrinterCapabilityProfile.genericEscposRaster(),
      );
      expect(LocalPrinterCatalog.routeHoldReason(active), isNull);
      expect(LocalPrinterCatalog.readRoutesForDispatch().single.id, held.id);
      expect(fixture.connections, 0);
    },
  );

  test(
    'malformed required capability fields are never replaced by a route save',
    () async {
      final route = await create();
      final malformed = [
        {
          ...route.toMap(),
          'capabilityProfile': {
            ...route.capabilityProfile.toMap(),
            'rasterWidthDots': 385,
          },
        },
      ];
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, malformed);
      expect(
        LocalPrinterCatalog.readRoutesForAdministration,
        throwsFormatException,
      );
      await expectLater(
        LocalPrinterCatalog.saveRoute(
          id: route.id,
          name: route.name,
          role: route.role,
          destination: route.destination,
          expectedRevision: route.revision,
          capabilityProfile: PrinterCapabilityProfile.genericEscposRaster(),
        ),
        throwsFormatException,
      );
      expect(settings.get(LocalPrinterCatalog.routesSettingKey), malformed);
    },
  );

  test(
    'role dispatch excludes unrelated holds while preserving catalog integrity checks',
    () async {
      final kitchen = await create(role: PrinterRole.kitchen);
      final held = await create(
        name: 'Held additional',
        role: PrinterRole.additional,
        destination: tcp('10.20.0.2'),
        capabilityProfile: PrinterCapabilityProfile(
          paperWidthMm: 80,
          rasterWidthDots: 576,
          language: PrinterCommandLanguage.windowsDriverRendered,
          cutter: PrinterCutter.none,
        ),
      );
      DeveloperAccess.lock();
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ).single.toMap(),
        kitchen.toMap(),
      );
      expect(
        () => LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.additional,
        ),
        throwsStateError,
      );
      expect(LocalPrinterCatalog.readRoutesForDispatch, throwsStateError);
      final malformed = {
        ...held.toMap(),
        'capabilityProfile': {
          ...held.capabilityProfile.toMap(),
          'rasterWidthDots': 385,
        },
      };
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [
        kitchen.toMap(),
        malformed,
      ]);
      expect(
        () => LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ),
        throwsFormatException,
      );
    },
  );
}
