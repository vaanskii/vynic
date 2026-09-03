import 'package:flutter/widgets.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

/// A scroll-safe content container. Wraps children in a scroll view so a panel
/// whose content is taller than the viewport (common at 1366×768 or under
/// 150% scaling) scrolls instead of overflowing with a yellow/black stripe.
///
/// Use this as the body of any fixed-height panel or side sheet whose content
/// length is data-driven.
class VynicScrollablePanel extends StatelessWidget {
  const VynicScrollablePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VynicSpacing.md),
    this.controller,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: child,
        );
        // If the panel has a bounded height, keep at least the viewport height
        // so short content top-aligns while tall content scrolls. In an
        // unbounded context (maxHeight == infinity) skip the floor — a
        // minHeight of infinity would throw.
        if (!constraints.hasBoundedHeight) return view;
        return SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}
