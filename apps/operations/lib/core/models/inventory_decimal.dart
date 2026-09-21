/// Twelve-place fixed-point arithmetic for procurement previews. Backend remains
/// authoritative. BigInt preserves money/quantity text without binary floats.
class InventoryDecimal {
  InventoryDecimal._(this.raw);
  final BigInt raw;
  static final scale = BigInt.from(10).pow(12);
  static InventoryDecimal parse(String value) {
    final text = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{0,12})?$').hasMatch(text))
      throw const FormatException('Invalid decimal');
    final parts = text.split('.');
    return InventoryDecimal._(
      BigInt.parse(parts.first) * scale +
          BigInt.parse((parts.length > 1 ? parts[1] : '').padRight(12, '0')),
    );
  }

  static InventoryDecimal get zero => InventoryDecimal._(BigInt.zero);
  InventoryDecimal operator +(InventoryDecimal other) =>
      InventoryDecimal._(raw + other.raw);
  InventoryDecimal operator *(InventoryDecimal other) =>
      InventoryDecimal._((raw * other.raw + scale ~/ BigInt.two) ~/ scale);
  InventoryDecimal operator /(InventoryDecimal other) {
    if (other.raw == BigInt.zero) throw const FormatException('Zero quantity');
    return InventoryDecimal._(
      (raw * scale + other.raw ~/ BigInt.two) ~/ other.raw,
    );
  }

  InventoryDecimal round(int places) =>
      InventoryDecimal.parse(toStringAsFixed(places));

  String toStringAsFixed(int places) {
    final divisor = BigInt.from(10).pow(12 - places);
    final rounded = (raw + divisor ~/ BigInt.two) ~/ divisor;
    final text = rounded.toString().padLeft(places + 1, '0');
    return places == 0
        ? text
        : '${text.substring(0, text.length - places)}.${text.substring(text.length - places)}';
  }
}
