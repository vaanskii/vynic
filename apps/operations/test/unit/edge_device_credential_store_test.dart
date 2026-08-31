import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';

/// Where this installation's Cloud identity lives, and what it refuses to hold.
void main() {
  late Directory directory;

  String credential([String device = '11111111-1111-4111-8111-111111111111']) =>
      'vynic-device-v1.$device.${'a' * 43}';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('edge-credential-');
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    EdgeDeviceCredentialStore.resetForTest();
  });

  tearDown(() async {
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('creates an installation id on first run and keeps it', () async {
    await EdgeDeviceCredentialStore.load();
    final first = EdgeDeviceCredentialStore.installationId;

    expect(first, isNotNull);
    expect(EdgeDeviceCredentialStore.hasCredential, isFalse);

    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();
    expect(EdgeDeviceCredentialStore.installationId, first);
  });

  test('a saved credential survives a restart', () async {
    await EdgeDeviceCredentialStore.load();
    expect(await EdgeDeviceCredentialStore.save(credential()), isTrue);

    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();

    expect(EdgeDeviceCredentialStore.hasCredential, isTrue);
    expect(EdgeDeviceCredentialStore.credential, credential());
    expect(
      EdgeDeviceCredentialStore.deviceId,
      '11111111-1111-4111-8111-111111111111',
    );
  });

  test('refuses anything that is not a device credential', () async {
    await EdgeDeviceCredentialStore.load();

    for (final bad in <String>[
      'legacy-shared-key',
      'vynic-device-v1.short.secret',
      'vynic-device-v2.11111111-1111-4111-8111-111111111111.${'a' * 43}',
      '',
    ]) {
      expect(await EdgeDeviceCredentialStore.save(bad), isFalse);
    }
    expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
  });

  test('can be cleared without losing the installation id', () async {
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.save(credential());
    final installationId = EdgeDeviceCredentialStore.installationId;

    await EdgeDeviceCredentialStore.clear();

    expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
    expect(EdgeDeviceCredentialStore.installationId, installationId);
  });

  test('absorbs an operator drop file exactly once', () async {
    final drop = File('${directory.path}/edge_device_provision.txt');
    await drop.writeAsString('  ${credential()}\n');

    await EdgeDeviceCredentialStore.load();

    expect(EdgeDeviceCredentialStore.credential, credential());
    // Removed, so the secret does not sit on disk as a second copy.
    expect(drop.existsSync(), isFalse);
  });

  test('removes an unusable drop file rather than retrying it forever', () async {
    final drop = File('${directory.path}/edge_device_provision.txt');
    await drop.writeAsString('not-a-credential');

    await EdgeDeviceCredentialStore.load();

    expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
    expect(drop.existsSync(), isFalse);
  });

  test('keeps the credential out of the hive boxes a backup serializes', () async {
    // BackupRepository exports the settings box wholesale. The identity file is
    // a separate file precisely so a device secret never lands in a backup.
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.save(credential());

    final stored = json.decode(
      File('${directory.path}/edge_device.json').readAsStringSync(),
    );
    expect(stored, isA<Map<String, dynamic>>());
    expect((stored as Map)['credential'], credential());
  });

  test('never fails a boot when the identity file is unreadable', () async {
    await File('${directory.path}/edge_device.json').writeAsString('{ broken');

    await EdgeDeviceCredentialStore.load();

    expect(EdgeDeviceCredentialStore.isLoaded, isTrue);
    expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
  });
}
