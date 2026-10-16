import 'pos_venue_profile.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../database/database_core.dart';
import '../../database/local_data_admission.dart';
import '../sync/api_config.dart';
import '../printing/printer_service.dart';
import '../printing/print_queue.dart';
import '../printing/cloud_printer_runtime.dart';
import '../printing/print_identity_admission.dart';
import '../pos/update/update_readiness.dart';
import 'edge_device_credential_store.dart';
import '../../database/repositories/inventory_repository.dart';
import '../menu/menu_client_compatibility.dart';

/// One complete durable configuration value; failed pulls retain the last good copy.
class RuntimeConfigSync {
  RuntimeConfigSync({http.Client? client}) : _client = client;
  final http.Client? _client;
  static final instance = RuntimeConfigSync();
  Timer? _timer;
  bool _busy = false;
  bool _shuttingDown = false;
  Future<void> start() async {
    if (_shuttingDown) return;
    if (_timer != null || !EdgeDeviceCredentialStore.hasCredential) return;
    unawaited(pull());
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(pull()),
    );
  }

  Future<void> pull() async {
    if (_busy || _shuttingDown) return;
    _busy = true;
    try {
      // Capture the complete request identity before either HTTP operation.
      final requestDevice = EdgeDeviceCredentialStore.deviceId;
      final requestVenue = EdgeDeviceCredentialStore.venueId;
      final requestCredential = EdgeDeviceCredentialStore.credential;
      final requestSettings = DatabaseCore.settingsBox;
      if (requestDevice == null ||
          requestCredential == null ||
          requestSettings == null ||
          !requestSettings.isOpen)
        return;
      final requestUri = Uri.parse('${ApiConfig.baseUrl}/edge/runtime-config');
      final headers = {
        ...ApiConfig.posSyncHeaders,
        'X-POS-Sync-Key': requestCredential,
        // A current request compatibility claim, never an offline-reader fence.
        'X-Vynic-Printer-Reader-Version':
            '${CloudPrinterRuntime.readerVersion}',
      };
      void requireRequestIdentity() {
        if (EdgeDeviceCredentialStore.deviceId != requestDevice ||
            EdgeDeviceCredentialStore.venueId != requestVenue ||
            EdgeDeviceCredentialStore.credential != requestCredential ||
            !identical(DatabaseCore.settingsBox, requestSettings) ||
            !requestSettings.isOpen ||
            PrintIdentityAdmission.identityTransitionActive) {
          throw StateError('Runtime configuration request identity changed');
        }
      }

      requireRequestIdentity();
      try {
        await PosVenueProfile.pushPending(client: _client);
      } catch (error) {
        debugPrint('Venue profile pending: $error');
      }
      requireRequestIdentity();
      final response = await (_client?.get ?? http.get)(
        requestUri,
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      requireRequestIdentity();
      final decoded = jsonDecode(response.body);
      if (!MenuClientCompatibility.observe(response.statusCode, decoded))
        return;
      if (response.statusCode != 200)
        throw StateError('Configuration request: ${response.statusCode}');
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid runtime snapshot');
      }
      final snapshot = decoded;
      final device = snapshot['device'];
      final venue = snapshot['venue'];
      if (snapshot['version'] is! int ||
          snapshot['version'] != 1 ||
          device is! Map ||
          venue is! Map ||
          device['id'] != requestDevice ||
          (requestVenue != null && venue['id'] != requestVenue))
        throw const FormatException('Unexpected Device configuration');
      final features = snapshot['features'];
      if (features is! List || features.any((key) => key is! String)) {
        throw const FormatException('Invalid feature snapshot');
      }
      for (final field in [
        'name',
        'branchName',
        'address',
        'phone',
        'legalId',
      ]) {
        if (venue[field] != null && venue[field] is! String) {
          throw const FormatException('Invalid venue profile');
        }
      }
      final config = device['runtimeConfig'] == null
          ? null
          : _canonicalConfig(
              device['runtimeConfig'],
              deviceId: requestDevice,
              venueId: requestVenue,
            );
      await UpdateReadiness.track(
        'Printer configuration',
        () => LocalDataAdmission.mutate(() async {
          requireRequestIdentity();
          // A timed-out native future can remain active after its job is held.
          if (PrintIdentityAdmission.activeSubmissions > 0) return;
          final previous = requestSettings.get('deviceRuntimeConfig');
          final changed =
              config != null &&
              _configurationChanged(
                previous,
                config,
                deviceId: requestDevice,
                venueId: requestVenue,
              );
          // Hold identity and native admission throughout awaited publication.
          await PrintIdentityAdmission.changeIdentity(() async {
            await InventoryRepository.applyRuntimeFeatures(
              List<String>.from(features),
            );
            if (venue['profileUpdatedAt'] != null &&
                requestSettings.get('pendingVenueProfile') == null) {
              await PosVenueProfile.cache(Map<String, dynamic>.from(venue));
            }
            final name = device['displayName'];
            if (name is String &&
                name.trim().isNotEmpty &&
                requestSettings.get('enrolledDeviceName') != name) {
              await requestSettings.put('enrolledDeviceName', name);
            }
            if (!changed || PrintQueue.pendingCount > 0) return;
            try {
              await requestSettings.put('deviceRuntimeConfig', config);
              await requestSettings.flush();
            } catch (publishError) {
              // Hive can expose a new value before flush fails. Restore the
              // complete prior value while both admissions remain held.
              try {
                if (previous == null) {
                  await requestSettings.delete('deviceRuntimeConfig');
                } else {
                  await requestSettings.put('deviceRuntimeConfig', previous);
                }
                await requestSettings.flush();
              } catch (restoreError) {
                LocalDataAdmission.failure ??=
                    'Printer configuration cache restoration could not be '
                    'confirmed; controlled recovery is required';
                throw StateError(
                  'Printer configuration publication failed ($publishError); '
                  'last cache restoration could not be confirmed ($restoreError). '
                  '${LocalDataAdmission.failure}',
                );
              }
              rethrow;
            }
            PrinterService.dispose();
            await PrinterService.initialize();
          });
        }),
      );
    } catch (error) {
      debugPrint('Runtime configuration retained: $error');
    } finally {
      _busy = false;
    }
  }

  static Map<String, dynamic> _canonicalConfig(
    dynamic raw, {
    required String deviceId,
    required String? venueId,
  }) {
    if (raw is! Map) throw const FormatException('Invalid configuration');
    if (raw['version'] == 2) {
      if (venueId == null) {
        throw const FormatException('Cloud v2 requires an enrolled Venue');
      }
      return CloudPrinterRuntime.decode(
        raw,
        boundDeviceId: deviceId,
        boundVenueId: venueId,
      ).toMap();
    }
    final config = Map<String, dynamic>.from(raw);
    validate(config);
    return jsonDecode(jsonEncode(config)) as Map<String, dynamic>;
  }

  static bool _configurationChanged(
    dynamic previous,
    Map<String, dynamic> next, {
    required String deviceId,
    required String? venueId,
  }) {
    if (previous == null) return true;
    final old = _canonicalConfig(
      previous,
      deviceId: deviceId,
      venueId: venueId,
    );
    if (old['version'] == 2) {
      if (next['version'] != 2) {
        throw StateError('Cloud v2 printer configuration cannot downgrade');
      }
      if (next['revision'] < old['revision']) {
        throw StateError(
          'Cloud printer configuration revision moved backwards',
        );
      }
      if (next['revision'] == old['revision'] &&
          jsonEncode(next) != jsonEncode(old)) {
        throw StateError(
          'Cloud printer configuration changed at the same revision',
        );
      }
    }
    return jsonEncode(old) != jsonEncode(next);
  }

  static void validate(Map<String, dynamic> config) {
    if (config['version'] == 2) {
      final device = EdgeDeviceCredentialStore.deviceId;
      final venue = EdgeDeviceCredentialStore.venueId;
      if (device == null ||
          venue == null ||
          EdgeDeviceCredentialStore.credential == null) {
        throw const FormatException(
          'Cloud v2 requires an enrolled Device and Venue',
        );
      }
      CloudPrinterRuntime.decode(
        config,
        boundDeviceId: device,
        boundVenueId: venue,
      );
      return;
    }
    if (config['version'] is! int ||
        config['version'] != 1 ||
        config['printers'] is! Map)
      throw const FormatException('Invalid configuration');
    for (final key in ['kitchen', 'receipt']) {
      final p = config['printers'][key];
      if (p is! Map ||
          p['enabled'] is! bool ||
          p['host'] is! String ||
          p['port'] is! int ||
          p['port'] < 1 ||
          p['port'] > 65535 ||
          (p['enabled'] && p['host'].isEmpty))
        throw const FormatException('Invalid printer');
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> shutdown() async {
    _shuttingDown = true;
    await stop();
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}
