part of '../mobile_admin_screen.dart';

/// The venue-wide activity feed.
///
/// Everything that is not the lifecycle of one Order: staff, menu, packages,
/// expenses, close day, backups, settings, the business date. An Order's own
/// story lives in the Audit tab, chronologically; this one is recent activity,
/// newest first.
class _ActivityTab extends StatefulWidget {
  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

/// The entity filters offered, in the order a manager looks for them.
const List<({String? type, String label})> _activityFilters = [
  (type: null, label: 'ყველა'),
  (type: GlobalAuditEntity.staff, label: 'გუნდი'),
  (type: GlobalAuditEntity.menuItem, label: 'მენიუ'),
  (type: GlobalAuditEntity.stockItem, label: 'მარაგები'),
  (type: GlobalAuditEntity.supplier, label: 'მომწოდებლები'),
  (type: GlobalAuditEntity.package, label: 'პაკეტები'),
  (type: GlobalAuditEntity.expense, label: 'ხარჯები'),
  (type: GlobalAuditEntity.closeDay, label: 'დღის დახურვა'),
  (type: GlobalAuditEntity.reservation, label: 'ჯავშნები'),
  (type: GlobalAuditEntity.order, label: 'შეკვეთები'),
  (type: GlobalAuditEntity.sale, label: 'გაყიდვები'),
  (type: GlobalAuditEntity.settings, label: 'პარამეტრები'),
  (type: GlobalAuditEntity.backup, label: 'ბექაფი'),
];

const List<({int? days, String label})> _activityRanges = [
  (days: 7, label: '7 დღე'),
  (days: 30, label: '30 დღე'),
  (days: null, label: 'ყველა'),
];

class _ActivityTabState extends State<_ActivityTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _scroll = ScrollController();
  final _entries = <GlobalAuditEntry>[];

  String? _entityType;
  int? _rangeDays = 30;
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// The subject a manager drilled into — "everything about this staff
  /// member". Cleared by tapping the chip that shows it.
  String? _entityId;
  String? _entityIdLabel;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _load(more: true);
    }
  }

  String? get _from {
    final days = _rangeDays;
    if (days == null) return null;
    final start = DateTime.now().subtract(Duration(days: days));
    return DateTime(start.year, start.month, start.day).toIso8601String();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (!_hasMore || _cursor == null)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await MobileApiService.getGlobalAuditLog(
        from: _from,
        entityType: _entityType,
        entityId: _entityId,
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (!more) _entries.clear();
        _entries.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '$e';
      });
    }
  }

  void _applyFilter({
    String? entityType,
    int? rangeDays,
    bool clearSubject = false,
    bool setRange = false,
  }) {
    setState(() {
      if (setRange) _rangeDays = rangeDays;
      if (!setRange) _entityType = entityType;
      if (clearSubject) {
        _entityId = null;
        _entityIdLabel = null;
      }
      _cursor = null;
      _hasMore = false;
    });
    _load();
  }

  void _drillInto(GlobalAuditEntry entry) {
    final id = entry.entityId;
    if (id == null || entry.entityType == null) return;
    setState(() {
      _entityType = entry.entityType;
      _entityId = id;
      _entityIdLabel = entry.subject ?? id;
      // A subject's whole history, not the last month of it.
      _rangeDays = null;
      _cursor = null;
      _hasMore = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final filter in _activityFilters) ...[
                _AdminFilterChip(
                  label: filter.label,
                  selected: _entityType == filter.type && _entityId == null,
                  onTap: () =>
                      _applyFilter(entityType: filter.type, clearSubject: true),
                ),
                SizedBox(width: 8),
              ],
            ],
          ),
        ),
        SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final range in _activityRanges) ...[
                _AdminFilterChip(
                  label: range.label,
                  selected: _rangeDays == range.days,
                  onTap: () =>
                      _applyFilter(rangeDays: range.days, setRange: true),
                ),
                SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (_entityIdLabel != null) ...[
          SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _AdminFilterChip(
                label: '✕  $_entityIdLabel',
                selected: true,
                onTap: () =>
                    _applyFilter(entityType: _entityType, clearSubject: true),
              ),
            ),
          ),
        ],
        SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return _AdminLoading();
    if (_error != null) {
      return _ErrorWidget(onRetry: () => _load());
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          'ამ ფილტრით ჩანაწერები არ არის',
          style: TextStyle(color: AdminTheme.textMuted, fontSize: 13),
        ),
      );
    }
    return RefreshIndicator(
      color: AdminTheme.primary,
      onRefresh: () => _load(),
      child: ListView.separated(
        controller: _scroll,
        padding: _adminScrollPadding(context),
        itemCount: _entries.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: 8),
        itemBuilder: (_, index) {
          if (index >= _entries.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AdminTheme.primary,
                  ),
                ),
              ),
            );
          }
          final entry = _entries[index];
          return _ActivityRow(
            entry: entry,
            onDrillIn: entry.entityId == null ? null : () => _drillInto(entry),
          );
        },
      ),
    );
  }
}

/// One row of the activity feed: what happened, to what, by whom, when.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, this.onDrillIn});

  final GlobalAuditEntry entry;
  final VoidCallback? onDrillIn;

  @override
  Widget build(BuildContext context) {
    final subject = entry.subject;
    final changes = [
      for (final change in entry.changes)
        if (GlobalAuditPresentation.changeLine(change) != null)
          GlobalAuditPresentation.changeLine(change)!,
    ];
    return GestureDetector(
      onTap: onDrillIn,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    GlobalAuditPresentation.actionLabel(entry.action),
                    style: TextStyle(
                      color: AdminTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _activityTime(entry.createdAt),
                  style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
                ),
              ],
            ),
            if (subject != null) ...[
              SizedBox(height: 3),
              Text(
                subject,
                style: TextStyle(
                  color: AdminTheme.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            for (final line in changes) ...[
              SizedBox(height: 3),
              Text(
                line,
                style: TextStyle(color: AdminTheme.accent, fontSize: 12),
              ),
            ],
            SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person_outline, size: 13, color: AdminTheme.textDim),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    entry.actorName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
                  ),
                ),
                if (entry.source != null) ...[
                  SizedBox(width: 8),
                  Text(
                    entry.source!,
                    style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
                  ),
                ],
                if (entry.entityType != null) ...[
                  SizedBox(width: 8),
                  Text(
                    GlobalAuditPresentation.entityLabel(entry.entityType),
                    style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _activityTime(DateTime dt) {
  final l = dt.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')} '
      '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}
