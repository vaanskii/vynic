import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Last explicit Cloud decision for this enrolled installation.
/// Absence or an unbound legacy feature list never authorizes an internal close.
/// Offline operation keeps the last verified decision; remote revocation takes
/// effect on the next successful pull. There is no client-invented time limit.
class NonFiscalCloseGrant {
  const NonFiscalCloseGrant({
    required this.deviceId,
    required this.venueId,
    required this.installationId,
    required this.credentialFingerprint,
    required this.enabled,
  });

  final String deviceId;
  final String venueId;
  final String installationId;
  final String credentialFingerprint;
  final bool enabled;

  static String fingerprint(String credential) =>
      sha256.convert(utf8.encode(credential)).toString();

  static NonFiscalCloseGrant? fromMap(Object? raw) {
    if (raw is! Map || raw['version'] != 1 || raw['enabled'] is! bool)
      return null;
    for (final key in [
      'deviceId',
      'venueId',
      'installationId',
      'credentialFingerprint',
    ]) {
      if (raw[key] is! String || (raw[key] as String).trim().isEmpty)
        return null;
    }
    return NonFiscalCloseGrant(
      deviceId: raw['deviceId'] as String,
      venueId: raw['venueId'] as String,
      installationId: raw['installationId'] as String,
      credentialFingerprint: raw['credentialFingerprint'] as String,
      enabled: raw['enabled'] as bool,
    );
  }

  bool allows({
    required String? device,
    required String? venue,
    required String? installation,
    required String? credential,
  }) =>
      enabled &&
      device == deviceId &&
      venue == venueId &&
      installation == installationId &&
      credential != null &&
      fingerprint(credential) == credentialFingerprint;

  Map<String, dynamic> toMap() => {
    'version': 1,
    'deviceId': deviceId,
    'venueId': venueId,
    'installationId': installationId,
    'credentialFingerprint': credentialFingerprint,
    'enabled': enabled,
  };
}
