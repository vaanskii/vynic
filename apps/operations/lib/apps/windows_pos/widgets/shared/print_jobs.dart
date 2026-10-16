import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_responsive.dart';
import 'package:vynic/core/ui/widgets/vynic_responsive_dialog.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

String _t(BuildContext context, String ka, String en) =>
    PosLocale.code(context) == 'en' ? en : ka;

String printJobStateLabel(BuildContext context, PrintJobState state) =>
    switch (state) {
      PrintJobState.queued => _t(context, 'რიგშია', 'Queued'),
      PrintJobState.reprint => _t(context, 'ასლი რიგშია', 'Copy queued'),
      PrintJobState.sending => _t(context, 'იგზავნება', 'Sending'),
      PrintJobState.sent => _t(
        context,
        'გაგზავნილია — ქაღალდი შესამოწმებელია',
        'Sent — check paper',
      ),
      PrintJobState.failed => _t(
        context,
        'არ გაგზავნილა — შეამოწმეთ კავშირი',
        'Not sent — check connection',
      ),
      PrintJobState.uncertain => _t(
        context,
        'შედეგი გაურკვეველია — შეამოწმეთ ქაღალდი',
        'Outcome unknown — check paper',
      ),
      PrintJobState.confirmed => _t(
        context,
        'ქაღალდი ოპერატორმა შეამოწმა',
        'Paper checked by operator',
      ),
    };

class PrintJobsNotice extends StatelessWidget {
  const PrintJobsNotice({super.key, this.onlyAttention = false});
  final bool onlyAttention;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: PrintJobRepository.changes,
    builder: (context, _, __) {
      List<PrintJob> jobs;
      String? error = PrintJobRepository.failure;
      try {
        jobs = PrintJobRepository.all();
      } catch (e) {
        jobs = [];
        error = e.toString();
      }
      final count = jobs.where((j) => j.needsAttention).length;
      if (onlyAttention && count == 0 && error == null && jobs.isEmpty)
        return const SizedBox.shrink();
      final label = error != null
          ? _t(
              context,
              'ბეჭდვის სია ვერ ჩაიტვირთა — საჭიროა შემოწმება',
              'Print jobs unavailable — review required',
            )
          : count > 0
          ? _t(
              context,
              '$count ბეჭდვა შესამოწმებელია',
              '$count print jobs need review',
            )
          : _t(context, 'ბეჭდვის სია', 'Print jobs');
      return Material(
        color: count > 0 || error != null
            ? VynicColors.warning.withValues(alpha: 0.12)
            : Colors.transparent,
        child: SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            key: const ValueKey('print-jobs-open'),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: VynicColors.textPrimary,
            ),
            onPressed: () => showPosModal<void>(
              context: context,
              builder: (_) => const PrintJobsDialog(),
            ),
            icon: Icon(
              count > 0 || error != null
                  ? Icons.print_disabled_outlined
                  : Icons.print_outlined,
            ),
            label: Text(label, textAlign: TextAlign.center),
          ),
        ),
      );
    },
  );
}

class PrintJobsDialog extends StatelessWidget {
  const PrintJobsDialog({super.key});
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: VynicColors.card,
    child: SizedBox(
      width: VynicResponsive.dialogWidth(context),
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _t(context, 'ბეჭდვის სია', 'Print jobs'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: _t(context, 'დახურვა', 'Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _t(
                context,
                'გაგზავნა ქაღალდის გამოსვლას არ ადასტურებს. გაურკვეველი ჩეკი ავტომატურად აღარ იგზავნება.',
                'Sending does not confirm paper output. An uncertain ticket is never sent again automatically.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: PrintJobRepository.changes,
              builder: (context, _, __) {
                try {
                  final failure = PrintJobRepository.failure;
                  if (failure != null) return _error(context, failure);
                  final jobs = PrintJobRepository.all().reversed.toList();
                  jobs.sort(
                    (a, b) => (a.needsAttention ? 0 : 1).compareTo(
                      b.needsAttention ? 0 : 1,
                    ),
                  );
                  if (jobs.isEmpty)
                    return Center(
                      child: Text(
                        _t(
                          context,
                          'ბეჭდვის ჩანაწერები ჯერ არ არის',
                          'No print jobs yet',
                        ),
                      ),
                    );
                  return ValueListenableBuilder(
                    valueListenable: PosSession.activeUser,
                    builder: (context, _, __) => ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: jobs.length,
                      separatorBuilder: (_, __) => const Divider(height: 24),
                      itemBuilder: (context, index) =>
                          _job(context, jobs[index]),
                    ),
                  );
                } catch (e) {
                  return _error(context, e.toString());
                }
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _error(BuildContext context, String error) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        Text(
          _t(
            context,
            'ბეჭდვა შეჩერებულია. საჭიროა ჩანაწერის შემოწმება.',
            'Printing is stopped. The journal needs review.',
          ),
        ),
        ExpansionTile(
          title: Text(_t(context, 'დეტალები', 'Details')),
          children: [SelectableText(error)],
        ),
      ],
    ),
  );

  Widget _job(BuildContext context, PrintJob job) {
    final target = switch (job.target) {
      PrintQueueTarget.kitchen => _t(context, 'სამზარეულო', 'Kitchen'),
      PrintQueueTarget.receipt => _t(context, 'ჩეკი', 'Receipt'),
      PrintQueueTarget.bar => _t(context, 'ბარი', 'Bar'),
      PrintQueueTarget.additional => _t(
        context,
        'დამატებითი პრინტერი',
        'Additional printer',
      ),
    };
    final allowed = PrintReconciliation.allowed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$target · ${job.label.split(' / ').last}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          printJobStateLabel(context, job.state),
          style: TextStyle(
            color: job.needsAttention
                ? VynicColors.warning
                : VynicColors.textPrimary,
          ),
        ),
        if (job.state == PrintJobState.sent ||
            job.state == PrintJobState.uncertain ||
            job.state == PrintJobState.confirmed)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (job.state != PrintJobState.confirmed)
                TextButton(
                  key: ValueKey('print-confirm-${job.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: allowed
                      ? () => _act(context, job, 'confirm')
                      : null,
                  child: Text(
                    _t(context, 'ქაღალდი შევამოწმე', 'Paper checked'),
                  ),
                ),
              OutlinedButton(
                key: ValueKey('print-reprint-${job.id}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed:
                    (job.target != PrintQueueTarget.receipt
                        ? PrintReconciliation.kitchenCopyAllowed
                        : allowed)
                    ? () => _act(context, job, 'reprint')
                    : null,
                child: Text(_t(context, 'მონიშნული ასლი', 'Labeled copy')),
              ),
            ],
          ),
        if (job.state == PrintJobState.failed)
          OutlinedButton(
            key: ValueKey('print-retry-${job.id}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: allowed ? () => _act(context, job, 'retry') : null,
            child: Text(
              _t(
                context,
                'კავშირი აღდგა — ხელახლა გაგზავნა',
                'Connection restored — retry',
              ),
            ),
          ),
        if (!allowed && !job.ready && job.state != PrintJobState.sending)
          Text(
            _t(
              context,
              PrintReconciliation.policy ==
                      PrintReconciliationPolicy.unconfigured
                  ? 'შემოწმების უფლების პოლიტიკა ჯერ დასადგენია.'
                  : 'მიმართეთ უფლებამოსილ ოპერატორს.',
              PrintReconciliation.policy ==
                      PrintReconciliationPolicy.unconfigured
                  ? 'Operator reconciliation policy is not configured.'
                  : 'Ask an authorized operator.',
            ),
          ),
        ExpansionTile(
          title: Text(
            _t(context, 'ისტორია და დეტალები', 'History and details'),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                '${job.id}\n${job.destination.display}\n${job.createdAt}',
              ),
            ),
            if (job.detail != null) SelectableText(job.detail!),
            for (final attempt in job.attempts)
              if (attempt['beep'] != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_t(context, 'ხმოვანი სიგნალი', 'Optional sound')} · '
                    '${attempt['id']} · ${switch (attempt['beep']['state']) {
                      'reserved' || 'uncertain' => _t(context, 'შედეგი უცნობია — არ მეორდება', 'Outcome unknown — no replay'),
                      'submitted' => _t(context, 'გაგზავნილია', 'Submitted'),
                      'notSent' => _t(context, 'არ გაგზავნილა', 'Not sent'),
                      _ => _t(context, 'ვერ შესრულდა', 'Failed'),
                    }} '
                    '${attempt['beep']['detail'] ?? ''}',
                  ),
                ),
            if (PrintJobRepository.optionalSignalFailure != null)
              SelectableText(PrintJobRepository.optionalSignalFailure!),
            for (final event in job.audit)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${event['at']} · ${event['action']} ${event['actorId'] ?? ''} ${event['reason'] ?? ''}',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _act(BuildContext context, PrintJob job, String action) =>
      showPosModal<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PrintActionDialog(
          job: job,
          action: action,
          simpleKitchen:
              action == 'reprint' && job.target != PrintQueueTarget.receipt,
        ),
      );
}

Future<String?> requestLabeledPrintCopyReason(BuildContext context) =>
    showPosModal<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PrintActionDialog(action: 'copy'),
    );

class KitchenCopyRequest {
  const KitchenCopyRequest(this.id);
  final String id;
  String get reason => PrintReconciliation.kitchenCopyReason;
}

Future<KitchenCopyRequest?> requestKitchenPrintCopy(BuildContext context) =>
    showPosModal<KitchenCopyRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const _PrintActionDialog(action: 'kitchenCopy', simpleKitchen: true),
    );

class _PrintActionDialog extends StatefulWidget {
  const _PrintActionDialog({
    this.job,
    required this.action,
    this.simpleKitchen = false,
  });
  final PrintJob? job;
  final String action;
  final bool simpleKitchen;
  @override
  State<_PrintActionDialog> createState() => _PrintActionState();
}

class _PrintActionState extends State<_PrintActionDialog> {
  final reason = TextEditingController();
  final requestId = const Uuid().v4();
  bool busy = false;
  String? error;
  bool get allowed => widget.simpleKitchen
      ? PrintReconciliation.kitchenCopyAllowed
      : PrintReconciliation.allowed;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VynicResponsiveDialog(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.simpleKitchen)
            Text(switch (widget.job?.target) {
              PrintQueueTarget.bar => 'ბარის ჩეკი',
              PrintQueueTarget.additional => 'დამატებითი პრინტერის ჩეკი',
              _ => 'სამზარეულოს ჩეკი',
            }, style: Theme.of(context).textTheme.titleLarge)
          else
            Text(
              _t(
                context,
                widget.action == 'confirm'
                    ? 'ქაღალდის შემოწმება'
                    : widget.action == 'retry'
                    ? 'ხელახლა გაგზავნა'
                    : 'მონიშნული ასლი',
                widget.action == 'confirm'
                    ? 'Confirm paper check'
                    : widget.action == 'retry'
                    ? 'Retry delivery'
                    : 'Labeled reprint',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          const SizedBox(height: 12),
          if (!widget.simpleKitchen)
            Text(
              _t(
                context,
                (widget.action == 'reprint' || widget.action == 'copy')
                    ? 'შეამოწმეთ, ხომ არ დაიბეჭდა პირველი ჩეკი. ახალი ასლი მონიშნული იქნება REPRINT-ით; ნუ მოამზადებთ კერძს ორჯერ.'
                    : widget.action == 'confirm'
                    ? 'დაადასტურეთ მხოლოდ ქაღალდისა და ჩეკის ნომრის შემოწმების შემდეგ.'
                    : 'წინა მცდელობას მონაცემები არ გაუგზავნია. შეამოწმეთ კავშირი და იგივე ჩეკი გაგზავნეთ.',
                (widget.action == 'reprint' || widget.action == 'copy')
                    ? 'Check whether the original printed. The new copy is labeled REPRINT; avoid preparing the meal twice.'
                    : widget.action == 'confirm'
                    ? 'Confirm only after checking the paper and ticket number.'
                    : 'The previous attempt wrote no bytes. Check the connection before retrying the same ticket.',
              ),
            ),
          if (!widget.simpleKitchen && !allowed)
            Text(
              _t(
                context,
                'შემოწმების უფლების პოლიტიკა ჯერ დასადგენია ან მიმართეთ უფლებამოსილ ოპერატორს.',
                'Reconciliation policy must be configured; ask an authorized operator.',
              ),
            ),
          const SizedBox(height: 16),
          if (!widget.simpleKitchen)
            PosOnScreenTextField(
              controller: reason,
              maxLines: 3,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: _t(
                  context,
                  'მიზეზი / შემოწმების შედეგი',
                  'Reason / check result',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: TextStyle(color: VynicColors.danger)),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: Text(
                  widget.simpleKitchen
                      ? 'გაუქმება'
                      : _t(context, 'გაუქმება', 'Cancel'),
                ),
              ),
              FilledButton(
                key: const ValueKey('print-action-submit'),
                onPressed: busy || !allowed ? null : _submit,
                child: Text(
                  widget.simpleKitchen
                      ? 'გაშვება'
                      : _t(
                          context,
                          busy ? 'ინახება...' : 'დადასტურება',
                          busy ? 'Saving...' : 'Confirm',
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _submit() async {
    if (busy) return;
    if (!widget.simpleKitchen &&
        (reason.text.trim().length < 3 || reason.text.length > 500)) {
      setState(
        () => error = _t(
          context,
          'მიუთითეთ მიზეზი (3–500 სიმბოლო)',
          'Enter a reason (3–500 characters)',
        ),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.action == 'kitchenCopy') {
        PrintReconciliation.authorizeKitchenCopy();
        if (mounted) Navigator.pop(context, KitchenCopyRequest(requestId));
        return;
      }
      if (widget.action == 'copy') {
        PrintReconciliation.authorizeCopy(reason.text);
        if (mounted) Navigator.pop(context, reason.text.trim());
        return;
      }
      if (widget.action == 'confirm')
        await PrintReconciliation.confirm(widget.job!, reason.text, requestId);
      else if (widget.action == 'retry')
        await PrintReconciliation.retryNotSent(
          widget.job!,
          reason.text,
          requestId,
        );
      else
        await PrintReconciliation.reprint(
          widget.job!,
          widget.simpleKitchen
              ? PrintReconciliation.productionCopyReason(widget.job!.target)
              : reason.text,
          requestId,
        );
      if (mounted) Navigator.pop(context);
    } catch (e, stack) {
      developer.log('Print reconciliation failed', error: e, stackTrace: stack);
      if (mounted)
        setState(() {
          busy = false;
          error = _t(
            context,
            'ქმედება ვერ დასრულდა — განაახლეთ ბეჭდვის სია.',
            'Action failed — refresh the print jobs list.',
          );
        });
    }
  }
}
