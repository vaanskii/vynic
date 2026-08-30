import 'package:flutter/material.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';

Future<void> showPosKeyboardSheet({
  required BuildContext context,
  required TextEditingController controller,
  PosKeyboardLanguage initialLanguage = PosKeyboardLanguage.georgian,
  String? title,
}) async {
  await showPosKeyboardInputSheet(
    context: context,
    controller: controller,
    initialLanguage: initialLanguage,
    title: title,
  );
}

Future<String?> showPosKeyboardInputSheet({
  required BuildContext context,
  required TextEditingController controller,
  PosKeyboardLanguage initialLanguage = PosKeyboardLanguage.georgian,
  String? title,
}) async {
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

      return SizedBox(
        width: MediaQuery.sizeOf(sheetContext).width,
        child: PosKeyboard(
          controller: controller,
          initialLanguage: initialLanguage,
          title: title,
          onClose: closeWithValue,
          onEnter: closeWithValue,
        ),
      );
    },
  );
}

Future<String?> showPosNumberKeyboardInputSheet({
  required BuildContext context,
  required String initialValue,
  required String title,
  int maxDigits = 15,
  bool allowDecimal = false,
  bool allowQuestionMark = false,
  int maxDecimalPlaces = 2,
}) async {
  final screenWidth = MediaQuery.sizeOf(context).width;
  var value = initialValue.trim();

  String? nextValueAfterDigit(String currentValue, String digit) {
    if (digit == '?') {
      if (!allowQuestionMark) return null;
      return '?';
    }

    if (digit == '.') {
      if (!allowDecimal ||
          maxDecimalPlaces == 0 ||
          currentValue.contains('.')) {
        return null;
      }
      return currentValue.isEmpty ? '0.' : '$currentValue.';
    }

    if (currentValue == '?') {
      return digit;
    }

    final proposed = currentValue.isEmpty || currentValue == '0'
        ? digit
        : '$currentValue$digit';
    final digitsOnly = proposed.replaceAll('.', '');
    if (digitsOnly.length > maxDigits) return null;

    if (allowDecimal && proposed.contains('.')) {
      final parts = proposed.split('.');
      if (parts.length > 1 && parts.last.length > maxDecimalPlaces) {
        return null;
      }
    }
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
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return _PosNumberKeyboardSheet(
            title: title,
            value: value,
            allowDecimal: allowDecimal,
            allowQuestionMark: allowQuestionMark,
            onDigit: (digit) {
              setSheetState(() {
                final next = nextValueAfterDigit(value, digit);
                if (next != null) value = next;
              });
            },
            onDelete: () {
              setSheetState(() {
                if (value.isNotEmpty) {
                  value = value.substring(0, value.length - 1);
                }
              });
            },
            onClear: () {
              setSheetState(() {
                value = '';
              });
            },
            onClose: () => Navigator.pop(sheetContext),
            onSave: () => Navigator.pop(sheetContext, value.trim()),
          );
        },
      );
    },
  );
}

class _PosNumberKeyboardSheet extends StatelessWidget {
  const _PosNumberKeyboardSheet({
    required this.title,
    required this.value,
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
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _accentDark = Color(0xFF0F766E);
  static const Color _danger = Color(0xFFFEE2E2);
  static const Color _dangerText = Color(0xFFB91C1C);

  final String title;
  final String value;
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
                      child: Text(
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
                      label: const Text('შენახვა'),
                      style: TextButton.styleFrom(
                        foregroundColor: _accentDark,
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'დახურვა',
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                      color: _muted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                  child: Text(
                    value.isEmpty
                        ? (allowQuestionMark
                              ? 'დააჭირეთ ციფრებს ან ?'
                              : 'დააჭირეთ ციფრებს შესაყვანად')
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.15,
                    children: [
                      for (final digit in const [
                        '1',
                        '2',
                        '3',
                        '4',
                        '5',
                        '6',
                        '7',
                        '8',
                        '9',
                      ])
                        _NumberKey(label: digit, onTap: () => onDigit(digit)),
                      _NumberKey(
                        label: allowDecimal
                            ? '.'
                            : (allowQuestionMark ? '?' : 'Clear'),
                        background: allowDecimal || allowQuestionMark
                            ? null
                            : _danger,
                        foreground: allowDecimal || allowQuestionMark
                            ? null
                            : _dangerText,
                        onTap: allowDecimal
                            ? () => onDigit('.')
                            : (allowQuestionMark
                                  ? () => onDigit('?')
                                  : onClear),
                      ),
                      _NumberKey(label: '0', onTap: () => onDigit('0')),
                      _NumberKey(
                        icon: Icons.backspace_outlined,
                        onTap: onDelete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberKey extends StatelessWidget {
  const _NumberKey({
    required this.onTap,
    this.label,
    this.icon,
    this.background,
    this.foreground,
  });

  static const Color _border = Color(0xFFE5E7EB);
  static const Color _text = Color(0xFF111827);
  static const Color _surface = Color(0xFFF9FAFB);
  static const Color _accent = Color(0xFF14B8A6);

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? _text;
    return Material(
      color: background ?? _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: _accent.withValues(alpha: 0.14),
        highlightColor: _accent.withValues(alpha: 0.08),
        child: Center(
          child: icon != null
              ? Icon(icon, color: fg, size: 21)
              : Text(
                  label ?? '',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}
