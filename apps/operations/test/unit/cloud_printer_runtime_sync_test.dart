import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/models/feature_keys.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/runtime_config_sync.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/printing/cloud_printer_runtime.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/services/printing/print_identity_admission.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/security/developer_access.dart';

import '../support/pos02_developer_fixture.dart';
import '../support/pos02_fixture.dart';

const _device = '10000000-0000-4000-8000-000000000001';
const _venue = '20000000-0000-4000-8000-000000000001';
const _otherDevice = '10000000-0000-4000-8000-000000000002';
const _otherVenue = '20000000-0000-4000-8000-000000000002';
const _configKey = 'deviceRuntimeConfig';

Map<String, dynamic> _route({
  PrinterRole role = PrinterRole.kitchen,
  String host = 'synthetic.invalid',
  bool enabled = true,
  int revision = 1,
  PrinterCapabilityProfile? profile,
}) => {
  'protocol': 1,
  'id': '${role.name}-cloud',
  'name': '${role.name} Cloud',
  'role': role.name,
  'revision': revision,
  'destination': PrinterDestination.tcp(host: host, port: 9100).toMap(),
  'capabilityProfile':
      (profile ?? PrinterCapabilityProfile.genericEscposRaster()).toMap(),
  'enabled': enabled,
};

Map<String, dynamic> _config({
  int revision = 7,
  String phase = 'ACTIVE',
  List<Map<String, dynamic>>? routes,
}) => {
  'version': 2,
  'deviceId': _device,
  'venueId': _venue,
  'revision': revision,
  'phase': phase,
  'minimumReaderVersion': 2,
  'printers': {
    'kitchen': {'enabled': false, 'host': '', 'port': 9100},
    'receipt': {'enabled': false, 'host': '', 'port': 9100},
  },
  'routes': routes ?? [_route()],
};

Map<String, dynamic> _snapshot(dynamic config) => {
  'version': 1,
  'features': [FeatureKeys.pos],
  'venue': {
    'id': _venue,
    'name': 'Synthetic Cloud venue',
    'branchName': 'Synthetic branch',
    'address': 'Synthetic address',
    'profileUpdatedAt': '2026-10-06T12:00:00Z',
  },
  'device': {
    'id': _device,
    'displayName': 'Synthetic Cloud terminal',
    'runtimeConfig': config,
  },
};

http.Response _response(dynamic config) => http.Response(
  jsonEncode(_snapshot(config)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Matcher _held(CloudPrinterDispatchHoldKind kind) => throwsA(
  isA<CloudPrinterDispatchHold>().having((hold) => hold.kind, 'kind', kind),
);

class _RuntimeSettingsBox extends UpdateTrackedBox<dynamic> {
  _RuntimeSettingsBox(super.inner);
  final trace = <String>[];
  Completer<void>? flushEntered;
  Completer<void>? releaseFlush;
  bool failNextFlush = false;
  bool rejectRestoreAfterFailedFlush = false;
  bool _rejectNextConfigPut = false;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    expect(LocalDataAdmission.insideMutation, true);
    if (key == _configKey) {
      trace.add('config.put');
      if (_rejectNextConfigPut) {
        _rejectNextConfigPut = false;
        throw StateError('Synthetic last-cache restoration write failure');
      }
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
    if (failNextFlush) {
      failNextFlush = false;
      _rejectNextConfigPut = rejectRestoreAfterFailedFlush;
      throw StateError('Synthetic configuration flush failure');
    }
    await super.flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Pos02Fixture fixture;
  late _RuntimeSettingsBox settings;

  Future<void> enroll({
    String device = _device,
    String venue = _venue,
    String secret = 'x',
  }) async {
    expect(
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: 'vynic-device-v1.$device.${secret * 40}',
        venueId: venue,
        venueName: 'Synthetic enrolled venue',
      ),
      true,
    );
  }

  Future<void> pull(dynamic config) async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/edge/runtime-config');
      expect(request.headers['X-Vynic-Printer-Reader-Version'], '2');
      expect(
        request.headers['X-POS-Sync-Key'],
        EdgeDeviceCredentialStore.credential,
      );
      return _response(config);
    });
    try {
      await RuntimeConfigSync(client: client).pull();
    } finally {
      client.close();
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'vynic-cloud-printer-sync-',
    );
    fixture = Pos02Fixture();
    await fixture.open(directory.path);
    await fixture.seed();
    await DatabaseCore.settingsBox!.delete(_configKey);
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await enroll();
    DeveloperAccess.resetForTest();
    UpdateReadiness.startupReady = true;
    settings = _RuntimeSettingsBox(DatabaseCore.settingsBox!);
    DatabaseCore.settingsBox = settings;
  });

  tearDown(() async {
    expect(fixture.connections, 0);
    expect(fixture.transmitted, isEmpty);
    expect(PrintIdentityAdmission.activeSubmissions, 0);
    if (settings.releaseFlush case final Completer<void> barrier) {
      if (!barrier.isCompleted) barrier.complete();
    }
    UpdateReadiness.enabled = false;
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    // A synthetic failed publication deliberately exercises this recovery
    // latch. Test cleanup is the explicit recovery boundary, never the pull.
    LocalDataAdmission.failure = null;
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = null;
    DeveloperAccess.resetForTest();
    DeveloperAccess.publicKeyOverride = null;
    await fixture.close();
    await directory.delete(recursive: true);
  });

  test(
    'valid v2 publishes one complete value and flushes under both admissions',
    () async {
      final config = _config();
      await pull(config);
      expect(settings.get(_configKey), config);
      expect(settings.trace, ['config.put', 'settings.flush']);
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ).single.id,
        'kitchen-cloud',
      );
      expect(settings.get('enrolledDeviceName'), 'Synthetic Cloud terminal');
      expect(SettingsRepository.getVenueAddress(), 'Synthetic address');
      expect(settings.get('runtimeFeatures'), [FeatureKeys.pos]);
      RuntimeConfigSync.validate(config);
    },
  );

  test(
    'valid cache remains dispatchable offline after reopening Hive and identity file',
    () async {
      await pull(_config());
      PrintQueue.stop();
      await PrintQueue.idle;
      final name = settings.name;
      await settings.close();
      settings = _RuntimeSettingsBox(await Hive.openBox(name));
      DatabaseCore.settingsBox = settings;
      EdgeDeviceCredentialStore.resetForTest();
      await EdgeDeviceCredentialStore.load();
      final offline = MockClient((request) async {
        throw http.ClientException('Synthetic offline request');
      });
      try {
        await RuntimeConfigSync(client: offline).pull();
      } finally {
        offline.close();
      }
      expect(settings.get(_configKey), _config());
      expect(settings.trace, isEmpty);
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ).single.destination.host,
        'synthetic.invalid',
      );
    },
  );

  for (final changed in ['Device', 'Venue', 'credential']) {
    test(
      'a stale HTTP response after $changed change cannot alter any cached snapshot',
      () async {
        await settings.inner.put(_configKey, _config());
        final before = jsonDecode(jsonEncode(settings.toMap()));
        final requested = Completer<void>();
        final response = Completer<http.Response>();
        final capturedCredential = EdgeDeviceCredentialStore.credential;
        final client = MockClient((request) async {
          expect(request.headers['X-POS-Sync-Key'], capturedCredential);
          requested.complete();
          return response.future;
        });
        final pulling = RuntimeConfigSync(client: client).pull();
        await requested.future.timeout(const Duration(seconds: 2));
        await enroll(
          device: changed == 'Device' ? _otherDevice : _device,
          venue: changed == 'Venue' ? _otherVenue : _venue,
          secret: changed == 'credential' ? 'y' : 'x',
        );
        response.complete(_response(_config(revision: 8)));
        await pulling;
        client.close();
        expect(settings.toMap(), before);
        expect(settings.trace, isEmpty);
        if (changed != 'credential') {
          expect(
            () => LocalPrinterCatalog.readRoutesForDispatch(
              role: PrinterRole.kitchen,
            ),
            throwsFormatException,
          );
        }
      },
    );
  }

  test(
    'identity is rechecked after waiting for local publication admission',
    () async {
      await settings.inner.put(_configKey, _config());
      final before = jsonDecode(jsonEncode(settings.toMap()));
      final admitted = Completer<void>();
      final release = Completer<void>();
      final writer = LocalDataAdmission.mutate(() async {
        admitted.complete();
        await release.future;
      });
      await admitted.future;
      final requested = Completer<void>();
      final client = MockClient((request) async {
        requested.complete();
        return _response(_config(revision: 8));
      });
      final pulling = RuntimeConfigSync(client: client).pull();
      await requested.future;
      await Future<void>.delayed(Duration.zero);
      await enroll(device: _otherDevice);
      release.complete();
      await writer;
      await pulling;
      client.close();
      expect(settings.toMap(), before);
      expect(settings.trace, isEmpty);
    },
  );

  test(
    'malformed or foreign v2 never mutates printers, features or profile',
    () async {
      await settings.inner.put(_configKey, _config());
      final before = jsonDecode(jsonEncode(settings.toMap()));
      for (final invalid in [
        _config()..['venueId'] = _otherVenue,
        _config()..['revision'] = 0,
        _config()..remove('minimumReaderVersion'),
        _config(routes: [_route()..remove('capabilityProfile')]),
        _config(
          routes: [
            _route()..['destination'] = {'kind': 'serial', 'port': 'COM1'},
          ],
        ),
        _config()
          ..['printers'] = {
            'kitchen': {'enabled': false, 'host': '', 'port': 9100},
          },
      ]) {
        await pull(invalid);
        expect(settings.toMap(), before);
        expect(settings.trace, isEmpty);
      }
    },
  );

  test(
    'malformed feature or venue metadata is rejected before publication',
    () async {
      final before = jsonDecode(jsonEncode(settings.toMap()));
      for (final body in [
        _snapshot(_config())..['features'] = [true],
        _snapshot(_config())..['venue'] = {'id': _venue, 'address': 123},
      ]) {
        final client = MockClient(
          (request) async => http.Response(jsonEncode(body), 200),
        );
        await RuntimeConfigSync(client: client).pull();
        client.close();
        expect(settings.toMap(), before);
        expect(settings.trace, isEmpty);
      }
    },
  );

  test(
    'cached v2 refuses downgrade, backwards revision and changed same revision',
    () async {
      final previous = _config();
      await settings.inner.put(_configKey, previous);
      final before = jsonDecode(jsonEncode(settings.toMap()));
      for (final invalid in [
        {
          'version': 1,
          'printers': {
            'kitchen': {
              'enabled': true,
              'host': 'synthetic.invalid',
              'port': 9100,
            },
            'receipt': {'enabled': false, 'host': '', 'port': 9100},
          },
        },
        _config(revision: 6),
        _config(routes: [_route(host: 'changed.synthetic.invalid')]),
        _config(phase: 'PREPARED'),
      ]) {
        await pull(invalid);
        expect(settings.toMap(), before);
        expect(settings.trace, isEmpty);
      }
    },
  );

  test(
    'same canonical revision is idempotent and a newer revision changes future routes',
    () async {
      await pull(_config());
      final captured = LocalPrinterCatalog.readRoutesForDispatch(
        role: PrinterRole.kitchen,
      ).single;
      settings.trace.clear();
      final same = _config();
      (same['routes'][0]['capabilityProfile'] as Map).remove('beep');
      await pull(
        Map<String, dynamic>.fromEntries(same.entries.toList().reversed),
      );
      expect(settings.trace, isEmpty);
      await pull(
        _config(
          revision: 8,
          routes: [_route(revision: 2, host: 'next.synthetic.invalid')],
        ),
      );
      expect(settings.trace, ['config.put', 'settings.flush']);
      expect(captured.revision, 1);
      expect(captured.destination.host, 'synthetic.invalid');
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ).single.revision,
        2,
      );
    },
  );

  test(
    'PREPARED and disabled routes hold and exact legacy stubs stop old TCP lookup fallback',
    () async {
      await pull(_config(phase: 'PREPARED'));
      for (final role in PrinterRole.values) {
        expect(
          () => LocalPrinterCatalog.readRoutesForDispatch(role: role),
          _held(CloudPrinterDispatchHoldKind.prepared),
        );
      }
      expect(
        LocalPrinterCatalog.readRoutesForDispatch,
        _held(CloudPrinterDispatchHoldKind.prepared),
      );
      expect(SettingsRepository.getKitchenPrinterIp(), '');
      expect(SettingsRepository.getReceiptPrinterIp(), '');
      expect(SettingsRepository.getKitchenPrinterPort(), 9100);
      expect(settings.get('printerKitchenIp'), 'synthetic.invalid');
      await pull(_config(revision: 8, routes: [_route(enabled: false)]));
      expect(
        () => LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ),
        _held(CloudPrinterDispatchHoldKind.disabled),
      );
      expect(
        () => LocalPrinterCatalog.readRoutesForDispatch(role: PrinterRole.bar),
        _held(CloudPrinterDispatchHoldKind.notConfigured),
      );
      expect(SettingsRepository.getKitchenPrinterIp(), '');
    },
  );

  test(
    'Cloud v2 owns every role and local records never override it',
    () async {
      final local = PrinterRoute.decode({
        'protocol': 1,
        'id': 'local-bar',
        'name': 'Local bar',
        'role': 'bar',
        'revision': 1,
        'destination': PrinterDestination.tcp(
          host: '10.20.0.2',
          port: 9100,
        ).toMap(),
      }).toMap();
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [local]);
      await pull(
        _config(
          routes: [
            for (final role in PrinterRole.values)
              _route(role: role, host: '${role.name}.synthetic.invalid'),
          ],
        ),
      );
      for (final role in PrinterRole.values) {
        expect(LocalPrinterCatalog.cloudOwnsRole(role), true);
        expect(
          LocalPrinterCatalog.readRoutesForDispatch(role: role).single.id,
          '${role.name}-cloud',
        );
      }
      await LocalDataAdmission.mutate(() => unlockSyntheticPrinterDeveloper());
      for (final role in PrinterRole.values) {
        await expectLater(
          LocalPrinterCatalog.saveRoute(
            name: 'Local ${role.name}',
            role: role,
            destination: PrinterDestination.tcp(host: '10.20.0.9', port: 9100),
            expectedRevision: 0,
          ),
          throwsStateError,
        );
      }
      expect(settings.get(LocalPrinterCatalog.routesSettingKey), [local]);
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [
        'malformed dormant local row',
      ]);
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ).single.id,
        'kitchen-cloud',
      );
    },
  );

  test(
    'missing Cloud v2 role is held even when a valid local route exists',
    () async {
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [
        PrinterRoute.decode({
          'protocol': 1,
          'id': 'local-bar',
          'name': 'Local bar',
          'role': 'bar',
          'revision': 1,
          'destination': PrinterDestination.tcp(
            host: '10.20.0.2',
            port: 9100,
          ).toMap(),
        }).toMap(),
      ]);
      await pull(_config());
      expect(
        () => LocalPrinterCatalog.readRoutesForDispatch(role: PrinterRole.bar),
        _held(CloudPrinterDispatchHoldKind.notConfigured),
      );
    },
  );

  test(
    'held enabled driver station does not disable another Cloud raster role',
    () async {
      await pull(
        _config(
          routes: [
            _route(),
            _route(
              role: PrinterRole.additional,
              host: 'held.synthetic.invalid',
              profile: PrinterCapabilityProfile(
                paperWidthMm: 80,
                rasterWidthDots: 576,
                language: PrinterCommandLanguage.windowsDriverRendered,
                cutter: PrinterCutter.none,
              ),
            ),
          ],
        ),
      );
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ).single.id,
        'kitchen-cloud',
      );
      expect(
        () => LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.additional,
        ),
        _held(CloudPrinterDispatchHoldKind.rendererUnavailable),
      );
      expect(
        LocalPrinterCatalog.readRoutesForDispatch,
        _held(CloudPrinterDispatchHoldKind.rendererUnavailable),
      );
    },
  );

  test(
    'pending jobs defer refresh and frozen accepted jobs keep the prior route afterward',
    () async {
      await settings.inner.put(_configKey, _config());
      final route = LocalPrinterCatalog.readRoutesForDispatch(
        role: PrinterRole.kitchen,
      ).single;
      final accepted = await PrintJobRepository.enqueue(
        PrintJob.create(
          id: 'synthetic-cloud-frozen',
          target: PrintQueueTarget.kitchen,
          destination: route.destination,
          printerId: route.id,
          routeRevision: route.revision,
          capabilityProfile: route.capabilityProfile,
          venueId: _venue,
          label: 'Synthetic frozen route',
          bytes: ascii.encode('SYNTHETIC ONLY\n'),
        ),
      );
      final next = _config(
        revision: 8,
        routes: [_route(revision: 2, host: 'next.synthetic.invalid')],
      );
      await pull(next);
      expect(settings.get(_configKey), _config());
      expect(settings.trace, isEmpty);
      await PrintJobRepository.transition(
        accepted.id,
        accepted.attemptId,
        PrintJobState.queued,
        PrintJobState.uncertain,
        detail: 'Synthetic fixture explicitly held',
      );
      await pull(next);
      expect(settings.get(_configKey), next);
      final stored = PrintJobRepository.read(accepted.id)!;
      expect(stored.destination.toMap(), accepted.destination.toMap());
      expect(
        stored.capabilityProfile.toMap(),
        accepted.capabilityProfile.toMap(),
      );
      expect(stored.routeRevision, 1);
      expect(stored.transmissionBytes, accepted.transmissionBytes);
      expect(stored.state, PrintJobState.uncertain);
    },
  );

  test(
    'unresolved native admission defers cache replacement even with no pending job',
    () async {
      await settings.inner.put(_configKey, _config());
      final token = PrintIdentityAdmission.beginSubmission();
      try {
        await pull(_config(revision: 8));
        expect(settings.get(_configKey), _config());
        expect(settings.trace, isEmpty);
      } finally {
        PrintIdentityAdmission.finishSubmission(token);
      }
      await pull(_config(revision: 8));
      expect(settings.get(_configKey), _config(revision: 8));
    },
  );

  test(
    'updater freeze and identity/native admission remain blocked throughout cache flush',
    () async {
      UpdateReadiness.enabled = true;
      settings.flushEntered = Completer<void>();
      final entered = settings.flushEntered!;
      settings.releaseFlush = Completer<void>();
      var completed = false;
      final pulling = pull(_config()).then((_) => completed = true);
      await entered.future.timeout(const Duration(seconds: 2));
      expect(completed, false);
      expect(LocalDataAdmission.blocked, false);
      expect(
        UpdateReadiness.activeOperations,
        contains('Printer configuration'),
      );
      var updaterClosed = false;
      expect(
        await UpdateReadiness.freeze(() async {
          updaterClosed = true;
        }),
        isNotNull,
      );
      expect(updaterClosed, false);
      expect(PrintIdentityAdmission.beginSubmission, throwsStateError);
      await expectLater(EdgeDeviceCredentialStore.clear(), throwsStateError);
      var anotherWriterEntered = false;
      final anotherWriter = LocalDataAdmission.mutate(() async {
        anotherWriterEntered = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(anotherWriterEntered, false);
      settings.releaseFlush!.complete();
      await pulling;
      await anotherWriter;
      expect(completed, true);
      expect(settings.get(_configKey), _config());
      expect(UpdateReadiness.activeOperations, isEmpty);
      expect(PrintIdentityAdmission.identityTransitionActive, false);
    },
  );

  test(
    'a failed publication flush restores the complete last good printer value',
    () async {
      final previous = _config();
      await settings.inner.put(_configKey, previous);
      settings.failNextFlush = true;
      await pull(_config(revision: 8));
      expect(settings.get(_configKey), previous);
      expect(settings.trace, [
        'config.put',
        'settings.flush',
        'config.put',
        'settings.flush',
      ]);
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.kitchen,
        ).single.id,
        'kitchen-cloud',
      );
    },
  );

  test(
    'failed publication and failed restoration latch all future mutations until recovery',
    () async {
      await settings.inner.put(_configKey, _config());
      settings.failNextFlush = true;
      settings.rejectRestoreAfterFailedFlush = true;
      await pull(_config(revision: 8));
      // Hive exposed the unconfirmed candidate before both failures. It must
      // never become authority for another admitted print or configuration write.
      expect(settings.get(_configKey), _config(revision: 8));
      final failure = LocalDataAdmission.failure;
      expect(failure, contains('controlled recovery is required'));
      final trace = List<String>.from(settings.trace);
      var admitted = false;
      await expectLater(
        LocalDataAdmission.mutate(() async {
          admitted = true;
        }),
        throwsStateError,
      );
      expect(admitted, false);
      await expectLater(
        PrintJobRepository.enqueue(
          fixture.job(id: 'synthetic-held-by-cache-failure'),
        ),
        throwsStateError,
      );
      expect(
        PrintJobRepository.read('synthetic-held-by-cache-failure'),
        isNull,
      );
      expect(UpdateReadiness.evaluate().status, 'BLOCKED');
      await pull(_config(revision: 9));
      expect(settings.trace, trace);
      expect(settings.get(_configKey), _config(revision: 8));
      expect(LocalDataAdmission.failure, failure);
    },
  );

  test(
    'v1 Cloud primary lookups and local bar routing retain their prior behavior',
    () async {
      await settings.inner.put(LocalPrinterCatalog.routesSettingKey, [
        PrinterRoute.decode({
          'protocol': 1,
          'id': 'local-bar',
          'name': 'Local bar',
          'role': 'bar',
          'revision': 1,
          'destination': PrinterDestination.tcp(
            host: '10.20.0.2',
            port: 9200,
          ).toMap(),
        }).toMap(),
      ]);
      await pull({
        'version': 1,
        'printers': {
          'kitchen': {
            'enabled': true,
            'host': 'synthetic.invalid',
            'port': 9200,
          },
          'receipt': {'enabled': false, 'host': '', 'port': 9100},
        },
      });
      expect(SettingsRepository.getKitchenPrinterIp(), 'synthetic.invalid');
      expect(SettingsRepository.getKitchenPrinterPort(), 9200);
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(role: PrinterRole.kitchen),
        isEmpty,
      );
      expect(
        LocalPrinterCatalog.readRoutesForDispatch(
          role: PrinterRole.bar,
        ).single.id,
        'local-bar',
      );
      expect(LocalPrinterCatalog.cloudOwnsRole(PrinterRole.bar), false);
    },
  );
}
