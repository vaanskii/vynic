import 'package:flutter/widgets.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_responsive.dart';

/// A responsive primary + secondary two-pane layout — the workhorse for the
/// POS shell (tables + order rail), menu (categories/items + cart), and order
/// detail (items + actions rail).
///
/// Behavior:
/// - When there's room ([VynicResponsive.canShowTwoPanes]), renders the two
///   panes side by side with [secondary] taking a rules-based panel width and
///   [primary] taking the rest.
/// - When width is tight (compact terminals, 1366×768 under 150% scaling), it
///   collapses to a single pane. By default it shows [primary] and hides
///   [secondary] — the caller is expected to surface [secondary] some other
///   way in compact mode (a sheet, a tab). Set [stackWhenCompact] to instead
///   stack them vertically in a scroll view.
///
/// This primitive never assumes a fixed screen size and never overflows: in
/// side-by-side mode the panel width is clamped so [primary] keeps a usable
/// minimum; in compact mode only one pane occupies the width.
class VynicTwoPaneLayout extends StatelessWidget {
  const VynicTwoPaneLayout({
    super.key,
    required this.primary,
    required this.secondary,
    this.secondaryOnRight = true,
    this.preferredPanelWidth = 380,
    this.minPrimaryWidth = 480,
    this.stackWhenCompact = false,
    this.showSecondaryInCompact = false,
    this.dividerColor = VynicColors.border,
  });

  final Widget primary;
  final Widget secondary;

  /// Side the [secondary] panel sits on when side by side.
  final bool secondaryOnRight;

  final double preferredPanelWidth;
  final double minPrimaryWidth;

  /// In compact mode, stack the two panes vertically (scrollable) instead of
  /// showing only [primary].
  final bool stackWhenCompact;

  /// In compact single-pane mode, show [secondary] instead of [primary].
  final bool showSecondaryInCompact;

  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoPanes = VynicResponsive.canShowTwoPanes(
          width,
          minPrimaryWidth: minPrimaryWidth,
        );

        if (!twoPanes) {
          if (stackWhenCompact) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [primary, secondary],
              ),
            );
          }
          return showSecondaryInCompact ? secondary : primary;
        }

        final panelWidth = VynicResponsive.panelWidth(
          width,
          preferred: preferredPanelWidth,
        );
        final divider = Container(width: 1, color: dividerColor);
        final panel = SizedBox(width: panelWidth, child: secondary);
        final main = Expanded(child: primary);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: secondaryOnRight
              ? [main, divider, panel]
              : [panel, divider, main],
        );
      },
    );
  }
}
