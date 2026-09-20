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
      label: const Text('აპლიკაციიდან გასვლა'),
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
    child: AlertDialog(
      title: const Text('აპლიკაციიდან გასვლა'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ნამდვილად გსურთ Vynic POS-ის დახურვა?'),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('მონაცემები ინახება და კავშირები იხურება…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy || widget.quit.shutdownStarted
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('გაუქმება'),
        ),
        FilledButton(
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
          child: const Text('გასვლა'),
        ),
      ],
    ),
  );
}
