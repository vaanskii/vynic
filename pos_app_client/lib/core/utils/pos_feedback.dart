import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// Transient messages, in the same vocabulary as everything else on the POS.
///
/// These used to be saturated blocks — navy `#1E3A8A`, slate `#1F2937`, a
/// fire-engine red — with white text and a heavy drop shadow. A third palette,
/// after the floor's and the admin's, and the loudest thing on a screen whose
/// whole design is quiet. They are panels now: the venue's off-white, a
/// hairline, and a single tinted square carrying the meaning.

enum PosToastStyle { success, error, info }

class _PosToastTheme {
  const _PosToastTheme({
    required this.fill,
    required this.border,
    required this.foreground,
    required this.icon,
    required this.defaultDuration,
  });

  /// The tone's wash, behind the icon only — never behind the message. A
  /// tinted card is a status; a tinted icon on a white card is a message with
  /// a status.
  final Color fill;
  final Color border;
  final Color foreground;
  final IconData icon;
  final Duration defaultDuration;
}

const _toastThemes = <PosToastStyle, _PosToastTheme>{
  PosToastStyle.success: _PosToastTheme(
    fill: VynicFloorTokens.successFill,
    border: VynicFloorTokens.successBorder,
    foreground: VynicFloorTokens.successText,
    icon: Icons.check_rounded,
    defaultDuration: Duration(milliseconds: 2000),
  ),
  PosToastStyle.error: _PosToastTheme(
    fill: VynicFloorTokens.dangerFill,
    border: VynicFloorTokens.dangerBorder,
    foreground: VynicFloorTokens.dangerText,
    icon: Icons.priority_high_rounded,
    defaultDuration: Duration(milliseconds: 3000),
  ),
  PosToastStyle.info: _PosToastTheme(
    fill: VynicFloorTokens.accentSoft,
    border: Color(0xFFE2DCF2),
    foreground: VynicFloorTokens.accentText,
    icon: Icons.info_outline_rounded,
    defaultDuration: Duration(milliseconds: 2400),
  ),
};

/// How many toasts are on screen, so a second one does not land exactly on top
/// of the first.
///
/// Every toast used to be inserted at the same `top: 28, right: 24`. Two in
/// quick succession — and a POS produces them in bursts, „order updated" then
/// „printed" — drew one on top of the other, so the first was unreadable and
/// the second looked like a rendering fault.
final List<_ToastSlot> _liveToasts = <_ToastSlot>[];

class _ToastSlot {
  _ToastSlot(this.rebuild);

  /// Asks this toast's overlay entry to repaint after the stack shifts.
  final VoidCallback rebuild;
}

const double _toastHeight = 62;
const double _toastGap = 10;

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
  final completer = Completer<void>();
  final controller = AnimationController(
    vsync: overlay,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  );

  late final OverlayEntry entry;
  late final _ToastSlot slot;

  entry = OverlayEntry(
    builder: (overlayContext) {
      final index = _liveToasts.indexOf(slot);
      final offset = (index < 0 ? 0 : index) * (_toastHeight + _toastGap);

      return Positioned(
        top: isTop ? 24 + offset : null,
        bottom: isTop ? null : 24 + offset,
        left: alignToRight ? null : 24,
        right: 24,
        child: IgnorePointer(
          // Pointer-transparent on purpose. A message that appears over a busy
          // floor screen must never be the thing a waiter taps by accident.
          ignoring: true,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0.35, 0),
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
                child: _PosToastCard(
                  theme: theme,
                  title: title,
                  message: message,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  slot = _ToastSlot(entry.markNeedsBuild);
  _liveToasts.add(slot);
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
        _liveToasts.remove(slot);
        // The ones still on screen close the gap this left behind.
        for (final other in _liveToasts) {
          other.rebuild();
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }),
  );

  await completer.future;
}

/// A panel, not a banner: the venue's own surface with a hairline round it and
/// one tinted square saying what kind of message this is.
class _PosToastCard extends StatelessWidget {
  const _PosToastCard({
    required this.theme,
    required this.title,
    required this.message,
  });

  final _PosToastTheme theme;
  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400, minHeight: _toastHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
        decoration: BoxDecoration(
          color: VynicFloorTokens.panel,
          borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
          border: Border.all(color: VynicFloorTokens.panelBorder),
          // The one place these screens carry a shadow. A panel floating over
          // another panel has nothing else to separate it from what it covers.
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A1C1A19),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.fill,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: theme.border),
              ),
              child: Icon(theme.icon, color: theme.foreground, size: 17),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VynicFloorTokens.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // 14, not 15: at the 0.85 paint scale a 1024x768
                      // terminal runs at, a message is the one thing that has
                      // to stay readable while it is disappearing.
                      color: title == null
                          ? VynicFloorTokens.text
                          : VynicFloorTokens.textMuted,
                      fontSize: 14,
                      fontWeight: title == null
                          ? FontWeight.w600
                          : FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    barrierColor: const Color(0x591C1A19),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: VynicFloorTokens.panel,
        surfaceTintColor: VynicFloorTokens.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        ),
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
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: VynicFloorTokens.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: VynicFloorTokens.textMuted,
                    height: 1.35,
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
                      labelStyle: const TextStyle(
                        color: VynicFloorTokens.textMuted,
                      ),
                      filled: true,
                      fillColor: VynicFloorTokens.page,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: VynicFloorTokens.panelBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: VynicFloorTokens.panelBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: VynicFloorTokens.accentText,
                        ),
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
                      style: TextButton.styleFrom(
                        foregroundColor: VynicFloorTokens.textMuted,
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: VynicFloorTokens.accentStrong,
                        foregroundColor: VynicFloorTokens.panel,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
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
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: VynicFloorTokens.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: VynicFloorTokens.textMuted,
                height: 1.35,
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
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: VynicFloorTokens.dangerText,
                    foregroundColor: VynicFloorTokens.panel,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
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
