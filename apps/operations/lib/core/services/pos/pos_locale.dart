import 'package:flutter/material.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'pos_strings.dart';

/// POS-only locale dependency above the Navigator, so already-open routes and
/// dialogs update without replacing their state, controllers or draft data.
class PosLocale extends InheritedWidget {
  const PosLocale({super.key, required this.language, required super.child});
  final String language;
  static String code(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PosLocale>()?.language ?? 'ka';
  static String? tr(BuildContext context, String? message) {
    if (message == null || code(context) != 'en') return message;
    return posEnglish[message] ?? message;
  }

  @override
  bool updateShouldNotify(PosLocale oldWidget) =>
      language != oldWidget.language;
}

class PosLocaleHost extends StatelessWidget {
  const PosLocaleHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final box = DatabaseCore.settingsBox;
    if (box == null) return PosLocale(language: 'ka', child: child);
    return ValueListenableBuilder(
      valueListenable: box.listenable(keys: ['defaultLanguage']),
      builder: (context, _, __) => PosLocale(
        language: SettingsRepository.getDefaultLanguage(),
        child: child,
      ),
    );
  }
}
