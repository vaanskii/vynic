import 'package:vynic/core/widgets/pos_text.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';

Future<void> showPosKeyboardSheet({
  required BuildContext context,
  required TextEditingController controller,
  PosKeyboardLanguage initialLanguage = PosKeyboardLanguage.georgian,
  String? title,
  bool standalone = false,
  bool followLocale = true,
}) async {
  await showPosKeyboardInputSheet(
    context: context,
    controller: controller,
    initialLanguage: initialLanguage,
    title: title,
    standalone: standalone,
    followLocale: followLocale,
  );
}

Future<String?> showPosKeyboardInputSheet({
  required BuildContext context,
  required TextEditingController controller,
  PosKeyboardLanguage initialLanguage = PosKeyboardLanguage.georgian,
  String? title,
  bool standalone = false,
  bool followLocale = true,
}) async {
  if (!PosInputSettings.useOnScreen(context)) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: PosText(title ?? 'ტექსტის შეყვანა'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const PosText('გაუქმება'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const PosText('შენახვა'),
          ),
        ],
      ),
    );
  }
  final screenWidth = MediaQuery.sizeOf(context).width;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    elevation: 0,
    enableDrag: false,
    constraints: BoxConstraints(minWidth: screenWidth, maxWidth: screenWidth),
    builder: (sheetContext) {
      void closeWithValue() {
        Navigator.pop(sheetContext, controller.text.trim());
      }

      return _KeyboardDock(
        child: SizedBox(
          width: MediaQuery.sizeOf(sheetContext).width,
          child: PosKeyboard(
            controller: controller,
            initialLanguage: initialLanguage,
            title: title,
            showPreview: standalone,
            followLocale: followLocale,
            onClose: closeWithValue,
            onEnter: closeWithValue,
          ),
        ),
      );
    },
  );
}

Future<String?> showPosNumberKeyboardInputSheet({
  required BuildContext context,
  required String initialValue,
  TextEditingController? controller,
  required String title,
  int maxDigits = 15,
  bool pin = false,
  bool allowDecimal = false,
  bool allowQuestionMark = false,
  int maxDecimalPlaces = 2,
}) async {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final editing =
      controller ?? TextEditingController(text: initialValue.trim());
  void changed(String next) {
    editing.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  String? nextValueAfterDigit(String currentValue, String digit) {
    if (digit == '?') return allowQuestionMark ? '?' : null;
    if (digit == '.' && (!allowDecimal || maxDecimalPlaces == 0 || pin))
      return null;
    final selection = editing.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, currentValue.length)
        : currentValue.length;
    final end = selection.isValid
        ? selection.end.clamp(start, currentValue.length)
        : currentValue.length;
    var proposed = currentValue == '?'
        ? digit
        : currentValue.replaceRange(start, end, digit);
    if (proposed == '.') proposed = '0.';
    if ('.'.allMatches(proposed).length > 1 ||
        proposed.replaceAll('.', '').length > maxDigits)
      return null;
    if (proposed.contains('.') &&
        proposed.split('.').last.length > maxDecimalPlaces)
      return null;
    return proposed;
  }

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    elevation: 0,
    enableDrag: false,
    constraints: BoxConstraints(minWidth: screenWidth, maxWidth: screenWidth),
    builder: (sheetContext) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: editing,
      builder: (context, value, _) => _KeyboardDock(
        onDisposed: controller == null ? editing.dispose : null,
        child: _PosNumberKeyboardSheet(
          title: title,
          value: value.text,
          pin: pin,
          showValue: controller == null,
          allowDecimal: allowDecimal,
          allowQuestionMark: allowQuestionMark,
          onDigit: (digit) {
            final next = nextValueAfterDigit(editing.text, digit);
            if (next != null) changed(next);
          },
          onDelete: () {
            if (editing.text.isNotEmpty)
              changed(editing.text.substring(0, editing.text.length - 1));
          },
          onClear: () => changed(''),
          onClose: () => Navigator.pop(sheetContext),
          onSave: () => Navigator.pop(sheetContext, editing.text.trim()),
        ),
      ),
    ),
  );
}

class _PosNumberKeyboardSheet extends StatelessWidget {
  const _PosNumberKeyboardSheet({
    required this.title,
    required this.value,
    this.pin = false,
    this.showValue = true,
    required this.allowDecimal,
    required this.allowQuestionMark,
    required this.onDigit,
    required this.onDelete,
    required this.onClear,
    required this.onClose,
    required this.onSave,
  });

  static const Color _panel = Colors.white;
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _accent = VynicFloorTokens.accentStrong;
  static const Color _accentDark = VynicFloorTokens.accentStrong;

  final String title;
  final String value;
  final bool pin;
  final bool showValue;
  final bool allowDecimal;
  final bool allowQuestionMark;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: _panel,
          border: Border(top: BorderSide(color: _border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.dialpad, color: _accentDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PosText(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onSave,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const PosText('შენახვა'),
                      style: TextButton.styleFrom(
                        foregroundColor: _accentDark,
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: PosLocale.tr(context, 'დახურვა'),
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                      color: _muted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (showValue)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _border),
                    ),
                    child: PosText(
                      value.isEmpty
                          ? (allowQuestionMark
                                ? 'დააჭირეთ ციფრებს ან ?'
                                : 'დააჭირეთ ციფრებს შესაყვანად')
                          : pin
                          ? '•' * value.length
                          : value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: value.isEmpty ? _muted : _text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                PinPad(
                  authentication: pin,
                  onDigitPressed: onDigit,
                  onDeletePressed: onDelete,
                  onClearPressed: onClear,
                  onSubmit: onSave,
                  showDecimalButton: allowDecimal,
                  showQuestionButton: allowQuestionMark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyboardDock extends StatefulWidget {
  const _KeyboardDock({required this.child, this.onDisposed});
  final VoidCallback? onDisposed;
  final Widget child;
  @override
  State<_KeyboardDock> createState() => _KeyboardDockState();
}

class _KeyboardDockState extends State<_KeyboardDock> {
  @override
  void dispose() {
    widget.onDisposed?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PosInputSettings.keyboardHeight.value = 0;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        PosInputSettings.keyboardHeight.value = context.size?.height ?? 0;
    });
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: widget.child,
    );
  }
}
