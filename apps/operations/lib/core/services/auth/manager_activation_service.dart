import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';

/// Activation creates no local authority: Cloud commits Staff and queues Edge delivery.
class PosManagerRegistrationService {
  static Future<void> complete({
    required String code,
    required String name,
    required String pin,
    required String requestId,
    String? setupId,
    http.Client? client,
  }) async {
    final String? credential;
    try {
      credential = EdgeDeviceCredentialStore.credential;
    } on StateError {
      throw const ActivationFailure(
        'აღდგენილი POS მონაცემებისთვის საჭიროა რესტორნის წვდომის გადამოწმება.',
      );
    }
    if (credential == null) {
      throw const ActivationFailure('ჯერ დააკავშირეთ POS რესტორანთან.');
    }
    late http.Response response;
    try {
      response = await (client?.post ?? http.post)(
        Uri.parse(
          '${ApiConfig.baseUrl}/edge/${setupId == null ? 'manager-activation' : 'manager-setup'}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'X-POS-Sync-Key': credential,
        },
        body: jsonEncode({
          if (setupId == null) 'code': code.trim() else 'setupId': setupId,
          'name': name.trim(),
          'pin': pin,
          'requestId': requestId,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const ActivationFailure(
        'კავშირი ვერ დამყარდა. გაიმეორეთ იგივე მონაცემებით; თუ აქტივაცია უკვე დასრულდა, სცადეთ ახალი PIN-ით შესვლა.',
      );
    }
    if (response.statusCode == 200) return;
    throw ActivationFailure(switch (response.statusCode) {
      401 =>
        setupId == null
            ? 'აქტივაციის კოდი ან POS-ის წვდომა მიუწვდომელია. გადაამოწმეთ კოდი და POS-ის კავშირი.'
            : 'POS-ის წვდომა ან პირველი რეგისტრაციის უფლება მიუწვდომელია. გადაამოწმეთ POS-ის კავშირი ან მიიღეთ ახალი დაკავშირების კოდი.',
      409 =>
        'ეს მონაცემები უკვე გამოიყენება. თუ აქტივაცია დასრულდა, შედით თქვენი PIN-ით; სხვა შემთხვევაში აირჩიეთ სხვა სახელი ან PIN.',
      429 => 'მცდელობები დროებით შეზღუდულია. სცადეთ მოგვიანებით.',
      400 => 'შეამოწმეთ სახელი და PIN — საჭიროა 4–6 ციფრი.',
      403 => 'ამ რესტორანში აქტივაცია მიუწვდომელია. დაუკავშირდით Vynic-ს.',
      _ => 'აქტივაცია ვერ დასრულდა. სცადეთ ხელახლა.',
    });
  }
}

class ActivationFailure implements Exception {
  const ActivationFailure(this.message);
  final String message;
}

/// Setup metadata is scoped by the current Device; the ID is only a stable retry key.
class PosManagerSetupStatus {
  const PosManagerSetupStatus(this.state, {this.setupId});
  final String state;
  final String? setupId;
  bool get ready => state == 'READY' && setupId != null;
}

class PosManagerSetupService {
  static Future<PosManagerSetupStatus> load({http.Client? client}) async {
    final String? credential;
    try {
      credential = EdgeDeviceCredentialStore.credential;
    } on StateError {
      return const PosManagerSetupStatus('RECONNECT_REQUIRED');
    }
    if (credential == null)
      return const PosManagerSetupStatus('RECONNECT_REQUIRED');
    try {
      final response = await (client?.get ?? http.get)(
        Uri.parse('${ApiConfig.baseUrl}/edge/manager-setup'),
        headers: {'X-POS-Sync-Key': credential},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 401)
        return const PosManagerSetupStatus('RECONNECT_REQUIRED');
      if (response.statusCode == 404)
        return const PosManagerSetupStatus('LEGACY_INVITATION');
      if (response.statusCode != 200)
        return const PosManagerSetupStatus('UNAVAILABLE');
      final body = jsonDecode(response.body);
      if (body is! Map ||
          !const [
            'READY',
            'COMPLETED',
            'EXISTING_MANAGER',
            'WAITING_PRIMARY',
            'LEGACY_INVITATION',
            'EXPIRED',
            'UNAVAILABLE',
          ].contains(body['state']))
        return const PosManagerSetupStatus('UNAVAILABLE');
      final id = body['setupId'];
      if (body['state'] == 'READY' &&
          (id is! String || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)))
        return const PosManagerSetupStatus('UNAVAILABLE');
      return PosManagerSetupStatus(
        body['state'] as String,
        setupId: id is String ? id : null,
      );
    } catch (_) {
      return const PosManagerSetupStatus('UNAVAILABLE');
    }
  }
}
