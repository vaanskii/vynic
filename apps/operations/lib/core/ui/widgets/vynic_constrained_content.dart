import 'package:flutter/widgets.dart';
import 'package:vynic/core/ui/vynic_responsive.dart';

/// Centers its child and caps its width so content columns don't stretch into
/// unreadable line lengths on 1920/2560-wide displays. Use for forms, reports,
/// settings — anywhere reading matters more than filling the screen.
class VynicConstrainedContent extends StatelessWidget {
  const VynicConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = VynicResponsive.maxContentWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
