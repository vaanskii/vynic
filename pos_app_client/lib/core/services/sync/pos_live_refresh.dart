import 'package:flutter/foundation.dart';

/// Bumps whenever POS-local data changes (Hive ingest, SyncHub, notifications).
/// Windows home / order screens listen to repaint badges, tables, and orders.
class PosLiveRefresh {
  PosLiveRefresh._();

  static final ValueNotifier<int> generation = ValueNotifier<int>(0);

  static void bump() {
    generation.value++;
  }
}
