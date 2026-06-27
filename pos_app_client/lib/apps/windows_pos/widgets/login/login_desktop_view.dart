import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class LoginDesktopView extends StatelessWidget {
  const LoginDesktopView({
    super.key,
    required this.pin,
    required this.isLoading,
    required this.workDate,
    required this.now,
    required this.onDigitPressed,
    required this.onClearPressed,
    required this.onDeletePressed,
    required this.onLoginPressed,
    required this.onOtherUserPressed,
    this.showCompanionApp = false,
    this.onCompanionAppPressed,
  });

  final String pin;
  final bool isLoading;
  final DateTime workDate;
  final DateTime now;
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onClearPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback? onLoginPressed;
  final VoidCallback onOtherUserPressed;
  final bool showCompanionApp;
  final VoidCallback? onCompanionAppPressed;

  static const _navy = Color(0xFF001F31);
  static const _navyLight = Color(0xFF073B53);
  static const _ink = Color(0xFF09243B);
  static const _muted = Color(0xFF52677A);
  static const _cyan = Color(0xFF319CB7);
  static const _teal = Color(0xFF14B8A6);

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _timeLabel(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${_twoDigits(value.minute)} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _dateLabel(DateTime value) {
    const months = [
      'იანვარი',
      'თებერვალი',
      'მარტი',
      'აპრილი',
      'მაისი',
      'ივნისი',
      'ივლისი',
      'აგვისტო',
      'სექტემბერი',
      'ოქტომბერი',
      'ნოემბერი',
      'დეკემბერი',
    ];
    return '${value.day} ${months[value.month - 1]}, ${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F5F7), Color(0xFFE6EDF0), Color(0xFFD9E5E9)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 850;
                  final dense = constraints.maxHeight < 720;

                  final cardDecoration = BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE4E9EC)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F2A3A).withValues(alpha: 0.10),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  );

                  final Widget card = Container(
                    constraints: BoxConstraints(maxWidth: stacked ? 460 : 860),
                    padding: EdgeInsets.all(stacked ? 22 : (dense ? 26 : 36)),
                    decoration: cardDecoration,
                    child: stacked
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildIdentityPanel(compact: true, dense: dense),
                              SizedBox(height: dense ? 18 : 26),
                              _buildLoginPanel(compact: true, dense: dense),
                            ],
                          )
                        : IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 10,
                                  child: _buildIdentityPanel(dense: dense),
                                ),
                                Container(
                                  width: 1,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 36,
                                  ),
                                  color: const Color(0xFFE9EEF1),
                                ),
                                Expanded(
                                  flex: 11,
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 300,
                                      ),
                                      child: _buildLoginPanel(dense: dense),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  );

                  final double vPad = dense ? 16 : 28;
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: stacked ? 18 : 34,
                      vertical: vPad,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - vPad * 2,
                      ),
                      child: Center(child: card),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: Color(0xFFDDE5E9))),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/logo/vynicnew.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Vynic POS',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            'სამუშაო თარიღი: ${_dateLabel(workDate)}',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFFD7DFE3),
          ),
          const Icon(Icons.schedule_rounded, color: _muted, size: 18),
          const SizedBox(width: 7),
          Text(
            _timeLabel(now),
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityPanel({bool compact = false, bool dense = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: compact ? 72 : (dense ? 60 : 88),
          height: compact ? 72 : (dense ? 60 : 88),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              compact ? 18 : (dense ? 16 : 24),
            ),
            boxShadow: [
              BoxShadow(
                color: _teal.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              compact ? 18 : (dense ? 16 : 24),
            ),
            child: Image.asset(
              'assets/logo/vynicnew.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        SizedBox(height: dense ? 5 : 12),
        Text(
          'Vynic POS',
          style: TextStyle(
            color: _ink,
            fontSize: dense ? 24 : 30,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'ვანკისი',
          style: TextStyle(
            color: _cyan,
            fontSize: dense ? 26 : 34,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        SizedBox(height: dense ? 1 : 4),
        const Text(
          'რესტორნის მართვის სისტემა',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        SizedBox(height: dense ? 7 : 20),
        Divider(
          color: const Color(0xFFE2E8F0),
          height: compact || dense ? 1 : 20,
        ),
        SizedBox(height: dense ? 6 : 12),
        _InfoTile(
          icon: Icons.storefront_outlined,
          label: 'ფილიალი',
          value: 'მთავარი ფილიალი',
          dense: dense,
        ),
        SizedBox(height: dense ? 4 : 7),
        _InfoTile(
          icon: Icons.desktop_windows_outlined,
          label: 'ტერმინალი',
          value: 'POS-01',
          dense: dense,
        ),
        SizedBox(height: dense ? 4 : 7),
        _InfoTile(
          icon: Icons.calendar_month_outlined,
          label: 'სამუშაო დღე',
          value: _dateLabel(workDate),
          dense: dense,
        ),
      ],
    );
  }

  Widget _buildLoginPanel({bool compact = false, bool dense = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PIN კოდით შესვლა',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink,
            fontSize: dense ? 18 : 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: dense ? 3 : 8),
        const Text(
          'შეიყვანეთ თქვენი 6-ნიშნა PIN კოდი',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        SizedBox(height: dense ? 8 : 18),
        Container(
          height: dense ? 42 : 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFDFE),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              for (var index = 0; index < 6; index++)
                Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: index < pin.length ? 11 : 16,
                      height: index < pin.length ? 11 : 16,
                      decoration: BoxDecoration(
                        color: index < pin.length ? _navy : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: index < pin.length
                              ? _navy
                              : const Color(0xFF94A3B8),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: dense ? 8 : 14),
        _buildKeypad(compact, dense),
        SizedBox(height: dense ? 8 : 14),
        SizedBox(
          height: dense ? 44 : 54,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onLoginPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: _navyLight,
              disabledBackgroundColor: const Color(0xFF94A3B8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Icon(Icons.lock_outline_rounded, size: 21),
            label: Text(
              isLoading ? 'მოწმდება...' : 'შესვლა',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        SizedBox(height: dense ? 0 : 10),
        TextButton.icon(
          onPressed: isLoading ? null : onOtherUserPressed,
          style: TextButton.styleFrom(foregroundColor: _navyLight),
          icon: const Icon(Icons.person_outline_rounded, size: 19),
          label: const Text(
            'სხვა მომხმარებელი',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (showCompanionApp) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: isLoading ? null : onCompanionAppPressed,
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('მენეჯერის აპი'),
          ),
        ],
      ],
    );
  }

  Widget _buildKeypad(bool compact, bool dense) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    final double hGap = dense ? 8 : 10;
    final double vGap = dense ? 8 : 10;

    Widget keyRow(List<Widget> cells) {
      final children = <Widget>[];
      for (var i = 0; i < cells.length; i++) {
        children.add(Expanded(child: cells[i]));
        if (i != cells.length - 1) children.add(SizedBox(width: hGap));
      }
      return Row(children: children);
    }

    final rowWidgets = <Widget>[];
    for (final row in rows) {
      rowWidgets.add(
        keyRow([
          for (final digit in row)
            _KeypadButton(
              label: digit,
              dense: dense,
              onTap: () => onDigitPressed(digit),
            ),
        ]),
      );
      rowWidgets.add(SizedBox(height: vGap));
    }
    rowWidgets.add(
      keyRow([
        _KeypadButton(
          label: 'გასუფთავება',
          icon: Icons.backspace_outlined,
          compact: true,
          dense: dense,
          onTap: onClearPressed,
        ),
        _KeypadButton(
          label: '0',
          dense: dense,
          onTap: () => onDigitPressed('0'),
        ),
        _KeypadButton(
          label: 'წაშლა',
          icon: Icons.backspace_rounded,
          compact: true,
          dense: dense,
          onTap: onDeletePressed,
        ),
      ]),
    );

    return Column(mainAxisSize: MainAxisSize.min, children: rowWidgets);
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.dense = false,
    this.statusOn = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool dense;
  final bool statusOn;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 43 : 56,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFEFE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE3E8)),
      ),
      child: Row(
        children: [
          Container(
            width: dense ? 29 : 35,
            height: dense ? 29 : 35,
            decoration: const BoxDecoration(
              color: LoginDesktopView._navyLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: icon == Icons.circle ? 11 : (dense ? 16 : 19),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: LoginDesktopView._muted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LoginDesktopView._ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (statusOn)
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.compact = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Widget content = icon == null
        ? Text(
            label,
            style: TextStyle(
              fontSize: dense ? 18 : 20,
              fontWeight: FontWeight.w700,
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: dense ? 16 : 18),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

    return SizedBox(
      height: dense ? 44 : 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: LoginDesktopView._ink,
          side: const BorderSide(color: Color(0xFFD8E0E5)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: content),
      ),
    );
  }
}

@Preview(name: 'Login — desktop', size: Size(1360, 768))
Widget loginDesktopViewPreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
    home: LoginDesktopView(
      pin: '123',
      isLoading: false,
      workDate: DateTime(2026, 6, 24),
      now: DateTime(2026, 6, 24, 11, 45),
      onDigitPressed: _noopDigit,
      onClearPressed: _noop,
      onDeletePressed: _noop,
      onLoginPressed: _noop,
      onOtherUserPressed: _noop,
    ),
  );
}

void _noop() {}
void _noopDigit(String _) {}
