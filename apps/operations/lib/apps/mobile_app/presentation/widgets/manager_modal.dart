import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';

/// Presentation-only replacement for Manager sheets. Result, dismissal and
/// Navigator semantics are unchanged. The route owns keyboard avoidance once.
Future<T?> showManagerModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  double maxWidth = 700,
}) => showDialog<T>(
  context: context,
  builder: (context) => ManagerThemeListener(
    child: Dialog(
      insetPadding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 700 ? 12 : 32,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final width = math.min(maxWidth, constraints.maxWidth);
          final height = math.min(840.0, constraints.maxHeight);
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: height),
            child: MediaQuery(
              data: media.copyWith(
                viewInsets: EdgeInsets.zero,
                size: Size(width, height),
              ),
              child: Builder(builder: builder),
            ),
          );
        },
      ),
    ),
  ),
);

/// Manager form surface: a fixed header and action row around a scrollable body.
/// The Dialog route alone owns keyboard avoidance; long forms remain reachable.
class ManagerFormDialog extends StatelessWidget {
  const ManagerFormDialog({
    super.key,
    this.title,
    this.maxWidth = 700,
    this.content,
    this.actions,
    this.backgroundColor,
    this.shape,
    this.insetPadding,
    this.contentPadding,
    this.titlePadding,
    this.actionsPadding,
    this.scrollable = true,
    this.actionsAlignment,
  });
  final Widget? title, content;
  final double maxWidth;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final EdgeInsets? insetPadding;
  final EdgeInsetsGeometry? contentPadding, titlePadding, actionsPadding;
  final bool scrollable;
  final MainAxisAlignment? actionsAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = managerThemeOf(context);
    final small = MediaQuery.sizeOf(context).width < 700;
    return Dialog(
      insetPadding: insetPadding ?? EdgeInsets.all(small ? 12 : 32),
      backgroundColor: backgroundColor ?? t.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: t.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 840),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Padding(
                padding:
                    titlePadding ??
                    EdgeInsets.fromLTRB(small ? 20 : 28, 18, 12, 16),
                child: DefaultTextStyle(
                  style: theme.textTheme.titleLarge!.copyWith(
                    fontSize: small ? 20 : 24,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                  child: title!,
                ),
              ),
              Divider(height: 1, color: t.borderSubtle),
            ],
            if (content != null)
              Flexible(
                child: SingleChildScrollView(
                  padding: contentPadding ?? EdgeInsets.all(small ? 20 : 28),
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: t.textPrimary,
                    ),
                    child: content!,
                  ),
                ),
              ),
            if (actions != null && actions!.isNotEmpty) ...[
              Divider(height: 1, color: t.borderSubtle),
              Padding(
                padding:
                    actionsPadding ??
                    EdgeInsets.fromLTRB(
                      small ? 20 : 28,
                      14,
                      small ? 20 : 28,
                      18,
                    ),
                child: OverflowBar(
                  alignment: actionsAlignment ?? MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: actions!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ManagerContentWidth extends StatelessWidget {
  const ManagerContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 1200,
  });
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// The preview's centered detail frame for existing scrollable workspaces.
/// The bounded body owns its scroll view; header/footer remain keyboard-safe.
class ManagerPageDialog extends StatelessWidget {
  const ManagerPageDialog({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = 880,
  });
  final String title;
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    final small = MediaQuery.sizeOf(context).width < 700;
    return Dialog(
      insetPadding: EdgeInsets.all(small ? 12 : 32),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 840),
        child: SizedBox(
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(small ? 20 : 28, 18, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'NotoSansGeorgian',
                          fontSize: small ? 20 : 24,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'დახურვა · Esc',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 21),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.borderSubtle),
              Expanded(child: child),
              Divider(height: 1, color: t.borderSubtle),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  small ? 20 : 28,
                  14,
                  small ? 20 : 28,
                  18,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('დახურვა'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
