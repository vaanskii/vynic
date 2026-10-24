/// A short, session-only authorization from an authenticated runtime pull.
/// Never serialized or restored with restaurant backups.
class NonFiscalCloseGrant {
  NonFiscalCloseGrant({
    required this.deviceId,
    required this.venueId,
    Stopwatch? age,
  }) : _age = age ?? (Stopwatch()..start());

  static const lifetime = Duration(minutes: 15);
  final String deviceId;
  final String venueId;
  final Stopwatch _age;

  bool allows(String? device, String? venue) =>
      device == deviceId && venue == venueId && _age.elapsed < lifetime;
}
