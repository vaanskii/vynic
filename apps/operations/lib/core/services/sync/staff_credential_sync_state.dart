import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';

/// Which staff credential the backend has acknowledged, and therefore which
/// PINs a snapshot still has to carry.
///
/// The POS used to put `pin` on every member of every snapshot, because it had
/// no way to tell a credential the server already holds from one it does not.
/// The server, having no way to tell either, ran bcrypt cost 12 over each one —
/// fourteen members cost roughly 2.7 seconds of a sync that changed no PIN at
/// all. This box is the missing answer, and it lives beside the user records
/// rather than inside them: a staff member is the restaurant's own record, and
/// cloud bookkeeping has no business being a field on it.
///
/// ## Why a fingerprint and not a flag
///
/// "Already synced" is not a property of a member, it is a property of a
/// *credential*. A flag would go on saying "synced" through a PIN change, and
/// the one snapshot that genuinely had to carry a PIN would be the one that
/// did not. What is stored is a hash of the PIN that was acknowledged, so the
/// question asked each sync — *is what I hold different from what the server
/// acknowledged* — is answered by the credential itself.
///
/// The stored value is a digest, never the PIN. The POS holds the plain PIN in
/// its own user box because it authenticates against it locally; this box adds
/// no second copy of it.
///
/// ## The acknowledgment rule
///
/// A fingerprint is recorded only after the server accepted the snapshot that
/// carried it, and it is the fingerprint that was *sent*, never the member's
/// current PIN — a PIN changed while a snapshot was in flight stays unsent and
/// goes with the next one. A server that reports it still has no credential for
/// a member (`staffNeedingPin`) makes that member unacknowledged again, so a
/// restored or re-provisioned backend re-collects the PINs it needs instead of
/// waiting for someone to change them.
///
/// ## Durability
///
/// Losing this box costs one snapshot that carries every PIN again — the same
/// thing every build did before it existed — so it is safe to fail. It is not
/// part of a backup: a restored install has acknowledged nothing, re-sends what
/// it holds, and that is the safe direction.
class StaffCredentialSyncState {
  StaffCredentialSyncState._();

  static const String boxName = 'staff_credential_sync_state';

  static Box<Map>? _box;

  static bool get isOpen => _box != null;

  /// Opens the box. Safe to call repeatedly; safe to fail.
  ///
  /// A POS that cannot open this box must still sync staff, so a failure here
  /// degrades to "nothing is acknowledged" — every PIN is carried, as it was
  /// before — rather than stopping staff sync altogether.
  static Future<void> open() async {
    if (_box != null) return;
    try {
      _box = await Hive.openBox<Map>(boxName);
    } catch (error) {
      debugPrint('[StaffSync] Could not open $boxName: $error');
    }
  }

  static Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  @visibleForTesting
  static Future<void> clearForTest() async {
    await _box?.clear();
  }

  /// A stable fingerprint for [pin]. Domain-separated so the digest cannot be
  /// confused with any other hash of the same string kept elsewhere.
  static String fingerprintOf(String pin) =>
      sha256.convert(utf8.encode('staff-pin:v1:$pin')).toString();

  /// The fingerprint the backend last acknowledged for [username], if any.
  static String? acknowledgedFingerprint(String username) {
    final raw = _box?.get(username);
    if (raw == null) return null;
    final fingerprint = raw['fingerprint'];
    return fingerprint is String && fingerprint.isNotEmpty ? fingerprint : null;
  }

  /// The staff entries one snapshot should carry.
  ///
  /// Identity and role go every time — they are what the mirror is for. A `pin`
  /// key is present only for a member whose credential the backend has not
  /// acknowledged: a member it has never seen, or one whose PIN changed since
  /// it did. This is the whole rule in one place, so the property that matters
  /// — an acknowledged staff list plus no PIN change carries no PIN — is
  /// something a test can state directly rather than infer from a network log.
  static StaffSnapshotSelection selectStaff(Iterable<User> users) {
    final knownUsernames = <String>{};
    final entries = <Map<String, dynamic>>[];
    final credentialsSent = <String, String>{};
    for (final user in users) {
      final username = user.username.trim();
      if (username.isEmpty) continue;
      // A repeated username is one identity on the server, so a second entry
      // could only restate or contradict the first.
      if (!knownUsernames.add(username)) continue;
      final pin = user.pinCode.trim();
      final fingerprint = pin.isEmpty ? null : fingerprintOf(pin);
      final carriesPin =
          fingerprint != null && acknowledgedFingerprint(username) != fingerprint;
      entries.add(<String, dynamic>{
        'username': username,
        if (carriesPin) 'pin': pin,
        'role': StaffRole.toApi(user.role),
      });
      if (carriesPin) credentialsSent[username] = fingerprint;
    }
    return StaffSnapshotSelection(
      entries: entries,
      credentialsSent: credentialsSent,
      knownUsernames: knownUsernames,
    );
  }

  /// Records that the backend accepted the snapshot carrying these
  /// fingerprints, keyed by username.
  ///
  /// The values must be the fingerprints that were *sent*. Recomputing them
  /// from the current PIN here would mark a PIN changed mid-flight as synced.
  static Future<void> markAccepted(
    Map<String, String> fingerprintsByUsername,
  ) async {
    final box = _box;
    if (box == null || fingerprintsByUsername.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await box.putAll(<String, Map>{
      for (final entry in fingerprintsByUsername.entries)
        entry.key: <String, dynamic>{
          'fingerprint': entry.value,
          'ackedAt': now,
        },
    });
  }

  /// Makes [usernames] unacknowledged, so the next snapshot carries their PINs.
  ///
  /// Used for the members the backend reports it holds no credential for.
  static Future<void> forget(Iterable<String> usernames) async {
    final box = _box;
    if (box == null) return;
    final known = usernames.where((username) => box.containsKey(username));
    if (known.isEmpty) return;
    await box.deleteAll(known.toList());
  }

  /// Forgets acknowledgments for members the POS no longer has.
  ///
  /// Bookkeeping only: it keeps the box proportional to the staff list rather
  /// than to everyone who ever worked here. Nothing is deleted from the user
  /// records themselves.
  static Future<void> pruneUnknown(Set<String> knownUsernames) async {
    final box = _box;
    if (box == null) return;
    final stale = box.keys
        .where((key) => key is String && !knownUsernames.contains(key))
        .toList();
    if (stale.isEmpty) return;
    await box.deleteAll(stale);
  }
}

/// What one snapshot's staff section carries, and what accepting it would
/// acknowledge.
class StaffSnapshotSelection {
  const StaffSnapshotSelection({
    required this.entries,
    required this.credentialsSent,
    required this.knownUsernames,
  });

  /// The wire entries, in staff-list order.
  final List<Map<String, dynamic>> entries;

  /// Username -> fingerprint of the PIN this snapshot carries for them.
  final Map<String, String> credentialsSent;

  /// Every username the POS holds.
  final Set<String> knownUsernames;

  /// How many entries carry a PIN. For the sync summary line.
  int get pinCount => credentialsSent.length;
}
