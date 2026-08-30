import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imglib;

import 'package:vynic/core/models/receipt_header_layout.dart';
import 'package:vynic/core/services/pos/venue_logo_service.dart';

/// Preparing a picked file for an 80mm thermal printer.
///
/// The printer is 576 dots wide and has two colours. What an operator picks is
/// a 4000px PNG with a transparent background, so the conversion is where the
/// logo either survives or turns into a black rectangle.

Uint8List _png(int width, int height, {int alpha = 255, imglib.Color? colour}) {
  final image = imglib.Image(width: width, height: height, numChannels: 4);
  imglib.fill(image, color: colour ?? imglib.ColorRgba8(20, 20, 20, alpha));
  return Uint8List.fromList(imglib.encodePng(image));
}

void main() {
  group('sizing', () {
    test('a wide logo is brought down to the paper width', () {
      final result = VenueLogoService.fromBytes(_png(2000, 500));

      expect(result.ok, isTrue);
      expect(result.width, VenueLogoService.maxWidth);
      // Aspect ratio held: 2000x500 is 4:1, so 560 wide is 140 tall.
      expect(result.height, 140);
    });

    test('what is stored is what the renderer will draw at 100%', () {
      // These two used to disagree — the upload capped at 384x160 and the
      // renderer drew into 384x120 — so „100%" printed a fraction of the
      // paper and needed upscaling to do even that.
      expect(VenueLogoService.maxWidth, receiptLogoMaxWidth);
      expect(VenueLogoService.maxHeight, receiptLogoMaxHeight);
    });

    test('a tall logo is bounded by height, not width', () {
      // A crest is taller than it is wide. Scaling it to the paper width would
      // push the order itself off the bottom of the receipt.
      final result = VenueLogoService.fromBytes(_png(400, 2000));

      expect(result.ok, isTrue);
      expect(result.height, VenueLogoService.maxHeight);
      expect(result.width, lessThanOrEqualTo(VenueLogoService.maxWidth));
    });

    test('a wide mark set to 100% very nearly fills the roll', () {
      // The complaint that started this: the slider said 100% and the logo
      // came out small.
      final stored = VenueLogoService.fromBytes(_png(2000, 500));
      final drawn = receiptLogoSize(
        sourceWidth: stored.width.toDouble(),
        sourceHeight: stored.height.toDouble(),
        scale: 1.0,
      );

      expect(drawn.width / receiptPaperWidth, greaterThan(0.9));
    });

    test('a square mark is bounded by height, and is still large', () {
      // It cannot fill the width without becoming 70mm tall, but 21% of the
      // paper — which is what it used to print at — is not „100%" either.
      final stored = VenueLogoService.fromBytes(_png(1000, 1000));
      final drawn = receiptLogoSize(
        sourceWidth: stored.width.toDouble(),
        sourceHeight: stored.height.toDouble(),
        scale: 1.0,
      );

      expect(drawn.height, receiptLogoMaxHeight);
      expect(drawn.width / receiptPaperWidth, greaterThan(0.4));
    });

    test('half means half', () {
      final stored = VenueLogoService.fromBytes(_png(2000, 500));
      final full = receiptLogoSize(
        sourceWidth: stored.width.toDouble(),
        sourceHeight: stored.height.toDouble(),
        scale: 1.0,
      );
      final half = receiptLogoSize(
        sourceWidth: stored.width.toDouble(),
        sourceHeight: stored.height.toDouble(),
        scale: 0.5,
      );

      expect(half.width, closeTo(full.width / 2, 0.01));
      expect(half.height, closeTo(full.height / 2, 0.01));
    });

    test('the PNG header gives back the size without a full decode', () {
      // The settings slider needs it on every frame to say how many
      // millimetres wide the mark will print.
      final stored = VenueLogoService.fromBytes(_png(300, 120));
      final size = VenueLogoService.pngSize(stored.png!);

      expect(size, isNotNull);
      expect(size!.width, 300);
      expect(size.height, 120);
    });

    test('a non-PNG has no readable size, rather than a made-up one', () {
      expect(
        VenueLogoService.pngSize(Uint8List.fromList(List.filled(64, 7))),
        isNull,
      );
    });

    test('a small logo is left at its own size', () {
      // Upscaling a 120px mark to 384 only makes the printer's dithering more
      // obvious.
      final result = VenueLogoService.fromBytes(_png(120, 60));

      expect(result.ok, isTrue);
      expect(result.width, 120);
      expect(result.height, 60);
    });
  });

  group('transparency', () {
    test('a transparent background becomes white, not black', () {
      // The raster conversion throws alpha away rather than honouring it, so a
      // logo with a transparent background used to print as a solid block.
      final result = VenueLogoService.fromBytes(
        _png(100, 100, alpha: 0, colour: imglib.ColorRgba8(0, 0, 0, 0)),
      );

      expect(result.ok, isTrue);
      final decoded = imglib.decodeImage(result.png!)!;
      final corner = decoded.getPixel(0, 0);
      expect(
        corner.r,
        greaterThan(250),
        reason: 'transparent pixels did not flatten to white',
      );
    });

    test('mid grey becomes solid ink or solid paper, never grey', () {
      // A thermal head has one dot and no shades: greyscale reaches the paper
      // as dithering, which on 80mm stock is a smudge. Every pixel is one or
      // the other by the time it is stored.
      final result = VenueLogoService.fromBytes(
        _png(60, 60, colour: imglib.ColorRgba8(120, 120, 120, 255)),
      );

      final decoded = imglib.decodeImage(result.png!)!;
      for (var y = 0; y < decoded.height; y += 7) {
        for (var x = 0; x < decoded.width; x += 7) {
          final value = decoded.getPixel(x, y).r;
          expect(value == 0 || value == 255, isTrue, reason: 'grey at $x,$y');
        }
      }
    });

    test('the threshold decides what counts as ink', () {
      // The same mid grey, read two ways: a wordmark wants only the darkest
      // parts, a photographic mark needs the mid-tones.
      final source = _png(
        20,
        20,
        colour: imglib.ColorRgba8(120, 120, 120, 255),
      );

      final strict = VenueLogoService.fromBytes(source, threshold: 60);
      final loose = VenueLogoService.fromBytes(source, threshold: 200);

      expect(imglib.decodeImage(strict.png!)!.getPixel(5, 5).r, 255);
      expect(imglib.decodeImage(loose.png!)!.getPixel(5, 5).r, 0);
    });

    test('a mark that is nearly all ink is flagged before it prints', () {
      // It comes out as a black slab and empties the paper roll.
      final result = VenueLogoService.fromBytes(
        _png(50, 50, colour: imglib.ColorRgba8(0, 0, 0, 255)),
      );

      expect(result.inkRatio, greaterThan(0.9));
      expect(result.isVeryHeavy, isTrue);
    });

    test('real ink survives the flattening', () {
      final result = VenueLogoService.fromBytes(
        _png(100, 100, colour: imglib.ColorRgba8(0, 0, 0, 255)),
      );

      final decoded = imglib.decodeImage(result.png!)!;
      expect(decoded.getPixel(50, 50).r, lessThan(10));
    });
  });

  group('refusals', () {
    test('something that is not an image is refused, not crashed on', () {
      final result = VenueLogoService.fromBytes(
        Uint8List.fromList('this is a text file'.codeUnits),
      );

      expect(result.ok, isFalse);
      expect(result.error, VenueLogoService.notAnImage);
      expect(result.png, isNull);
    });

    test('a missing file is refused', () async {
      final result = await VenueLogoService.fromFile('/no/such/logo.png');

      expect(result.ok, isFalse);
      expect(result.error, VenueLogoService.unreadable);
    });
  });

  test('the stored bytes are a decodable PNG, not the original file', () {
    // What goes in the database is what the printer draws. Storing the source
    // untouched would mean the operator never sees the conversion until a
    // customer is holding the receipt.
    final source = _png(1200, 400);
    final result = VenueLogoService.fromBytes(source);

    expect(result.png, isNot(equals(source)));
    expect(imglib.decodeImage(result.png!), isNotNull);
    expect(result.png!.length, lessThan(source.length));
  });
}
