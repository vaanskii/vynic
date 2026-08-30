import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/security/developer_access.dart';

/// The developer panel is the one place in the app where the user is assumed
/// hostile — the venue owns the machine and has every reason to poke at the
/// tools they were not sold. These pin the checks that stand between a curious
/// manager and the wipe button.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Ed25519 algorithm;
  late SimpleKeyPair signingKey;

  setUpAll(() async {
    algorithm = Ed25519();
    signingKey = await algorithm.newKeyPair();
    final publicKey = await signingKey.extractPublicKey();
    DeveloperAccess.publicKeyOverride = base64Url.encode(publicKey.bytes);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dev_access_test');
    Hive.init(tempDir.path);
    DatabaseCore.settingsBox = await Hive.openBox('settings_dev_access_test');
    DeveloperAccess.resetForTest();
  });

  tearDown(() async {
    await DatabaseCore.settingsBox?.deleteFromDisk();
    DatabaseCore.settingsBox = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<String> signToken({
    String? terminal,
    Duration validFor = const Duration(hours: 8),
    Duration issuedAgo = Duration.zero,
    List<String>? scopes,
    SimpleKeyPair? withKey,
  }) async {
    final issuedAt = DateTime.now().toUtc().subtract(issuedAgo);
    final payload = <String, dynamic>{
      'v': 1,
      'jti': 'test-${issuedAt.microsecondsSinceEpoch}',
      'terminal': terminal ?? DeveloperAccess.terminalId,
      'issuedAt': issuedAt.toIso8601String(),
      'expiresAt': issuedAt.add(validFor).toIso8601String(),
      if (scopes != null) 'scopes': scopes,
    };
    final bytes = utf8.encode(json.encode(payload));
    final signature = await algorithm.sign(
      bytes,
      keyPair: withKey ?? signingKey,
    );
    return '${base64Url.encode(bytes)}.${base64Url.encode(signature.bytes)}';
  }

  test('a token signed by the Vynic key unlocks the panel', () async {
    final result = await DeveloperAccess.unlock(await signToken());

    expect(result.isSuccess, isTrue);
    expect(DeveloperAccess.isUnlocked, isTrue);
    expect(DeveloperAccess.can(DeveloperScope.wipe), isTrue);
  });

  test('a token signed by any other key is rejected', () async {
    final impostor = await algorithm.newKeyPair();
    final result = await DeveloperAccess.unlock(
      await signToken(withKey: impostor),
    );

    expect(result.failure, DeveloperUnlockFailure.badSignature);
    expect(DeveloperAccess.isUnlocked, isFalse);
  });

  test('editing the payload invalidates the signature', () async {
    // The whole point of signing: a token whose scopes have been widened by
    // hand no longer verifies, so there is nothing to gain from reading one.
    final token = await signToken(scopes: [DeveloperScope.diagnostics]);
    final parts = token.split('.');
    final payload =
        json.decode(utf8.decode(base64Url.decode(parts.first)))
            as Map<String, dynamic>;
    payload['scopes'] = DeveloperScope.all;
    final tampered =
        '${base64Url.encode(utf8.encode(json.encode(payload)))}.${parts.last}';

    final result = await DeveloperAccess.unlock(tampered);

    expect(result.failure, DeveloperUnlockFailure.badSignature);
  });

  test('a token for another terminal is rejected', () async {
    final result = await DeveloperAccess.unlock(
      await signToken(terminal: 'some-other-venues-terminal'),
    );

    expect(result.failure, DeveloperUnlockFailure.wrongTerminal);
  });

  test("a wildcard token opens any terminal", () async {
    final result = await DeveloperAccess.unlock(await signToken(terminal: '*'));

    expect(result.isSuccess, isTrue);
  });

  test('an expired token is rejected', () async {
    final result = await DeveloperAccess.unlock(
      await signToken(
        validFor: const Duration(hours: 1),
        issuedAgo: const Duration(hours: 3),
      ),
    );

    expect(result.failure, DeveloperUnlockFailure.expired);
  });

  test('a narrow token cannot reach the tools it was not issued for', () async {
    await DeveloperAccess.unlock(
      await signToken(scopes: [DeveloperScope.diagnostics]),
    );

    expect(DeveloperAccess.can(DeveloperScope.diagnostics), isTrue);
    expect(DeveloperAccess.can(DeveloperScope.wipe), isFalse);
    expect(DeveloperAccess.can(DeveloperScope.restore), isFalse);
  });

  test(
    'winding the machine clock back does not revive an expired token',
    () async {
      // A POS sitting offline in a restaurant has an editable clock, so expiry
      // is floored at the latest time the terminal has ever observed.
      final future = DateTime.now().toUtc().add(const Duration(days: 30));
      await DatabaseCore.settingsBox!.put(
        'developerClockHighWater',
        future.toIso8601String(),
      );

      final result = await DeveloperAccess.unlock(
        await signToken(validFor: const Duration(hours: 8)),
      );

      expect(result.failure, DeveloperUnlockFailure.expired);
      expect(
        DeveloperAccess.effectiveNowForTest().isAfter(DateTime.now().toUtc()),
        isTrue,
      );
    },
  );

  test('garbage in the field is rejected without throwing', () async {
    for (final junk in const ['', 'nonsense', 'a.b', 'not-base64.@@@@']) {
      final result = await DeveloperAccess.unlock(junk);
      expect(result.isSuccess, isFalse, reason: junk);
    }
  });

  test('locking clears the session', () async {
    await DeveloperAccess.unlock(await signToken());
    expect(DeveloperAccess.isUnlocked, isTrue);

    DeveloperAccess.lock();

    expect(DeveloperAccess.isUnlocked, isFalse);
    expect(DeveloperAccess.can(DeveloperScope.diagnostics), isFalse);
  });

  test('the terminal id is stable across reads', () {
    final first = DeveloperAccess.terminalId;
    expect(DeveloperAccess.terminalId, first);
    expect(DeveloperAccess.terminalIdShort, first);
  });

  test('the terminal id carries the venue name and stays short', () async {
    // The id gets read down a phone line. A UUID was unique and unusable.
    await DatabaseCore.settingsBox!.put('venueName', 'Kaprisi');
    DeveloperAccess.resetForTest();

    final id = DeveloperAccess.terminalId;

    expect(id, startsWith('KAPRISI-'));
    expect(id.length, 'KAPRISI-'.length + 5);
    expect(RegExp(r'^[0-9A-Z-]+$').hasMatch(id), isTrue);
  });

  test('a venue name that survives no transliteration still gets an id', () {
    // Georgian reduces to nothing under the slug rules. The random half alone
    // is still a perfectly good identifier — it just loses the mnemonic.
    DatabaseCore.settingsBox!.put('venueName', 'კაპრისი');
    DeveloperAccess.resetForTest();

    expect(DeveloperAccess.terminalId.length, 5);
  });

  test('a long venue name is capped', () {
    DatabaseCore.settingsBox!.put(
      'venueName',
      'The Extremely Long Restaurant Name Company',
    );
    DeveloperAccess.resetForTest();

    expect(DeveloperAccess.terminalId.length, 10 + 1 + 5);
  });

  test('the id does not move when the venue is renamed', () async {
    await DatabaseCore.settingsBox!.put('venueName', 'First');
    DeveloperAccess.resetForTest();
    final original = DeveloperAccess.terminalId;
    await DeveloperAccess.persistTerminalId();

    await DatabaseCore.settingsBox!.put('venueName', 'Second');
    DeveloperAccess.resetForTest();

    // Tokens are already signed against the original; an id that followed a
    // rename would silently invalidate every one of them.
    expect(DeveloperAccess.terminalId, original);
  });
}
