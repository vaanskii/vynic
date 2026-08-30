/// Crockford base32 for the one-time unlock codes.
///
/// Deliberately duplicated from the POS
/// (`lib/core/services/security/developer_code_format.dart`) rather than
/// shared: this tool must not depend on the POS package, or building the
/// Unlocker would drag the whole point-of-sale in behind it. Thirty lines of
/// alphabet is the cheaper coupling. Keep the two in step — the tests assert a
/// round trip against the same vectors.
///
/// Not RFC 4648: that alphabet contains 0/O, 1/I and 1/L, which is a bad
/// property for a string somebody reads down a phone line to a restaurant
/// manager. Crockford drops I, L, O and U from the alphabet and folds them back
/// to 1, 1, 0 on the way in, so a misheard character still decodes correctly.
///
/// Sixteen characters carry exactly 80 bits, which is the code size.
library;

const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Encodes [bytes] and groups the result in fours: `A7K2-9QMX-3PLD-8FZT`.
String encodeDeveloperCode(List<int> bytes) {
  final buffer = StringBuffer();
  var accumulator = 0;
  var bits = 0;

  for (final byte in bytes) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      buffer.write(_alphabet[(accumulator >> bits) & 0x1f]);
    }
  }
  if (bits > 0) {
    buffer.write(_alphabet[(accumulator << (5 - bits)) & 0x1f]);
  }

  final raw = buffer.toString();
  final groups = <String>[
    for (var i = 0; i < raw.length; i += 4)
      raw.substring(i, i + 4 > raw.length ? raw.length : i + 4),
  ];
  return groups.join('-');
}

/// Decodes a typed code, or returns null if it is not [byteLength] bytes worth.
///
/// Tolerant on the way in — case, dashes, spaces, and the confusable letters
/// are all normalised — because the alternative is a support call that fails on
/// a typo rather than on anything real.
List<int>? decodeDeveloperCode(String input, {int byteLength = 10}) {
  final normalized = input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-_]'), '')
      .replaceAll('I', '1')
      .replaceAll('L', '1')
      .replaceAll('O', '0');
  if (normalized.isEmpty) return null;

  final bytes = <int>[];
  var accumulator = 0;
  var bits = 0;

  for (final character in normalized.split('')) {
    final value = _alphabet.indexOf(character);
    if (value < 0) return null;
    accumulator = (accumulator << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((accumulator >> bits) & 0xff);
    }
  }

  return bytes.length == byteLength ? bytes : null;
}
