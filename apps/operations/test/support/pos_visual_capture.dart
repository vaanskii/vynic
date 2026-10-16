import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/ui/pos_theme.dart';

const posVisualKey = ValueKey('pos-visual-fixture');
Future<void> loadPosVisualFonts() async {
  await (FontLoader(
    PosTheme.fontFamily,
  )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> capturePosVisual(WidgetTester tester, String name) async {
  final destination = Platform.environment['POS_UI_PROOF_DIR'];
  if (destination == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(posVisualKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(destination).create(recursive: true);
    await File(
      '$destination/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
