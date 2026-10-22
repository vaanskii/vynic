import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Real fonts for captures (flutter_test otherwise renders the box font).
Future<void> loadCaptureFonts() async {
  const mf = '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String p) async => ByteData.view(Uint8List.fromList(File(p).readAsBytesSync()).buffer);
  final noto = FontLoader('NotoSansGeorgian')..addFont(f('assets/fonts/NotoSansGeorgian.ttf'));
  await noto.load();
  // Default family (no fontFamily) → the app's bundled Georgian face, like OS fallback on the real device.
  final roboto = FontLoader('Roboto')..addFont(f('assets/fonts/NotoSansGeorgian.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(f('$mf/MaterialIcons-Regular.otf'));
  await icons.load();
  // monospace + default families fall back to Roboto
  for (final fam in ['monospace', '.SF UI Text', '.AppleSystemUIFont', 'Segoe UI', 'FlutterTest', 'Ahem']) {
    final l = FontLoader(fam)..addFont(f('assets/fonts/NotoSansGeorgian.ttf'));
    await l.load();
  }
}
