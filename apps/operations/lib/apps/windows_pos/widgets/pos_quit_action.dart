import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/widgets/pos_text.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/services/pos/pos_quit.dart';

Future<bool>? _activeConfirmation;

/// Shared by Settings and the Windows close request (including Alt+F4).
Future<bool> confirmPosQuit(BuildContext context, {PosQuit? quit}) {
  return _activeConfirmation ??=
      showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _QuitDialog(quit: quit ?? PosQuit.instance),
          )
          .then((result) => result ?? false)
          .whenComplete(() => _activeConfirmation = null);
}

class PosQuitAction extends StatelessWidget {
  const PosQuitAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.power_settings_new),
      label: const PosText('აპლიკაციიდან გასვლა'),
      onPressed: () async {
        if (await confirmPosQuit(context)) {
          // Cleanup already succeeded. Required avoids a second confirmation.
          await ServicesBinding.instance.exitApplication(AppExitType.required);
        }
      },
    );
  }
}

class _QuitDialog extends StatefulWidget {
  const _QuitDialog({required this.quit});
  final PosQuit quit;
  @override
  State<_QuitDialog> createState() => _QuitDialogState();
}

class _QuitDialogState extends State<_QuitDialog> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !widget.quit.shutdownStarted,
    child: Dialog(
      key: const ValueKey('pos-quit-modal'),
      backgroundColor: VynicFloorTokens.panel,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: VynicFloorTokens.panelBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: VynicFloorTokens.dangerFill,
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      color: VynicFloorTokens.dangerText,
                      size: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const PosText(
                'აპლიკაციიდან გასვლა',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: VynicFloorTokens.text,
                ),
              ),
              const SizedBox(height: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PosText('ნამდვილად გსურთ Vynic POS-ის დახურვა?'),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const PosText('მონაცემები ინახება და კავშირები იხურება…'),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    PosText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(120, 48),
                      foregroundColor: VynicFloorTokens.text,
                      side: const BorderSide(
                        color: VynicFloorTokens.panelBorder,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _busy || widget.quit.shutdownStarted
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const PosText('გაუქმება'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 48),
                      backgroundColor: VynicFloorTokens.dangerText,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() {
                              _busy = true;
                              _error = null;
                            });
                            final error = await widget.quit.prepare();
                            if (!mounted) return;
                            if (error == null) {
                              Navigator.pop(context, true);
                            } else {
                              setState(() {
                                _busy = false;
                                _error = error;
                              });
                            }
                          },
                    child: const PosText('გასვლა'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
