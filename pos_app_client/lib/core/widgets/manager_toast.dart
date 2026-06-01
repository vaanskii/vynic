import 'package:flutter/material.dart';

/// Visual variant for manager overlay toasts (aligned with brand pills + extras).
enum ManagerToastVariant {
  /// Indigo gradient — default success / neutral highlights.
  standard,

  /// Red gradient — validation / critical errors.
  error,

  /// Amber gradient — server/API reachable issues while WS may still be up.
  warning,

  /// Rose / deep red — realtime socket / network drop.
  connectionLost,

  /// Emerald gradient — link restored.
  connectionRestored,
}

class ManagerToast {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    ManagerToastVariant? variant,
  }) {
    final v = variant ?? (isError ? ManagerToastVariant.error : ManagerToastVariant.standard);
    _insertToast(context, message, v);
  }

  static void showConnectionLost(BuildContext context, {required bool socketIssue}) {
    _insertToast(
      context,
      socketIssue ? 'კავშირის პრობლემა' : 'სერვერთან კავშირი გაწყდა',
      socketIssue ? ManagerToastVariant.connectionLost : ManagerToastVariant.warning,
    );
  }

  static void showConnectionRestored(BuildContext context) {
    _insertToast(
      context,
      'სერვერთან კავშირი აღდგა',
      ManagerToastVariant.connectionRestored,
    );
  }

  static void _insertToast(BuildContext context, String message, ManagerToastVariant variant) {
    void tryInsert({int attempt = 0}) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
          Navigator.maybeOf(context, rootNavigator: true)?.overlay;
      if (overlay == null) {
        if (attempt < 8) {
          WidgetsBinding.instance.addPostFrameCallback((_) => tryInsert(attempt: attempt + 1));
        }
        return;
      }

      late OverlayEntry overlayEntry;
      overlayEntry = OverlayEntry(
        builder: (ctx) => _ToastWidget(
          message: message,
          variant: variant,
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

class _ToastSpec {
  const _ToastSpec({
    required this.gradient,
    required this.icon,
    required this.glow,
    required this.borderColor,
  });

  final LinearGradient gradient;
  final IconData icon;
  final Color glow;
  final Color borderColor;
}

_ToastSpec _specFor(ManagerToastVariant variant) {
  switch (variant) {
    case ManagerToastVariant.standard:
      return _ToastSpec(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        icon: Icons.bolt_rounded,
        glow: const Color(0xFF6366F1),
        borderColor: Colors.white24,
      );
    case ManagerToastVariant.error:
      return _ToastSpec(
        gradient: const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        icon: Icons.error_outline_rounded,
        glow: const Color(0xFFEF4444),
        borderColor: const Color(0x66FECACA),
      );
    case ManagerToastVariant.warning:
      return _ToastSpec(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        icon: Icons.cloud_off_rounded,
        glow: const Color(0xFFF59E0B),
        borderColor: const Color(0x66FDE68A),
      );
    case ManagerToastVariant.connectionLost:
      return _ToastSpec(
        gradient: const LinearGradient(
          colors: [Color(0xFFE11D48), Color(0xFF9F1239)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        icon: Icons.wifi_off_rounded,
        glow: const Color(0xFFE11D48),
        borderColor: const Color(0x66FECDD3),
      );
    case ManagerToastVariant.connectionRestored:
      return _ToastSpec(
        gradient: const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        icon: Icons.wifi_rounded,
        glow: const Color(0xFF10B981),
        borderColor: const Color(0x66A7F3D0),
      );
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ManagerToastVariant variant;
  final VoidCallback onDismissed;

  const _ToastWidget({
    required this.message,
    required this.variant,
    required this.onDismissed,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late Animation<double> _scale;

  static const _visibleDuration = Duration(milliseconds: 3200);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 280),
      vsync: this,
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();

    Future.delayed(_visibleDuration, () {
      if (mounted) _controller.reverse().then((_) => widget.onDismissed());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(widget.variant);
    final topInset = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: topInset + 12,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(
              scale: _scale,
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: spec.gradient,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: spec.borderColor, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: spec.glow.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: -2,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(spec.icon, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.25,
                              letterSpacing: 0.2,
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
      ),
    );
  }
}
