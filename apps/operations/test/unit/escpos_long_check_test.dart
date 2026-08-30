import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/escpos_kitchen_renderer.dart';

/// Rows of the raster bitmap carried by the GS v 0 chunks in [bytes].
///
/// Each row is one bit per dot, MSB first; a set bit is ink.
List<List<int>> _decodeRasterRows(List<int> bytes) {
  final rows = <List<int>>[];
  int i = 0;
  while (i < bytes.length) {
    // GS v 0 m xL xH yL yH d1..dk
    if (i + 8 <= bytes.length &&
        bytes[i] == 0x1D &&
        bytes[i + 1] == 0x76 &&
        bytes[i + 2] == 0x30) {
      final widthBytes = bytes[i + 4] | (bytes[i + 5] << 8);
      final height = bytes[i + 6] | (bytes[i + 7] << 8);
      int p = i + 8;
      for (int y = 0; y < height; y++) {
        rows.add(bytes.sublist(p, p + widthBytes));
        p += widthBytes;
      }
      i = p;
      continue;
    }
    i++;
  }
  return rows;
}

int _inkBits(List<int> row) {
  int count = 0;
  for (final byte in row) {
    for (int bit = 0; bit < 8; bit++) {
      if (byte & (1 << bit) != 0) count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a kitchen check taller than the old fixed canvas stays on paper', () async {
    // Enough items to push the check well past the 2000px background that used
    // to be pre-painted, which left the tail unpainted and printed it black.
    final items = List<String>.generate(40, (i) => '3x ITEM ${i + 1}');

    final bytes = await EscposKitchenRenderer.generateBytes(
      items: items,
      tableNumber: 'T8 + T7',
      waiterName: 'anna',
      createdAt: DateTime(2026, 8, 26, 16, 40, 5),
      resolveOperatorDisplayName: (rawName, {required bool isEnglish}) =>
          rawName,
    );

    final rows = _decodeRasterRows(bytes);
    expect(rows.length, greaterThan(2000));

    // The renderer leaves a blank bottom margin, so the tail must be blank.
    final tail = rows.sublist(rows.length - 40);
    for (int i = 0; i < tail.length; i++) {
      expect(
        _inkBits(tail[i]),
        0,
        reason: 'row ${rows.length - 40 + i} of ${rows.length} printed ink in '
            'what should be the blank bottom margin',
      );
    }

    // And no row anywhere may be a solid black band.
    final rowWidthBits = rows.first.length * 8;
    for (int y = 0; y < rows.length; y++) {
      expect(
        _inkBits(rows[y]),
        lessThan(rowWidthBits),
        reason: 'row $y of ${rows.length} is a solid black band',
      );
    }
  });
}
