import 'package:flutter/foundation.dart';

import '../../models/feature_keys.dart';
export '../../models/feature_keys.dart';

/// Server-resolved session capabilities. No plan/override calculation or disk cache.
abstract final class ManagerEntitlements {
  static final profile = ValueNotifier<Map<String, dynamic>?>(null);
  static final features = ValueNotifier<Set<String>>({});
  static final pastDue = ValueNotifier<bool>(false);
  static bool has(String feature) => features.value.contains(feature);
  static List<int> get destinations => [
    0,
    1,
    2,
    if (has(FeatureKeys.inventory)) 3,
    if (has(FeatureKeys.managerReservations)) 4,
    5,
  ];
  static void apply(Map<String, dynamic> snapshot) {
    if (snapshot['profile'] is Map)
      profile.value = Map<String, dynamic>.from(snapshot['profile'] as Map);
    final rawFeatures = snapshot['features'];
    final next =
        snapshot['commercialAccess'] == false ||
            rawFeatures is! List ||
            rawFeatures.any((key) => key is! String)
        ? <String>{}
        : rawFeatures.cast<String>().toSet();
    pastDue.value =
        (snapshot['subscription'] is Map
            ? (snapshot['subscription'] as Map)['status']
            : null) ==
        'PAST_DUE';
    if (!setEquals(features.value, next)) features.value = next;
  }

  static void clear() {
    profile.value = null;
    features.value = {};
    pastDue.value = false;
  }
}
