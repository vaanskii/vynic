import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';

/// Shared PIN/number layout. Callers retain their validation and submit rules.
/// Hardware input is focus-scoped, never captured from another dialog/field.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onDigitPressed,
    required this.onClearPressed,
    required this.onDeletePressed,
    this.showDecimalButton = false,
    this.showQuestionButton = false,
    this.onToggleSign,
    this.onSubmit,
    this.enabled = true,
    this.dense = false,
    this.authentication = false,
  });
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onClearPressed;
  final VoidCallback onDeletePressed;
  final bool showDecimalButton;
  final bool showQuestionButton;
  final VoidCallback? onToggleSign;
  final VoidCallback? onSubmit;
  final bool enabled;
  final bool dense;
  final bool authentication;
  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.enabled ||
        event is! KeyDownEvent ||
        ModalRoute.of(context)?.isCurrent == false ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed)
      return KeyEventResult.ignored;
    final c = event.character;
    if (c != null && RegExp(r'^[0-9]$').hasMatch(c)) {
      widget.onDigitPressed(c);
    } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.onDeletePressed();
    } else if (event.logicalKey == LogicalKeyboardKey.delete) {
      widget.onClearPressed();
    } else if ((c == '.' || c == ',') && widget.showDecimalButton) {
      widget.onDigitPressed('.');
    } else if (c == '?' && widget.showQuestionButton) {
      widget.onDigitPressed('?');
    } else if (c == '-' && widget.onToggleSign != null) {
      widget.onToggleSign!();
    } else if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        widget.onSubmit != null) {
      widget.onSubmit!();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _button(String label, VoidCallback action, {IconData? icon}) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: SizedBox(
            height: widget.dense ? 44 : 52,
            child: OutlinedButton(
              onPressed: widget.enabled
                  ? () {
                      _focus.requestFocus();
                      action();
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: VynicFloorTokens.text,
                backgroundColor: VynicFloorTokens.canvas,
                side: const BorderSide(color: VynicFloorTokens.panelBorder),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: icon == null
                  ? Text(
                      label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Tooltip(message: label, child: Icon(icon, size: 22)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _key,
    child: ValueListenableBuilder<bool>(
      valueListenable: PosInputSettings.enabled,
      builder: (context, _, __) => SizedBox(
        width: 340,
        child: !widget.authentication && !PosInputSettings.useOnScreen(context)
            ? OutlinedButton.icon(
                onPressed: widget.enabled ? _focus.requestFocus : null,
                icon: const Icon(Icons.keyboard_outlined),
                label: Text(
                  PosLocale.tr(context, 'გამოიყენეთ ფიზიკური კლავიატურა')!,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 3; row++)
                    Row(
                      children: [
                        for (var col = 1; col <= 3; col++)
                          _button(
                            '${row * 3 + col}',
                            () => widget.onDigitPressed('${row * 3 + col}'),
                          ),
                      ],
                    ),
                  Row(
                    children: [
                      _button(
                        PosLocale.tr(context, 'გასუფთავება')!,
                        widget.onClearPressed,
                        icon: Icons.clear_all_rounded,
                      ),
                      _button('0', () => widget.onDigitPressed('0')),
                      _button(
                        PosLocale.tr(context, 'წაშლა')!,
                        widget.onDeletePressed,
                        icon: Icons.backspace_outlined,
                      ),
                    ],
                  ),
                  if (widget.showDecimalButton ||
                      widget.showQuestionButton ||
                      widget.onToggleSign != null)
                    Row(
                      children: [
                        if (widget.showDecimalButton)
                          _button('.', () => widget.onDigitPressed('.')),
                        if (widget.showQuestionButton)
                          _button('?', () => widget.onDigitPressed('?')),
                        if (widget.onToggleSign != null)
                          _button('+ / −', widget.onToggleSign!),
                      ],
                    ),
                ],
              ),
      ),
    ),
  );
}
