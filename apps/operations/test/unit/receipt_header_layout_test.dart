import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/models/receipt_header_layout.dart';

/// Where the mark and the words sit at the top of a check.
///
/// Both were centred unconditionally, because both were hardcoded. The
/// arithmetic here is what puts them somewhere else without pushing either off
/// the edge of 80mm paper.

const double _paper = 576;

void main() {
  group('alignment', () {
    test('centre splits the free space', () {
      final offset = ReceiptAlign.center.offsetFor(
        paperWidth: _paper,
        contentWidth: 200,
      );
      expect(offset, (576 - 200) / 2);
    });

    test('left and right keep a margin off the paper edge', () {
      // Thermal printers cut inconsistently, and a logo flush to the edge is
      // the one that comes out clipped.
      expect(
        ReceiptAlign.left.offsetFor(paperWidth: _paper, contentWidth: 200),
        8,
      );
      expect(
        ReceiptAlign.right.offsetFor(paperWidth: _paper, contentWidth: 200),
        576 - 200 - 8,
      );
    });

    test('content as wide as the paper starts at zero, never negative', () {
      // A negative offset draws off the left edge and silently loses the first
      // characters of the venue's name.
      for (final align in ReceiptAlign.values) {
        expect(
          align.offsetFor(paperWidth: _paper, contentWidth: 600),
          0,
          reason: align.name,
        );
      }
    });

    test('every alignment keeps the content on the paper', () {
      for (final align in ReceiptAlign.values) {
        final offset = align.offsetFor(paperWidth: _paper, contentWidth: 300);
        expect(offset, greaterThanOrEqualTo(0), reason: align.name);
        expect(offset + 300, lessThanOrEqualTo(_paper), reason: align.name);
      }
    });
  });

  group('storage', () {
    test('round-trips through the settings box', () {
      for (final align in ReceiptAlign.values) {
        expect(ReceiptAlign.fromStorage(align.storageValue), align);
      }
    });

    test('an unset or unknown value centres, as it always did', () {
      // Every terminal that predates this setting has nothing stored, and its
      // receipts have to keep printing the way they printed yesterday.
      expect(ReceiptAlign.fromStorage(null), ReceiptAlign.center);
      expect(ReceiptAlign.fromStorage(''), ReceiptAlign.center);
      expect(ReceiptAlign.fromStorage('justified'), ReceiptAlign.center);
      expect(ReceiptAlign.fromStorage(7), ReceiptAlign.center);
    });
  });

  group('the header as a whole', () {
    test('defaults to what the hardcoded version did', () {
      const layout = ReceiptHeaderLayout();
      expect(layout.logoAlign, ReceiptAlign.center);
      expect(layout.textAlign, ReceiptAlign.center);
      expect(layout.logoFirst, isTrue);
    });

    test('one element moves without disturbing the other', () {
      const layout = ReceiptHeaderLayout();
      final moved = layout.copyWith(logoAlign: ReceiptAlign.left);

      expect(moved.logoAlign, ReceiptAlign.left);
      expect(moved.textAlign, ReceiptAlign.center);
      expect(moved.logoFirst, isTrue);
    });

    test('the name can be put above the logo', () {
      const layout = ReceiptHeaderLayout();
      expect(layout.copyWith(logoFirst: false).logoFirst, isFalse);
    });
  });
}
