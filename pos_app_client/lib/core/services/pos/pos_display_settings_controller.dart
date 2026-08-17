import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/services/database_service.dart';

class PosDisplaySettingsController {
  PosDisplaySettingsController._();

  static final ValueNotifier<PosDisplaySettings> settings =
      ValueNotifier<PosDisplaySettings>(PosDisplaySettings.defaults);

  static Future<void> loadFromStorage() async {
    final next = DatabaseService.getPosDisplaySettings();
    settings.value = next;
    await _applyFullscreenMode(next.fullscreenPosMode);
  }

  static Future<void> save(PosDisplaySettings next) async {
    await DatabaseService.setPosDisplaySettings(next);
    settings.value = next;
    await _applyFullscreenMode(next.fullscreenPosMode);
  }

  static Future<void> preview(PosDisplaySettings next) async {
    settings.value = next;
    await _applyFullscreenMode(next.fullscreenPosMode);
  }

  static Future<void> _applyFullscreenMode(bool enabled) async {
    if (enabled) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}
