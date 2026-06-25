import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

class AdminAuditLogSection extends StatelessWidget {
  const AdminAuditLogSection({
    super.key,
    required this.selectedAuditYear,
    required this.selectedAuditMonth,
    required this.onChangeAuditMonth,
    required this.onSetSelectedAuditMonth,
  });

  final int selectedAuditYear;
  final int selectedAuditMonth;
  final ValueChanged<int> onChangeAuditMonth;
  final ValueChanged<DateTime> onSetSelectedAuditMonth;

  static const Color _primaryColor = AdminDesign.accentDark;
  static const Color _surface = AdminDesign.panelSoft;
  static const Color _card = AdminDesign.panel;
  static const Color _border = AdminDesign.border;
  static const Color _text = AdminDesign.text;
  static const Color _muted = AdminDesign.muted;

  DateTime _lastActivity(AuditReport report) {
    final events = report.sortedEvents;
    final eventTs = events.isNotEmpty
        ? events.first.timestamp
        : report.openedAt;
    return report.updatedAt.isAfter(eventTs) ? report.updatedAt : eventTs;
  }

  List<AuditReport> _normalizeAuditReports(List<AuditReport> source) {
    final sorted = List<AuditReport>.from(source)
      ..sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
    return sorted;
  }

  int _statusRank(AuditReportStatus status) {
    switch (status) {
      case AuditReportStatus.open:
        return 0;
      case AuditReportStatus.closed:
        return 1;
      case AuditReportStatus.cancelled:
        return 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: DatabaseService.getAuditLogBox().listenable(),
      builder: (context, _, __) {
        final isMobile = MediaQuery.of(context).size.width < 600;

        final reports = _normalizeAuditReports(
          DatabaseService.getAuditReports(),
        );
        final selectedMonthDate = DateTime(
          selectedAuditYear,
          selectedAuditMonth,
        );
        final currentBusinessDate = DatabaseService.getCurrentDate();
        final currentBusinessMonth = DateTime(
          currentBusinessDate.year,
          currentBusinessDate.month,
        );

        final monthOptionsSet = <DateTime>{};
        for (final report in reports) {
          final businessDate = _businessDateForReport(report);
          monthOptionsSet.add(DateTime(businessDate.year, businessDate.month));
        }
        monthOptionsSet.add(currentBusinessMonth);
        monthOptionsSet.add(
          DateTime(selectedMonthDate.year, selectedMonthDate.month),
        );

        final monthOptions = monthOptionsSet.toList()
          ..sort((a, b) => b.compareTo(a));
        final normalizedSelectedMonth = DateTime(
          selectedMonthDate.year,
          selectedMonthDate.month,
        );
        final isNextDisabled = !normalizedSelectedMonth.isBefore(
          currentBusinessMonth,
        );

        final selectedMonthHasData = reports.any((report) {
          final businessDate = _businessDateForReport(report);
          return businessDate.year == selectedMonthDate.year &&
              businessDate.month == selectedMonthDate.month;
        });

        if (!selectedMonthHasData && reports.isNotEmpty) {
          final latestReport = reports.reduce((current, next) {
            final currentDate = _businessDateForReport(current);
            final nextDate = _businessDateForReport(next);
            if (nextDate.isAfter(currentDate)) {
              return next;
            }
            if (nextDate.isBefore(currentDate)) {
              return current;
            }
            return next.updatedAt.isAfter(current.updatedAt) ? next : current;
          });
          final latestMonthDate = _businessDateForReport(latestReport);
          final targetMonth = DateTime(
            latestMonthDate.year,
            latestMonthDate.month,
          );
          if (targetMonth != normalizedSelectedMonth) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) {
                return;
              }
              onSetSelectedAuditMonth(targetMonth);
            });
          }
        }

        final monthReports =
            reports.where((report) {
                final businessDate = _businessDateForReport(report);
                return businessDate.year == selectedMonthDate.year &&
                    businessDate.month == selectedMonthDate.month;
              }).toList()
              ..sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));

        final dayGroups = <String, _AuditDayData>{};
        for (final report in monthReports) {
          final dayDate = _businessDateForReport(report);
          final dayKey = _formatDateIso(dayDate);
          final group = dayGroups.putIfAbsent(
            dayKey,
            () => _AuditDayData(date: dayDate),
          );
          group.reports.add(report);
        }

        final dayEntries = dayGroups.entries.toList()
          ..sort((a, b) => b.value.date.compareTo(a.value.date));

        int countByStatus(List<AuditReport> source, AuditReportStatus status) {
          return source.where((report) => report.status == status).length;
        }

        final monthOpenCount = countByStatus(
          monthReports,
          AuditReportStatus.open,
        );
        final monthClosedCount = countByStatus(
          monthReports,
          AuditReportStatus.closed,
        );
        final monthCancelledCount = countByStatus(
          monthReports,
          AuditReportStatus.cancelled,
        );

        final todayKey = _formatDateIso(currentBusinessDate);
        final isCurrentMonthSelected =
            normalizedSelectedMonth.year == currentBusinessMonth.year &&
            normalizedSelectedMonth.month == currentBusinessMonth.month;

        final todayGroup = isCurrentMonthSelected ? dayGroups[todayKey] : null;
        final todayReports = todayGroup?.reports ?? const <AuditReport>[];

        final filterSubtitle = isCurrentMonthSelected
            ? '${_getGeorgianMonthName(selectedMonthDate.month)} ${selectedMonthDate.year} • პროგრამის თარიღი ${DatabaseService.getGeorgianFormattedDate(currentBusinessDate)}'
            : '${_getGeorgianMonthName(selectedMonthDate.month)} ${selectedMonthDate.year}';

        return SizedBox.expand(
          child: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminSectionHeader(
                      icon: Icons.fact_check_outlined,
                      title: 'აუდიტის კონტროლი',
                      subtitle:
                          'მომხმარებლების მოქმედებები, ცვლილებების დრო და ოპერაციული ისტორია.',
                      badge: AdminStatusBadge(
                        icon: Icons.event_note_outlined,
                        label: '${monthReports.length} ჩანაწერი',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: isMobile
                          ? Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'ფილტრი',
                                            style: TextStyle(
                                              color: _text,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            filterSubtitle,
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<DateTime>(
                                      icon: const Icon(
                                        Icons.calendar_month,
                                        color: _primaryColor,
                                      ),
                                      onSelected: (value) =>
                                          onSetSelectedAuditMonth(value),
                                      itemBuilder: (context) => monthOptions.map((
                                        m,
                                      ) {
                                        return PopupMenuItem(
                                          value: m,
                                          child: Text(
                                            '${_getGeorgianMonthName(m.month)} ${m.year}',
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'ფილტრი',
                                        style: TextStyle(
                                          color: _text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        filterSubtitle,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => onChangeAuditMonth(-1),
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    size: 18,
                                  ),
                                  color: _text,
                                  splashRadius: 18,
                                ),
                                SizedBox(
                                  width: 210,
                                  child: DropdownButtonFormField<DateTime>(
                                    value: monthOptions.firstWhere(
                                      (month) =>
                                          month.year ==
                                              normalizedSelectedMonth.year &&
                                          month.month ==
                                              normalizedSelectedMonth.month,
                                      orElse: () => normalizedSelectedMonth,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                      filled: true,
                                      fillColor: _surface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: _border,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _text,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    iconEnabledColor: _primaryColor,
                                    items: monthOptions.map((monthDate) {
                                      final label =
                                          '${_getGeorgianMonthName(monthDate.month)} ${monthDate.year}';
                                      return DropdownMenuItem<DateTime>(
                                        value: monthDate,
                                        child: Text(label),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        onSetSelectedAuditMonth(value);
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  onPressed: isNextDisabled
                                      ? null
                                      : () => onChangeAuditMonth(1),
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                  ),
                                  color: _text,
                                  splashRadius: 18,
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: isMobile
                              ? (MediaQuery.of(context).size.width - 42) / 2
                              : 120,
                          child: _buildStatTile(
                            'აქტიური',
                            monthOpenCount,
                            const Color(0xFFF59E0B),
                          ),
                        ),
                        SizedBox(
                          width: isMobile
                              ? (MediaQuery.of(context).size.width - 42) / 2
                              : 120,
                          child: _buildStatTile(
                            'დახურული',
                            monthClosedCount,
                            const Color(0xFF10B981),
                          ),
                        ),
                        SizedBox(
                          width: isMobile
                              ? (MediaQuery.of(context).size.width - 42) / 2
                              : 120,
                          child: _buildStatTile(
                            'გაუქმებული',
                            monthCancelledCount,
                            const Color(0xFFEF4444),
                          ),
                        ),
                        SizedBox(
                          width: isMobile
                              ? (MediaQuery.of(context).size.width - 42) / 2
                              : 120,
                          child: _buildStatTile(
                            'სულ',
                            monthReports.length,
                            _primaryColor,
                          ),
                        ),
                        if (isCurrentMonthSelected)
                          SizedBox(
                            width: isMobile ? double.infinity : 120,
                            child: _buildStatTile(
                              'დღევანდელი',
                              todayReports.length,
                              const Color(0xFF7C3AED),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (dayEntries.isEmpty)
                      _buildAuditEmptyState()
                    else
                      Column(
                        children: dayEntries.map((entry) {
                          final dayDate = entry.value.date;
                          final dayReports =
                              List<AuditReport>.from(entry.value.reports)
                                ..sort((a, b) {
                                  final rank = _statusRank(
                                    a.status,
                                  ).compareTo(_statusRank(b.status));
                                  if (rank != 0) {
                                    return rank;
                                  }
                                  return _lastActivity(
                                    b,
                                  ).compareTo(_lastActivity(a));
                                });
                          final georgianDate =
                              DatabaseService.getGeorgianFormattedDate(dayDate);
                          final dayIso = _formatDateIso(dayDate);
                          final dayOpenCount = countByStatus(
                            dayReports,
                            AuditReportStatus.open,
                          );
                          final dayClosedCount = countByStatus(
                            dayReports,
                            AuditReportStatus.closed,
                          );
                          final dayCancelledCount = countByStatus(
                            dayReports,
                            AuditReportStatus.cancelled,
                          );

                          return Card(
                            color: _card,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: _border),
                            ),
                            child: Theme(
                              data: Theme.of(
                                context,
                              ).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 8 : 12,
                                  vertical: 2,
                                ),
                                childrenPadding: EdgeInsets.fromLTRB(
                                  isMobile ? 8 : 12,
                                  0,
                                  isMobile ? 8 : 12,
                                  12,
                                ),
                                iconColor: _primaryColor,
                                collapsedIconColor: _muted,
                                leading: const Icon(
                                  Icons.calendar_month_outlined,
                                  color: _primaryColor,
                                  size: 20,
                                ),
                                title: Text(
                                  georgianDate,
                                  style: const TextStyle(
                                    color: _text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  isMobile
                                      ? 'სულ ${dayReports.length} ქმედება'
                                      : '$dayIso • ${_getGeorgianWeekdayName(dayDate.weekday)} • სულ ${dayReports.length}',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: [
                                    _miniBadge(
                                      'A',
                                      dayOpenCount,
                                      const Color(0xFFF59E0B),
                                    ),
                                    _miniBadge(
                                      'D',
                                      dayClosedCount,
                                      const Color(0xFF10B981),
                                    ),
                                    _miniBadge(
                                      'G',
                                      dayCancelledCount,
                                      const Color(0xFFEF4444),
                                    ),
                                  ],
                                ),
                                children: [
                                  for (var i = 0; i < dayReports.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == dayReports.length - 1
                                            ? 0
                                            : 8,
                                      ),
                                      child: _buildAuditReportCard(
                                        context,
                                        dayReports[i],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatTile(String label, int value, Color color) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label:$value',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAuditReportCard(BuildContext context, AuditReport report) {
    final statusLabel = _auditStatusLabel(report.status);
    final statusColor = _auditStatusColor(report.status);
    final openedAt = _formatAuditTimestamp(report.openedAt);
    final closedAt = report.closedAt != null
        ? _formatAuditTimestamp(report.closedAt!)
        : 'აქტიური';
    final events = report.sortedEvents;
    final lastEvent = events.isNotEmpty ? events.first : null;
    final lastUpdated = lastEvent?.timestamp ?? report.updatedAt;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'სუფრა: ${report.tableNumbers.isEmpty ? 'TA-${report.orderId}' : report.tableNumbers.join(', ')}',
                    style: const TextStyle(
                      color: _text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Order #${report.orderId}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metaChip('გახსნა', '${report.openedByName} • $openedAt'),
                _metaChip('ბოლო ქმედება', _formatAuditTimestamp(lastUpdated)),
                _metaChip('დასრულება', closedAt),
                if (report.closedByName != null &&
                    report.closedByName!.isNotEmpty)
                  _metaChip('დახურა', report.closedByName!),
                _metaChip('მოქმედებები', '${events.length}'),
                if (lastEvent != null)
                  _metaChip(
                    'ბოლო ცვლილება',
                    '${_auditEventLabel(lastEvent.type)} • ${lastEvent.waiterName}',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showAuditReportDetails(context, report),
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: const Text('დეტალურად ნახვა'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBFDBFE),
                  foregroundColor: _text,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: _muted),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700, color: _text),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.security_outlined, size: 36, color: _muted),
          SizedBox(height: 8),
          Text(
            'ამ პერიოდში აუდიტის ჩანაწერები არ არის',
            style: TextStyle(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'როგორც კი ოფიციანტები იმუშავებენ შეკვეთებზე, ისტორია აქ გამოჩნდება.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _showAuditReportDetails(
    BuildContext context,
    AuditReport report,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (context) {
        final isMobile = MediaQuery.of(context).size.width < 600;
        final events = report.sortedEvents;
        return Dialog(
          insetPadding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 20)
              : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 780,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 12 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMobile
                                  ? 'Audit #${report.orderId}'
                                  : 'Audit Report • Order #${report.orderId}',
                              style: TextStyle(
                                color: _text,
                                fontSize: isMobile ? 16 : 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'სუფრა: ${report.tableNumbers.isEmpty ? 'TA-${report.orderId}' : report.tableNumbers.join(', ')}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: _muted, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaChip(
                        'Opened by',
                        '${report.openedByName} (${report.openedById})',
                      ),
                      _metaChip(
                        'Opened at',
                        _formatAuditTimestamp(report.openedAt),
                      ),
                      if (report.closedAt != null)
                        _metaChip(
                          'Closed at',
                          _formatAuditTimestamp(report.closedAt!),
                        ),
                      if (report.closedByName != null &&
                          report.closedByName!.isNotEmpty)
                        _metaChip(
                          'Closed by',
                          '${report.closedByName!} (${report.closedById ?? '-'})',
                        ),
                      _metaChip('Status', _auditStatusLabel(report.status)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ქმედებების ქრონოლოგია (Who • What • When)',
                    style: TextStyle(
                      color: _text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: events.isEmpty
                        ? const Center(
                            child: Text(
                              'ამ რეპორტზე ცვლილებები არ არის',
                              style: TextStyle(color: _muted, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: events.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) =>
                                _buildAuditEventTile(events[index], index),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAuditEventTile(AuditEvent event, int sequence) {
    final icon = _auditEventIcon(event.type);
    final color = _auditEventColor(event.type);
    final label = _auditEventLabel(event.type);
    final timestamp = _formatAuditTimestamp(event.timestamp);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$sequence. $label • ${event.itemName}',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                timestamp,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _metaChip('Operator', '${event.waiterName} (${event.waiterId})'),
              _metaChip('Qty', '${event.previousQty} → ${event.newQty}'),
            ],
          ),
          if (event.note != null && event.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: Text(
                event.note!,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _auditStatusLabel(AuditReportStatus status) {
    switch (status) {
      case AuditReportStatus.open:
        return 'აქტიური';
      case AuditReportStatus.closed:
        return 'დახურული';
      case AuditReportStatus.cancelled:
        return 'გაუქმებული';
    }
  }

  Color _auditStatusColor(AuditReportStatus status) {
    switch (status) {
      case AuditReportStatus.open:
        return const Color(0xFFF59E0B);
      case AuditReportStatus.closed:
        return const Color(0xFF10B981);
      case AuditReportStatus.cancelled:
        return const Color(0xFFEF4444);
    }
  }

  IconData _auditEventIcon(AuditEventType type) {
    switch (type) {
      case AuditEventType.addItem:
        return Icons.add_circle_outline;
      case AuditEventType.reduceQty:
        return Icons.remove_circle_outline;
      case AuditEventType.deleteItem:
        return Icons.delete_outline;
      case AuditEventType.cancelTable:
        return Icons.block;
      case AuditEventType.custom:
        return Icons.info_outline;
    }
  }

  Color _auditEventColor(AuditEventType type) {
    switch (type) {
      case AuditEventType.addItem:
        return const Color(0xFF16A34A);
      case AuditEventType.reduceQty:
        return const Color(0xFFD97706);
      case AuditEventType.deleteItem:
        return const Color(0xFFDC2626);
      case AuditEventType.cancelTable:
        return const Color(0xFFB91C1C);
      case AuditEventType.custom:
        return const Color(0xFF475569);
    }
  }

  String _auditEventLabel(AuditEventType type) {
    switch (type) {
      case AuditEventType.addItem:
        return 'დამატება';
      case AuditEventType.reduceQty:
        return 'რაოდენობის შემცირება';
      case AuditEventType.deleteItem:
        return 'პოზიციის წაშლა';
      case AuditEventType.cancelTable:
        return 'მაგიდის დახურვა';
      case AuditEventType.custom:
        return 'ჩანაწერი';
    }
  }

  String _formatAuditTimestamp(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _formatDateIso(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _getGeorgianWeekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'ორშაბათი';
      case DateTime.tuesday:
        return 'სამშაბათი';
      case DateTime.wednesday:
        return 'ოთხშაბათი';
      case DateTime.thursday:
        return 'ხუთშაბათი';
      case DateTime.friday:
        return 'პარასკევი';
      case DateTime.saturday:
        return 'შაბათი';
      case DateTime.sunday:
      default:
        return 'კვირა';
    }
  }

  String _getGeorgianMonthName(int month) {
    const months = [
      'იანვარი',
      'თებერვალი',
      'მარტი',
      'აპრილი',
      'მაისი',
      'ივნისი',
      'ივლისი',
      'აგვისტო',
      'სექტემბერი',
      'ოქტომბერი',
      'ნოემბერი',
      'დეკემბერი',
    ];
    if (month < 1 || month > 12) {
      return 'უცნობი';
    }
    return months[month - 1];
  }

  DateTime _businessDateForReport(AuditReport report) {
    final openedLocal = report.openedAt.toLocal();
    return DateTime(openedLocal.year, openedLocal.month, openedLocal.day);
  }
}

class _AuditDayData {
  _AuditDayData({required this.date});

  final DateTime date;
  final List<AuditReport> reports = <AuditReport>[];
}
