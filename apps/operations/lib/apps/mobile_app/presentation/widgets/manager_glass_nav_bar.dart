import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

/// Themed bottom bar with a sliding active pill (solid on Android and iOS).
class ManagerGlassNavBar extends StatefulWidget {
  const ManagerGlassNavBar({
    super.key,
    required this.pageController,
    required this.selectedIndex,
    required this.itemCount,
    required this.items,
    required this.onTap,
  });

  final PageController pageController;
  final int selectedIndex;
  final int itemCount;
  final List<ManagerNavItem> items;
  final ValueChanged<int> onTap;

  @override
  State<ManagerGlassNavBar> createState() => _ManagerGlassNavBarState();
}

class ManagerNavItem {
  const ManagerNavItem({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

class _ManagerGlassNavBarState extends State<ManagerGlassNavBar> {
  static const _radius = 34.0;

  bool _scrubbing = false;
  double _barWidth = 0;

  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_onPageMoved);
  }

  @override
  void didUpdateWidget(covariant ManagerGlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController.removeListener(_onPageMoved);
      widget.pageController.addListener(_onPageMoved);
    }
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onPageMoved);
    super.dispose();
  }

  void _onPageMoved() {
    if (mounted) setState(() {});
  }

  double get _pagePosition {
    if (!widget.pageController.hasClients) {
      return widget.selectedIndex.toDouble();
    }
    final page = widget.pageController.page;
    if (page == null) return widget.selectedIndex.toDouble();
    return page;
  }

  void _beginScrub() {
    setState(() => _scrubbing = true);
    HapticFeedback.mediumImpact();
  }

  void _endScrub() {
    if (!_scrubbing) return;
    setState(() => _scrubbing = false);
    final target = _pagePosition.round().clamp(0, widget.itemCount - 1);
    widget.pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    HapticFeedback.selectionClick();
  }

  void _scrubByDelta(double dx) {
    if (!widget.pageController.hasClients || _barWidth <= 0) return;
    final slot = _barWidth / widget.itemCount;
    final next = (_pagePosition - dx / slot).clamp(
      0.0,
      (widget.itemCount - 1).toDouble(),
    );
    final pageWidth = widget.pageController.position.viewportDimension;
    if (pageWidth > 0) {
      widget.pageController.jumpTo(pageWidth * next);
    }
  }

  bool get _pillAnimates {
    if (_scrubbing) return false;
    if (!widget.pageController.hasClients) return true;
    return !widget.pageController.position.isScrollingNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ManagerDashboardAppearance>(
      valueListenable: ManagerAppPreferences.dashboardAppearance,
      builder: (context, appearance, _) {
        final nav = DashboardThemeData.forAppearance(appearance).nav;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: [
                  BoxShadow(
                    color: nav.outerShadow,
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: _barSurface(nav),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _barSurface(ManagerNavBarTheme nav) {
    return GestureDetector(
      onLongPressStart: (_) => _beginScrub(),
      onLongPressEnd: (_) => _endScrub(),
      onLongPressCancel: _endScrub,
      onHorizontalDragUpdate: (d) {
        if (!_scrubbing) return;
        _scrubByDelta(d.delta.dx);
      },
      onHorizontalDragEnd: (_) => _endScrub(),
      onHorizontalDragCancel: _endScrub,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: nav.barGradientBottom,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: nav.borderColor, width: 1.2),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _barWidth = constraints.maxWidth;
            final barWidth = _barWidth;
            final slotWidth = barWidth / widget.itemCount;
            final page = _pagePosition;
            final pillLeft = (page * slotWidth).clamp(
              0.0,
              barWidth - slotWidth,
            );

            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
                  duration: _pillAnimates
                      ? const Duration(milliseconds: 320)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  left: pillLeft + 2,
                  top: 2,
                  bottom: 2,
                  width: slotWidth - 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [nav.pillGradientStart, nav.pillGradientEnd],
                      ),
                      border: nav.pillBorderWidth > 0
                          ? Border.all(
                              color: nav.pillBorderColor,
                              width: nav.pillBorderWidth,
                            )
                          : null,
                      boxShadow: nav.pillGlowBlur > 0
                          ? [
                              BoxShadow(
                                color: nav.pillGlowColor,
                                blurRadius: nav.pillGlowBlur,
                                spreadRadius: -1,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
                Row(
                  children: List.generate(widget.itemCount, (index) {
                    final item = widget.items[index];
                    final distance = (page - index).abs();
                    final t = (1 - distance.clamp(0.0, 1.0));
                    final iconSize = 23.0 + 2.0 * t;
                    final iconColor = Color.lerp(
                      nav.inactiveIconColor.withValues(
                        alpha: nav.inactiveIconOpacity,
                      ),
                      nav.activeIconColor,
                      t,
                    )!;

                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onTap(index);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          height: 44,
                          child: Tooltip(
                            message: item.label,
                            child: Icon(
                              item.icon,
                              size: iconSize,
                              color: iconColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
