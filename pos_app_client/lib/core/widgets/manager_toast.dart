import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/core/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/core/theme/manager_theme.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

/// Visual variant for manager overlay toasts.
enum ManagerToastVariant {
  standard,
  error,
}

/// Resolved colors for manager toasts / snackbars.
class ManagerToastColors {
  const ManagerToastColors({
    required this.background,
    required this.border,
    required this.text,
    required this.accent,
    required this.icon,
    required this.shadow,
  });

  final Color background;
  final Color border;
  final Color text;
  final Color accent;
  final Color icon;
  final Color shadow;

  static ManagerToastColors resolve(
    DashboardThemeData theme, {
    required bool isError,
    Color? accentOverride,
  }) {
    if (isError) {
      if (theme.isDark) {
        return ManagerToastColors(
          background: theme.surfaceElevated,
          border: theme.bad.withValues(alpha: 0.5),
          text: theme.textPrimary,
          accent: theme.bad,
          icon: theme.bad,
          shadow: Colors.black.withValues(alpha: 0.4),
        );
      }
      return ManagerToastColors(
        background: const Color(0xFFFEF2F2),
        border: const Color(0xFFFECACA),
        text: const Color(0xFF7F1D1D),
        accent: theme.bad,
        icon: const Color(0xFFB91C1C),
        shadow: theme.bad.withValues(alpha: 0.12),
      );
    }

    final accent = accentOverride ?? theme.good;
    if (theme.isDark) {
      return ManagerToastColors(
        background: theme.surfaceElevated,
        border: accent.withValues(alpha: 0.45),
        text: theme.textPrimary,
        accent: accent,
        icon: accent,
        shadow: Colors.black.withValues(alpha: 0.4),
      );
    }
    return ManagerToastColors(
      background: const Color(0xFFECFDF5),
      border: const Color(0xFFA7F3D0),
      text: const Color(0xFF065F46),
      accent: accent,
      icon: const Color(0xFF047857),
      shadow: accent.withValues(alpha: 0.12),
    );
  }
}

class ManagerToast {
  static DashboardThemeData _themeOf(BuildContext context) {
    try {
      return managerThemeOf(context);
    } catch (_) {
      return DashboardThemeData.forAppearance(
        ManagerAppPreferences.dashboardAppearance.value,
      );
    }
  }

  /// Floating overlay toast (top of screen).
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    ManagerToastVariant? variant,
    Color? accentColor,
  }) {
    final v = variant ??
        (isError ? ManagerToastVariant.error : ManagerToastVariant.standard);
    _insertToast(context, message, v, accentColor: accentColor);
  }

  /// Themed [SnackBar] (bottom floating card).
  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
    IconData? icon,
    Color? accentColor,
  }) {
    if (!context.mounted) return;
    final theme = _themeOf(context);
    final colors = ManagerToastColors.resolve(
      theme,
      isError: isError,
      accentOverride: accentColor,
    );
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        elevation: 0,
        backgroundColor: Colors.transparent,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon ??
                    (isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded),
                size: 18,
                color: colors.icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _insertToast(
    BuildContext context,
    String message,
    ManagerToastVariant variant, {
    Color? accentColor,
  }) {
    final theme = _themeOf(context);
    void tryInsert({int attempt = 0}) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
          Navigator.maybeOf(context, rootNavigator: true)?.overlay;
      if (overlay == null) {
        if (attempt < 8) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => tryInsert(attempt: attempt + 1),
          );
        }
        return;
      }

      late OverlayEntry overlayEntry;
      overlayEntry = OverlayEntry(
        builder: (ctx) => _ToastWidget(
          message: message,
          variant: variant,
          theme: theme,
          accentColor: accentColor,
          onDismissed: () {
            if (overlayEntry.mounted) overlayEntry.remove();
          },
        ),
      );

      overlay.insert(overlayEntry);
    }

    tryInsert();
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ManagerToastVariant variant;
  final DashboardThemeData theme;
  final Color? accentColor;
  final VoidCallback onDismissed;

  const _ToastWidget({
    required this.message,
    required this.variant,
    required this.theme,
    this.accentColor,
    required this.onDismissed,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const _visibleDuration = Duration(milliseconds: 4500);
  double _dragOffset = 0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
      vsync: this,
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    Future.delayed(_visibleDuration, () {
      if (mounted && !_dismissing) _dismiss();
    });
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.variant == ManagerToastVariant.error;
    final topInset = MediaQuery.paddingOf(context).top;
    final colors = ManagerToastColors.resolve(
      widget.theme,
      isError: isError,
      accentOverride: widget.accentColor,
    );

    return Positioned(
      top: topInset + 10 + _dragOffset.clamp(-120.0, 0.0),
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.delta.dy >= 0) return;
              setState(() {
                _dragOffset += details.delta.dy;
              });
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_dragOffset < -48 || velocity < -400) {
                _dismiss();
              } else {
                setState(() => _dragOffset = 0);
              }
            },
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 36,
                        margin: const EdgeInsets.only(right: 12, top: 2),
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
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
