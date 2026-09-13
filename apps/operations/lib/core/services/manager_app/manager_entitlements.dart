import 'package:flutter/foundation.dart';

import '../../models/feature_keys.dart';
export '../../models/feature_keys.dart';

/// Server-resolved session capabilities. No plan/override calculation or disk cache.
abstract final class ManagerEntitlements {
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
    final next = snapshot['commercialAccess'] == false
        ? <String>{}
        : (snapshot['features'] as List).cast<String>().toSet();
    pastDue.value = (snapshot['subscription'] as Map?)?['status'] == 'PAST_DUE';
    if (!setEquals(features.value, next)) features.value = next;
  }

  static void clear() {
    features.value = {};
    pastDue.value = false;
  }
}
