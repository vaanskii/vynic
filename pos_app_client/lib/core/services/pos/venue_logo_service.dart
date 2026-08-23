import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as imglib;

/// Turning a file someone picked into something a receipt printer can print.
///
/// A thermal printer is 576 dots wide and has exactly two colours. Handing it
/// a 4000px logo with a gradient and an alpha channel gets you a grey smear,
/// so the file is resized, flattened onto white and re-encoded before it is
/// ever stored. Doing it here rather than at print time means the operator
/// sees, at the moment they upload, what will actually come out of the
/// printer.
abstract final class VenueLogoService {
  /// Stored at exactly the size the renderer is willing to draw.
  ///
  /// These used to be smaller than the draw box (384x160 against a 576-wide
  /// roll), so the upload threw away resolution the renderer then wanted back —
  /// and a logo set to „100%" printed at a fraction of the paper. Matching the
  /// two means 100% needs no upscaling and looks like what was uploaded.
  static const int maxWidth = 560;
  static const int maxHeight = 260;

  /// Refuses anything that is not plausibly an image before decoding it.
  static const int maxSourceBytes = 12 * 1024 * 1024;

  /// What went wrong, so the caller can say which.
  static const String unreadable = 'unreadable';
  static const String tooLarge = 'tooLarge';
  static const String notAnImage = 'notAnImage';

  /// The pixel size of a stored PNG, read from its header.
  ///
  /// Cheaper than decoding, and the settings panel needs it on every frame to
  /// say how wide the mark will print. IHDR is always the first chunk: an
  /// 8-byte signature, a 4-byte length, the tag, then width and height as
  /// big-endian 32-bit integers.
  static ({int width, int height})? pngSize(Uint8List png) {
    if (png.length < 24) return null;
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < signature.length; i++) {
      if (png[i] != signature[i]) return null;
    }
    if (png[12] != 0x49 || png[13] != 0x48 || png[14] != 0x44) return null;

    int readUint32(int at) =>
        (png[at] << 24) |
        (png[at + 1] << 16) |
        (png[at + 2] << 8) |
        png[at + 3];

    final width = readUint32(16);
    final height = readUint32(20);
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }

  /// How much of the mark is ink, 0–1.
  ///
  /// Surfaced so the operator can be warned before they print: a logo that is
  /// 90% black empties the paper roll and comes out as a rectangle.
  static double _inkRatio(imglib.Image image) {
    var ink = 0;
    var total = 0;
    for (final pixel in image) {
      total++;
      if (pixel.r < 128) ink++;
    }
    return total == 0 ? 0 : ink / total;
  }

  /// Reads [path] and returns print-ready PNG bytes, or a failure reason.
  static Future<VenueLogoResult> fromFile(String path, {int? threshold}) async {
    final file = File(path);
    Uint8List raw;
    try {
      if (!await file.exists()) {
        return const VenueLogoResult.failed(unreadable);
      }
      final length = await file.length();
      if (length > maxSourceBytes) {
        return const VenueLogoResult.failed(tooLarge);
      }
      raw = await file.readAsBytes();
    } catch (error, stackTrace) {
      developer.log(
        'Could not read logo file',
        error: error,
        stackTrace: stackTrace,
        name: 'VenueLogoService',
      );
      return const VenueLogoResult.failed(unreadable);
    }

    return fromBytes(raw, threshold: threshold);
  }

  /// How dark a pixel has to be to become ink, 0–255.
  ///
  /// Lower prints less: only the darkest parts of the image survive, which is
  /// what a clean wordmark wants. Higher catches mid-tones, which a
  /// photographic mark needs and a line drawing does not.
  static const int defaultThreshold = 160;

  /// The same, for bytes that are already in hand.
  static VenueLogoResult fromBytes(Uint8List raw, {int? threshold}) {
    final decoded = imglib.decodeImage(raw);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return const VenueLogoResult.failed(notAnImage);
    }

    // Flatten onto white first. A PNG with a transparent background prints as
    // a black rectangle otherwise — the alpha is thrown away by the raster
    // conversion, not honoured by it.
    final flattened = imglib.Image(
      width: decoded.width,
      height: decoded.height,
    );
    imglib.fill(flattened, color: imglib.ColorRgb8(255, 255, 255));
    imglib.compositeImage(flattened, decoded);

    final needsResize =
        flattened.width > maxWidth || flattened.height > maxHeight;
    final sized = needsResize
        ? imglib.copyResize(
            flattened,
            width: flattened.width / maxWidth >= flattened.height / maxHeight
                ? maxWidth
                : null,
            height: flattened.width / maxWidth >= flattened.height / maxHeight
                ? null
                : maxHeight,
            interpolation: imglib.Interpolation.average,
          )
        : flattened;

    // Traced to solid black on white rather than left as greyscale.
    //
    // A thermal head has one dot and no shades. Handing it a grey image makes
    // it dither, and dithered grey on 80mm paper is a smudge — the reason an
    // uploaded logo comes out looking nothing like the file. Thresholding
    // first gives hard edges: the mark prints as the shape it is, which is
    // what „make it a vector" means once it reaches paper.
    final grey = imglib.grayscale(sized);
    final cut = threshold ?? defaultThreshold;
    for (final pixel in grey) {
      final ink = pixel.r <= cut;
      final value = ink ? 0 : 255;
      pixel
        ..r = value
        ..g = value
        ..b = value
        ..a = 255;
    }

    return VenueLogoResult.ready(
      png: Uint8List.fromList(imglib.encodePng(grey)),
      width: grey.width,
      height: grey.height,
      inkRatio: _inkRatio(grey),
    );
  }
}

/// A prepared logo, or why one could not be prepared.
class VenueLogoResult {
  const VenueLogoResult.ready({
    required this.png,
    required this.width,
    required this.height,
    this.inkRatio = 0,
  }) : error = null;

  const VenueLogoResult.failed(this.error)
    : png = null,
      width = 0,
      height = 0,
      inkRatio = 0;

  final Uint8List? png;
  final int width;
  final int height;

  /// Fraction of the mark that will print as ink.
  final double inkRatio;
  final String? error;

  bool get ok => error == null && png != null;

  /// Mostly black. Prints as a slab and drinks the paper roll — worth saying
  /// so at upload rather than after a shift's worth of receipts.
  bool get isVeryHeavy => inkRatio > 0.55;
}
