import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Signed server time plus suspend-aware elapsed time. Restored anchors are
/// accepted only from the OS vault after the service proves same-boot continuity.
class OfflineLease {
  static const maxDuration = 24 * 60 * 60 * 1000;
  Map<String, dynamic>? _claims;
  int? _anchor;
  int? _lastElapsed;
  int? _lastWall;
  int? _acceptedElapsed;
  int? _acceptedWall;
  Object? _envelope;
  String? _nonce;

  Map<String, dynamic> checkpoint() => {
    'envelope': _envelope,
    'nonce': _nonce,
    'requestElapsed': _anchor,
    'acceptedElapsed': _acceptedElapsed,
    'acceptedWall': _acceptedWall,
    'lastElapsed': _lastElapsed,
    'lastWall': _lastWall,
  };

  Future<void> restore(
    Map<String, dynamic> saved, {
    required List<int> publicKey,
    required String device,
    required String venue,
    required String installation,
    required int elapsed,
    required int wall,
  }) async {
    for (final name in [
      'requestElapsed',
      'acceptedElapsed',
      'acceptedWall',
      'lastElapsed',
      'lastWall',
    ]) {
      if (saved[name] is! int || (saved[name] as int) < 0) {
        throw const FormatException('Invalid persisted clock anchor');
      }
    }
    if (saved['nonce'] is! String ||
        saved['lastElapsed'] < saved['acceptedElapsed'] ||
        saved['lastWall'] < saved['acceptedWall'] - 2000) {
      throw const FormatException('Invalid persisted clock checkpoint');
    }
    await accept(
      saved['envelope'],
      publicKey: publicKey,
      nonce: saved['nonce'] as String,
      device: device,
      venue: venue,
      installation: installation,
      requestElapsed: saved['requestElapsed'],
      elapsed: saved['acceptedElapsed'],
      wall: saved['acceptedWall'],
    );
    _lastElapsed = saved['lastElapsed'];
    _lastWall = saved['lastWall'];
    check(elapsed: elapsed, wall: wall);
  }

  String reason = 'VERIFICATION_REQUIRED';
  String kind = 'SUBSCRIPTION';
  int remainingMs = 0;
  int? entitlementRemainingMs;
  bool get allowed => reason == 'VALID';

  Future<void> accept(
    Object? envelope, {
    required List<int> publicKey,
    required String nonce,
    required String device,
    required String venue,
    required String installation,
    required int requestElapsed,
    required int elapsed,
    required int wall,
  }) async {
    if (envelope is! Map ||
        envelope['payload'] is! String ||
        envelope['signature'] is! String ||
        (envelope['payload'] as String).length > 8192)
      throw const FormatException('Invalid lease');
    final bytes = base64Decode(envelope['payload'] as String);
    final valid = await Ed25519().verify(
      bytes,
      signature: Signature(
        base64Decode(envelope['signature'] as String),
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const FormatException('Invalid lease signature');
    final c = jsonDecode(utf8.decode(bytes));
    if (c is! Map<String, dynamic> ||
        c['version'] != 1 ||
        c['nonce'] != nonce ||
        c['deviceId'] != device ||
        c['venueId'] != venue ||
        c['installationId'] != installation ||
        !['VALID', 'EXPIRED', 'REVOKED'].contains(c['status']) ||
        !['TRIAL', 'SUBSCRIPTION'].contains(c['kind']) ||
        c['issuedAt'] is! int ||
        c['deadline'] is! int ||
        (c['entitlementEndsAt'] != null && c['entitlementEndsAt'] is! int) ||
        c['deadline'] < c['issuedAt'] ||
        c['deadline'] - c['issuedAt'] > maxDuration ||
        (c['status'] == 'VALID' &&
            c['entitlementEndsAt'] != null &&
            c['deadline'] > c['entitlementEndsAt']) ||
        elapsed < requestElapsed ||
        elapsed - requestElapsed > 30000) {
      throw const FormatException('Invalid lease binding or deadline');
    }
    _envelope = envelope;
    _nonce = nonce;
    _acceptedElapsed = elapsed;
    _acceptedWall = wall;
    _claims = c;
    kind = c['kind'] as String;
    // Counting the entire request transit time is deliberately conservative.
    _anchor = requestElapsed;
    _lastElapsed = elapsed;
    _lastWall = wall;
    reason = c['status'] as String;
    check(elapsed: elapsed, wall: wall);
  }

  void restrict(String value) {
    reason = value;
    remainingMs = 0;
  }

  void check({required int elapsed, required int wall}) {
    if (!allowed) return;
    if (_anchor == null ||
        elapsed < _lastElapsed! ||
        wall < _lastWall! + elapsed - _lastElapsed! - 2000 ||
        wall < _acceptedWall! + elapsed - _acceptedElapsed! - 2000 ||
        // A hypervisor can pause the guest monotonic clock while wall time
        // advances. Treat either direction of drift as uncertain continuity;
        // counting only elapsed time would extend the signed offline deadline.
        wall > _lastWall! + elapsed - _lastElapsed! + 2000 ||
        wall > _acceptedWall! + elapsed - _acceptedElapsed! + 2000) {
      restrict('VERIFICATION_REQUIRED');
      return;
    }
    _lastElapsed = elapsed;
    _lastWall = wall;
    final serverNow = (_claims!['issuedAt'] as int) + elapsed - _anchor!;
    remainingMs = (_claims!['deadline'] as int) - serverNow;
    final cutoff = _claims!['entitlementEndsAt'] as int?;
    entitlementRemainingMs = cutoff == null ? null : cutoff - serverNow;
    if (cutoff != null && serverNow >= cutoff) {
      restrict('EXPIRED');
    } else if (remainingMs <= 0) {
      restrict('VERIFICATION_REQUIRED');
    }
  }
}
