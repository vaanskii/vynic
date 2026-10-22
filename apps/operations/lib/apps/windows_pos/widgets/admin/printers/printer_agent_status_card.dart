import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/services/printing/printer_agent_profile.dart';
import 'package:vynic/core/services/printing/printer_agent_runtime_profile.dart';
import 'package:vynic/core/services/security/developer_access.dart';

/// Manual, read-only inspection of an explicitly configured local agent.
/// The default source is the real pinned mTLS factory, with no startup probe.
/// This widget has no job, service-installation or physical activation API.
class PrinterAgentStatusCard extends StatefulWidget {
  const PrinterAgentStatusCard({
    super.key,
    this.source = const PrinterAgentRuntimeProfile(),
  });
  final PrinterAgentRuntimeHealthSource source;

  @override
  State<PrinterAgentStatusCard> createState() => _PrinterAgentStatusCardState();
}

class _PrinterAgentStatusCardState extends State<PrinterAgentStatusCard> {
  PrinterAgentHealth? _health;
  PrinterAgentRuntimeBinding? _observedBinding;
  DateTime? _checkedAt;
  Object? _failure;
  bool _checking = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    DeveloperAccess.unlocked.addListener(_scopeChanged);
  }

  @override
  void didUpdateWidget(PrinterAgentStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.source, oldWidget.source)) {
      _generation++;
      _health = null;
      _observedBinding = null;
      _checkedAt = null;
      _failure = null;
      _checking = false;
    }
  }

  void _scopeChanged() {
    if (mounted && !DeveloperAccess.can(DeveloperScope.printers)) {
      _generation++;
      setState(() {
        _health = null;
        _observedBinding = null;
        _checkedAt = null;
        _failure = null;
        _checking = false;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    DeveloperAccess.unlocked.removeListener(_scopeChanged);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_checking ||
        !widget.source.isConfigured ||
        !DeveloperAccess.can(DeveloperScope.printers)) {
      return;
    }
    final generation = ++_generation;
    try {
      if (!DeveloperAccess.can(DeveloperScope.printers)) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.scopeDenied,
        );
      }
      final source = widget.source;
      final captured = source.currentBinding;
      captured.requireUsable();
      setState(() {
        _checking = true;
        _health = null;
        _observedBinding = null;
        _checkedAt = null;
        _failure = null;
      });
      final health = await source.health();
      if (!mounted || generation != _generation) return;
      if (!DeveloperAccess.can(DeveloperScope.printers)) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.scopeDenied,
        );
      }
      final current = source.currentBinding;
      current.requirePins(health.pins);
      captured.requirePins(health.pins);
      if (!captured.sameEnrollment(current)) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.bindingMismatch,
        );
      }
      setState(() {
        _health = health;
        _observedBinding = captured;
        _checkedAt = DateTime.now();
        _checking = false;
      });
    } catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure =
            failure is PrinterAgentException ||
                failure is PrinterAgentRuntimeException
            ? failure
            : const PrinterAgentException(PrinterAgentFailure.unavailable);
        _health = null;
        _observedBinding = null;
        _checkedAt = null;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DeveloperAccess.unlocked,
      builder: (context, _, _) {
        if (!DeveloperAccess.can(DeveloperScope.printers)) {
          return const SizedBox.shrink();
        }
        var health = _health;
        var failure = _failure;
        if (health != null) {
          try {
            final observed = _observedBinding!;
            final current = widget.source.currentBinding;
            current.requirePins(health.pins);
            observed.requirePins(health.pins);
            if (!current.sameEnrollment(observed)) {
              throw const PrinterAgentRuntimeException(
                PrinterAgentRuntimeFailure.bindingMismatch,
              );
            }
          } catch (error) {
            health = null;
            failure = error is PrinterAgentRuntimeException
                ? error
                : const PrinterAgentException(PrinterAgentFailure.unavailable);
          }
        }
        final configured = widget.source.isConfigured;
        return Container(
          key: const ValueKey('printer-agent-status-card'),
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AdminDesign.panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = Row(
                    children: [
                      const Icon(
                        Icons.dns_outlined,
                        color: AdminDesign.accentDark,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'ბეჭდვის აგენტი',
                          style: TextStyle(
                            color: AdminDesign.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  );
                  if (!configured) return title;
                  final refresh = OutlinedButton.icon(
                    key: const ValueKey('printer-agent-refresh'),
                    onPressed: _checking ? null : _refresh,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_checking ? 'მოწმდება…' : 'სტატუსის შემოწმება'),
                    style: AdminDesign.outlineButtonStyle(),
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 12), refresh],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      refresh,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              if (!configured)
                _message(
                  'ახალი აგენტის პროფილი ჯერ არ არის მითითებული.',
                  AdminTones.neutral,
                )
              else if (_checking)
                _message('აგენტის სტატუსი მოწმდება.', AdminTones.info)
              else if (failure != null)
                _message(_failureMessage(failure), AdminTones.warning)
              else if (health == null)
                _message('სტატუსი ჯერ არ შემოწმებულა.', AdminTones.neutral)
              else ...[
                Text(
                  'ბოლო შემოწმების შედეგი · ${_time(_checkedAt!)}',
                  key: const ValueKey('printer-agent-checked-at'),
                  style: const TextStyle(
                    color: AdminDesign.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _badge(
                      _lifecycle(health),
                      health.softwareReady
                          ? AdminTones.success
                          : AdminTones.warning,
                    ),
                    _badge(
                      health.configuredScope == PrinterAgentScope.local
                          ? 'ადგილობრივი რიგი'
                          : 'რესტორნის საერთო რიგი',
                      AdminTones.neutral,
                    ),
                    _badge('ფიზიკური ბეჭდვა შეჩერებულია', AdminTones.warning),
                  ],
                ),
                const SizedBox(height: 10),
                _message(
                  'სერვისის მომზადება და მოწყობილობის მიბმა '
                  'ჯერ დასადასტურებელია. ახალი რიგიდან ბეჭდვა არ გააქტიურებულა.',
                  AdminTones.info,
                ),
                if (health.printerHolds.isNotEmpty ||
                    health.holdReasons.contains(
                      PrinterAgentHoldReason.retainedQueueHold,
                    )) ...[
                  const SizedBox(height: 10),
                  _message(
                    'რიგში ბეჭდვის შედეგი შესამოწმებელია'
                    '${health.printerHolds.isEmpty ? '.' : ': ${health.printerHolds.length} პრინტერი.'} '
                    'გაურკვეველი ბეჭდვა ავტომატურად არ გადაიგზავნება.',
                    AdminTones.warning,
                  ),
                ],
                if (health.activeAdmissions > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'მიმდინარე მოთხოვნა: ${health.activeAdmissions}',
                    style: const TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              const Text(
                'მიმდინარე პრინტერების მუშაობა უცვლელია. '
                'სტატუსის შემოწმება არაფერს ბეჭდავს.',
                style: TextStyle(color: AdminDesign.muted, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _message(String text, AdminTone tone) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: tone.fill,
      border: Border.all(color: tone.border),
      borderRadius: BorderRadius.circular(AdminDesign.radius),
    ),
    child: Text(text, style: TextStyle(color: tone.text, fontSize: 13)),
  );

  Widget _badge(String text, AdminTone tone) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: tone.fill,
      border: Border.all(color: tone.border),
      borderRadius: BorderRadius.circular(AdminDesign.radius),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: tone.text,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String _lifecycle(PrinterAgentHealth health) => switch (health.state) {
    PrinterAgentLifecycle.newHost => 'სერვისი მომზადებულია',
    PrinterAgentLifecycle.starting => 'სერვისი იწყება',
    PrinterAgentLifecycle.running =>
      health.softwareReady ? 'აგენტი ხელმისაწვდომია' : 'სერვისი შესამოწმებელია',
    PrinterAgentLifecycle.draining => 'სერვისი ასრულებს მიმდინარე მოთხოვნებს',
    PrinterAgentLifecycle.stopped => 'სერვისი შეჩერებულია',
    PrinterAgentLifecycle.held => 'სერვისი მოლოდინშია',
  };

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';

  String _failureMessage(Object failure) {
    if (failure is PrinterAgentRuntimeException) {
      return switch (failure.reason) {
        PrinterAgentRuntimeFailure.notConfigured =>
          'ახალი აგენტის პროფილი ჯერ არ არის მითითებული.',
        PrinterAgentRuntimeFailure.invalidProfile =>
          'აგენტის პროფილი ან სერტიფიკატის მიბმა შესამოწმებელია.',
        PrinterAgentRuntimeFailure.profileUnavailable =>
          'აგენტის პროფილი ან სერტიფიკატის ფაილი ვერ იკითხება.',
        PrinterAgentRuntimeFailure.missingDevice =>
          'შემოწმებისთვის მოწყობილობის რეგისტრაცია აკლია.',
        PrinterAgentRuntimeFailure.missingVenue =>
          'შემოწმებისთვის რესტორნის იდენტობა აკლია.',
        PrinterAgentRuntimeFailure.missingInstallation =>
          'შემოწმებისთვის ამ ინსტალაციის იდენტობა აკლია.',
        PrinterAgentRuntimeFailure.identityChanging =>
          'მოწყობილობის იდენტობა იცვლება; შემოწმება შეჩერებულია.',
        PrinterAgentRuntimeFailure.restorationHeld =>
          'აღდგენილი მონაცემების მიბმა ჯერ დასადასტურებელია.',
        PrinterAgentRuntimeFailure.bindingMismatch =>
          'აგენტის პროფილი ამ მოწყობილობას ან რესტორანს არ ემთხვევა.',
        PrinterAgentRuntimeFailure.profileChanged =>
          'აგენტის პროფილი შეიცვალა; სტატუსი ხელახლა შეამოწმეთ.',
        PrinterAgentRuntimeFailure.scopeDenied =>
          'შემოწმებისთვის პრინტერების ტექნიკური წვდომაა საჭირო.',
      };
    }
    final reason = (failure as PrinterAgentException).reason;
    return switch (reason) {
      PrinterAgentFailure.invalidProfile =>
        'აგენტის პროფილი ან სერტიფიკატის მიბმა შესამოწმებელია.',
      PrinterAgentFailure.authentication =>
        'აგენტის უსაფრთხო კავშირი ვერ დასტურდება.',
      PrinterAgentFailure.unavailable =>
        'აგენტი ვერ უკავშირდება; გადაამოწმეთ ადგილობრივი სერვისი.',
      PrinterAgentFailure.profileMismatch =>
        'აგენტის იდენტობა ან კონფიგურაციის ვერსია არ ემთხვევა პროფილს.',
      PrinterAgentFailure.provisioningHeld =>
        'აგენტის მომზადება ჯერ დასადასტურებელია.',
      PrinterAgentFailure.protocolMismatch =>
        'აგენტის პასუხის ვერსია შესამოწმებელია.',
    };
  }
}
