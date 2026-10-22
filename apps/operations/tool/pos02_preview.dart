import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/print_jobs.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import '../test/support/pos02_preview_harness.dart';

Future<void> main() async {
  if (!kDebugMode || !(Platform.isMacOS || Platform.isWindows)) {
    throw UnsupportedError(
      'POS02 preview requires macOS or Windows debug mode',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('POS02_TEST_PRINTER_HOST');
  final session = await Pos02PreviewSession.open(
    transport: PreviewTransport(
      physicalHost: endpoint.isEmpty ? null : endpoint,
    ),
  );
  debugPrint(
    'POS02 SYNTHETIC PREVIEW data=${session.directory.path}; HTTP blocked; no startup print',
  );
  runApp(Pos02PreviewApp(session: session));
}

class Pos02PreviewApp extends StatelessWidget {
  const Pos02PreviewApp({super.key, required this.session});
  final Pos02PreviewSession session;
  @override
  Widget build(BuildContext context) => PosLocale(
    language: 'en',
    child: MaterialApp(
      title: 'Vynic POS02 — synthetic preview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'NotoSansGeorgian',
      ),
      home: _PreviewScreen(session: session),
    ),
  );
}

class _PreviewScreen extends StatefulWidget {
  const _PreviewScreen({required this.session});
  final Pos02PreviewSession session;
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  bool busy = false;
  String status =
      'Ready. No print jobs exist. Physical printers are disconnected from this preview.';
  PrintQueueTarget target = PrintQueueTarget.kitchen;

  Future<void> _send({bool physical = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      DateTime? approvedAt;
      if (physical) {
        var decided = false;
        approvedAt = await showDialog<DateTime>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('One physical TEST page'),
            content: Text(
              'Target: ${widget.session.transport.physicalHost}:9100\n\nOnly continue if this exact device/model and the current safe window have been approved. This sends one labeled synthetic page. It does not test power/cable/paper interruption or confirm paper output.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (decided) return;
                  decided = true;
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (decided) return;
                  decided = true;
                  Navigator.pop(context, DateTime.now());
                },
                child: const Text('Approved now — one TEST page'),
              ),
            ],
          ),
        );
        if (approvedAt == null || !mounted) return;
      }
      setState(() {
        status = 'Rendering and admitting one labeled synthetic job…';
      });
      final job = await widget.session.sendSample(
        target,
        physical: physical,
        currentWindowApproved: physical,
        approvedAt: approvedAt,
      );
      if (mounted)
        setState(
          () => status =
              '${physical ? 'Physical TCP attempt' : 'SIMULATED transport'}: ${printJobStateLabel(context, job.state)}\nJob: ${job.id}\nPhysical paper is not confirmed.',
        );
    } catch (error) {
      if (mounted) setState(() => status = 'Test action failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('POS02 • SYNTHETIC TEST PREVIEW')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fresh test data. HTTP blocked. Fake printer by default.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'This is the POS02 print/journal preparation harness. Production data, enrollment, sync and updater startup are not opened. Reconciliation stays read-only until the owner policy is chosen.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Synthetic data directory:\n${widget.session.directory.path}',
              ),
              const SizedBox(height: 24),
              DropdownButton<PrintQueueTarget>(
                value: target,
                onChanged: busy
                    ? null
                    : (value) => setState(() => target = value!),
                items: const [
                  DropdownMenuItem(
                    value: PrintQueueTarget.kitchen,
                    child: Text('სამზარეულო / Kitchen sample'),
                  ),
                  DropdownMenuItem(
                    value: PrintQueueTarget.receipt,
                    child: Text('ქვითარი / Receipt sample'),
                  ),
                ],
              ),
              DropdownButton<PreviewOutcome>(
                value: widget.session.transport.outcome,
                onChanged: busy
                    ? null
                    : (value) => setState(
                        () => widget.session.transport.outcome = value!,
                      ),
                items: const [
                  DropdownMenuItem(
                    value: PreviewOutcome.sent,
                    child: Text('Fake TCP sent'),
                  ),
                  DropdownMenuItem(
                    value: PreviewOutcome.connectionFailure,
                    child: Text('Fake no-byte connection failure'),
                  ),
                  DropdownMenuItem(
                    value: PreviewOutcome.partialWrite,
                    child: Text('Fake partial-write uncertainty'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('preview-simulate'),
                    onPressed: busy ? null : () => _send(),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Simulate one TEST job'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('preview-physical'),
                    onPressed:
                        busy || widget.session.transport.physicalHost == null
                        ? null
                        : () => _send(physical: true),
                    child: const Text('Physical TEST page — explicit opt-in'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.session.transport.physicalHost == null
                    ? 'No physical endpoint is configured. No live printer can be reached.'
                    : 'Opt-in endpoint ${widget.session.transport.physicalHost}:9100 requires current approval for each single TEST job.',
              ),
              const SizedBox(height: 24),
              SelectableText(status),
              const SizedBox(height: 16),
              const PrintJobsNotice(),
              const SizedBox(height: 12),
              const Text(
                'TEST / DO NOT PREPARE. Simulated “sent” proves no paper output. Close and relaunch to get another fresh isolated directory.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
