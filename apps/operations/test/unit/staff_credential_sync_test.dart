import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/sync/staff_credential_sync_state.dart';

/// Which staff PINs a POS snapshot carries, and when.
///
/// The behaviour this replaces put `pin` on every staff member of every
/// snapshot, so the server re-derived a bcrypt cost-12 hash per member on a
/// sync that changed no credential at all — about 2.7 seconds for fourteen
/// people. The property that has to hold instead is stated directly below: an
/// acknowledged staff list with no PIN change carries no PIN.
void main() {
  late Directory directory;

  User user(String username, {String pin = '1234', String role = 'waiter'}) =>
      User(username: username, pinCode: pin, role: role);

  /// Acknowledges everything the selection carried, the way an accepted
  /// snapshot leaves the POS.
  Future<void> acceptSnapshot(StaffSnapshotSelection selection) async {
    await StaffCredentialSyncState.markAccepted(selection.credentialsSent);
    await StaffCredentialSyncState.pruneUnknown(selection.knownUsernames);
  }

  bool carriesPin(Map<String, dynamic> entry) => entry.containsKey('pin');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('staff-credential-sync-');
    Hive.init(directory.path);
    await StaffCredentialSyncState.open();
  });

  tearDown(() async {
    await StaffCredentialSyncState.close();
    await Hive.deleteFromDisk();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('a fresh install carries every PIN once', () async {
    final selection = StaffCredentialSyncState.selectStaff([
      user('mary'),
      user('nino', pin: '5678', role: 'manager'),
    ]);

    expect(selection.entries.every(carriesPin), isTrue);
    expect(selection.pinCount, 2);
    expect(selection.entries.first['pin'], '1234');
    expect(selection.entries.last['role'], 'MANAGER');
  });

  test('an acknowledged staff list carries no PIN on the next snapshot', () async {
    final staff = [user('mary'), user('nino', pin: '5678')];
    await acceptSnapshot(StaffCredentialSyncState.selectStaff(staff));

    final next = StaffCredentialSyncState.selectStaff(staff);

    expect(next.entries.any(carriesPin), isFalse);
    expect(next.pinCount, 0);
    // Identity and role are still what the mirror is for.
    expect(next.entries.map((e) => e['username']), ['mary', 'nino']);
    expect(next.entries.first['role'], 'WAITER');
  });

  test('repeated routine snapshots keep carrying nothing', () async {
    final staff = [user('mary'), user('nino', pin: '5678')];
    for (var i = 0; i < 5; i++) {
      final selection = StaffCredentialSyncState.selectStaff(staff);
      if (i > 0) expect(selection.pinCount, 0, reason: 'snapshot ${i + 1}');
      await acceptSnapshot(selection);
    }

    expect(StaffCredentialSyncState.selectStaff(staff).pinCount, 0);
  });

  test('a changed PIN is carried again, and only for the member who changed it',
      () async {
    final mary = user('mary');
    final nino = user('nino', pin: '5678');
    await acceptSnapshot(
      StaffCredentialSyncState.selectStaff([mary, nino]),
    );

    mary.pinCode = '9999';
    final selection = StaffCredentialSyncState.selectStaff([mary, nino]);

    expect(selection.pinCount, 1);
    expect(selection.entries.first['pin'], '9999');
    expect(carriesPin(selection.entries.last), isFalse);
  });

  test('a role change alone carries no PIN', () async {
    final mary = user('mary');
    await acceptSnapshot(StaffCredentialSyncState.selectStaff([mary]));

    mary.role = 'manager';
    final selection = StaffCredentialSyncState.selectStaff([mary]);

    expect(selection.pinCount, 0);
    expect(selection.entries.single['role'], 'MANAGER');
  });

  test('a newly created member carries its PIN so the server can create it',
      () async {
    final mary = user('mary');
    await acceptSnapshot(StaffCredentialSyncState.selectStaff([mary]));

    final selection = StaffCredentialSyncState.selectStaff([
      mary,
      user('gio', pin: '4321'),
    ]);

    expect(selection.pinCount, 1);
    expect(selection.entries.last['username'], 'gio');
    expect(selection.entries.last['pin'], '4321');
  });

  test('a snapshot the server never accepted carries its PINs again', () async {
    final staff = [user('mary')];
    // Built, but never acknowledged — the push failed.
    StaffCredentialSyncState.selectStaff(staff);

    expect(StaffCredentialSyncState.selectStaff(staff).pinCount, 1);
  });

  test('a PIN changed while its snapshot was in flight stays unsent', () async {
    final mary = user('mary');
    final inFlight = StaffCredentialSyncState.selectStaff([mary]);
    mary.pinCode = '9999';
    await acceptSnapshot(inFlight);

    final next = StaffCredentialSyncState.selectStaff([mary]);

    expect(next.pinCount, 1);
    expect(next.entries.single['pin'], '9999');
  });

  test('a server that reports it has no credential gets the PIN back', () async {
    final staff = [user('mary'), user('nino', pin: '5678')];
    await acceptSnapshot(StaffCredentialSyncState.selectStaff(staff));

    await StaffCredentialSyncState.forget(['mary']);
    final selection = StaffCredentialSyncState.selectStaff(staff);

    expect(selection.pinCount, 1);
    expect(selection.entries.first['pin'], '1234');
    expect(carriesPin(selection.entries.last), isFalse);
  });

  test('a departed member is forgotten, and a returning one is re-collected',
      () async {
    final mary = user('mary');
    final nino = user('nino', pin: '5678');
    await acceptSnapshot(StaffCredentialSyncState.selectStaff([mary, nino]));

    await acceptSnapshot(StaffCredentialSyncState.selectStaff([mary]));
    final rehired = StaffCredentialSyncState.selectStaff([mary, nino]);

    expect(StaffCredentialSyncState.acknowledgedFingerprint('nino'), isNull);
    expect(rehired.pinCount, 1);
    expect(rehired.entries.last['pin'], '5678');
  });

  test('nothing acknowledged is stored as a PIN', () async {
    await acceptSnapshot(
      StaffCredentialSyncState.selectStaff([user('mary', pin: '1234')]),
    );

    final stored = Hive.box<Map>(StaffCredentialSyncState.boxName).get('mary');

    expect(stored, isNotNull);
    expect(stored!['fingerprint'], isNot(contains('1234')));
    expect(
      stored['fingerprint'],
      StaffCredentialSyncState.fingerprintOf('1234'),
    );
  });

  test('a closed box degrades to carrying every PIN rather than none', () async {
    final staff = [user('mary')];
    await acceptSnapshot(StaffCredentialSyncState.selectStaff(staff));
    await StaffCredentialSyncState.close();

    expect(StaffCredentialSyncState.selectStaff(staff).pinCount, 1);
  });
}
