import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic_devtool/src/signing_key.dart';
import 'package:vynic_devtool/src/token_signer.dart';

/// The signing logic here is a second implementation of what the POS verifies.
/// Two implementations drift, so these pin the wire format: a token this tool
/// produces has to satisfy the same checks `DeveloperAccess.unlock` runs.
void main() {
  late Ed25519 algorithm;
  late SigningKey key;

  setUpAll(() async {
    algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    key = SigningKey(
      keyPair: keyPair,
      publicKeyBase64: base64Url.encode(publicKey.bytes),
      sourcePath: 'test',
    );
  });

  Future<Map<String, dynamic>> payloadOf(SignedToken token) async {
    final parts = token.value.split('.');
    return json.decode(utf8.decode(base64Url.decode(parts[0])))
        as Map<String, dynamic>;
  }

  test('a signed token verifies against its own public key', () async {
    final token = await TokenSigner.sign(
      key: key,
      terminal: 'abc-123',
      validFor: const Duration(hours: 8),
    );

    final parts = token.value.split('.');
    final verified = await algorithm.verify(
      base64Url.decode(parts[0]),
      signature: Signature(
        base64Url.decode(parts[1]),
        publicKey: await key.keyPair.extractPublicKey(),
      ),
    );

    expect(verified, isTrue);
  });

  test('the payload carries every field the POS reads', () async {
    final token = await TokenSigner.sign(
      key: key,
      terminal: 'abc-123',
      validFor: const Duration(hours: 8),
    );
    final payload = await payloadOf(token);

    expect(payload['v'], 1);
    expect(payload['terminal'], 'abc-123');
    expect(payload['jti'], isNotEmpty);
    expect(DateTime.tryParse(payload['issuedAt'] as String), isNotNull);
    expect(DateTime.tryParse(payload['expiresAt'] as String), isNotNull);
  });

  test(
    'a full grant omits scopes, which the POS reads as everything',
    () async {
      final token = await TokenSigner.sign(
        key: key,
        terminal: 'abc-123',
        validFor: const Duration(hours: 8),
      );

      expect((await payloadOf(token)).containsKey('scopes'), isFalse);
    },
  );

  test('a narrowed grant writes the scopes it kept', () async {
    final token = await TokenSigner.sign(
      key: key,
      terminal: 'abc-123',
      validFor: const Duration(hours: 2),
      scopes: const [TokenScope.diagnostics, TokenScope.errors],
    );

    expect(
      (await payloadOf(token))['scopes'],
      containsAll(<String>[TokenScope.diagnostics, TokenScope.errors]),
    );
  });

  test('a master token is bound to the wildcard terminal', () async {
    final token = await TokenSigner.sign(
      key: key,
      terminal: kAnyTerminal,
      validFor: const Duration(days: 90),
    );

    expect(token.isMasterKey, isTrue);
    expect((await payloadOf(token))['terminal'], '*');
    expect(token.suggestedFileName, contains('master'));
  });

  test('a key that is not the shipped one is flagged', () async {
    expect(key.matchesShippedBuild, isFalse);

    final shipped = SigningKey(
      keyPair: key.keyPair,
      publicKeyBase64: kShippedPublicKeyBase64,
      sourcePath: 'test',
    );
    expect(shipped.matchesShippedBuild, isTrue);
  });
}
