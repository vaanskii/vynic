import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'core/services/sync/api_config.dart';
import 'startup_pos.dart';

Future<void> main() async {
  final macDevelopment =
      Platform.isMacOS && kDebugMode && ApiConfig.environment == 'development';
  if (!Platform.isWindows && !macDevelopment) {
    throw UnsupportedError(
      'Vynic POS requires Windows, or macOS debug development',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  await startPos();
}
