import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';

/// True on desktop POS targets (Windows/macOS/Linux) where we show the bottom sheet keyboard.
bool shouldUsePosOnScreenKeyboard() {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

/// Full-width bottom sheet keyboard (transparent barrier), shared by Windows POS and manager app on desktop.
Future<void> showPosOnScreenKeyboardSheet({
  required BuildContext context,
  required TextEditingController controller,
  String language = 'ka',
}) async {
  await showPosKeyboardSheet(
    context: context,
    controller: controller,
    initialLanguage: PosKeyboardLanguage.fromCode(language),
  );
}

/// Text field that opens [showPosOnScreenKeyboardSheet] on desktop; normal keyboard on mobile OS.
class PosOnScreenTextField extends StatelessWidget {
  const PosOnScreenTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.style,
    this.keyboardLanguage = 'ka',
    this.onChanged,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final String keyboardLanguage;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  Future<void> _openKeyboard(BuildContext context) async {
    await showPosOnScreenKeyboardSheet(
      context: context,
      controller: controller,
      language: keyboardLanguage,
    );
    onChanged?.call(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldUsePosOnScreenKeyboard()) {
      return TextField(
        controller: controller,
        style: style,
        decoration: decoration,
        onChanged: onChanged,
        maxLines: maxLines,
      );
    }

    return InkWell(
      onTap: () => _openKeyboard(context),
      borderRadius: BorderRadius.circular(12),
      child: IgnorePointer(
        child: TextField(
          controller: controller,
          readOnly: true,
          style: style,
          decoration: decoration,
          maxLines: maxLines,
        ),
      ),
    );
  }
}
