import 'package:vynic/core/widgets/pos_text.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
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

Future<void> showPosUpdateDialog(
  BuildContext context, {
  PosUpdater? updater,
  bool offer = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: !offer,
  builder: (context) => Dialog(
    backgroundColor: AdminDesign.panel,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.system_update_alt_rounded,
                    color: AdminDesign.accentDark,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: PosText(
                      'Vynic POS',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AdminDesign.text,
                      ),
                    ),
                  ),
                  if (!offer)
                    IconButton(
                      tooltip: 'დახურვა',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              PosUpdateSettings(
                updater: updater,
                embedded: true,
                onLater: offer
                    ? () async {
                        await (updater ?? PosUpdater.instance).later();
                        if (context.mounted) Navigator.pop(context);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

class PosUpdateSettings extends StatelessWidget {
  const PosUpdateSettings({
    super.key,
    this.updater,
    this.embedded = false,
    this.onLater,
  });
  final PosUpdater? updater;
  final bool embedded;
  final Future<void> Function()? onLater;

  @override
  Widget build(BuildContext context) {
    final u = updater ?? PosUpdater.instance;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final busy = u.checking || u.status == 'CHECKING';
        final downloading = u.status == 'DOWNLOADING';
        final offline = u.connectionIssue != null;
        final failed = offline || u.releaseCheckFailed || u.status == 'FAILED';
        final title = !u.configured
            ? 'განახლების სერვისი მიუწვდომელია'
            : u.visibleInstallStage != null
            ? u.visibleInstallStage!
            : busy
            ? updateLabels['CHECKING']!
            : offline
            ? 'განახლების სერვისთან კავშირი ვერ დამყარდა'
            : u.releaseCheckFailed
            ? 'განახლებების შემოწმება ვერ მოხერხდა'
            : u.localBlock ?? updateLabels[u.status] ?? 'სტატუსი მიუწვდომელია';
        final detail = !u.configured
            ? 'გაუშვით POS დაყენებული Vynic-ის მალსახმობიდან.'
            : offline
            ? 'სცადეთ ხელახლა. დაყენებული ვერსია არ შეცვლილა.'
            : u.releaseCheckFailed
            ? 'განახლებების სერვერი მიუწვდომელია. გადაამოწმეთ ქსელი და სცადეთ ხელახლა.'
            : u.visibleInstallStage != null
            ? 'დაელოდეთ პროცესის დასრულებას. POS ავტომატურად თავიდან ჩაირთვება; მონაცემები შენარჩუნდება.'
            : u.localBlock != null
            ? 'განახლება არ დაწყებულა. დაასრულეთ მითითებული ოპერაცია და ხელახლა აირჩიეთ განახლება ახლა.'
            : downloading
            ? 'ჩამოტვირთვა ფონურად მიმდინარეობს. შეგიძლიათ გააგრძელოთ მუშაობა.'
            : u.hasStagedUpdate
            ? 'ახალი ვერსია ჩამოტვირთულია. განახლებისას POS თავიდან ჩაირთვება.'
            : u.status == 'ROLLED_BACK'
            ? 'ახალი ვერსია ვერ გაეშვა. წინა ვერსია აღდგენილია; მონაცემები შენარჩუნებულია.'
            : u.status == 'FAILED'
            ? 'სცადეთ ხელახლა. დამატებითი ინფორმაცია იხილეთ დეტალებში.'
            : 'ახალი ვერსიები ფონურად ჩამოიტვირთება. დაყენებას ყოველთვის თქვენ ადასტურებთ.';
        final diagnostics = u.connectionIssue ?? u.state['reason'] as String?;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const PosText(
              'პროგრამის განახლება',
              style: TextStyle(
                fontSize: 15,
                color: AdminDesign.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  failed
                      ? Icons.cloud_off_outlined
                      : u.hasStagedUpdate
                      ? Icons.download_done_rounded
                      : Icons.update_rounded,
                  color: failed ? AdminDesign.warning : AdminDesign.accentDark,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PosText(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AdminDesign.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PosText(
              detail,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AdminDesign.muted,
              ),
            ),
            if (u.visibleInstallStage != null) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AdminDesign.panelSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Wrap(
                spacing: 32,
                runSpacing: 12,
                children: [
                  _VersionValue(
                    label: 'დაყენებული ვერსია',
                    value: u.currentVersion.isEmpty ? '—' : u.currentVersion,
                  ),
                  if ((downloading || u.hasStagedUpdate) &&
                      u.version.isNotEmpty)
                    _VersionValue(label: 'ახალი ვერსია', value: u.version),
                ],
              ),
            ),
            if (u.lastUpdateRolledBack && u.status != 'ROLLED_BACK') ...[
              const SizedBox(height: 12),
              const PosText(
                'ბოლო განახლება ვერ დასრულდა — წინა ვერსია აღდგენილია.',
                style: TextStyle(color: AdminDesign.warning, height: 1.5),
              ),
            ],
            if (downloading && !offline) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                color: AdminDesign.accentDark,
                backgroundColor: AdminDesign.accentSoft,
                value: (u.state['total'] as num? ?? 0) > 0
                    ? ((u.state['downloaded'] as num? ?? 0) /
                              (u.state['total'] as num))
                          .clamp(0.0, 1.0)
                    : null,
              ),
              const SizedBox(height: 8),
              PosText(
                _downloadProgress(u.state),
                style: const TextStyle(
                  color: AdminDesign.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (diagnostics != null && diagnostics.isNotEmpty && failed)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const PosText(
                  'დეტალები',
                  style: TextStyle(fontSize: 13),
                ),
                children: [
                  SelectableText(
                    diagnostics,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminDesign.muted,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (u.hasStagedUpdate)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminDesign.accentDark,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: u.inputHeld || u.preparingInstall
                        ? null
                        : () => unawaited(u.installNow()),
                    icon: u.preparingInstall
                        ? const _UpdateSpinner()
                        : const Icon(Icons.restart_alt, size: 18),
                    label: const PosText('განახლება ახლა'),
                  ),
                if (u.configured && !u.hasStagedUpdate && !u.inputHeld)
                  OutlinedButton.icon(
                    onPressed: busy || (downloading && !offline)
                        ? null
                        : () => unawaited(u.check()),
                    icon: busy
                        ? const _UpdateSpinner()
                        : const Icon(Icons.refresh, size: 18),
                    label: PosText(
                      busy
                          ? 'მოწმდება…'
                          : failed
                          ? 'ხელახლა შემოწმება'
                          : 'შემოწმება',
                    ),
                  ),
                if (onLater != null)
                  TextButton(
                    onPressed: u.installing || u.preparingInstall
                        ? null
                        : () => unawaited(onLater!()),
                    child: const PosText('მოგვიანებით'),
                  ),
              ],
            ),
          ],
        );
        if (embedded) return content;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AdminDesign.panel,
            border: Border.all(color: AdminDesign.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(color: Colors.transparent, child: content),
        );
      },
    );
  }
}

class _VersionValue extends StatelessWidget {
  const _VersionValue({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      PosText(
        label,
        style: const TextStyle(fontSize: 12, color: AdminDesign.muted),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AdminDesign.text,
        ),
      ),
    ],
  );
}

class _UpdateSpinner extends StatelessWidget {
  const _UpdateSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

String _downloadProgress(Map<String, dynamic> state) {
  final downloaded = (state['downloaded'] as num? ?? 0).clamp(
    0,
    double.infinity,
  );
  final total = state['total'] as num? ?? 0;
  final received = (downloaded / (1024 * 1024)).toStringAsFixed(1);
  if (total <= 0) return '$received MB';
  final percent = (downloaded / total * 100).clamp(0, 100).toStringAsFixed(0);
  return '$percent% · $received / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    if (!u.hasStagedUpdate ||
        u.version == offered ||
        u.version == u.deferredVersion ||
        u.inputHeld)
      return;
    offered = u.version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = widget.navigatorKey.currentContext;
      if (context == null || !mounted) return;
      unawaited(showPosUpdateDialog(context, updater: u, offer: true));
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ExcludeFocus(
        excluding: u.blockingOverlay,
        child: AbsorbPointer(absorbing: u.blockingOverlay, child: widget.child),
      ),
      if (u.blockingOverlay)
        Positioned.fill(
          child: Material(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (u.startupFailure == null)
                    const CircularProgressIndicator()
                  else
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 36,
                    ),
                  const SizedBox(height: 20),
                  PosText(
                    u.probation
                        ? (u.startupFailure == null
                              ? u.startupStage
                              : 'პროგრამის გაშვება ვერ დასრულდა')
                        : u.visibleInstallStage ?? updateLabels['INSTALLING']!,
                    style: const TextStyle(color: Colors.white),
                  ),

                  if (u.probation) ...[
                    const SizedBox(height: 12),
                    PosText(
                      '${u.startupSeconds} წმ',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (u.startupFailure != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        child: SelectableText(
                          u.startupFailure!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: () => unawaited(u.retryStartupCheck()),
                        child: const PosText('ხელახლა შემოწმება'),
                      ),
                      const PosText(
                        'თუ პრობლემა გრძელდება, გახსენით Vynic Setup და აირჩიეთ აღდგენა.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
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
