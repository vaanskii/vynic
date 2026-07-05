import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_shadows.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

/// A flat, bordered Vynic surface. Optionally floats with the single panel
/// shadow token. Mirrors `admin_design.dart`'s panel so an admin screen can
/// migrate onto it with no visual change.
class VynicCard extends StatelessWidget {
  const VynicCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VynicSpacing.md),
    this.color = VynicColors.card,
    this.floating = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// When true, adds the panel shadow token; otherwise flat with a 1px border.
  final bool floating;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color,
      borderRadius: VynicRadius.smAll,
      border: Border.all(color: VynicColors.border),
      boxShadow: floating ? VynicShadows.panel : VynicShadows.none,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          borderRadius: VynicRadius.smAll,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}
