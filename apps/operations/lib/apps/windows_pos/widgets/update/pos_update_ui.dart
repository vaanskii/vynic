import 'package:vynic/core/widgets/pos_text.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';

const updateLabels = {
  'UP_TO_DATE': 'პროგრამა განახლებულია',
  'CHECKING': 'მოწმდება ახალი ვერსია',
  'DOWNLOADING': 'ახალი ვერსია იტვირთება',
  'READY_TO_INSTALL': 'ახალი ვერსია ხელმისაწვდომია',
  'BLOCKED': 'განახლება დროებით შეუძლებელია',
  'INSTALLING': 'მიმდინარეობს განახლება',
  'RESTARTING': 'პროგრამა თავიდან ირთვება',
  'SUCCESS': 'პროგრამა განახლდა',
  'FAILED': 'განახლება ვერ დასრულდა',
  'ROLLED_BACK': 'აღდგა წინა ვერსია',
};

class PosUpdateSettings extends StatelessWidget {
  const PosUpdateSettings({super.key, this.updater});
  final PosUpdater? updater;
  @override
  Widget build(BuildContext context) {
    final u = updater ?? PosUpdater.instance;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PosText(
                'პროგრამის განახლება',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              PosText(
                u.configured
                    ? (u.localBlock ??
                          updateLabels[u.status] ??
                          updateLabels['FAILED']!)
                    : 'განახლების სერვისი მიუწვდომელია',
              ),
              if (u.version.isNotEmpty || u.state['current'] != null)
                PosText(
                  u.status == 'ROLLED_BACK' || u.status == 'UP_TO_DATE'
                      ? (u.state['current'] as String? ?? u.version)
                      : u.version,
                ),
              if (u.status == 'DOWNLOADING')
                LinearProgressIndicator(
                  value: (u.state['total'] as num? ?? 0) > 0
                      ? (u.state['downloaded'] as num? ?? 0) /
                            (u.state['total'] as num)
                      : null,
                ),
              if (u.configured)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      if (u.status == 'READY_TO_INSTALL' ||
                          u.status == 'BLOCKED')
                        FilledButton(
                          onPressed: () => unawaited(u.installNow()),
                          child: const PosText('განახლება ახლა'),
                        ),
                      if (!u.inputHeld)
                        TextButton(
                          onPressed: () => unawaited(u.check()),
                          child: const PosText('შემოწმება'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosUpdateHost extends StatefulWidget {
  const PosUpdateHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.updater,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final PosUpdater? updater;
  @override
  State<PosUpdateHost> createState() => _PosUpdateHostState();
}

class _PosUpdateHostState extends State<PosUpdateHost> {
  PosUpdater get u => widget.updater ?? PosUpdater.instance;
  String? offered;
  @override
  void initState() {
    super.initState();
    u.addListener(changed);
  }

  @override
  void dispose() {
    u.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    if (u.status != 'READY_TO_INSTALL' ||
        u.version == offered ||
        u.version == u.deferredVersion ||
        u.inputHeld)
      return;
    offered = u.version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = widget.navigatorKey.currentContext;
      if (context == null || !mounted) return;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const PosText('ახალი ვერსია ხელმისაწვდომია'),
            content: PosText(u.version),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(u.later());
                },
                child: const PosText('მოგვიანებით'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(u.installNow());
                },
                child: const PosText('განახლება ახლა'),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ExcludeFocus(
        excluding: u.inputHeld,
        child: AbsorbPointer(absorbing: u.inputHeld, child: widget.child),
      ),
      if (u.inputHeld)
        Positioned.fill(
          child: Material(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  PosText(
                    u.probation
                        ? 'პროგრამა მზადდება'
                        : updateLabels['INSTALLING']!,
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (u.installing)
                    TextButton(
                      onPressed: () => unawaited(u.installNow()),
                      child: const PosText('სტატუსის შემოწმება'),
                    ),
                ],
              ),
            ),
          ),
        ),
      if (u.localBlock != null && !u.inputHeld)
        Positioned(
          bottom: 16,
          left: 24,
          right: 24,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PosText(u.localBlock!),
            ),
          ),
        ),
    ],
  );
}
