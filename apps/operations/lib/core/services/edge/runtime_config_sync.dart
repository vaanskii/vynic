import 'pos_venue_profile.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../database/database_core.dart';
import '../sync/api_config.dart';
import '../printing/printer_service.dart';
import '../printing/print_queue.dart';
import 'edge_device_credential_store.dart';
import '../../database/repositories/inventory_repository.dart';

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
      try {
        await PosVenueProfile.pushPending(client: _client);
      } catch (error) {
        debugPrint('Venue profile pending: $error');
      }
      final response = await (_client?.get ?? http.get)(
        Uri.parse('${ApiConfig.baseUrl}/edge/runtime-config'),
        headers: ApiConfig.posSyncHeaders,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200)
        throw StateError('Configuration request: ${response.statusCode}');
      final snapshot = jsonDecode(response.body) as Map<String, dynamic>;
      if (snapshot['version'] != 1 ||
          snapshot['device']?['id'] != EdgeDeviceCredentialStore.deviceId ||
          (EdgeDeviceCredentialStore.venueId != null &&
              snapshot['venue']?['id'] != EdgeDeviceCredentialStore.venueId))
        throw const FormatException('Unexpected Device configuration');
      final features = snapshot['features'];
      if (features is! List || features.any((key) => key is! String)) {
        throw const FormatException('Invalid feature snapshot');
      }
      await InventoryRepository.applyRuntimeFeatures(
        List<String>.from(features),
      );
      final venue = snapshot['venue'] as Map<String, dynamic>;
      if (venue['profileUpdatedAt'] != null &&
          DatabaseCore.settingsBox?.get('pendingVenueProfile') == null) {
        await PosVenueProfile.cache(venue);
      }
      final name = snapshot['device']['displayName'];
      if (name is String &&
          name.trim().isNotEmpty &&
          DatabaseCore.settingsBox?.get('enrolledDeviceName') != name) {
        await DatabaseCore.settingsBox!.put('enrolledDeviceName', name);
      }
      final config = snapshot['device']['runtimeConfig'];
      if (config == null)
        return; // Existing local printers remain until explicitly configured in Cloud.
      validate(config as Map<String, dynamic>);
      if (jsonEncode(DatabaseCore.settingsBox?.get('deviceRuntimeConfig')) ==
          jsonEncode(config))
        return;
      if (PrintQueue.pendingCount > 0)
        return; // Apply on a later pull, between print jobs.
      await DatabaseCore.settingsBox!.put('deviceRuntimeConfig', config);
      PrinterService.dispose();
      await PrinterService.initialize();
    } catch (error) {
      debugPrint('Runtime configuration retained: $error');
    } finally {
      _busy = false;
    }
  }

  static void validate(Map<String, dynamic> config) {
    if (config['version'] != 1 || config['printers'] is! Map)
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
