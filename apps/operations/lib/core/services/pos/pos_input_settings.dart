import 'package:flutter/material.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';

/// Local POS preference. Manager never activates this controller.
class PosInputSettings {
  PosInputSettings._();
  static final enabled = ValueNotifier<bool>(true);
  static bool active = false;
  static final keyboardHeight = ValueNotifier<double>(0);
  static bool get showKeyboard => !active || enabled.value;

  static bool useOnScreen(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<PosInputScope>();
    return showKeyboard;
  }

  static void load() {
    active = true;
    enabled.value = SettingsRepository.getPosOnScreenInputEnabled();
  }

  static Future<void> save(bool value) async {
    await SettingsRepository.setPosOnScreenInputEnabled(value);
    enabled.value = value;
  }
}

class PosInputScope extends InheritedNotifier<ValueNotifier<bool>> {
  PosInputScope({super.key, required Widget child})
    : super(
        notifier: PosInputSettings.enabled,
        child: _PosKeyboardViewport(child: child),
      );
}

class _PosKeyboardViewport extends StatelessWidget {
  const _PosKeyboardViewport({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: PosInputSettings.keyboardHeight,
    builder: (context, height, _) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          viewInsets: media.viewInsets.copyWith(
            bottom: height > media.viewInsets.bottom
                ? height
                : media.viewInsets.bottom,
          ),
        ),
        child: child,
      );
    },
  );
}
