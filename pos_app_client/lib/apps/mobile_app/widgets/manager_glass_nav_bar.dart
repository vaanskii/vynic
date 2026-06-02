import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Frosted bottom bar with a sliding green active pill and long-press scrub.
class ManagerGlassNavBar extends StatefulWidget {
  const ManagerGlassNavBar({
    super.key,
    required this.pageController,
    required this.itemCount,
    required this.items,
    required this.onTap,
  });

  final PageController pageController;
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
  static const _activeGreen = Color(0xFF10B981);
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
    if (!widget.pageController.hasClients) return 0;
    return widget.pageController.page ??
        widget.pageController.initialPage.toDouble();
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
    final next = (_pagePosition - dx / slot)
        .clamp(0.0, (widget.itemCount - 1).toDouble());
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 30,
                spreadRadius: -4,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: GestureDetector(
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF3A3A48).withValues(alpha: 0.55),
                        const Color(0xFF0B0B11).withValues(alpha: 0.62),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _barWidth = constraints.maxWidth;
                      final barWidth = _barWidth;
                      final slotWidth = barWidth / widget.itemCount;
                      final page = _pagePosition;
                      final pillLeft =
                          (page * slotWidth).clamp(0.0, barWidth - slotWidth);

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
                                  colors: [
                                    _activeGreen.withValues(alpha: 0.42),
                                    const Color(0xFF059669)
                                        .withValues(alpha: 0.28),
                                  ],
                                ),
                                border: Border.all(
                                  color: _activeGreen.withValues(alpha: 0.65),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _activeGreen.withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    spreadRadius: -2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: List.generate(widget.itemCount, (index) {
                              final item = widget.items[index];
                              final distance = (page - index).abs();
                              final t = (1 - distance.clamp(0.0, 1.0));
                              final iconSize = 23.0 + 2.0 * t;
                              final opacity = 0.42 + 0.58 * t;

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
                                        color: Colors.white
                                            .withValues(alpha: opacity),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
