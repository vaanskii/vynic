import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:vynic/core/services/security/developer_access.dart';

/// Disposable signing identity; never imports or changes real signing keys.
Future<void> unlockSyntheticPrinterDeveloper({List<String>? scopes}) async {
  DeveloperAccess.resetForTest();
  final algorithm = Ed25519();
  final key = await algorithm.newKeyPair();
  DeveloperAccess.publicKeyOverride = base64Url.encode(
    (await key.extractPublicKey()).bytes,
  );
  final now = DateTime.now().toUtc();
  final bytes = utf8.encode(
    jsonEncode({
      'v': 1,
      'jti': 'synthetic-printer-${now.microsecondsSinceEpoch}',
      'terminal': DeveloperAccess.terminalId,
      'issuedAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
      'scopes': scopes ?? [DeveloperScope.printers],
    }),
  );
  final signature = await algorithm.sign(bytes, keyPair: key);
  final result = await DeveloperAccess.unlock(
    '${base64Url.encode(bytes)}.${base64Url.encode(signature.bytes)}',
  );
  if (!result.isSuccess) throw StateError('Synthetic developer unlock failed');
}
