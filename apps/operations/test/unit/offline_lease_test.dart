import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/licensing/offline_lease.dart';

void main() {
  late SimpleKeyPair key;
  late List<int> publicKey;
  late OfflineLease lease;
  const now = 1800000000000;
  Future<Map<String, String>> signed([
    Map<String, dynamic> changes = const {},
  ]) async {
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'nonce': 'fresh',
        'deviceId': 'device',
        'venueId': 'venue',
        'installationId': 'install',
        'issuedAt': now,
        'deadline': now + OfflineLease.maxDuration,
        'entitlementEndsAt': null,
        'status': 'VALID',
        'kind': 'SUBSCRIPTION',
        ...changes,
      }),
    );
    return {
      'payload': base64Encode(bytes),
      'signature': base64Encode(
        (await Ed25519().sign(bytes, keyPair: key)).bytes,
      ),
    };
  }

  Future<void> accept(
    Object? envelope, {
    String nonce = 'fresh',
    int request = 1000,
    int elapsed = 1100,
  }) => lease.accept(
    envelope,
    publicKey: publicKey,
    nonce: nonce,
    device: 'device',
    venue: 'venue',
    installation: 'install',
    requestElapsed: request,
    elapsed: elapsed,
    wall: now,
  );
  setUp(() async {
    key = await Ed25519().newKeyPair();
    publicKey = (await key.extractPublicKey()).bytes;
    lease = OfflineLease();
  });
  test('valid offline outage expires absolutely including suspend', () async {
    await accept(await signed());
    expect(lease.allowed, true);
    lease.check(
      elapsed: 1000 + OfflineLease.maxDuration - 1,
      wall: now + OfflineLease.maxDuration - 1,
    );
    expect(lease.allowed, true);
    lease.check(
      elapsed: 1000 + OfflineLease.maxDuration,
      wall: now + OfflineLease.maxDuration,
    );
    expect(lease.reason, 'VERIFICATION_REQUIRED');
  });
  for (final kind in ['TRIAL', 'SUBSCRIPTION']) {
    test(
      '$kind absolute cutoff is expired, not connectivity failure',
      () async {
        await accept(
          await signed({
            'kind': kind,
            'entitlementEndsAt': now + 2000,
            'deadline': now + 2000,
          }),
        );
        lease.check(elapsed: 3000, wall: now + 2000);
        expect(lease.reason, 'EXPIRED');
      },
    );
  }
  for (final pair in {
    'deviceId': 'other',
    'venueId': 'other',
    'installationId': 'other',
    'nonce': 'old',
    'version': 2,
    'deadline': now + OfflineLease.maxDuration + 1,
    'issuedAt': 'bad',
  }.entries) {
    test('rejects ${pair.key} mismatch/malformed', () async {
      await expectLater(
        accept(await signed({pair.key: pair.value})),
        throwsFormatException,
      );
      expect(lease.allowed, false);
    });
  }
  test('tampering and malformed envelope fail signature validation', () async {
    final envelope = await signed();
    envelope['payload'] = base64Encode(utf8.encode('{}'));
    await expectLater(accept(envelope), throwsFormatException);
    await expectLater(accept({'payload': 4}), throwsFormatException);
  });
  test(
    'signed overlong entitlement cutoff and delayed responses are refused',
    () async {
      await expectLater(
        accept(await signed({'entitlementEndsAt': now + 500})),
        throwsFormatException,
      );
      await expectLater(
        accept(await signed(), elapsed: 40000),
        throwsFormatException,
      );
    },
  );
  test('clock rollback sticks until fresh online validation', () async {
    await accept(await signed());
    lease.check(elapsed: 1200, wall: now - 5000);
    expect(lease.allowed, false);
    lease.check(elapsed: 1300, wall: now + 5000);
    expect(lease.allowed, false);
    await accept(
      await signed({'nonce': 'new'}),
      nonce: 'new',
      request: 1300,
      elapsed: 1400,
    );
    expect(lease.allowed, true);
  });
  test('measured VM suspension cannot extend a signed cutoff', () async {
    await accept(
      await signed({
        'deadline': now + 120000,
        'entitlementEndsAt': now + 120000,
      }),
    );
    final saved = lease.checkpoint();
    // Actual QA measurement: host/wall advanced 136647ms, guest only 74266ms.
    lease.check(elapsed: 1100 + 74266, wall: now + 136647);
    expect(lease.reason, 'VERIFICATION_REQUIRED');
    final restored = OfflineLease();
    await restored.restore(
      saved,
      publicKey: publicKey,
      device: 'device',
      venue: 'venue',
      installation: 'install',
      elapsed: 1100 + 74266,
      wall: now + 136647,
    );
    expect(restored.reason, 'VERIFICATION_REQUIRED');
  });
  test('small cumulative forward drift cannot reset the tolerance', () async {
    await accept(await signed());
    for (var i = 1; i <= 2; i++) {
      lease.check(elapsed: 1100 + i * 1000, wall: now + i * 2000);
      expect(lease.allowed, true);
    }
    lease.check(elapsed: 4100, wall: now + 6000);
    expect(lease.reason, 'VERIFICATION_REQUIRED');
  });
  test('elapsed reset, restart, reboot and reinstall cannot renew', () async {
    await accept(await signed());
    lease.check(elapsed: 500, wall: now);
    expect(lease.allowed, false);
    lease = OfflineLease();
    expect(lease.allowed, false);
    await expectLater(
      accept(await signed(), nonce: 'new-process'),
      throwsFormatException,
    );
  });
  test(
    'received revocation remains on later outage and old response replay',
    () async {
      final old = await signed();
      await accept(await signed({'status': 'REVOKED', 'deadline': now}));
      expect(lease.reason, 'REVOKED');
      lease.check(elapsed: 999999, wall: now + 999999);
      expect(lease.reason, 'REVOKED');
      await expectLater(accept(old, nonce: 'new'), throwsFormatException);
      expect(lease.reason, 'REVOKED');
    },
  );
  test('renewal uses the new server time and fresh nonce', () async {
    await accept(await signed());
    await accept(
      await signed({
        'nonce': 'new',
        'issuedAt': now + 1000,
        'deadline': now + 1000 + OfflineLease.maxDuration,
      }),
      nonce: 'new',
      request: 2000,
      elapsed: 2100,
    );
    expect(lease.remainingMs, OfflineLease.maxDuration - 100);
  });
  for (final kind in ['TRIAL', 'SUBSCRIPTION']) {
    test('$kind restored lease keeps the original commercial cutoff', () async {
      await accept(
        await signed({
          'kind': kind,
          'entitlementEndsAt': now + 5000,
          'deadline': now + 5000,
        }),
      );
      final saved = lease.checkpoint();
      final restored = OfflineLease();
      await restored.restore(
        saved,
        publicKey: publicKey,
        device: 'device',
        venue: 'venue',
        installation: 'install',
        elapsed: 6000,
        wall: now + 5000,
      );
      expect(restored.reason, 'EXPIRED');
      expect(restored.kind, kind);
    });
  }
  for (final binding in ['device', 'venue', 'installation']) {
    test('restored signed lease rejects changed $binding', () async {
      await accept(await signed());
      final restored = OfflineLease();
      await expectLater(
        restored.restore(
          lease.checkpoint(),
          publicKey: publicKey,
          device: binding == 'device' ? 'other' : 'device',
          venue: binding == 'venue' ? 'other' : 'venue',
          installation: binding == 'installation' ? 'other' : 'install',
          elapsed: 2000,
          wall: now + 900,
        ),
        throwsFormatException,
      );
      expect(restored.allowed, false);
    });
  }
  test(
    'restore counts time closed without accepting a new request transit anchor',
    () async {
      await accept(await signed());
      final saved = lease.checkpoint();
      final restored = OfflineLease();
      await restored.restore(
        saved,
        publicKey: publicKey,
        device: 'device',
        venue: 'venue',
        installation: 'install',
        elapsed: 3601100,
        wall: now + 3600000,
      );
      expect(restored.remainingMs, OfflineLease.maxDuration - 3600100);
      expect(restored.checkpoint()['requestElapsed'], 1000);
      final again = OfflineLease();
      await again.restore(
        restored.checkpoint(),
        publicKey: publicKey,
        device: 'device',
        venue: 'venue',
        installation: 'install',
        elapsed: 7201100,
        wall: now + 7200000,
      );
      expect(again.remainingMs, OfflineLease.maxDuration - 7200100);
    },
  );
}
