/// Human-readable notification title/body from WS / FCM payloads.
class NotificationMessageCopy {
  const NotificationMessageCopy({required this.title, required this.message});

  final String title;
  final String message;
}

NotificationMessageCopy buildReservationsCopy(Map<String, dynamic> payload) {
  final action = (payload['action'] ?? '').toString().trim().toLowerCase();
  final customerName = (payload['customerName'] ?? '').toString().trim();
  final resDateRaw = (payload['reservationDate'] ?? '').toString().trim();
  final resDate =
      resDateRaw.length >= 10 ? resDateRaw.substring(0, 10) : resDateRaw;
  final resTime = (payload['reservationTime'] ?? '').toString().trim();
  final tablesRaw = payload['tableNumbers'];
  final tables = tablesRaw is List
      ? tablesRaw
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty && s != '0')
            .toList()
      : <String>[];
  final today = DateTime.now().toIso8601String().substring(0, 10);

  final detailParts = <String>[
    if (customerName.isNotEmpty) customerName,
    if (tables.isNotEmpty) 'მაგიდა ${tables.join(', ')}',
    if (resTime.isNotEmpty) 'დრო: $resTime',
    if (resDate.isNotEmpty && resDate != today) 'თარიღი: $resDate',
  ];
  final detail = detailParts.join(' • ');

  final walkIn = customerName.toLowerCase() == 'walk-in' ||
      customerName.toLowerCase().contains('walk-in');

  if (action == 'deleted' || action == 'cancelled') {
    return NotificationMessageCopy(
      title: 'რეზერვაცია',
      message: detail.isNotEmpty
          ? 'რეზერვაცია გაუქმდა — $detail'
          : 'რეზერვაცია გაუქმდა',
    );
  }

  if (walkIn) {
    return NotificationMessageCopy(
      title: 'მაგიდა',
      message: detail.isNotEmpty
          ? 'ახალი walk-in — $detail'
          : 'ახალი walk-in',
    );
  }

  if (action == 'created') {
    final isFuture = resDate.isNotEmpty && resDate.compareTo(today) > 0;
    final headline = isFuture ? 'მომავალი რეზერვაცია' : 'ახალი რეზერვაცია';
    return NotificationMessageCopy(
      title: 'რეზერვაციები',
      message: detail.isNotEmpty ? '$headline — $detail' : headline,
    );
  }

  if (action == 'updated') {
    return NotificationMessageCopy(
      title: 'რეზერვაციები',
      message: detail.isNotEmpty
          ? 'რეზერვაცია განახლდა — $detail'
          : 'რეზერვაცია განახლდა',
    );
  }

  return NotificationMessageCopy(
    title: 'რეზერვაციები',
    message:
        detail.isNotEmpty ? 'რეზერვაცია — $detail' : 'რეზერვაცია განახლდა',
  );
}

NotificationMessageCopy buildOrderCreatedCopy(Map<String, dynamic> payload) {
  final id = payload['posOrderId'];
  final walkIn = payload['walkIn'] == true;
  final tableLabel = (payload['tableLabel'] ?? '').toString().trim();
  final tableNumbersRaw = payload['tableNumbers'];
  final tableNumbers = tableNumbersRaw is List
      ? tableNumbersRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).join(', ')
      : '';
  final tableSeg = tableLabel.isNotEmpty
      ? tableLabel
      : tableNumbers.isNotEmpty
      ? tableNumbers
      : '';
  final tablePart = tableSeg.isNotEmpty ? ' — მაგიდა $tableSeg' : '';
  final idPart = id != null ? ' #$id' : '';

  if (walkIn) {
    return NotificationMessageCopy(
      title: 'მაგიდა',
      message: 'ახალი walk-in$idPart$tablePart',
    );
  }
  return NotificationMessageCopy(
    title: 'შეკვეთა',
    message: id != null
        ? 'შეიქმნა ახალი შეკვეთა #$id$tablePart'
        : 'შეიქმნა ახალი შეკვეთა$tablePart',
  );
}

/// Walk-in table orders are stored as reservations but should open მაგიდები.
bool isWalkInNotificationMeta(Map<String, dynamic> meta) {
  if (meta['walkIn'] == true) return true;
  final name = (meta['customerName'] ?? '').toString().trim().toLowerCase();
  return name == 'walk-in' || name.contains('walk-in');
}

/// Order id for walk-in taps when only a reservation payload is present.
int? orderIdFromWalkInNotificationMeta(Map<String, dynamic> meta) {
  final direct = meta['posOrderId'];
  if (direct is num) return direct.toInt();
  if (direct != null) {
    final parsed = int.tryParse(direct.toString());
    if (parsed != null) return parsed;
  }

  final linked = meta['linkedOrderId'];
  if (linked is num) return linked.toInt();
  if (linked != null) {
    final parsed = int.tryParse(linked.toString());
    if (parsed != null) return parsed;
  }

  final touches = meta['touches'];
  if (touches is List) {
    for (final t in touches) {
      if (t is! Map) continue;
      final m = Map<String, dynamic>.from(t);
      if (!isWalkInNotificationMeta(m)) continue;
      final id = orderIdFromWalkInNotificationMeta(m);
      if (id != null) return id;
    }
  }

  final notes = (meta['notes'] ?? '').toString();
  final match = RegExp(r'order\s*#(\d+)', caseSensitive: false).firstMatch(notes);
  if (match != null) return int.tryParse(match.group(1)!);

  return null;
}

String? tableNumberFromNotificationMeta(Map<String, dynamic> meta) {
  final label = (meta['tableLabel'] ?? '').toString().trim();
  if (label.isNotEmpty) {
    return label.replaceAll('Table ', '').split(',').first.trim();
  }
  final numbers = meta['tableNumbers'];
  if (numbers is List && numbers.isNotEmpty) {
    return _displayTableNumber(numbers.first, meta['floor']?.toString());
  }
  return null;
}

/// POS encodes 2nd-floor tables as 10+N; API uses tableNumber + floor.
String _displayTableNumber(dynamic raw, String? floorHint) {
  final encoded = raw is num ? raw.toInt() : int.tryParse(raw.toString());
  if (encoded == null) return raw.toString().trim();
  final floor = (floorHint ?? '').trim().toLowerCase();
  if (floor == 'second' && encoded > 10) return (encoded - 10).toString();
  if (encoded > 10 && floor.isEmpty) return (encoded - 10).toString();
  return encoded.toString();
}

int? orderIdFromNotificationMessage(String message) {
  final match = RegExp(r'#(\d+)').firstMatch(message);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

String? tableNumberFromNotificationMessage(String message) {
  final match = RegExp(
    r'მაგიდა\s+([^—\n•]+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (match == null) return null;
  return match.group(1)?.split(',').first.trim();
}

Map<String, dynamic> enrichWalkInReservationNotificationMeta(
  Map<String, dynamic> payload,
) {
  if (!isWalkInNotificationMeta(payload)) return payload;
  final meta = Map<String, dynamic>.from(payload);
  meta['walkIn'] = true;
  final orderId = orderIdFromWalkInNotificationMeta(meta);
  if (orderId != null) meta['posOrderId'] = orderId;
  final table = tableNumberFromNotificationMeta(meta);
  if (table != null && table.isNotEmpty) {
    meta.putIfAbsent('tableLabel', () => table);
  }
  return meta;
}

NotificationMessageCopy buildOrderCancelledCopy(Map<String, dynamic> payload) {
  final id = payload['posOrderId'];
  final tableLabel = (payload['tableLabel'] ?? '').toString().trim();
  if (tableLabel.isNotEmpty) {
    return NotificationMessageCopy(
      title: 'მაგიდა',
      message: 'მაგიდა $tableLabel გაუქმდა',
    );
  }
  return NotificationMessageCopy(
    title: 'შეკვეთა',
    message: id != null ? 'შეკვეთა #$id გაუქმდა' : 'შეკვეთა გაუქმდა',
  );
}
