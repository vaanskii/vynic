import 'dart:convert';

import 'package:hive/hive.dart';

/// Durable staging for a future first-POS activation, never a live menu writer.
///
/// The isolated box holds the complete server snapshot, including disabled
/// products. Activation into operational boxes requires a separately proven
/// authority handover and is deliberately unavailable.
class RestaurantFoundationImport {
  RestaurantFoundationImport(this.staging);

  final Box<String> staging;
  static final Set<Box<String>> _writing = {};

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<bool> stage({
    required Map<String, dynamic> snapshot,
    required String enrolledVenueId,
    required String enrolledDeviceId,
    required Iterable<Box<dynamic>> operationalBoxes,
  }) async {
    if (snapshot['version'] != 1 ||
        snapshot['authority'] != 'CLOUD' ||
        snapshot['operationalActivationAllowed'] != false ||
        snapshot['venueId'] != enrolledVenueId ||
        snapshot['deviceId'] != enrolledDeviceId ||
        snapshot['snapshotId'] is! String ||
        (snapshot['snapshotId'] as String).isEmpty ||
        snapshot['categories'] is! List ||
        snapshot['profile'] is! Map) {
      throw StateError('Unsupported or incorrectly bound foundation');
    }
    final encoded = jsonEncode(_canonical(snapshot));
    if (_writing.contains(staging)) {
      throw StateError(
        'Foundation import is in progress; retry after completion',
      );
    }
    final existing = staging.get('snapshot');
    if (existing != null) {
      if (existing == encoded) return false;
      throw StateError('A different foundation is already staged');
    }
    final boxes = operationalBoxes.toList();
    if (boxes.isEmpty || boxes.any((box) => !box.isOpen || box.isNotEmpty)) {
      throw StateError(
        'Foundation import requires verified empty operational state',
      );
    }
    // One durable value is the complete import and its completion marker.
    // No partial writes to live menu, settings, Orders, Tables or journals.
    _writing.add(staging);
    try {
      await staging.put('snapshot', encoded);
      await staging.flush();
      return true;
    } finally {
      _writing.remove(staging);
    }
  }

  Map<String, dynamic>? read() {
    final value = staging.get('snapshot');
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }
}
