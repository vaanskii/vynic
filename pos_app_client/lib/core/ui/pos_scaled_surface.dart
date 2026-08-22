import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Applies the operator's UI-scale setting to the whole POS, and keeps the
/// layout above the size the POS is actually designed for.
///
/// Two things happen here.
///
/// **Scale.** The subtree is laid out in a box of `window ÷ scale` and painted
/// at `scale`, so at 90% everything is drawn 10% smaller *and* the layout gets
/// 11% more room to spend. A bare `Transform` would shrink the pixels while
/// every breakpoint, rail width and minimum height still believed it had the
/// full window, so nothing would actually fit better.
///
/// **Floor.** The layout box never goes below [designSize]. A window smaller
/// than that — or a scale that would take it below — lays out at the design
/// size and is painted down to fit. That is what makes a small screen show the
/// same layout, shrunk, instead of the same layout overflowing: the widgets
/// always get the room they were built for, and the shortfall is absorbed in
/// pixels rather than in torn layouts.
class PosScaledSurface extends StatelessWidget {
  const PosScaledSurface({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  /// The smallest layout the POS is built for.
  ///
  /// The floor is a promise that no screen is laid out in less room than it was
  /// verified at — but it is also a tax. A 1024-wide terminal has to paint the
  /// whole layout down to fit, so the wider this is, the smaller everything is
  /// on the screens that can least afford it.
  ///
  /// 1200 is the lowest value the overflow matrix in
  /// `home_sections_layout_test.dart` currently passes at; 1180 tears the
  /// take-away section and the action rail by 19–69pt. It was 1280, so a
  /// 1024x768 terminal now paints at 0.853 instead of 0.800 — about 7% bigger.
  ///
  /// It is deliberately *not* low enough to un-pin the operator's „მასშტაბი"
  /// setting, which stays inert below roughly 1138 (that is where 90% and 100%
  /// stop resolving to the same factor at this width). Getting there needs
  /// those two sections to survive ~1120, which is layout work, not a constant.
  static const Size designSize = Size(1200, 720);
  
  /// Box the subtree is laid out in, and the factor it is painted at.
  ///
  /// Split out so the behaviour can be checked without pumping a window.
  ///
  /// The layout is *derived from* the paint factor rather than computed on its
  /// own. An earlier version floored each axis independently — width up to
  /// 1280, height left alone — which gave the layout box a different aspect
  /// ratio from the window. Painting it uniformly then letterboxed it: at
  /// 1024x768 the app drew into 1024x614 and left a 154pt dead strip along the
  /// bottom. Because `layout = window / paint`, that cannot happen here —
  /// `layout * paint` is the window, exactly, on both axes.
  static ({Size layout, double paint}) resolve(Size window, double scale) {
    if (scale <= 0 || window.width <= 0 || window.height <= 0) {
      return (layout: window, paint: 1);
    }
    // Paint at what the operator asked for, unless honouring the design floor
    // forces it lower. `window / designSize` is the largest factor that still
    // leaves the layout at least [designSize] on that axis.
    final paint = math.min(
      scale,
      math.min(
        window.width / designSize.width,
        window.height / designSize.height,
      ),
    );
    return (
      layout: Size(window.width / paint, window.height / paint),
      paint: paint,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return child;
        }

        final resolved = resolve(Size(width, height), scale);
        if ((resolved.paint - 1).abs() < 0.001 &&
            (resolved.layout.width - width).abs() < 0.5 &&
            (resolved.layout.height - height).abs() < 0.5) {
          return child;
        }

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: resolved.layout.width,
            maxHeight: resolved.layout.height,
            child: Transform.scale(
              scale: resolved.paint,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: resolved.layout.width,
                height: resolved.layout.height,
                // Responsive decisions below must read the box they are
                // actually laid out in, not the window.
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: resolved.layout),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
