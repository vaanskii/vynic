import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class HomeLandingDashboard extends StatefulWidget {
  const HomeLandingDashboard({
    super.key,
    required this.username,
    required this.roleLabel,
    required this.workDate,
    required this.sessionStartedAt,
    required this.openTablesCount,
    required this.takeAwayCount,
    required this.reservationCount,
    required this.printerConfigured,
    required this.notificationUnreadCount,
    required this.onNotificationTap,
    required this.onTablesTap,
    required this.onCalculatorTap,
    required this.onTakeAwayTap,
    required this.onReservationsTap,
    required this.onXReportTap,
    required this.onLogoutTap,
    this.onAdminTap,
  });

  final String username;
  final String roleLabel;
  final DateTime workDate;
  final DateTime sessionStartedAt;
  final int openTablesCount;
  final int takeAwayCount;
  final int reservationCount;
  final bool printerConfigured;
  final int notificationUnreadCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onTablesTap;
  final VoidCallback onCalculatorTap;
  final VoidCallback onTakeAwayTap;
  final VoidCallback onReservationsTap;
  final VoidCallback onXReportTap;
  final VoidCallback? onAdminTap;
  final VoidCallback onLogoutTap;

  @override
  State<HomeLandingDashboard> createState() => _HomeLandingDashboardState();
}

class _HomeLandingDashboardState extends State<HomeLandingDashboard> {
  static const _navy = Color(0xFF001F31);
  static const _ink = Color(0xFF09243B);
  static const _muted = Color(0xFF52677A);
  static const _green = Color(0xFF11CF73);

  late DateTime _now;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _timeLabel(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${_twoDigits(value.minute)} $period';
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

  String get _sessionDuration {
    final elapsed = _now.difference(widget.sessionStartedAt);
    final hours = elapsed.inHours.clamp(0, 99);
    final minutes = elapsed.inMinutes.remainder(60);
    final seconds = elapsed.inSeconds.remainder(60);
    return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      _HomeAction(
        title: 'მაგიდები',
        subtitle: 'მაგიდების მართვა და შეკვეთები',
        icon: Icons.table_restaurant_outlined,
        tint: const Color(0xFFD9F2FF),
        iconColor: const Color(0xFF123F53),
        onTap: widget.onTablesTap,
      ),
      _HomeAction(
        title: 'დათვლილი მენიუ',
        subtitle: 'მენიუს ელემენტების დათვლა და მართვა',
        icon: Icons.room_service_outlined,
        tint: const Color(0xFFDCF8EB),
        iconColor: const Color(0xFF164C52),
        onTap: widget.onCalculatorTap,
      ),
      _HomeAction(
        title: 'წასაღებები',
        subtitle: 'წასაღები შეკვეთების შექმნა და მართვა',
        icon: Icons.shopping_bag_outlined,
        tint: const Color(0xFFFFF0D4),
        iconColor: const Color(0xFF6C4718),
        onTap: widget.onTakeAwayTap,
      ),
      _HomeAction(
        title: 'რეზერვაციები',
        subtitle: 'ჯავშნების ნახვა და მართვა',
        icon: Icons.calendar_month_outlined,
        tint: const Color(0xFFF0E2FF),
        iconColor: const Color(0xFF573092),
        onTap: widget.onReservationsTap,
      ),
      _HomeAction(
        title: 'X რეპორტი',
        subtitle: 'დღის ფინანსური ანგარიში და რეპორტები',
        icon: Icons.description_outlined,
        tint: const Color(0xFFD9F2FF),
        iconColor: const Color(0xFF174F69),
        onTap: widget.onXReportTap,
      ),
      if (widget.onAdminTap != null)
        _HomeAction(
          title: 'მართვის ცენტრი',
          subtitle: 'სისტემის პარამეტრები და მომხმარებლები',
          icon: Icons.settings_outlined,
          tint: const Color(0xFFE9EDF2),
          iconColor: const Color(0xFF25425A),
          onTap: widget.onAdminTap!,
        ),
    ];

    return ColoredBox(
      color: _navy,
      child: Stack(
        children: [
          const Positioned.fill(child: _DashboardBackdrop()),
          SafeArea(
            child: Column(
              children: [
                _buildBrandBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 700;
                      final dense = constraints.maxHeight < 800;
                      final shouldScroll =
                          compact || constraints.maxHeight < 570;
                      final horizontalPadding = compact ? 20.0 : 48.0;
                      final topPadding = dense ? 22.0 : 34.0;
                      final bottomPadding = dense ? 8.0 : 18.0;
                      final content = Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1560),
                          child: SizedBox(
                            height: shouldScroll
                                ? null
                                : constraints.maxHeight -
                                      topPadding -
                                      bottomPadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildGreeting(compact, dense),
                                SizedBox(height: dense ? 12 : 28),
                                _buildSessionStrip(compact, dense),
                                SizedBox(height: dense ? 12 : 24),
                                _buildActionGrid(actions, dense: dense),
                                if (shouldScroll)
                                  SizedBox(height: dense ? 10 : 18)
                                else
                                  const Spacer(),
                                Center(
                                  child: _buildLogoutButton(compact, dense),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      if (shouldScroll) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            topPadding,
                            horizontalPadding,
                            bottomPadding,
                          ),
                          child: content,
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          topPadding,
                          horizontalPadding,
                          bottomPadding,
                        ),
                        child: content,
                      );
                    },
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF001725).withValues(alpha: 0.78),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showWorkDate = constraints.maxWidth >= 760;
          return Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(5),
                child: Image.asset(
                  'assets/logo/vynic.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Vynic POS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (showWorkDate) ...[
                Text(
                  'სამუშაო თარიღი: ${_dateLabel(widget.workDate)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                  ),
                ),
                Container(
                  height: 24,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ],
              const Icon(Icons.schedule, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                _timeLabel(_now),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(width: 14),
              _NotificationButton(
                unreadCount: widget.notificationUnreadCount,
                onTap: widget.onNotificationTap,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGreeting(bool compact, bool dense) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'გამარჯობა, ${widget.username}',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 28 : (dense ? 28 : 36),
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        _buildRoleBadge(compact, dense),
      ],
    );
  }

  Widget _buildRoleBadge(bool compact, bool dense) {
    final visual = _roleVisual(widget.roleLabel);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact || dense ? 11 : 13,
        vertical: compact || dense ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: visual.color.withValues(alpha: 0.78),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: visual.color.withValues(alpha: 0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            visual.icon,
            color: visual.color,
            size: compact || dense ? 16 : 18,
          ),
          const SizedBox(width: 7),
          Text(
            widget.roleLabel,
            style: TextStyle(
              color: visual.color,
              fontSize: compact || dense ? 13 : 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  _RoleVisual _roleVisual(String roleLabel) {
    switch (roleLabel.trim()) {
      case 'მენეჯერი':
        return const _RoleVisual(
          icon: Icons.admin_panel_settings_outlined,
          color: Color(0xFFFFC857),
        );
      case 'სუპერვაიზერი':
        return const _RoleVisual(
          icon: Icons.supervisor_account_outlined,
          color: Color(0xFFC69CFF),
        );
      case 'ოფიციანტი':
        return const _RoleVisual(
          icon: Icons.room_service_outlined,
          color: Color(0xFF63D5FF),
        );
      default:
        return const _RoleVisual(
          icon: Icons.badge_outlined,
          color: Color(0xFF7DE2C3),
        );
    }
  }

  Widget _buildSessionStrip(bool compact, bool dense) {
    final items = [
      _SessionItem(
        icon: Icons.storefront_outlined,
        eyebrow: 'რესტორანი / ფილიალი',
        value: 'ვანკისი',
      ),
      const _SessionItem(
        icon: Icons.desktop_windows_outlined,
        eyebrow: 'ტერმინალი',
        value: 'ტერმინალი 01',
      ),
      const _SessionItem(
        icon: Icons.circle,
        eyebrow: 'სტატუსი',
        value: 'სისტემა მზად არის',
        isPositive: true,
      ),
      _SessionItem(
        icon: Icons.calendar_today_outlined,
        eyebrow: 'სამუშაო თარიღი',
        value: _dateLabel(widget.workDate),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : (dense ? 18 : 28),
        vertical: compact ? 16 : (dense ? 10 : 18),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: compact
          ? Wrap(
              spacing: 22,
              runSpacing: 20,
              children: [
                for (final item in items) SizedBox(width: 245, child: item),
              ],
            )
          : Row(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  Expanded(child: items[index]),
                  if (index != items.length - 1)
                    Container(
                      width: 1,
                      height: dense ? 42 : 52,
                      margin: EdgeInsets.symmetric(horizontal: dense ? 10 : 18),
                      color: Colors.white.withValues(alpha: 0.17),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _buildActionGrid(List<_HomeAction> actions, {required bool dense}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1050 ? 3 : (width >= 620 ? 2 : 1);
        final spacing = dense ? 14.0 : 18.0;
        final cardHeight = dense ? 144.0 : 180.0;

        if (actions.length == 5 && columns == 3) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: cardHeight,
                      child: _ActionCard(action: actions[0], dense: dense),
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: SizedBox(
                      height: cardHeight,
                      child: _ActionCard(action: actions[1], dense: dense),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing),
              Row(
                children: [
                  for (var index = 2; index < actions.length; index++) ...[
                    Expanded(
                      child: SizedBox(
                        height: cardHeight,
                        child: _ActionCard(
                          action: actions[index],
                          dense: dense,
                        ),
                      ),
                    ),
                    if (index != actions.length - 1) SizedBox(width: spacing),
                  ],
                ],
              ),
            ],
          );
        }

        final cardWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final action in actions)
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _ActionCard(action: action, dense: dense),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLogoutButton(bool compact, bool dense) {
    return SizedBox(
      width: compact ? double.infinity : (dense ? 460 : 560),
      height: dense ? 46 : 60,
      child: OutlinedButton.icon(
        onPressed: widget.onLogoutTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.86)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontSize: dense ? 15 : 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: Icon(Icons.logout_rounded, size: dense ? 21 : 26),
        label: const Text('გასვლა'),
      ),
    );
  }

  Widget _buildFooter() {
    final items = [
      _FooterItem(
        icon: Icons.table_restaurant_outlined,
        label: 'ღია მაგიდები',
        value: '${widget.openTablesCount}',
      ),
      _FooterItem(
        icon: Icons.shopping_bag_outlined,
        label: 'წასაღებები',
        value: '${widget.takeAwayCount}',
      ),
      _FooterItem(
        icon: Icons.calendar_month_outlined,
        label: 'დღევანდელი ჯავშნები',
        value: '${widget.reservationCount}',
      ),
      _FooterItem(
        icon: Icons.history_toggle_off_outlined,
        label: 'ცვლის დრო',
        value: _sessionDuration,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF03283A).withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: items[index],
              ),
            ),
            if (index != items.length - 1)
              Container(
                width: 1,
                height: 38,
                color: Colors.white.withValues(alpha: 0.16),
              ),
          ],
        ],
      ),
    );
  }
}

class _HomeAction {
  const _HomeAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final VoidCallback onTap;
}

class _RoleVisual {
  const _RoleVisual({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({required this.action, required this.dense});

  final _HomeAction action;
  final bool dense;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: _hovered ? 1.012 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.action.onTap,
            borderRadius: BorderRadius.circular(15),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.all(widget.dense ? 16 : 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: _hovered
                      ? const Color(0xFF60BEEA)
                      : Colors.white.withValues(alpha: 0.65),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _hovered ? 0.2 : 0.12,
                    ),
                    blurRadius: _hovered ? 28 : 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: widget.dense ? 76 : 98,
                    height: widget.dense ? 76 : 98,
                    decoration: BoxDecoration(
                      color: widget.action.tint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.action.icon,
                      color: widget.action.iconColor,
                      size: widget.dense ? 40 : 52,
                    ),
                  ),
                  SizedBox(width: widget.dense ? 16 : 26),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.action.title,
                          style: TextStyle(
                            color: _HomeLandingDashboardState._ink,
                            fontSize: widget.dense ? 17 : 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: widget.dense ? 7 : 12),
                        Text(
                          widget.action.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _HomeLandingDashboardState._muted,
                            fontSize: widget.dense ? 12 : 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 160),
                    offset: _hovered ? const Offset(0.18, 0) : Offset.zero,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: _HomeLandingDashboardState._ink,
                      size: widget.dense ? 26 : 32,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionItem extends StatelessWidget {
  const _SessionItem({
    required this.icon,
    required this.eyebrow,
    required this.value,
    this.isPositive = false,
  });

  final IconData icon;
  final String eyebrow;
  final String value;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isPositive
                ? _HomeLandingDashboardState._green
                : Colors.white,
            size: icon == Icons.circle ? 15 : 22,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPositive
                      ? _HomeLandingDashboardState._green
                      : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterItem extends StatelessWidget {
  const _FooterItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF0C4A65),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.76),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.unreadCount, required this.onTap});

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'შეტყობინებები',
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded, color: Colors.white),
          if (unreadCount > 0)
            Positioned(
              right: -4,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFC928),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Color(0xFF1B2A36),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardBackdrop extends StatelessWidget {
  const _DashboardBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DashboardBackdropPainter());
  }
}

class _DashboardBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x2947B5E8), Color(0x00002337)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.08, size.height * 0.42),
              radius: size.width * 0.34,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);

    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    for (var row = 0; row < 6; row++) {
      for (var column = 0; column < 4; column++) {
        canvas.drawCircle(
          Offset(18 + (column * 22), size.height * 0.58 + (row * 22)),
          3,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@Preview(name: 'Home dashboard — desktop', size: Size(1440, 900))
Widget homeLandingDashboardPreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
    home: HomeLandingDashboard(
      username: 'ნინო',
      roleLabel: 'ოფიციანტი',
      workDate: DateTime(2026, 6, 24),
      sessionStartedAt: DateTime.now().subtract(
        const Duration(hours: 2, minutes: 15),
      ),
      openTablesCount: 12,
      takeAwayCount: 3,
      reservationCount: 8,
      printerConfigured: true,
      notificationUnreadCount: 1,
      onNotificationTap: () {},
      onTablesTap: () {},
      onCalculatorTap: () {},
      onTakeAwayTap: () {},
      onReservationsTap: () {},
      onXReportTap: () {},
      onAdminTap: () {},
      onLogoutTap: () {},
    ),
  );
}
