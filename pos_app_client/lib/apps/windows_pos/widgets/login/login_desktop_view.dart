import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:flutter/widget_previews.dart';

class LoginDesktopView extends StatelessWidget {
  /// What this venue is called, for the login screen's headline.
  ///
  /// Read at build time rather than passed in: the login view is rebuilt after
  /// setup completes, and threading it through every constructor for one
  /// string would touch more of this file than the change is worth.
  static String get _venueName {
    try {
      return DatabaseService.getVenueName();
    } catch (_) {
      return '';
    }
  }

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
    this.showCompanionApp = false,
    this.onCompanionAppPressed,
  });

  /// Listenable so a keystroke only rebuilds the PIN dots + login button,
  /// not the whole login card (keypad, logo, clock).
  final ValueListenable<String> pin;
  final bool isLoading;
  final DateTime workDate;
  final DateTime now;
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onClearPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback? onLoginPressed;
  final bool showCompanionApp;
  final VoidCallback? onCompanionAppPressed;

  static const _ink = VynicFloorTokens.text;
  static const _muted = VynicFloorTokens.textMuted;
  static const _accent = VynicFloorTokens.accentStrong;
  static const _accentSoft = VynicFloorTokens.accentSoft;
  static const _line = VynicFloorTokens.panelBorder;

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
    return _buildScaffold();
  }

  Widget _buildScaffold() {
    return ColoredBox(
      color: VynicFloorTokens.page,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 920;
                  final dense = constraints.maxHeight < 690;
                  final panels = stacked
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LoginPanelSurface(
                              child: _buildIdentityPanel(
                                compact: true,
                                dense: dense,
                              ),
                            ),
                            SizedBox(height: dense ? 12 : 16),
                            _LoginPanelSurface(
                              child: _buildLoginPanel(dense: dense),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _LoginPanelSurface(
                                child: _buildIdentityPanel(dense: dense),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 5,
                              child: _LoginPanelSurface(
                                compact: true,
                                child: _buildLoginPanel(dense: dense),
                              ),
                            ),
                          ],
                        );

                  final double vPad = dense ? 16 : 28;
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: stacked ? 16 : 34,
                      vertical: vPad,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - vPad * 2,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: stacked ? 500 : 1040,
                          ),
                          child: panels,
                        ),
                      ),
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
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: VynicFloorTokens.panel,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          return Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/logo/vynic-logo.png',
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
              if (!compact) ...[
                Flexible(
                  child: Text(
                    'სამუშაო თარიღი: ${_dateLabel(workDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
                Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: _line,
                ),
              ],
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
          );
        },
      ),
    );
  }

  Widget _buildIdentityPanel({bool compact = false, bool dense = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: compact
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Container(
              width: compact ? 72 : (dense ? 64 : 84),
              height: compact ? 72 : (dense ? 64 : 84),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/logo/vynic-logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'რესტორნის მართვის სისტემა',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: dense ? 10 : 18),
        Text(
          'Vynic POS',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: _ink,
            fontSize: dense ? 26 : 34,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        // The venue's own name, not this one's. „ვანკისი" was hardcoded here,
        // so every restaurant that installed the POS logged into someone
        // else's. Hidden entirely until setup has been through, rather than
        // leaving a gap where a name goes.
        if (_venueName.isNotEmpty)
          Text(
            _venueName,
            textAlign: compact ? TextAlign.center : TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _accent,
              fontSize: dense ? 22 : 30,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        SizedBox(height: dense ? 8 : 12),
        Text(
          'შედით PIN კოდით და გააგრძელეთ მაგიდების, შეკვეთებისა და მენიუს მართვა.',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: const TextStyle(color: _muted, fontSize: 14, height: 1.45),
        ),
        SizedBox(height: dense ? 14 : 24),
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
        SizedBox(height: dense ? 4 : 7),
        _InfoTile(
          icon: Icons.check_circle_outline_rounded,
          label: 'სისტემა',
          value: 'მზად არის შესვლისთვის',
          dense: dense,
          statusOn: true,
        ),
      ],
    );
  }

  Widget _buildLoginPanel({bool dense = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: Container(
            width: dense ? 42 : 48,
            height: dense ? 42 : 48,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: const Icon(
              Icons.lock_person_outlined,
              color: _accent,
              size: 24,
            ),
          ),
        ),
        SizedBox(height: dense ? 10 : 16),
        Text(
          'PIN კოდი',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink,
            fontSize: dense ? 22 : 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        const Text(
          'შეიყვანეთ თანამშრომლის PIN',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        SizedBox(height: dense ? 12 : 20),
        Container(
          height: dense ? 46 : 58,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: VynicFloorTokens.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: ValueListenableBuilder<String>(
            valueListenable: pin,
            builder: (context, pinValue, _) => Row(
              children: [
                for (var index = 0; index < 6; index++)
                  Expanded(
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: index < pinValue.length ? 11 : 16,
                        height: index < pinValue.length ? 11 : 16,
                        decoration: BoxDecoration(
                          color: index < pinValue.length
                              ? _accent
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: index < pinValue.length
                                ? _accent
                                : const Color(0xFFCFCAC3),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: dense ? 8 : 14),
        _buildKeypad(dense),
        SizedBox(height: dense ? 10 : 16),
        SizedBox(
          height: dense ? 44 : 54,
          child: ValueListenableBuilder<String>(
            valueListenable: pin,
            builder: (context, pinValue, _) => ElevatedButton.icon(
              onPressed: (isLoading || pinValue.length < 4)
                  ? null
                  : onLoginPressed,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: _accent,
                disabledBackgroundColor: const Color(0xFFC7C2D2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
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
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        if (showCompanionApp) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: isLoading ? null : onCompanionAppPressed,
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('მენეჯერის აპი'),
          ),
        ],
      ],
    );
  }

  Widget _buildKeypad(bool dense) {
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
          icon: Icons.clear_all_rounded,
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
          dense: dense,
          onTap: onDeletePressed,
        ),
      ]),
    );

    return Column(mainAxisSize: MainAxisSize.min, children: rowWidgets);
  }
}

class _LoginPanelSurface extends StatelessWidget {
  const _LoginPanelSurface({required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 28 : 32),
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1C1A19),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
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
        color: VynicFloorTokens.metricFill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Row(
        children: [
          Container(
            width: dense ? 29 : 35,
            height: dense ? 29 : 35,
            decoration: BoxDecoration(
              color: statusOn
                  ? VynicFloorTokens.successFill
                  : VynicFloorTokens.accentSoft,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: statusOn
                    ? VynicFloorTokens.successBorder
                    : VynicFloorTokens.panelBorder,
              ),
            ),
            child: Icon(
              icon,
              color: statusOn
                  ? VynicFloorTokens.successText
                  : VynicFloorTokens.accentStrong,
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
                    fontWeight: FontWeight.w600,
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
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
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
          backgroundColor: VynicFloorTokens.canvas,
          side: const BorderSide(color: VynicFloorTokens.panelBorder),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      pin: ValueNotifier('123'),
      isLoading: false,
      workDate: DateTime(2026, 6, 24),
      now: DateTime(2026, 6, 24, 11, 45),
      onDigitPressed: _noopDigit,
      onClearPressed: _noop,
      onDeletePressed: _noop,
      onLoginPressed: _noop,
    ),
  );
}

void _noop() {}
void _noopDigit(String _) {}
