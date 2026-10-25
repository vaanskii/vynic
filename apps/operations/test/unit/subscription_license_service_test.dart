import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/licensing/subscription_license.dart';
import 'package:vynic/core/services/licensing/license_continuity.dart';

class MemoryVault extends LicenseVault {
  final records = <String, String>{};
  final writes = <String>[];
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? readGate;
  Completer<void>? readReady;
  Completer<void>? writeGate;
  Completer<void>? writeReady;
  @override
  Future<String?> read(String account) async {
    if (failRead) throw StateError('synthetic locked vault');
    final value = records[account];
    readReady?.complete();
    await readGate?.future;
    return value;
  }

  @override
  Future<void> write(String account, String value) async {
    if (failWrite) throw StateError('synthetic full vault');
    writeReady?.complete();
    final gate = writeGate;
    writeReady = null;
    writeGate = null;
    await gate?.future;
    writes.add(value);
    records[account] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SimpleKeyPair key;
  late String trustedKey;
  late SubscriptionLicense license;
  late MockClient client;
  int elapsed = 1000;
  int wallOffset = 0;
  String boot = 'boot-one';
  bool clockUnavailable = false;
  int leaseDurationMs = 86400000;
  int clockReads = 0;
  void Function(int)? onClockRead;
  late MemoryVault vault;
  SubscriptionLicense makeLicense() => SubscriptionLicense(
    client: client,
    continuity: () async {
      if (clockUnavailable) throw StateError('synthetic clock failure');
      onClockRead?.call(++clockReads);
      return LicenseClockSample(elapsed, boot);
    },
    wallClock: () => 1800000000000 + elapsed + wallOffset,
    vault: vault,
    trustedKey: trustedKey,
  );
  Future<void> restart() async {
    license.dispose();
    license = makeLicense();
    await license.start();
    while (license.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  String mode = 'VALID';
  Map<String, dynamic>? oldEnvelope;
  final nonces = <String>[];
  Completer<void>? responseGate;
  Completer<void>? responseReady;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vynic-license-fixture-');
    Hive.init(directory.path);
    DatabaseCore.settingsBox = await Hive.openBox('license-fixture');
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.saveEnrollment(
      rawCredential:
          'vynic-device-v1.00000000-0000-4000-8000-000000000001.test-only-000000000000000000000000',
      venueId: 'fixture-venue',
      venueName: 'Fixture',
    );
    key = await Ed25519().newKeyPair();
    trustedKey = base64Encode((await key.extractPublicKey()).bytes);
    elapsed = 1000;
    wallOffset = 0;
    boot = 'boot-one';
    clockUnavailable = false;
    leaseDurationMs = 86400000;
    clockReads = 0;
    onClockRead = null;
    vault = MemoryVault();
    mode = 'VALID';
    oldEnvelope = null;
    nonces.clear();
    responseGate = null;
    responseReady = null;
    client = MockClient((request) async {
      expect(request.url.path, '/edge/subscription-lease');
      expect(
        request.headers['X-POS-Sync-Key'],
        EdgeDeviceCredentialStore.credential,
      );
      final nonce = jsonDecode(request.body)['nonce'] as String;
      nonces.add(nonce);
      if (mode == 'OUTAGE') throw const SocketException('synthetic outage');
      if (mode == 'DENIED') return http.Response('{}', 401);
      if (mode == 'REPLAY') return http.Response(jsonEncode(oldEnvelope), 200);
      final now = DateTime.now().millisecondsSinceEpoch;
      final bytes = utf8.encode(
        jsonEncode({
          'version': 1,
          'nonce': nonce,
          'deviceId': EdgeDeviceCredentialStore.deviceId,
          'venueId': EdgeDeviceCredentialStore.venueId,
          'installationId': EdgeDeviceCredentialStore.installationId,
          'issuedAt': now,
          'deadline': mode == 'VALID' ? now + leaseDurationMs : now,
          'entitlementEndsAt': now + leaseDurationMs,
          'kind': 'TRIAL',
          'status': mode,
        }),
      );
      final envelope = {
        'payload': base64Encode(bytes),
        'signature': base64Encode(
          (await Ed25519().sign(bytes, keyPair: key)).bytes,
        ),
      };
      oldEnvelope ??= envelope;
      responseReady?.complete();
      await responseGate?.future;
      return http.Response(jsonEncode(envelope), 200);
    });
    license = makeLicense()..enabled = true;
  });
  tearDown(() async {
    license.dispose();
    client.close();
    await Hive.close();
    DatabaseCore.settingsBox = null;
    EdgeDeviceCredentialStore.resetForTest();
    await directory.delete(recursive: true);
  });
  Future<void> delayedResponse({
    required int elapsedAdvance,
    int wallAdjustment = 0,
    Future<void> Function()? whilePending,
  }) async {
    responseReady = Completer<void>();
    responseGate = Completer<void>();
    final checking = license.verify();
    await responseReady!.future; // The signed response already exists.
    elapsed += elapsedAdvance;
    wallOffset += wallAdjustment;
    await whilePending?.call();
    responseGate!.complete();
    await checking;
    responseReady = null;
    responseGate = null;
  }

  test(
    'pending response across VM pause never installs a stale lease',
    () async {
      leaseDurationMs = 120000;
      await delayedResponse(elapsedAdvance: 1000, wallAdjustment: 180000);
      expect(license.lease.reason, 'VERIFICATION_REQUIRED');
      expect(
        jsonDecode(vault.records.values.single)['reason'],
        'VERIFICATION_REQUIRED',
      );
      await expectLater(license.requireSale(), throwsStateError);
      // Restoring the wall clock, restarting, and replaying the old signed
      // response cannot erase the protected denial or renew the original anchor.
      wallOffset = 0;
      mode = 'OUTAGE';
      await restart();
      expect(license.lease.allowed, false);
      mode = 'REPLAY';
      await license.verify();
      expect(license.lease.allowed, false);
      mode = 'VALID';
      await license.verify();
      expect(license.lease.allowed, true);
      expect(license.lease.remainingMs, leaseDurationMs);
    },
  );
  test('paused renewal cannot replace an existing valid anchor', () async {
    await license.verify();
    await delayedResponse(elapsedAdvance: 1000, wallAdjustment: 180000);
    expect(license.lease.reason, 'VERIFICATION_REQUIRED');
    expect(jsonDecode(vault.records.values.single)['lease'], isNull);
  });
  test(
    'negative request-time clock adjustment requires verification',
    () async {
      await delayedResponse(elapsedAdvance: 1000, wallAdjustment: -60000);
      expect(license.lease.reason, 'VERIFICATION_REQUIRED');
      expect(
        jsonDecode(vault.records.values.single)['reason'],
        'VERIFICATION_REQUIRED',
      );
    },
  );
  for (final delay in [5000, 10000]) {
    test(
      'bounded network/sleep delay ${delay}ms consumes lease time',
      () async {
        await delayedResponse(elapsedAdvance: delay);
        expect(license.lease.allowed, true);
        expect(license.lease.remainingMs, leaseDurationMs - delay);
        final saved = Map<String, String>.from(vault.records);
        mode = 'OUTAGE';
        elapsed += 5000;
        await restart();
        expect(license.lease.allowed, true);
        expect(license.lease.remainingMs, leaseDurationMs - delay - 5000);
        expect(vault.records, saved);
      },
    );
  }
  test('long suspend-aware request exceeds existing transit bound', () async {
    await delayedResponse(elapsedAdvance: 40000);
    expect(license.lease.allowed, false);
    expect(vault.records, isEmpty);
  });
  test(
    'commercial cutoff reached during normal transit stays expired',
    () async {
      leaseDurationMs = 2000;
      await delayedResponse(elapsedAdvance: 3000);
      expect(license.lease.reason, 'EXPIRED');
      expect(jsonDecode(vault.records.values.single)['reason'], 'EXPIRED');
    },
  );
  for (final denied in ['REVOKED', 'EXPIRED']) {
    test('request drift cannot clear an existing $denied decision', () async {
      mode = denied;
      await license.verify();
      mode = 'VALID';
      await delayedResponse(elapsedAdvance: 1000, wallAdjustment: 180000);
      expect(license.lease.reason, denied);
      expect(jsonDecode(vault.records.values.single)['reason'], denied);
      mode = 'OUTAGE';
      wallOffset = 0;
      await restart();
      expect(license.lease.reason, denied);
    });
    test('signed $denied response survives request wall drift', () async {
      mode = denied;
      await delayedResponse(elapsedAdvance: 1000, wallAdjustment: 180000);
      expect(license.lease.reason, denied);
      expect(jsonDecode(vault.records.values.single)['reason'], denied);
    });
  }
  test('concurrent auth denial wins over paused positive response', () async {
    await delayedResponse(
      elapsedAdvance: 1000,
      wallAdjustment: 180000,
      whilePending: license.authenticationDenied,
    );
    expect(license.lease.reason, 'REVOKED');
    expect(jsonDecode(vault.records.values.single)['reason'], 'REVOKED');
  });
  test(
    'continuity guard also brackets asynchronous signature verification',
    () async {
      onClockRead = (read) {
        if (read == 3) {
          elapsed += 1000;
          wallOffset += 180000;
        }
      };
      await license.verify();
      expect(license.lease.reason, 'VERIFICATION_REQUIRED');
      expect(jsonDecode(vault.records.values.single)['lease'], isNull);
      expect(
        vault.writes.map((value) => jsonDecode(value)['lease']),
        everyElement(isNull),
      );
    },
  );
  test('boot change after response cannot persist a positive lease', () async {
    onClockRead = (read) {
      if (read == 3) boot = 'boot-two';
    };
    await license.verify();
    expect(license.lease.reason, 'VERIFICATION_REQUIRED');
    expect(
      vault.writes.map((value) => jsonDecode(value)['lease']),
      everyElement(isNull),
    );
  });
  test(
    'expiry during signature verification persists only an expired decision',
    () async {
      leaseDurationMs = 2000;
      onClockRead = (read) {
        if (read == 3) elapsed += 3000;
      };
      await license.verify();
      expect(license.lease.reason, 'EXPIRED');
      expect(jsonDecode(vault.records.values.single)['reason'], 'EXPIRED');
      expect(
        vault.writes.map((value) => jsonDecode(value)['lease']),
        everyElement(isNull),
      );
    },
  );
  test(
    'outage preserves valid lease, reconnect renews with a fresh challenge',
    () async {
      await license.verify();
      expect(license.lease.allowed, true);
      elapsed += 3600000;
      mode = 'OUTAGE';
      await license.verify();
      expect(license.lease.allowed, true);
      expect(license.offline, true);
      expect(license.lease.remainingMs, 82800000);
      mode = 'VALID';
      await license.verify();
      expect(license.lease.allowed, true);
      expect(license.lease.remainingMs, 86400000);
      expect(nonces.toSet().length, nonces.length);
    },
  );
  test(
    'confirmed denial survives outage, replay, restart and portable backup boundary',
    () async {
      await license.verify();
      mode = 'DENIED';
      await license.verify();
      expect(license.lease.reason, 'REVOKED');
      mode = 'REPLAY';
      await license.verify();
      expect(license.lease.reason, 'REVOKED');
      mode = 'OUTAGE';
      await license.verify();
      expect(license.lease.reason, 'REVOKED');
      expect(
        PosBackupFormat.deviceSettings,
        containsAll(['subscriptionLicenseDenial', 'subscriptionLicenseBills']),
      );
      // Restore an old restaurant settings file; the protected denial wins.
      await DatabaseCore.settingsBox!.delete('subscriptionLicenseDenial');
      await restart();
      expect(license.lease.reason, 'REVOKED');
      mode = 'VALID';
      await license.verify();
      expect(license.lease.allowed, true);
      expect(
        DatabaseCore.settingsBox!.get('subscriptionLicenseDenial'),
        isNull,
      );
    },
  );
  test('restarted process cannot use an old successful envelope', () async {
    await license.verify();
    license.dispose();
    mode = 'REPLAY';
    license = makeLicense()..enabled = true;
    await license.verify();
    expect(license.lease.allowed, false);
    expect(license.lease.reason, 'VERIFICATION_REQUIRED');
  });
  test(
    'same boot restart during outage preserves original deadline including suspend',
    () async {
      await license.verify();
      final original = Map<String, String>.from(vault.records);
      elapsed += 3600000; // closed application / simulated suspended OS
      mode = 'OUTAGE';
      await restart();
      expect(license.lease.allowed, true);
      expect(license.lease.remainingMs, 82800000);
      expect(vault.records, original); // restart does not rewrite an anchor
      await license.requireSale();
      elapsed += 3600000;
      await restart();
      expect(license.lease.remainingMs, 79200000);
      mode = 'REPLAY';
      await license.verify();
      expect(license.lease.remainingMs, 79200000);
      mode = 'VALID';
      await license.verify();
      expect(license.lease.remainingMs, 86400000);
    },
  );
  for (final fault in [
    'reboot',
    'elapsed reset',
    'wall rollback',
    'wall forward / paused guest clock',
    'missing',
    'malformed',
    'binding',
    'signature',
    'anchor',
    'locked',
    'pin',
  ]) {
    test(
      'restart refuses $fault without renewing or mislabeling unpaid',
      () async {
        await license.verify();
        mode = 'OUTAGE';
        elapsed += 3600000;
        if (fault == 'reboot') boot = 'boot-two';
        if (fault == 'elapsed reset') elapsed = 1;
        if (fault == 'wall rollback') wallOffset = -60000;
        if (fault == 'wall forward / paused guest clock') wallOffset = 62381;
        if (fault == 'missing') vault.records.clear();
        if (fault == 'malformed') vault.records.updateAll((_, __) => '{');
        if (fault == 'locked') vault.failRead = true;
        if (fault == 'pin') trustedKey = base64Encode(List.filled(32, 0));
        if (['binding', 'signature', 'anchor'].contains(fault)) {
          vault.records.updateAll((_, raw) {
            final record = jsonDecode(raw);
            if (fault == 'binding') record['binding'] = 'other-installation';
            if (fault == 'signature')
              record['lease']['envelope']['signature'] = base64Encode(
                List.filled(64, 0),
              );
            if (fault == 'anchor')
              record['lease']['requestElapsed'] = elapsed + 1;
            return jsonEncode(record);
          });
        }
        await restart();
        expect(license.lease.reason, 'VERIFICATION_REQUIRED');
        await expectLater(license.requireSale(), throwsStateError);
      },
    );
  }
  test(
    'guest pause denial survives restart until fresh online verification',
    () async {
      await license.verify();
      elapsed += 74266;
      wallOffset = 62381;
      mode = 'OUTAGE';
      await license.check();
      expect(license.lease.reason, 'VERIFICATION_REQUIRED');
      wallOffset = 0;
      await restart();
      await expectLater(license.requireSale(), throwsStateError);
      mode = 'VALID';
      await license.verify();
      expect(license.lease.allowed, true);
    },
  );
  test(
    'expiry while closed is retained and cannot be undone by restoring wall time',
    () async {
      await license.verify();
      elapsed += 86400001;
      mode = 'OUTAGE';
      await restart();
      expect(license.lease.reason, 'EXPIRED');
      elapsed = 2000;
      await DatabaseCore.settingsBox!.clear();
      await restart();
      expect(license.lease.reason, 'EXPIRED');
    },
  );
  test(
    'rollback observed during operation leaves a protected sticky restriction',
    () async {
      await license.verify();
      wallOffset = -5000;
      await license.check();
      expect(license.lease.reason, 'VERIFICATION_REQUIRED');
      wallOffset = 0;
      mode = 'OUTAGE';
      await restart();
      expect(license.lease.reason, 'VERIFICATION_REQUIRED');
      mode = 'VALID';
      await license.verify();
      expect(license.lease.allowed, true);
    },
  );
  test('failed positive anchor write never admits a new session', () async {
    vault.failWrite = true;
    await license.verify();
    expect(license.lease.allowed, false);
    expect(license.error, 'VERIFICATION_UNAVAILABLE');
  });
  test(
    'signed revocation restricts even when protected storage is unavailable',
    () async {
      await license.verify();
      vault.failWrite = true;
      mode = 'REVOKED';
      await license.verify();
      expect(license.lease.reason, 'REVOKED');
      expect(license.error, 'CONTINUITY_STORAGE_UNAVAILABLE');
      mode = 'OUTAGE';
      await restart();
      expect(license.lease.reason, 'REVOKED');
    },
  );
  test('denial wins over an in-flight protected positive write', () async {
    await license.verify();
    final ready = Completer<void>();
    final release = Completer<void>();
    vault.writeReady = ready;
    vault.writeGate = release;
    final verification = license.verify();
    await ready.future;
    final denied = license.authenticationDenied();
    release.complete();
    await Future.wait([verification, denied]);
    expect(license.lease.reason, 'REVOKED');
    expect(jsonDecode(vault.records.values.single)['reason'], 'REVOKED');
    mode = 'OUTAGE';
    await restart();
    expect(license.lease.reason, 'REVOKED');
  });
  test(
    'received revocation supersedes a cached positive read during startup',
    () async {
      await license.verify();
      license.dispose();
      license = makeLicense();
      mode = 'OUTAGE';
      vault.readReady = Completer<void>();
      vault.readGate = Completer<void>();
      final starting = license.start();
      await vault.readReady!.future;
      await license.authenticationDenied();
      vault.readGate!.complete();
      await starting;
      while (license.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(license.lease.reason, 'REVOKED');
      expect(jsonDecode(vault.records.values.single)['reason'], 'REVOKED');
    },
  );
  test(
    'missing clock never relabels received revocation as a network restriction',
    () async {
      await license.verify();
      await license.authenticationDenied();
      clockUnavailable = true;
      await license.check();
      expect(license.lease.reason, 'REVOKED');
      mode = 'OUTAGE';
      await restart();
      expect(license.lease.reason, 'REVOKED');
    },
  );
  test(
    'clock continuity failure blocks operational action but leaves sync admissible',
    () async {
      await license.verify();
      elapsed = 10;
      await expectLater(
        license.operation('createOrder', () async => 1),
        throwsStateError,
      );
      expect(await license.operation('Runtime features', () async => 2), 2);
      expect(await license.operation('Hive write', () async => 3), 3);
    },
  );
  test(
    'an admitted write finishes through a received restriction; next sale is refused',
    () async {
      await license.verify();
      final result = await license.operation('createOrder', () async {
        license.lease.restrict('REVOKED');
        return license.operation('updateOrder', () async {
          await license.requireSale();
          return 4;
        });
      });
      expect(result, 4);
      await expectLater(
        license.operation('createOrder', () async => 5),
        throwsStateError,
      );
    },
  );
  test(
    'settlement exemption cannot escape into later asynchronous sales',
    () async {
      final release = Completer<void>();
      late Future<void> delayed;
      await license.operation('closeTable', () async {
        delayed = release.future.then(
          (_) => license.operation('createOrder', () async {}),
        );
      });
      final rejected = expectLater(delayed, throwsStateError);
      release.complete();
      await rejected;
    },
  );

  test(
    'runtime auth denial supersedes an older in-flight signed success',
    () async {
      await license.verify();
      responseGate = Completer<void>();
      responseReady = Completer<void>();
      final checking = license.verify();
      await responseReady!.future;
      await license.authenticationDenied();
      responseGate!.complete();
      await checking;
      expect(license.lease.reason, 'REVOKED');
      expect(
        (DatabaseCore.settingsBox!.get('subscriptionLicenseDenial')
            as Map)['reason'],
        'REVOKED',
      );
    },
  );
  test(
    'settlement scope admits only close writes, never new items or reopen',
    () async {
      await license.operation('closeTable', () async {
        expect(await license.operation('saveSaleRecord', () async => 1), 1);
        for (final operation in [
          'createOrder',
          'addItem',
          'restoreClosedOrderFromSale',
          'recordAdvanceReceipt',
          'activate',
          'transferItems',
          'cancelOrder',
        ]) {
          await expectLater(
            license.operation(operation, () async {}),
            throwsStateError,
          );
        }
      });
    },
  );
}
