import 'dart:io';
import 'package:flutter/widgets.dart';
import 'startup_pos.dart';

Future<void> main() async {
  if (!Platform.isWindows)
    throw UnsupportedError('Vynic POS supports Windows only');
  WidgetsFlutterBinding.ensureInitialized();
  await startPos();
}
