part of '../mobile_admin_screen.dart';

DateTime _lastActivity(AuditReport r) {
  final events = r.sortedEvents;
  final eventTs = events.isNotEmpty ? events.first.timestamp : r.openedAt;
  return r.updatedAt.isAfter(eventTs) ? r.updatedAt : eventTs;
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

class _AuditTab extends StatefulWidget {
  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  String? _error;
  List<AuditReport> _reports = [];
  late DateTime _selectedMonth;
  String? _statusFilter;
  bool _didAutoSelectLatestMonth = false;

  DateTime _businessNow() {
    final raw = MonitoringSocketService.currentBusinessDate.value;
    if (raw != null && raw.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(raw.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return DateTime.now();
  }

  @override
  void initState() {
    super.initState();
    final now = _businessNow();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
    MonitoringSocketService.auditCounter.addListener(_onAuditUpdate);
    MonitoringSocketService.updateCounter.addListener(_onAuditUpdate);
  }

  @override
  void dispose() {
    MonitoringSocketService.auditCounter.removeListener(_onAuditUpdate);
    MonitoringSocketService.updateCounter.removeListener(_onAuditUpdate);
    super.dispose();
  }

  void _onAuditUpdate() {
    debugPrint('[AuditTab] realtime signal — reloading audit from server');
    if (mounted) _load(silent: true);
  }

  List<AuditReport> _filterByOpenedMonth(
    List<AuditReport> source,
    DateTime month,
  ) {
    return source.where((r) {
      final opened = r.openedAt.toLocal();
      return opened.year == month.year && opened.month == month.month;
    }).toList();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // Load full history then filter by opened month (same rule as Windows Hive UI).
      final raw = await MobileApiService.getAuditReports(
        allHistory: true,
        status: _statusFilter,
      );
      var fetched = raw
          .whereType<Map>()
          .map((m) => AuditReport.fromMap(m.cast<String, dynamic>()))
          .toList();
      fetched = _filterByOpenedMonth(fetched, _selectedMonth)
        ..sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));

      if (fetched.isEmpty &&
          !_didAutoSelectLatestMonth &&
          _statusFilter == null) {
        final all = raw
            .whereType<Map>()
            .map((m) => AuditReport.fromMap(m.cast<String, dynamic>()))
            .toList()
          ..sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
        if (all.isNotEmpty) {
          final latest = _lastActivity(all.first).toLocal();
          _didAutoSelectLatestMonth = true;
          setState(() {
            _selectedMonth = DateTime(latest.year, latest.month);
          });
          await _load(silent: true);
          return;
        }
      }
      if (mounted) {
        setState(() {
          _reports = fetched;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Map<String, List<AuditReport>> get _byDay {
    final sorted = List<AuditReport>.from(_reports)
      ..sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));

    final groups = <String, List<AuditReport>>{};
    for (final r in sorted) {
      final local = _lastActivity(r).toLocal();
      final key =
          '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(r);
    }
    return groups;
  }

  List<MapEntry<String, List<AuditReport>>> get _sortedDays =>
      _byDay.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

  int _count(AuditReportStatus s) => _reports.where((r) => r.status == s).length;

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.month == 1 ? _selectedMonth.year - 1 : _selectedMonth.year,
        _selectedMonth.month == 1 ? 12 : _selectedMonth.month - 1,
      );
    });
    _load();
  }

  void _nextMonth() {
    final now = _businessNow();
    final current = DateTime(now.year, now.month);
    if (_selectedMonth.isBefore(current)) {
      setState(() {
        _selectedMonth = DateTime(
          _selectedMonth.month == 12 ? _selectedMonth.year + 1 : _selectedMonth.year,
          _selectedMonth.month == 12 ? 1 : _selectedMonth.month + 1,
        );
      });
      _load();
    }
  }

  bool get _isCurrentMonth {
    final now = _businessNow();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        _buildStats(),
        _buildStatusFilter(),
        if (_loading)
          const Expanded(child: _AdminLoading())
        else if (_error != null)
          Expanded(child: _ErrorWidget(onRetry: _load))
        else if (_reports.isEmpty)
          Expanded(child: _buildEmpty())
        else
          Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _prevMonth,
              color: AdminTheme.text,
              splashRadius: 20,
            ),
            Expanded(
              child: Text(
                '${_georgianMonth(_selectedMonth.month)} ${_selectedMonth.year}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.text,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _isCurrentMonth ? null : _nextMonth,
              color: _isCurrentMonth ? AdminTheme.textMuted : Colors.white,
              splashRadius: 20,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _load,
              color: AdminTheme.primary,
              splashRadius: 18,
            ),
          ],
        ),
      );

  Widget _buildStats() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            _statChip('აქტიური', _count(AuditReportStatus.open), const Color(0xFFF59E0B)),
            SizedBox(width: 8),
            _statChip('დახურული', _count(AuditReportStatus.closed), const Color(0xFF10B981)),
            SizedBox(width: 8),
            _statChip('გაუქმებული', _count(AuditReportStatus.cancelled), const Color(0xFFEF4444)),
            SizedBox(width: 8),
            _statChip('სულ', _reports.length, AdminTheme.primary),
          ],
        ),
      );

  Widget _statChip(String label, int value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminTheme.border),
          ),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
              ),
              Text(label, style: TextStyle(fontSize: 10, color: AdminTheme.textMuted)),
            ],
          ),
        ),
      );

  Widget _buildStatusFilter() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _AdminFilterChip(
                label: 'ყველა',
                selected: _statusFilter == null,
                onTap: () {
                  setState(() => _statusFilter = null);
                  _load();
                },
              ),
              SizedBox(width: 8),
              _AdminFilterChip(
                label: 'აქტიური',
                selected: _statusFilter == 'OPEN',
                onTap: () {
                  setState(() => _statusFilter = 'OPEN');
                  _load();
                },
              ),
              SizedBox(width: 8),
              _AdminFilterChip(
                label: 'დახურული',
                selected: _statusFilter == 'CLOSED',
                onTap: () {
                  setState(() => _statusFilter = 'CLOSED');
                  _load();
                },
              ),
              SizedBox(width: 8),
              _AdminFilterChip(
                label: 'გაუქმებული',
                selected: _statusFilter == 'CANCELLED',
                onTap: () {
                  setState(() => _statusFilter = 'CANCELLED');
                  _load();
                },
              ),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.security_outlined, size: 48, color: AdminTheme.textMuted),
              SizedBox(height: 12),
              Text(
                'ამ პერიოდში Audit ჩანაწერები არ არის',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AdminTheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Windows POS-ის მომხმარებლების ქმედებები გამოჩნდება აქ.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );

  Widget _buildList() => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: _adminScrollPadding(context).copyWith(top: 10),
          children: _sortedDays
              .map(
                (entry) => _DayGroup(
                  dayKey: entry.key,
                  reports: entry.value,
                  onTapReport: (r) => _showDetails(context, r),
                ),
              )
              .toList(),
        ),
      );

  void _showDetails(BuildContext context, AuditReport report) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _AuditDetailDialog(report: report),
    );
  }

  static String _georgianMonth(int m) {
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
    return (m >= 1 && m <= 12) ? months[m - 1] : '';
  }
}

class _DayGroup extends StatelessWidget {
  final String dayKey;
  final List<AuditReport> reports;
  final void Function(AuditReport) onTapReport;

  const _DayGroup({
    required this.dayKey,
    required this.reports,
    required this.onTapReport,
  });

  int _count(AuditReportStatus s) => reports.where((r) => r.status == s).length;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(dayKey) ?? DateTime.now();
    final georgianDate = _georgianDate(date);

    return Card(
      color: AdminTheme.surfaceElevated,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AdminTheme.border),
      ),
      elevation: 0,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('admin-audit-$dayKey'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: AdminTheme.primary,
          collapsedIconColor: AdminTheme.textMuted,
          leading: Icon(Icons.calendar_month_outlined, color: AdminTheme.primary, size: 20),
          title: Text(
            georgianDate,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AdminTheme.text,
            ),
          ),
          subtitle: Text(
            '$dayKey • სულ ${reports.length}',
            style: TextStyle(fontSize: 12, color: AdminTheme.textMuted),
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              _miniBadge('A', _count(AuditReportStatus.open), const Color(0xFFF59E0B)),
              _miniBadge('D', _count(AuditReportStatus.closed), const Color(0xFF10B981)),
              _miniBadge('G', _count(AuditReportStatus.cancelled), const Color(0xFFEF4444)),
            ],
          ),
          children: (() {
            final ordered = List<AuditReport>.from(reports)
              ..sort((a, b) {
                final rank = _statusRank(a.status).compareTo(
                  _statusRank(b.status),
                );
                if (rank != 0) {
                  return rank;
                }
                return _lastActivity(b).compareTo(_lastActivity(a));
              });
            return ordered.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: i == ordered.length - 1 ? 0 : 8),
                child: _AuditReportCard(report: r, onTap: () => onTapReport(r)),
              );
            }).toList();
          })(),
        ),
      ),
    );
  }

  Widget _miniBadge(String label, int value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$label:$value',
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );

  static String _georgianDate(DateTime d) {
    const months = [
      'იანვ',
      'თებ',
      'მარ',
      'აპრ',
      'მაი',
      'ივნ',
      'ივლ',
      'აგვ',
      'სექ',
      'ოქტ',
      'ნოე',
      'დეკ',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _AuditReportCard extends StatelessWidget {
  final AuditReport report;
  final VoidCallback onTap;

  const _AuditReportCard({required this.report, required this.onTap});

  static Color _statusColor(AuditReportStatus s) {
    switch (s) {
      case AuditReportStatus.open:
        return const Color(0xFFF59E0B);
      case AuditReportStatus.closed:
        return const Color(0xFF10B981);
      case AuditReportStatus.cancelled:
        return const Color(0xFFEF4444);
    }
  }

  static String _statusLabel(AuditReportStatus s) {
    switch (s) {
      case AuditReportStatus.open:
        return 'აქტიური';
      case AuditReportStatus.closed:
        return 'დახურული';
      case AuditReportStatus.cancelled:
        return 'გაუქმებული';
    }
  }

  static String _fmtTs(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(report.status);
    final events = report.sortedEvents;
    final lastEvent = events.isNotEmpty ? events.first : null;

    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(report.status),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'სუფრა: ${report.tableNumbers.isEmpty ? 'TA-${report.orderId}' : report.tableNumbers.join(', ')}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.text,
                  ),
                ),
              ),
              Text(
                'Order #${report.orderId}',
                style: TextStyle(color: AdminTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              _chip('გახსნა', '${report.openedByName} • ${_fmtTs(report.openedAt)}'),
              _chip('განახლება', _fmtTs(report.updatedAt)),
              _chip('მოქმედებები', '${events.length}'),
              if (report.closedAt != null) _chip('დახურვა', _fmtTs(report.closedAt!)),
              if (report.closedByName != null) _chip('დახურა', report.closedByName!),
              if (lastEvent != null)
                _chip('ბოლო', '${_eventLabel(lastEvent.type)} • ${lastEvent.waiterName}'),
            ],
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.fact_check_outlined, size: 15),
              label: const Text('დეტალები'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AdminTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminTheme.border),
        ),
        child: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 11, color: AdminTheme.textMuted),
            children: [
              TextSpan(
                text: '$label: ',
                style: TextStyle(fontWeight: FontWeight.w700, color: AdminTheme.text),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );

  static String _eventLabel(AuditEventType t) {
    switch (t) {
      case AuditEventType.addItem:
        return 'დამატება';
      case AuditEventType.reduceQty:
        return 'რაოდენობის შემცირება';
      case AuditEventType.deleteItem:
        return 'წაშლა';
      case AuditEventType.cancelTable:
        return 'გაუქმება';
      case AuditEventType.custom:
        return 'ჩანაწერი';
    }
  }
}

class _AuditDetailDialog extends StatelessWidget {
  final AuditReport report;
  const _AuditDetailDialog({required this.report});

  static String _fmtTs(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final events = report.sortedEvents;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      backgroundColor: AdminTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AdminTheme.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                          'Audit #${report.orderId}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.text,
                          ),
                        ),
                        Text(
                          'სუფრა: ${report.tableNumbers.isEmpty ? 'TA-${report.orderId}' : report.tableNumbers.join(', ')}',
                          style: TextStyle(fontSize: 12, color: AdminTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => MobileAdminScreen.viewCheckPdf(context, report.orderId),
                    icon: Icon(
                      Icons.receipt_long_rounded,
                      color: AdminTheme.primary,
                      size: 20,
                    ),
                    tooltip: 'ქვითრის ნახვა',
                  ),
                  SizedBox(width: 4),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AdminTheme.textMuted, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  _chip('Opened by', '${report.openedByName} (${report.openedById})'),
                  _chip('Opened at', _fmtTs(report.openedAt)),
                  if (report.closedAt != null) _chip('Closed at', _fmtTs(report.closedAt!)),
                  if (report.closedByName != null)
                    _chip('Closed by', '${report.closedByName!} (${report.closedById ?? '-'})'),
                  _chip('Status', _statusLabel(report.status)),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'ქმედებების ქრონოლოგია (Who • What • When)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminTheme.text),
              ),
              SizedBox(height: 8),
              Expanded(
                child: events.isEmpty
                    ? Center(
                        child: Text(
                          'ამ რეპორტზე ცვლილებები არ არის',
                          style: TextStyle(color: AdminTheme.textMuted, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: events.length,
                        separatorBuilder: (_, __) => SizedBox(height: 6),
                        itemBuilder: (_, i) => _EventTile(
                          event: events[i],
                          seq: events.length - i,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AdminTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminTheme.border),
        ),
        child: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 11, color: AdminTheme.textMuted),
            children: [
              TextSpan(
                text: '$label: ',
                style: TextStyle(fontWeight: FontWeight.w700, color: AdminTheme.text),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );

  static String _statusLabel(AuditReportStatus s) {
    switch (s) {
      case AuditReportStatus.open:
        return 'აქტიური';
      case AuditReportStatus.closed:
        return 'დახურული';
      case AuditReportStatus.cancelled:
        return 'გაუქმებული';
    }
  }
}

class _EventTile extends StatelessWidget {
  final AuditEvent event;
  final int seq;
  const _EventTile({required this.event, required this.seq});

  static Color _color(AuditEventType t) {
    switch (t) {
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

  static IconData _icon(AuditEventType t) {
    switch (t) {
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

  static String _label(AuditEventType t) {
    switch (t) {
      case AuditEventType.addItem:
        return 'დამატება';
      case AuditEventType.reduceQty:
        return 'რაოდენობის შემცირება';
      case AuditEventType.deleteItem:
        return 'პოზ. წაშლა';
      case AuditEventType.cancelTable:
        return 'მაგიდის გაუქმება';
      case AuditEventType.custom:
        return 'ჩანაწერი';
    }
  }

  static String _fmtTs(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(event.type);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(_icon(event.type), color: color, size: 15),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$seq. ${_label(event.type)} • ${event.itemName}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.text,
                  ),
                ),
              ),
              Text(
                _fmtTs(event.timestamp),
                style: TextStyle(color: AdminTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _metaChip('Operator', '${event.waiterName} (${event.waiterId})'),
              _metaChip('Qty', '${event.previousQty} → ${event.newQty}'),
            ],
          ),
          if (event.note != null && event.note!.isNotEmpty) ...[
            SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminTheme.border),
              ),
              child: Text(
                event.note!,
                style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AdminTheme.text,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 11, color: AdminTheme.textMuted),
            children: [
              TextSpan(
                text: '$label: ',
                style: TextStyle(fontWeight: FontWeight.w700, color: AdminTheme.text),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );
}
