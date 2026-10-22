import 'dart:convert';

/// A reconnect cannot transfer existing restaurant data to another tenant.
class LocalVenueMismatch extends StateError {
  LocalVenueMismatch({required this.storedVenueId, required this.targetVenueId})
    : super(
        'This POS contains data for Venue $storedVenueId, but the device is '
        'connecting to Venue $targetVenueId. Reconnect to the original Venue, '
        'or back up the complete POS data directory and use a fresh installation '
        'for the new restaurant. Existing data has been preserved.',
      );

  final String storedVenueId;
  final String targetVenueId;
}

/// Checks persisted ownership before identity changes or startup recovery.
/// Pending Menu commits count even when their canonical row is not written yet.
void validateLocalVenueBinding({
  required String venueId,
  String? restoredVenueId,
  String? canonical,
  String? baseline,
  String? pendingCommit,
  Iterable<String> journal = const [],
}) {
  void check(Object? stored) {
    if (stored is! String || stored.trim().isEmpty) {
      throw const FormatException(
        'Stored restaurant data has no Venue identity',
      );
    }
    if (stored != venueId) {
      throw LocalVenueMismatch(storedVenueId: stored, targetVenueId: venueId);
    }
  }

  void checkMenu(String raw) => check((jsonDecode(raw) as Map)['venueId']);

  if (restoredVenueId != null) check(restoredVenueId);
  if (canonical != null) checkMenu(canonical);
  if (baseline != null) checkMenu(baseline);
  if (pendingCommit != null) {
    final frame = jsonDecode(pendingCommit) as Map;
    checkMenu(frame['canonical'] as String);
    checkMenu(frame['projection'] as String);
    for (final entry in frame['puts'] as List) {
      check((entry as Map)['venueId']);
    }
  }
  for (final raw in journal) {
    check((jsonDecode(raw) as Map)['venueId']);
  }
}
