import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/services/security/developer_public_key.dart';

/// End-to-end check that `tool/dev_key.dart` and the shipped public key are
/// still two halves of the same pair.
///
/// Rotating one without the other produces a build nobody can service, and the
/// failure only shows up on a customer's terminal at the worst moment. Skipped
/// where the private key is absent — that is every machine but the
/// developer's, which is the point of it being in `secrets/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keyFile = File('../secrets/developer_signing_key.json');

  test(
    'a token signed with the private key opens the shipped build',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('dev_roundtrip');
      Hive.init(tempDir.path);
      DatabaseCore.settingsBox = await Hive.openBox('settings_roundtrip_test');
      DeveloperAccess.publicKeyOverride = null;
      DeveloperAccess.resetForTest();

      try {
        final stored =
            json.decode(keyFile.readAsStringSync()) as Map<String, dynamic>;

        expect(
          stored['publicKey'],
          kDeveloperPublicKeyBase64,
          reason:
              'secrets/developer_signing_key.json and developer_public_key.dart '
              'have drifted apart — re-run `dart run tool/dev_key.dart keygen` '
              'and paste the printed key, or restore the matching private key.',
        );

        final algorithm = Ed25519();
        final keyPair = await algorithm.newKeyPairFromSeed(
          base64Url.decode(stored['privateKey'] as String),
        );
        final issuedAt = DateTime.now().toUtc();
        final payload = utf8.encode(
          json.encode({
            'v': 1,
            'jti': 'roundtrip',
            'terminal': DeveloperAccess.terminalId,
            'issuedAt': issuedAt.toIso8601String(),
            'expiresAt': issuedAt
                .add(const Duration(hours: 1))
                .toIso8601String(),
          }),
        );
        final signature = await algorithm.sign(payload, keyPair: keyPair);
        final token =
            '${base64Url.encode(payload)}.${base64Url.encode(signature.bytes)}';

        final result = await DeveloperAccess.unlock(token);

        expect(result.isSuccess, isTrue);
        expect(DeveloperAccess.grantedScopes, DeveloperScope.all);
      } finally {
        DeveloperAccess.resetForTest();
        await DatabaseCore.settingsBox?.deleteFromDisk();
        DatabaseCore.settingsBox = null;
        await Hive.close();
        await tempDir.delete(recursive: true);
      }
    },
    skip: keyFile.existsSync() ? false : 'no private key on this machine',
  );
}
