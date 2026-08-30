// GENERATED FILE — DO NOT EDIT.
//
// Rendered from packages/contracts/schema/table-identity.contract.json
// by packages/contracts/scripts/generate.mjs.
//
// Change the schema and regenerate; edits here are overwritten and
// CI fails on a stale or hand-edited output.

/// Table identity: the canonical [encodeTableRef] form and the transitional
/// integer [encodeTableCode] encoding shared with pos_app_server.
library;

const int tableIdentityContractVersion = 1;

/// Separator between the floor key and the table number in a table ref.
const String tableRefSeparator = '/';

class _Floor {
  const _Floor({
    required this.key,
    required this.offset,
    required this.maxTableNumber,
  });

  final String key;
  final int offset;
  final int? maxTableNumber;
}

const List<_Floor> _floors = [
  _Floor(key: 'first', offset: 0, maxTableNumber: 10),
  _Floor(key: 'second', offset: 10, maxTableNumber: null),
];

const int _minTableNumber = 1;

_Floor? _floorByKey(String key) {
  for (final floor in _floors) {
    if (floor.key == key) return floor;
  }
  return null;
}

/// The parsed table number, or null when [raw] is not a whole number at or
/// above the minimum.
int? _parseTableNumber(String raw) {
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < _minTableNumber) return null;
  return parsed;
}

/// Whether [floor] and [tableNumber] can be represented as a legacy code.
///
/// Pickers must hide tables that fail this check rather than offering them,
/// because [encodeTableCode] throws for exactly the same inputs.
bool canEncodeTableCode({
  required String floor,
  required String tableNumber,
}) {
  final parsed = _parseTableNumber(tableNumber);
  if (parsed == null) return false;
  final target = _floorByKey(floor);
  if (target == null) return false;
  final max = target.maxTableNumber;
  return max == null || parsed <= max;
}

/// Encodes [floor] and [tableNumber] into the legacy integer code.
///
/// Throws [ArgumentError] rather than returning a code that would decode as a
/// different table.
int encodeTableCode({required String floor, required String tableNumber}) {
  final parsed = _parseTableNumber(tableNumber);
  if (parsed == null) {
    throw ArgumentError('Invalid table number: $tableNumber');
  }
  final target = _floorByKey(floor);
  if (target == null) {
    throw ArgumentError(
      'Floor "$floor" cannot be encoded as a reservation table code; '
      'only ${_floors.map((f) => f.key).join('/')} are supported',
    );
  }
  final max = target.maxTableNumber;
  if (max != null && parsed > max) {
    throw ArgumentError(
      'Table $parsed on the $floor floor cannot be encoded as a '
      'reservation table code (would decode as another floor\'s table)',
    );
  }
  return parsed + target.offset;
}

/// Decodes a legacy integer code back into a floor and table number.
///
/// Total by design: it validates nothing, so every code — including ones
/// [encodeTableCode] would never produce — maps somewhere, exactly as the
/// hand-written implementations did.
({String floor, String tableNumber}) decodeTableCode(int code) {
    if (code > 10) {
      return (floor: 'second', tableNumber: '${code - 10}');
    }
    return (floor: 'first', tableNumber: '${code - 0}');
}

/// The canonical, lossless reference: `floor${tableRefSeparator}tableNumber`.
String encodeTableRef({required String floor, required String tableNumber}) {
  return '$floor$tableRefSeparator$tableNumber';
}

/// Parses [raw] back into a floor and table number, or null when malformed.
///
/// Splits on the FIRST separator only: floor keys never contain it, so any
/// later occurrence belongs to the table number.
({String floor, String tableNumber})? tryDecodeTableRef(String raw) {
  final separator = raw.indexOf(tableRefSeparator);
  if (separator <= 0 || separator >= raw.length - 1) {
    return null;
  }
  final floor = raw.substring(0, separator).trim();
  final tableNumber = raw.substring(separator + 1).trim();
  if (floor.isEmpty || tableNumber.isEmpty) {
    return null;
  }
  return (floor: floor, tableNumber: tableNumber);
}
