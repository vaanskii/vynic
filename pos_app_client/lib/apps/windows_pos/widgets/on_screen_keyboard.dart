import 'package:flutter/material.dart';

class OnScreenKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final String language; // 'en' or 'ka'
  final VoidCallback onClose;
  final VoidCallback? onEnter; // Optional callback for Enter key
  final bool showHeader;

  const OnScreenKeyboard({
    super.key,
    required this.controller,
    required this.language,
    required this.onClose,
    this.onEnter,
    this.showHeader = true,
  });

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  bool _isShiftPressed = false;
  bool _isCapsLockOn = false;

  static const Color _backgroundColor = Colors.white;
  static const Color _headerColor = Color(0xFFF9FAFB);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _surfaceColor = Colors.white;
  static const Color _specialSurfaceColor = Color(0xFFEDF0F8);
  static const Color _textColor = Color(0xFF1F2430);
  static const Color _mutedTextColor = Color(0xFF4B5563);
  static const Color _accentColor = Color(0xFFB48A57);
  static const Color _dangerColor = Color(0xFFFFE8E5);
  static const Color _dangerBorderColor = Color(0xFFF5B5AE);

  // English QWERTY layout
  static const List<List<String>> _englishLayout = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  // Georgian QWERTY layout
  static const List<List<String>> _georgianLayout = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['ქ', 'წ', 'ე', 'რ', 'ტ', 'ყ', 'უ', 'ი', 'ო', 'პ'],
    ['ა', 'ს', 'დ', 'ფ', 'გ', 'ჰ', 'ჯ', 'კ', 'ლ'],
    ['ზ', 'ხ', 'ც', 'ვ', 'ბ', 'ნ', 'მ'],
  ];

  // Georgian shift mappings
  static const Map<String, String> _georgianShiftMap = {
    'ს': 'შ',
    'რ': 'ღ',
    'ჯ': 'ჟ',
    'წ': 'ჭ',
    'ტ': 'თ',
    'ც': 'ჩ',
    'ზ': 'ძ',
  };

  // Ensure selection indices stay within the current text bounds.
  TextSelection _sanitizeSelection() {
    final textLength = widget.controller.text.length;
    int start = widget.controller.selection.start;
    int end = widget.controller.selection.end;

    if (start < 0 || start > textLength) {
      start = textLength;
    }
    if (end < 0 || end > textLength) {
      end = textLength;
    }
    if (start > end) {
      final temp = start;
      start = end;
      end = temp;
    }

    final sanitized = TextSelection(baseOffset: start, extentOffset: end);
    if (sanitized != widget.controller.selection) {
      widget.controller.selection = sanitized;
    }
    return sanitized;
  }

  void _onKeyPress(String key) {
    // Apply case transformation
    String finalKey = key;

    // For Georgian keyboard with shift/caps lock
    if (widget.language == 'ka' && (_isCapsLockOn || _isShiftPressed)) {
      // Check if this key has a special shift mapping
      if (_georgianShiftMap.containsKey(key)) {
        finalKey = _georgianShiftMap[key]!;
      } else {
        // Otherwise, just uppercase it
        finalKey = key.toUpperCase();
      }
    } else if (widget.language == 'en' && (_isCapsLockOn || _isShiftPressed)) {
      // For English, just uppercase
      finalKey = key.toUpperCase();
    }

    // If shift was pressed (not caps lock), turn it off after one key
    if (_isShiftPressed && !_isCapsLockOn) {
      setState(() {
        _isShiftPressed = false;
      });
    }

    final text = widget.controller.text;
    final selection = _sanitizeSelection();
    final newText = text.replaceRange(selection.start, selection.end, finalKey);
    widget.controller.text = newText;
    widget.controller.selection = TextSelection.collapsed(
      offset: selection.start + finalKey.length,
    );
  }

  void _onBackspace() {
    final text = widget.controller.text;
    final selection = _sanitizeSelection();
    if (selection.start != selection.end) {
      final newText = text.replaceRange(selection.start, selection.end, '');
      widget.controller.text = newText;
      widget.controller.selection = TextSelection.collapsed(
        offset: selection.start,
      );
    } else if (selection.start > 0) {
      final newText = text.replaceRange(selection.start - 1, selection.end, '');
      widget.controller.text = newText;
      widget.controller.selection = TextSelection.collapsed(
        offset: selection.start - 1,
      );
    }
  }

  void _onSpace() {
    _onKeyPress(' ');
  }

  void _onClear() {
    widget.controller.clear();
    widget.controller.selection = const TextSelection.collapsed(offset: 0);
  }

  void _onEnter() {
    if (widget.onEnter != null) {
      widget.onEnter!();
    } else {
      _onKeyPress('\n');
    }
  }

  void _onShift() {
    setState(() {
      _isShiftPressed = !_isShiftPressed;
      // If we're in caps lock and press shift, turn off caps lock
      if (_isCapsLockOn) {
        _isCapsLockOn = false;
      }
    });
  }

  void _onCapsLock() {
    setState(() {
      _isCapsLockOn = !_isCapsLockOn;
      _isShiftPressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.language == 'en' ? _englishLayout : _georgianLayout;

    return Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        border: const Border(
          top: BorderSide(color: Color(0xFFE1E5EE), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _headerColor,
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFD7DDE8), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.keyboard, color: _accentColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.language == 'en'
                                ? 'English Keyboard'
                                : 'ქართული კლავიატურა',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.black54,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Close keyboard',
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                return Column(
                  children: [
                    _buildFullWidthRow(layout[0], maxWidth),
                    const SizedBox(height: 3),
                    _buildFullWidthRow(layout[1], maxWidth),
                    const SizedBox(height: 3),
                    _buildSecondRow(layout[2], maxWidth),
                    const SizedBox(height: 3),
                    _buildThirdRow(layout[3], maxWidth),
                    const SizedBox(height: 3),
                    _buildBottomRow(maxWidth),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static const double _keyHorizontalPad = 4.0;

  /// Scales a keyboard row down when [maxWidth] is tight (e.g. inside a dialog).
  Widget _fitKeyboardRow(double maxWidth, Widget row) {
    return SizedBox(
      width: maxWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: row,
      ),
    );
  }

  Widget _buildFullWidthRow(List<String> keys, double maxWidth) {
    final horizontalPadding = keys.length * _keyHorizontalPad;
    final minKeyWidth = maxWidth < 520 ? 28.0 : 36.0;
    final keyWidth = ((maxWidth - horizontalPadding) / keys.length).clamp(
      minKeyWidth,
      58.0,
    );
    return _fitKeyboardRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys.map((key) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildKey(key, width: keyWidth),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSecondRow(List<String> keys, double maxWidth) {
    final sizes = _rowWithSideKeys(
      maxWidth: maxWidth,
      letterCount: keys.length,
      preferredSideWidth: 75,
      minSideWidth: 44,
      minLetterWidth: 24,
    );
    return _fitKeyboardRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(
              'Caps',
              _onCapsLock,
              width: sizes.sideWidth,
              isActive: _isCapsLockOn,
            ),
          ),
          ...keys.map((key) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildKey(key, width: sizes.letterWidth),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(
              '',
              _onBackspace,
              icon: Icons.backspace_outlined,
              width: sizes.sideWidth,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThirdRow(List<String> keys, double maxWidth) {
    final sizes = _rowWithSideKeys(
      maxWidth: maxWidth,
      letterCount: keys.length,
      preferredSideWidth: 90,
      minSideWidth: 48,
      minLetterWidth: 22,
    );
    return _fitKeyboardRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(
              'Shift',
              _onShift,
              width: sizes.sideWidth,
              isActive: _isShiftPressed,
            ),
          ),
          ...keys.map((key) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildKey(key, width: sizes.letterWidth),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(
              'Enter',
              _onEnter,
              width: sizes.sideWidth,
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  ({double sideWidth, double letterWidth}) _rowWithSideKeys({
    required double maxWidth,
    required int letterCount,
    required double preferredSideWidth,
    required double minSideWidth,
    required double minLetterWidth,
  }) {
    final childCount = letterCount + 2;
    final contentWidth = maxWidth - childCount * _keyHorizontalPad;
    var sideWidth = preferredSideWidth.clamp(minSideWidth, preferredSideWidth);
    var letterWidth = (contentWidth - 2 * sideWidth) / letterCount;

    if (letterWidth < minLetterWidth) {
      letterWidth = minLetterWidth;
      sideWidth = ((contentWidth - letterCount * letterWidth) / 2).clamp(
        minSideWidth,
        preferredSideWidth,
      );
    }

    letterWidth = letterWidth.clamp(minLetterWidth, 58.0);
    final used = 2 * sideWidth + letterCount * letterWidth;
    if (used > contentWidth && used > 0) {
      final scale = contentWidth / used;
      sideWidth = (sideWidth * scale).clamp(minSideWidth, preferredSideWidth);
      letterWidth = (letterWidth * scale).clamp(minLetterWidth, 58.0);
    }

    return (sideWidth: sideWidth, letterWidth: letterWidth);
  }

  Widget _buildKey(String key, {double? width}) {
    // Display the key based on shift/caps state
    String displayKey = key;
    if (_isCapsLockOn || _isShiftPressed) {
      // For Georgian keyboard, check if there's a special shift mapping
      if (widget.language == 'ka' && _georgianShiftMap.containsKey(key)) {
        displayKey = _georgianShiftMap[key]!;
      } else {
        displayKey = key.toUpperCase();
      }
    }

    return SizedBox(
      width: width,
      height: 46,
      child: Material(
        color: _surfaceColor,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _borderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _onKeyPress(key),
          splashColor: _accentColor.withOpacity(0.18),
          highlightColor: _accentColor.withOpacity(0.1),
          child: Center(
            child: Text(
              displayKey,
              style: TextStyle(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialKey(
    String label,
    VoidCallback onTap, {
    IconData? icon,
    double? width,
    bool isActive = false,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
  }) {
    final Color baseColor = isActive
        ? _accentColor
        : (backgroundColor ?? _specialSurfaceColor);
    final Color contentColor =
        foregroundColor ?? (isActive ? Colors.white : _textColor);
    final Color outlineColor = isActive
        ? _accentColor.withOpacity(0.45)
        : (borderColor ?? _borderColor);

    return SizedBox(
      width: width,
      height: 46,
      child: Material(
        color: baseColor,
        elevation: isActive ? 3 : 1.5,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outlineColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: _accentColor.withOpacity(0.18),
          highlightColor: _accentColor.withOpacity(0.1),
          child: Center(
            child: icon != null
                ? Icon(icon, color: contentColor, size: 22)
                : Text(
                    label,
                    style: TextStyle(
                      color: contentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRow(double maxWidth) {
    const clearWidth = 66.0;
    const symbolWidth = 52.0;
    const switchWidth = 60.0;
    const fixedWidth = clearWidth + (symbolWidth * 4) + switchWidth;
    const totalPadding = 7 * _keyHorizontalPad;
    final spaceWidth = (maxWidth - fixedWidth - totalPadding).clamp(
      36.0,
      360.0,
    );

    return _fitKeyboardRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Clear button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(
              'Clear',
              _onClear,
              width: 66,
              backgroundColor: _dangerColor,
              foregroundColor: const Color(0xFFB42323),
              borderColor: _dangerBorderColor,
            ),
          ),

          // Left side symbols
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(',', () => _onKeyPress(','), width: 52),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey('.', () => _onKeyPress('.'), width: 52),
          ),

          // Space bar - fixed width
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(
              'Space',
              _onSpace,
              width: spaceWidth,
              backgroundColor: _surfaceColor,
              foregroundColor: _mutedTextColor,
            ),
          ),

          // Right side symbols
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey('?', () => _onKeyPress('?'), width: 52),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey('!', () => _onKeyPress('!'), width: 52),
          ),

          // Language/Symbol switch placeholder
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildSpecialKey(
              '@#',
              () {}, // Could be used to switch to symbols layout
              width: 60,
              backgroundColor: _specialSurfaceColor,
            ),
          ),
        ],
      ),
    );
  }
}
