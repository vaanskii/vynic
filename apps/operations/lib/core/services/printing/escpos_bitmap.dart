import 'package:image/image.dart' as imglib;

/// Converts rendered images into ESC/POS raster bitmap bytes.
class EscposBitmap {
  const EscposBitmap._();

  /// Convert image to ESC/POS bitmap format (1-bit)
  /// Uses GS v 0 raster bitmap for line-by-line printing (no horizontal splitting)
  static List<int> convert(imglib.Image image) {
    List<int> bytes = [];

    const gs = 0x1D;

    // Use GS v 0 command for printing raster bitmap.
    // For reliability on some printers, split long images into chunks.
    // GS v 0 m xL xH yL yH d1...dk

    final width = image.width;
    final height = image.height;

    // Width must be multiple of 8
    final widthBytes = (width + 7) ~/ 8;

    // Many 80mm thermal printers cut or ignore the tail of very tall raster
    // payloads, so chunk image height into safe slices.
    const int maxChunkHeight = 256;

    for (int startY = 0; startY < height; startY += maxChunkHeight) {
      final int chunkHeight = (startY + maxChunkHeight <= height)
          ? maxChunkHeight
          : height - startY;

      // GS v 0 command - raster bitmap mode
      bytes.addAll([gs, 0x76, 0x30, 0x00]); // GS v 0 m (m=0 normal)

      // Width in bytes (xL xH)
      bytes.add(widthBytes & 0xFF);
      bytes.add((widthBytes >> 8) & 0xFF);

      // Chunk height in dots (yL yH)
      bytes.add(chunkHeight & 0xFF);
      bytes.add((chunkHeight >> 8) & 0xFF);

      // Convert only this chunk to 1-bit bitmap data
      for (int y = startY; y < startY + chunkHeight; y++) {
        for (int x = 0; x < widthBytes; x++) {
          int byte = 0;
          for (int bit = 0; bit < 8; bit++) {
            final int px = x * 8 + bit;
            if (px < width) {
              final pixel = image.getPixel(px, y);
              final r = pixel.r.toInt();
              final g = pixel.g.toInt();
              final b = pixel.b.toInt();
              final luminance = (0.299 * r + 0.587 * g + 0.114 * b).toInt();

              // Threshold: darker than 128 is printed black.
              if (luminance < 128) {
                byte |= (1 << (7 - bit));
              }
            }
          }
          bytes.add(byte);
        }
      }
    }

    return bytes;
  }
}
