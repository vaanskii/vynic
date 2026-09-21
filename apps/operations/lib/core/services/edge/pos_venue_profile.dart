import 'dart:convert';
import 'edge_device_credential_store.dart';
import 'package:http/http.dart' as http;
import '../../database/database_core.dart';
import '../sync/api_config.dart';

/// Durable local identity and an explicit pending Cloud update; never blocks POS work.
abstract final class PosVenueProfile {
  static Future<void> cache(Map<String, dynamic> profile) async {
    final box = DatabaseCore.settingsBox;
    if (box == null) return;
    final values = <String, String>{
      'venueName': profile['name'] ?? '',
      'venueBranchName': profile['branchName'] ?? '',
      'venueAddress': profile['address'] ?? '',
      'venuePhone': profile['phone'] ?? '',
      'venueLegalId': profile['legalId'] ?? '',
    };
    final changed = {
      for (final entry in values.entries)
        if (box.get(entry.key) != entry.value) entry.key: entry.value,
    };
    if (changed.isNotEmpty) await box.putAll(changed);
  }

  static Future<void> pushPending({http.Client? client}) async {
    final box = DatabaseCore.settingsBox;
    final pending = box?.get('pendingVenueProfile');
    if (pending == null) return;
    if (pending is! Map ||
        pending['venueId'] != EdgeDeviceCredentialStore.venueId) {
      // A backup from a different Venue may carry a pending edit, never its authority.
      await box!.delete('pendingVenueProfile');
      return;
    }
    final identity = jsonEncode(pending);
    final encoded = jsonEncode(pending['profile']);
    final response = await (client?.put ?? http.put)(
      Uri.parse('${ApiConfig.baseUrl}/edge/venue-profile'),
      headers: ApiConfig.posSyncHeaders,
      body: encoded,
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200)
      throw StateError(
        'პროფილი ჯერ არ სინქრონიზებულა (${response.statusCode})',
      );
    if (jsonEncode(box?.get('pendingVenueProfile')) == identity) {
      await box!.delete('pendingVenueProfile');
    }
  }
}
