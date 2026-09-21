import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';

class PosKeyboard extends StatefulWidget {
  const PosKeyboard({
    super.key,
    required this.controller,
    required this.initialLanguage,
    required this.onClose,
    this.onEnter,
    this.title,
    this.showHeader = true,
    this.showPreview = false,
    this.followLocale = true,
  });

  final TextEditingController controller;
  final PosKeyboardLanguage initialLanguage;
  final VoidCallback onClose;
  final VoidCallback? onEnter;
  final String? title;
  final bool showHeader;
  final bool showPreview;
  final bool followLocale;

  @override
  State<PosKeyboard> createState() => _PosKeyboardState();
}

class _PosKeyboardState extends State<PosKeyboard> {
  static const Color _panel = Colors.white;
  static const Color _softSurface = Color(0xFFF9FAFB);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _accent = VynicFloorTokens.accentStrong;
  static const Color _accentDark = VynicFloorTokens.accentStrong;
  static const Color _danger = Color(0xFFFEE2E2);
  static const Color _dangerText = Color(0xFFB91C1C);

  static const Map<String, String> _georgianShiftMap = {
    'ს': 'შ',
    'რ': 'ღ',
    'ჯ': 'ჟ',
    'წ': 'ჭ',
    'ტ': 'თ',
    'ც': 'ჩ',
    'ზ': 'ძ',
  };

  static const List<List<String>> _englishLayout = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  static const List<List<String>> _georgianLayout = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['ქ', 'წ', 'ე', 'რ', 'ტ', 'ყ', 'უ', 'ი', 'ო', 'პ'],
    ['ა', 'ს', 'დ', 'ფ', 'გ', 'ჰ', 'ჯ', 'კ', 'ლ'],
    ['ზ', 'ხ', 'ც', 'ვ', 'ბ', 'ნ', 'მ'],
  ];

  late PosKeyboardLanguage _language;
  String? _appLanguage;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<PosLocale>();
    if (widget.followLocale &&
        scope != null &&
        scope.language != _appLanguage) {
      _appLanguage = scope.language;
      _language = PosKeyboardLanguage.fromCode(scope.language);
      _shift = false;
      _caps = false;
    }
  }

  bool _shift = false;
  bool _caps = false;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
  }

  @override
  void didUpdateWidget(covariant PosKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLanguage != widget.initialLanguage) {
      _language = widget.initialLanguage;
      _shift = false;
      _caps = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PosInputSettings.useOnScreen(context)) return const SizedBox.shrink();
    final layout = _language == PosKeyboardLanguage.english
        ? _englishLayout
        : _georgianLayout;

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
                if (widget.showHeader) _buildHeader(),
                const SizedBox(height: 10),
                if (widget.showPreview)
                  _KeyboardPreview(
                    controller: widget.controller,
                    title: widget.title,
                  ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Column(
                      children: [
                        _buildCharacterRow(layout[0], constraints.maxWidth),
                        const SizedBox(height: 6),
                        _buildCharacterRow(layout[1], constraints.maxWidth),
                        const SizedBox(height: 6),
                        _buildHomeRow(layout[2], constraints.maxWidth),
                        const SizedBox(height: 6),
                        _buildShiftRow(layout[3], constraints.maxWidth),
                        const SizedBox(height: 6),
                        _buildBottomRow(constraints.maxWidth),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.keyboard_outlined, color: _accentDark),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            PosLocale.tr(context, widget.title ?? 'კლავიატურა')!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _LanguageToggle(
          language: _language,
          onChanged: (language) {
            setState(() {
              _language = language;
              _shift = false;
              _caps = false;
            });
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: PosLocale.tr(context, 'დახურვა'),
          onPressed: widget.onClose,
          icon: const Icon(Icons.close),
          color: _muted,
        ),
      ],
    );
  }

  Widget _buildCharacterRow(List<String> keys, double maxWidth) {
    return _fitRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: keys
            .map(
              (key) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _KeyboardButton(
                  width: _letterWidth(keys.length, maxWidth),
                  label: _displayFor(key),
                  onTap: () => _insertCharacter(key),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildHomeRow(List<String> keys, double maxWidth) {
    final letterWidth = _letterWidth(keys.length + 2, maxWidth);
    return _fitRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _KeyboardButton(
              width: letterWidth * 1.45,
              label: 'Caps',
              isActive: _caps,
              onTap: _toggleCaps,
            ),
          ),
          ...keys.map(
            (key) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _KeyboardButton(
                width: letterWidth,
                label: _displayFor(key),
                onTap: () => _insertCharacter(key),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _KeyboardButton(
              width: letterWidth * 1.45,
              icon: Icons.backspace_outlined,
              onTap: _backspace,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftRow(List<String> keys, double maxWidth) {
    final letterWidth = _letterWidth(keys.length + 2, maxWidth);
    return _fitRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _KeyboardButton(
              width: letterWidth * 1.7,
              label: 'Shift',
              isActive: _shift,
              onTap: _toggleShift,
            ),
          ),
          ...keys.map(
            (key) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _KeyboardButton(
                width: letterWidth,
                label: _displayFor(key),
                onTap: () => _insertCharacter(key),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _KeyboardButton(
              width: letterWidth * 1.7,
              label: PosLocale.tr(context, 'შეყვანა')!,
              background: _accentDark,
              foreground: Colors.white,
              onTap: _enter,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRow(double maxWidth) {
    const fixedPadding = 8 * 6.0;
    final spaceWidth = (maxWidth - 420 - fixedPadding).clamp(180.0, 420.0);
    return _fitRow(
      maxWidth,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bottomKey(
            width: 76,
            label: PosLocale.tr(context, 'გასუფთავება')!,
            icon: Icons.clear_all_rounded,
            background: _danger,
            foreground: _dangerText,
            onTap: _clear,
          ),
          _bottomKey(width: 54, label: ',', onTap: () => _insertRaw(',')),
          _bottomKey(width: 54, label: '.', onTap: () => _insertRaw('.')),
          _bottomKey(
            width: spaceWidth,
            label: PosLocale.tr(context, 'გამოტოვება')!,
            icon: Icons.space_bar,
            onTap: () => _insertRaw(' '),
          ),
          _bottomKey(width: 54, label: '?', onTap: () => _insertRaw('?')),
          _bottomKey(width: 54, label: '!', onTap: () => _insertRaw('!')),
          _bottomKey(
            width: 82,
            label: _language == PosKeyboardLanguage.georgian ? 'EN' : 'ქარ',
            icon: Icons.language,
            onTap: _switchLanguage,
          ),
        ],
      ),
    );
  }

  Widget _bottomKey({
    required double width,
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    Color? background,
    Color? foreground,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: _KeyboardButton(
        width: width,
        label: label,
        icon: icon,
        background: background,
        foreground: foreground,
        onTap: onTap,
      ),
    );
  }

  Widget _fitRow(double maxWidth, Widget child) {
    return SizedBox(
      width: maxWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  double _letterWidth(int keyCount, double maxWidth) {
    final value = ((maxWidth - keyCount * 6) / keyCount).clamp(36.0, 62.0);
    return value;
  }

  String _displayFor(String key) {
    if (!(_shift || _caps)) {
      return key;
    }

    if (_language == PosKeyboardLanguage.georgian) {
      return _georgianShiftMap[key] ?? key.toUpperCase();
    }
    return key.toUpperCase();
  }

  TextSelection _selection() {
    final length = widget.controller.text.length;
    var start = widget.controller.selection.start;
    var end = widget.controller.selection.end;
    if (start < 0 || start > length) start = length;
    if (end < 0 || end > length) end = length;
    if (start > end) {
      final temp = start;
      start = end;
      end = temp;
    }
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  void _insertCharacter(String key) {
    _insertRaw(_displayFor(key));
    if (_shift && !_caps) {
      setState(() {
        _shift = false;
      });
    }
  }

  void _insertRaw(String value) {
    final selection = _selection();
    final text = widget.controller.text;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, value),
      selection: TextSelection.collapsed(
        offset: selection.start + value.length,
      ),
    );
  }

  void _backspace() {
    final selection = _selection();
    final text = widget.controller.text;
    if (selection.isCollapsed && selection.start == 0) return;
    final start = selection.isCollapsed
        ? selection.start -
              text.substring(0, selection.start).characters.last.length
        : selection.start;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, selection.end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }

  void _clear() {
    widget.controller.clear();
    widget.controller.selection = const TextSelection.collapsed(offset: 0);
  }

  void _enter() {
    if (widget.onEnter != null) {
      widget.onEnter!();
      return;
    }
    _insertRaw('\n');
  }

  void _toggleShift() {
    setState(() {
      _shift = !_shift;
      if (_shift) _caps = false;
    });
  }

  void _toggleCaps() {
    setState(() {
      _caps = !_caps;
      if (_caps) _shift = false;
    });
  }

  void _switchLanguage() {
    setState(() {
      _language = _language == PosKeyboardLanguage.georgian
          ? PosKeyboardLanguage.english
          : PosKeyboardLanguage.georgian;
      _shift = false;
      _caps = false;
    });
  }
}

class _KeyboardPreview extends StatelessWidget {
  const _KeyboardPreview({required this.controller, this.title});
  final String? title;

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      decoration: InputDecoration(
        hintText: title,
        filled: true,
        fillColor: Color(0xFFF6F7F9),
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.language, required this.onChanged});

  final PosKeyboardLanguage language;
  final ValueChanged<PosKeyboardLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageChip(
            label: PosKeyboardLanguage.georgian.label,
            selected: language == PosKeyboardLanguage.georgian,
            onTap: () => onChanged(PosKeyboardLanguage.georgian),
          ),
          _LanguageChip(
            label: PosKeyboardLanguage.english.label,
            selected: language == PosKeyboardLanguage.english,
            onTap: () => onChanged(PosKeyboardLanguage.english),
          ),
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? VynicFloorTokens.accentStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _KeyboardButton extends StatelessWidget {
  const _KeyboardButton({
    required this.width,
    required this.onTap,
    this.label,
    this.icon,
    this.isActive = false,
    this.background,
    this.foreground,
  });

  final double width;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;
  final bool isActive;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final bg = isActive
        ? _PosKeyboardState._accentDark
        : (background ?? _PosKeyboardState._softSurface);
    final fg =
        foreground ?? (isActive ? Colors.white : _PosKeyboardState._text);

    return SizedBox(
      width: width,
      height: 46,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isActive
                ? _PosKeyboardState._accentDark
                : _PosKeyboardState._border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          canRequestFocus: false,
          onTap: onTap,
          splashColor: _PosKeyboardState._accent.withValues(alpha: 0.14),
          highlightColor: _PosKeyboardState._accent.withValues(alpha: 0.08),
          child: Center(
            child: icon != null
                ? Tooltip(
                    message: label ?? '',
                    child: Icon(icon, color: fg, size: 20),
                  )
                : Text(
                    label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
