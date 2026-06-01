import 'dart:async';

import 'package:flutter/material.dart';

enum PosToastStyle { success, error, info }

class _PosToastTheme {
  const _PosToastTheme({
    required this.backgroundColor,
    required this.textColor,
    required this.icon,
    required this.iconColor,
    required this.defaultDuration,
  });

  final Color backgroundColor;
  final Color textColor;
  final IconData icon;
  final Color iconColor;
  final Duration defaultDuration;
}

const _toastThemes = <PosToastStyle, _PosToastTheme>{
  PosToastStyle.success: _PosToastTheme(
    backgroundColor: Color(0xFF1E3A8A),
    textColor: Colors.white,
    icon: Icons.check_circle,
    iconColor: Color(0xFFBBF7D0),
    defaultDuration: Duration(milliseconds: 1800),
  ),
  PosToastStyle.error: _PosToastTheme(
    backgroundColor: Color(0xFFB91C1C),
    textColor: Colors.white,
    icon: Icons.error_rounded,
    iconColor: Color(0xFFFFE4E6),
    defaultDuration: Duration(milliseconds: 2500),
  ),
  PosToastStyle.info: _PosToastTheme(
    backgroundColor: Color(0xFF1F2937),
    textColor: Colors.white,
    icon: Icons.info_outline,
    iconColor: Color(0xFFBFDBFE),
    defaultDuration: Duration(milliseconds: 2200),
  ),
};

Future<void> showPosToast({
  required BuildContext context,
  required String message,
  PosToastStyle style = PosToastStyle.info,
  String? title,
  Duration? duration,
  ToastPosition position = ToastPosition.top,
  bool alignToRight = true,
}) async {
  final theme = _toastThemes[style] ?? _toastThemes[PosToastStyle.info]!;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return;
  }

  final isTop = position == ToastPosition.top;
  final margin = alignToRight
      ? EdgeInsets.only(top: isTop ? 28 : 0, bottom: isTop ? 0 : 28, right: 24)
      : EdgeInsets.only(
          top: isTop ? 28 : 0,
          bottom: isTop ? 0 : 28,
          left: 24,
          right: 24,
        );

  final completer = Completer<void>();
  final controller = AnimationController(
    vsync: overlay,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      return Positioned(
        top: isTop ? margin.top : null,
        bottom: isTop ? null : margin.bottom,
        left: alignToRight ? null : margin.left,
        right: alignToRight ? margin.right : margin.right,
        child: IgnorePointer(
          // Let gestures pass through so toast never blocks interaction.
          ignoring: true,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: controller,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                ),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: controller,
                curve: Curves.easeOut,
                reverseCurve: Curves.easeIn,
              ),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: theme.backgroundColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(theme.icon, color: theme.iconColor, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (title != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: theme.textColor.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Text(
                                message,
                                style: TextStyle(
                                  color: theme.textColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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
    },
  );

  overlay.insert(entry);
  unawaited(
    Future<void>(() async {
      try {
        await controller.forward();
        await Future<void>.delayed(duration ?? theme.defaultDuration);
        await controller.reverse();
      } finally {
        entry.remove();
        controller.dispose();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }),
  );

  await completer.future;
}

enum ToastPosition { top, bottom }

Future<T?> showPosDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext dialogContext) builder,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: builder(dialogContext),
        ),
      );
    },
  );
}

Future<void> showSuccessToast(BuildContext context, String message) {
  return showPosToast(
    context: context,
    message: message,
    style: PosToastStyle.success,
  );
}

Future<void> showErrorToast(BuildContext context, String message) {
  return showPosToast(
    context: context,
    message: message,
    style: PosToastStyle.error,
  );
}

Future<String?> promptForAdminPassword({
  required BuildContext context,
  String title = 'Admin Access Required',
  String message = 'Enter administrator password to proceed.',
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? capturedPassword;

  await showPosDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      bool obscureText = true;
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 20),
                Form(
                  key: formKey,
                  child: TextFormField(
                    controller: controller,
                    obscureText: obscureText,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Admin Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(() {
                          obscureText = !obscureText;
                        }),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Password is required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false) {
                          capturedPassword = controller.text.trim();
                          Navigator.of(dialogContext).pop();
                        }
                      },
                      child: const Text(
                        'Confirm',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  controller.dispose();
  return capturedPassword;
}

Future<bool> confirmDeletion({
  required BuildContext context,
  String title = 'Confirm Deletion',
  String message =
      'Are you sure you want to delete this item? This action cannot be undone.',
  String confirmLabel = 'Delete',
}) async {
  bool confirmed = false;

  await showPosDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    confirmed = true;
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  return confirmed;
}
