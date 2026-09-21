import 'package:flutter/material.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';

/// Compatibility adapter for embedded POS keyboards; all keys live in PosKeyboard.
class OnScreenKeyboard extends StatelessWidget {
  const OnScreenKeyboard({
    super.key,
    required this.controller,
    required this.language,
    required this.onClose,
    this.onEnter,
    this.showHeader = true,
  });
  final TextEditingController controller;
  final String language;
  final VoidCallback onClose;
  final VoidCallback? onEnter;
  final bool showHeader;
  @override
  Widget build(BuildContext context) => PosKeyboard(
    controller: controller,
    initialLanguage: PosKeyboardLanguage.fromCode(language),
    onClose: onClose,
    onEnter: onEnter,
    showHeader: showHeader,
    showPreview: false,
  );
}
