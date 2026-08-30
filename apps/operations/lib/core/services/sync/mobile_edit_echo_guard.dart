/// Suppresses POS echo notifications on mobile after the user edits from this app.
class MobileEditEchoGuard {
  MobileEditEchoGuard._();

  static final Map<int, DateTime> _orderSuppressUntil = <int, DateTime>{};
  static final Map<String, DateTime> _tableSuppressUntil = <String, DateTime>{};

  static const Duration _defaultTtl = Duration(seconds: 60);

  static void markOrderEdited(int posOrderId, {Duration? ttl}) {
    _orderSuppressUntil[posOrderId] = DateTime.now().add(ttl ?? _defaultTtl);
  }

  static void markTableEdited(
    String tableNumber,
    String floor, {
    Duration? ttl,
  }) {
    final key = '${tableNumber.trim()}_${floor.trim()}';
    if (key.replaceAll('_', '').isEmpty) return;
    _tableSuppressUntil[key] = DateTime.now().add(ttl ?? _defaultTtl);
  }

  static bool shouldSuppressPosEcho(int? posOrderId) {
    if (posOrderId == null) return false;
    final until = _orderSuppressUntil[posOrderId];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _orderSuppressUntil.remove(posOrderId);
      return false;
    }
    return true;
  }

  static bool shouldSuppressTableEcho(String tableNumber, String floor) {
    final key = '${tableNumber.trim()}_${floor.trim()}';
    final until = _tableSuppressUntil[key];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _tableSuppressUntil.remove(key);
      return false;
    }
    return true;
  }
}
