import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'package:vynic/core/ui/vynic_motion.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/widgets/pos_text.dart';

/// POS route policy, scoped to the modal. Manager and page themes are untouched.
/// Keep each caller's dismissal/admission rules; form owners guard dirty drafts.
Future<T?> showPosModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  Color? barrierColor,
  String? barrierLabel,
  RouteSettings? routeSettings,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  useRootNavigator: useRootNavigator,
  barrierColor: barrierColor ?? VynicFloorTokens.text.withValues(alpha: .38),
  barrierLabel: barrierLabel,
  routeSettings: routeSettings,
  animationStyle: AnimationStyle(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : VynicMotion.fast,
    reverseDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : VynicMotion.fast,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  ),
  builder: (context) => PosKeyboardViewport(
    child: PosDialogTheme(child: Builder(builder: builder)),
  ),
);

class PosDialogTheme extends StatelessWidget {
  const PosDialogTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(borderRadius: VynicRadius.smAll);
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(PosTheme.controlSize),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: VynicSpacing.md,
          vertical: VynicSpacing.sm,
        ),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(
        base.textTheme.labelLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final border = OutlineInputBorder(
      borderRadius: VynicRadius.smAll,
      borderSide: const BorderSide(color: VynicFloorTokens.panelBorder),
    );
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          brightness: Brightness.light,
          primary: VynicFloorTokens.accentStrong,
          onPrimary: Colors.white,
          surface: VynicFloorTokens.panel,
          onSurface: VynicFloorTokens.text,
          error: VynicFloorTokens.dangerText,
        ),
        textTheme: base.textTheme.apply(
          bodyColor: VynicFloorTokens.text,
          displayColor: VynicFloorTokens.text,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: VynicFloorTokens.panel,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: VynicRadius.lgAll),
          titleTextStyle: base.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: VynicFloorTokens.text,
          ),
          contentTextStyle: base.textTheme.bodyLarge?.copyWith(
            fontSize: 15,
            height: 1.45,
            color: VynicFloorTokens.textMuted,
          ),
          actionsPadding: const EdgeInsets.all(VynicSpacing.lg),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: VynicFloorTokens.canvas,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(
              color: VynicFloorTokens.accentStrong,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.all(VynicSpacing.md),
          labelStyle: const TextStyle(
            fontSize: 15,
            color: VynicFloorTokens.textMuted,
          ),
          errorMaxLines: 3,
          helperMaxLines: 3,
        ),
        filledButtonTheme: FilledButtonThemeData(style: button),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: button.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? VynicFloorTokens.panelBorder
                  : VynicFloorTokens.accentStrong,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? VynicFloorTokens.textMuted
                  : Colors.white,
            ),
            elevation: const WidgetStatePropertyAll(0),
          ),
        ),
        textButtonTheme: TextButtonThemeData(style: button),
        outlinedButtonTheme: OutlinedButtonThemeData(style: button),
        iconButtonTheme: const IconButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(PosTheme.controlSize),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// A shared form surface with fixed title/actions and a scrollable body.
/// Insets include the POS keyboard dock as well as the platform keyboard.
class PosFormDialog extends StatelessWidget {
  const PosFormDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    required this.onClose,
    this.subtitle,
    this.width = 560,
    this.bodyKey,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final double width;
  final Key? bodyKey;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (PosInputSettings.keyboardHeight.value > 0) {
          Navigator.of(context).pop();
        } else {
          onClose?.call();
        }
      },
    },
    child: PosKeyboardViewport(
      child: PosDialogTheme(
        child: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            // Anchor the title independently of the dock. Only the scrollable body
            // loses space; opening/dismissing a keyboard never recenters the form.
            final top = math.max(
              16.0,
              (media.size.height - media.padding.vertical - 660) / 2,
            );
            final available = math.max(
              0.0,
              media.size.height -
                  media.viewInsets.vertical -
                  media.padding.vertical -
                  top -
                  16,
            );
            return Dialog(
              alignment: Alignment.topCenter,
              insetPadding: EdgeInsets.fromLTRB(16, top, 16, 16),
              // No extra 100ms inset animation competing with the keyboard dock.
              insetAnimationDuration: Duration.zero,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                key: bodyKey,
                constraints: BoxConstraints(
                  maxWidth: width,
                  maxHeight: math.min(660, available),
                ),
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PosText(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 4),
                                    PosText(
                                      subtitle!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: VynicFloorTokens.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: PosLocale.tr(context, 'დახურვა'),
                              onPressed: onClose,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(
                        height: 1,
                        color: VynicFloorTokens.panelBorder,
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(VynicSpacing.lg),
                          child: child,
                        ),
                      ),
                      const Divider(
                        height: 1,
                        color: VynicFloorTokens.panelBorder,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: OverflowBar(
                          alignment: MainAxisAlignment.end,
                          spacing: 12,
                          overflowSpacing: 8,
                          children: actions,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class PosFormError extends StatelessWidget {
  const PosFormError(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(VynicSpacing.sm),
      decoration: BoxDecoration(
        color: VynicFloorTokens.dangerFill,
        border: Border.all(color: VynicFloorTokens.dangerBorder),
        borderRadius: VynicRadius.smAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: VynicFloorTokens.dangerText,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PosText(
              message,
              style: const TextStyle(
                color: VynicFloorTokens.dangerText,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
