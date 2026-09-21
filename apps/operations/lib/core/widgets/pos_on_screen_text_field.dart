import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_input_mode.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
export 'package:vynic/core/widgets/pos_keyboard/pos_input_mode.dart';

bool shouldUsePosOnScreenKeyboard([BuildContext? context]) =>
    !kIsWeb &&
    (context == null
        ? PosInputSettings.showKeyboard
        : PosInputSettings.useOnScreen(context)) &&
    (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

Future<void> showPosOnScreenKeyboardSheet({
  required BuildContext context,
  required TextEditingController controller,
  String language = 'ka',
}) => showPosKeyboardSheet(
  context: context,
  controller: controller,
  initialLanguage: PosKeyboardLanguage.fromCode(language),
);

/// The focused form controller is the only editing buffer. Both hardware and
/// touch edits notify consumers immediately, including programmatic key edits.
class PosOnScreenTextField extends StatefulWidget {
  const PosOnScreenTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.style,
    this.keyboardLanguage,
    this.onChanged,
    this.maxLines = 1,
    this.enabled = true,
    this.mode = PosInputMode.text,
    this.focusNode,
    this.inputFormatters,
    this.maxDigits = 15,
    this.allowQuestionMark = false,
    this.maxDecimalPlaces = 2,
  });
  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final String? keyboardLanguage;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool enabled;
  final PosInputMode mode;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final int maxDigits;
  final bool allowQuestionMark;
  final int maxDecimalPlaces;
  @override
  State<PosOnScreenTextField> createState() => _PosFieldState();
}

class _PosFieldState extends State<PosOnScreenTextField> {
  late String _last;
  bool _opening = false;
  bool _normalizing = false;
  @override
  void initState() {
    super.initState();
    _listen();
    PosInputSettings.keyboardHeight.addListener(_keepVisible);
  }

  void _keepVisible() {
    if (!_opening || PosInputSettings.keyboardHeight.value == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _opening)
        Scrollable.ensureVisible(
          context,
          alignment: 0,
          duration: const Duration(milliseconds: 120),
        );
    });
  }

  void _listen() {
    _last = widget.controller.text;
    widget.controller.addListener(_changed);
  }

  List<TextInputFormatter> get _formatters {
    if (widget.inputFormatters != null) return widget.inputFormatters!;
    if (widget.mode == PosInputMode.text) return const [];
    return [
      TextInputFormatter.withFunction((old, next) {
        if (widget.allowQuestionMark && next.text == '?') return next;
        final decimal = widget.mode == PosInputMode.decimal;
        final valid = RegExp(
          decimal ? r'^\d*(\.\d*)?$' : r'^\d*$',
        ).hasMatch(next.text);
        final limit = widget.mode == PosInputMode.pin ? 6 : widget.maxDigits;
        if (!valid || next.text.replaceAll('.', '').length > limit) return old;
        if (decimal &&
            next.text.contains('.') &&
            next.text.split('.').last.length > widget.maxDecimalPlaces)
          return old;
        return next;
      }),
    ];
  }

  void _changed() {
    if (_normalizing) return;
    var value = widget.controller.value;
    final old = TextEditingValue(
      text: _last,
      selection: TextSelection.collapsed(offset: _last.length),
    );
    for (final formatter in _formatters) {
      value = formatter.formatEditUpdate(old, value);
    }
    if (value != widget.controller.value) {
      _normalizing = true;
      widget.controller.value = value;
      _normalizing = false;
    }
    final text = value.text;
    if (_last == text) return;
    _last = text;
    widget.onChanged?.call(text);
  }

  @override
  void didUpdateWidget(covariant PosOnScreenTextField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      _listen();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    PosInputSettings.keyboardHeight.removeListener(_keepVisible);
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    await Scrollable.ensureVisible(
      context,
      alignment: 0,
      duration: const Duration(milliseconds: 160),
    );
    if (!mounted) {
      _opening = false;
      return;
    }
    try {
      if (widget.mode == PosInputMode.text) {
        await showPosKeyboardInputSheet(
          context: context,
          controller: widget.controller,
          title: widget.decoration.labelText,
          followLocale: widget.keyboardLanguage == null,
          initialLanguage: PosKeyboardLanguage.fromCode(
            widget.keyboardLanguage ?? PosLocale.code(context),
          ),
        );
      } else {
        await showPosNumberKeyboardInputSheet(
          context: context,
          initialValue: widget.controller.text,
          controller: widget.controller,
          title: widget.decoration.labelText ?? '',
          allowDecimal: widget.mode == PosInputMode.decimal,
          pin: widget.mode == PosInputMode.pin,
          maxDigits: widget.maxDigits,
          allowQuestionMark: widget.allowQuestionMark,
          maxDecimalPlaces: widget.maxDecimalPlaces,
        );
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final touch =
        widget.mode == PosInputMode.pin ||
        shouldUsePosOnScreenKeyboard(context);
    final numeric = widget.mode != PosInputMode.text;
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      readOnly: touch,
      showCursor: true,
      obscureText: widget.mode == PosInputMode.pin,
      enableSuggestions: widget.mode != PosInputMode.pin,
      autocorrect: !numeric,
      maxLines: widget.maxLines,
      style: widget.style,
      keyboardType: numeric
          ? TextInputType.numberWithOptions(
              decimal: widget.mode == PosInputMode.decimal,
            )
          : TextInputType.text,
      inputFormatters: _formatters,
      onTap: touch && widget.enabled ? _open : null,
      decoration: widget.decoration.copyWith(
        labelText: PosLocale.tr(context, widget.decoration.labelText),
        hintText: PosLocale.tr(context, widget.decoration.hintText),
      ),
    );
  }
}
