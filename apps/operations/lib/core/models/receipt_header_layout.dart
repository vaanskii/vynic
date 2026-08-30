import 'dart:ui' show Size;

/// The printable width of an 80mm roll, in printer dots.
const double receiptPaperWidth = 576;

/// Kept clear on each side. Thermal printers cut inconsistently and content
/// flush to the edge comes out clipped.
const double receiptSideMargin = 8;

/// The largest a logo may be drawn, at 100%.
///
/// Both numbers used to be smaller than this — 384 wide on 576-wide paper, and
/// 120 tall — *and* the upload step capped the stored image at 384x160 before
/// the renderer ever saw it. The two compounded: a square mark set to „100%"
/// printed at 120 dots, which is 21% of the paper. The slider was not wrong
/// about its own arithmetic; it was reporting a fraction of a box nobody could
/// see.
const double receiptLogoMaxWidth = receiptPaperWidth - receiptSideMargin * 2;

/// 260 dots is about 32mm — a large logo on a receipt, and the point at which
/// a square mark stops being the thing that pushes the order down the page.
const double receiptLogoMaxHeight = 260;

/// How big a logo actually prints.
///
/// The single answer for both the printer and the settings preview: they used
/// to compute it separately, which is how a preview can agree with a slider and
/// disagree with the paper.
Size receiptLogoSize({
  required double sourceWidth,
  required double sourceHeight,
  required double scale,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) return Size.zero;
  final boxWidth = receiptLogoMaxWidth * scale;
  final boxHeight = receiptLogoMaxHeight * scale;
  final fit = boxWidth / sourceWidth < boxHeight / sourceHeight
      ? boxWidth / sourceWidth
      : boxHeight / sourceHeight;
  return Size(sourceWidth * fit, sourceHeight * fit);
}

/// Where the venue's logo and name sit at the top of a printed check.
///
/// Both were centred, unconditionally, because both were hardcoded. A venue
/// with a wide wordmark and a short name wants them arranged differently from
/// one with a round crest, and neither should have to ask for a build to say
/// so.
enum ReceiptAlign {
  left,
  center,
  right;

  static ReceiptAlign fromStorage(Object? raw) {
    final name = raw?.toString();
    for (final value in ReceiptAlign.values) {
      if (value.name == name) return value;
    }
    return ReceiptAlign.center;
  }

  String get storageValue => name;

  /// Georgian label for the settings picker.
  String get label => switch (this) {
    ReceiptAlign.left => 'მარცხნივ',
    ReceiptAlign.center => 'ცენტრში',
    ReceiptAlign.right => 'მარჯვნივ',
  };

  /// Left edge for something [contentWidth] wide on a [paperWidth] receipt.
  ///
  /// [margin] keeps a left- or right-aligned element off the very edge of the
  /// paper, where thermal printers cut inconsistently.
  double offsetFor({
    required double paperWidth,
    required double contentWidth,
    double margin = 8,
  }) {
    final free = paperWidth - contentWidth;
    if (free <= 0) return 0;
    return switch (this) {
      ReceiptAlign.left => margin,
      ReceiptAlign.center => free / 2,
      ReceiptAlign.right => free - margin,
    };
  }
}

/// The header's whole arrangement: where the mark goes, where the words go,
/// and which comes first.
class ReceiptHeaderLayout {
  const ReceiptHeaderLayout({
    this.logoAlign = ReceiptAlign.center,
    this.textAlign = ReceiptAlign.center,
    this.logoFirst = true,
    this.logoScale = 1.0,
  });

  /// Smallest and largest the logo may be drawn, as a fraction of the space it
  /// is allowed. Below a third it is unreadable on thermal paper; above 1 it
  /// would overrun the box the renderer fits it into.
  static const double minScale = 0.3;
  static const double maxScale = 1.0;

  final ReceiptAlign logoAlign;
  final ReceiptAlign textAlign;

  /// Logo above the name, or the name above the logo.
  final bool logoFirst;

  /// How much of its allowed box the logo fills.
  ///
  /// 1.0 is as large as the mark can print: [receiptLogoMaxWidth] across, or
  /// [receiptLogoMaxHeight] down, whichever binds first. A wordmark usually
  /// wants less.
  final double logoScale;

  double get clampedScale => logoScale.clamp(minScale, maxScale);

  ReceiptHeaderLayout copyWith({
    ReceiptAlign? logoAlign,
    ReceiptAlign? textAlign,
    bool? logoFirst,
    double? logoScale,
  }) {
    return ReceiptHeaderLayout(
      logoAlign: logoAlign ?? this.logoAlign,
      textAlign: textAlign ?? this.textAlign,
      logoFirst: logoFirst ?? this.logoFirst,
      logoScale: logoScale ?? this.logoScale,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReceiptHeaderLayout &&
        other.logoAlign == logoAlign &&
        other.textAlign == textAlign &&
        other.logoFirst == logoFirst &&
        other.logoScale == logoScale;
  }

  @override
  int get hashCode => Object.hash(logoAlign, textAlign, logoFirst, logoScale);
}
