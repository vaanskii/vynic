part of '../mobile_admin_screen.dart';

/// The venue-wide activity feed.
///
/// Everything that is not the lifecycle of one Order: staff, menu, packages,
/// expenses, close day, backups, settings, the business date. An Order's own
/// story lives in the Audit tab, chronologically; this one is recent activity,
/// newest first.
class _ActivityTab extends StatefulWidget {
  const _ActivityTab({this.onOpenOperationalAudit});
  final VoidCallback? onOpenOperationalAudit;
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

  Future<void> _showFilters() => showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => ManagerFormDialog(
        title: const Text('აქტივობის ფილტრები'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ManagerSectionHeading('პერიოდი'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final range in _activityRanges)
                  _AdminFilterChip(
                    label: range.label,
                    selected: _rangeDays == range.days,
                    onTap: () {
                      _applyFilter(rangeDays: range.days, setRange: true);
                      update(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const ManagerSectionHeading('ჩანაწერის ტიპი'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in _activityFilters)
                  _AdminFilterChip(
                    label: filter.label,
                    selected: _entityType == filter.type && _entityId == null,
                    onTap: () {
                      _applyFilter(entityType: filter.type, clearSubject: true);
                      update(() {});
                    },
                  ),
              ],
            ),
            if (_entityIdLabel != null) ...[
              const SizedBox(height: 16),
              _AdminFilterChip(
                label: '✕  $_entityIdLabel',
                selected: true,
                onTap: () {
                  _applyFilter(entityType: _entityType, clearSubject: true);
                  update(() {});
                },
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('დახურვა'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _adminScrollPadding(context),
        children: [
          ManagerPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ManagerSectionHeading(
                        'აქტივობის ჟურნალი',
                        action: 'ფილტრები',
                        onAction: _showFilters,
                      ),
                    ),
                    if (widget.onOpenOperationalAudit != null)
                      PopupMenuButton<String>(
                        tooltip: 'აუდიტის სხვა ხედები',
                        onSelected: (_) => widget.onOpenOperationalAudit!(),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'operational',
                            child: Text('ოპერაციული აუდიტი'),
                          ),
                        ],
                      ),
                  ],
                ),
                if (_entityIdLabel != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _applyFilter(
                        entityType: _entityType,
                        clearSubject: true,
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(_entityIdLabel!),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _ErrorWidget(onRetry: () => _load())
                else if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'ამ ფილტრით ჩანაწერები არ არის',
                      style: managerDesignText(context, 13, muted: true),
                    ),
                  )
                else
                  for (final entry in _entries)
                    _ActivityRow(
                      entry: entry,
                      onDrillIn: entry.entityId == null
                          ? null
                          : () => _drillInto(entry),
                    ),
                if (_hasMore && !_loading)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
    final time = entry.createdAt.toLocal();
    final changes = [
      for (final change in entry.changes)
        if (GlobalAuditPresentation.changeLine(change) != null)
          GlobalAuditPresentation.changeLine(change)!,
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        style: managerDesignText(context, 11, muted: true),
      ),
      title: Text(
        _managerActivityLabel(entry.action),
        style: managerDesignText(context, 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.subject != null)
            Text(
              entry.subject!,
              style: managerDesignText(context, 11, muted: true),
            ),
          Text(
            [
              entry.actorName,
              if (entry.source != null) entry.source!,
            ].join(' · '),
            style: managerDesignText(context, 11, muted: true),
          ),
        ],
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => ManagerFormDialog(
          title: Text(_managerActivityLabel(entry.action)),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.subject != null)
                Text(
                  entry.subject!,
                  style: managerDesignText(
                    context,
                    20,
                    weight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 18),
              ManagerKeyValue('თარიღი და დრო', _activityTime(entry.createdAt)),
              ManagerKeyValue('ავტორი', entry.actorName),
              if (entry.source != null) ManagerKeyValue('წყარო', entry.source!),
              if (entry.entityType != null)
                ManagerKeyValue(
                  'ტიპი',
                  GlobalAuditPresentation.entityLabel(entry.entityType),
                ),
              if (changes.isNotEmpty) ...[
                const SizedBox(height: 20),
                const ManagerSectionHeading('ცვლილებები'),
                for (final line in changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(line, style: managerDesignText(context, 13)),
                  ),
              ],
              if (onDrillIn != null)
                ManagerDetailLink(
                  'ობიექტის ისტორია',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    onDrillIn!();
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('დახურვა'),
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

String _managerActivityLabel(String action) =>
    const {
      'MENU_ITEM_CREATED': 'მენიუს პროდუქტი დაემატა',
      'MENU_ITEM_UPDATED': 'მენიუს პროდუქტი შეიცვალა',
      'MENU_ITEM_DELETED': 'მენიუს პროდუქტი წაიშალა',
      'STAFF_CREATED': 'თანამშრომელი დაემატა',
      'STAFF_UPDATED': 'თანამშრომელი შეიცვალა',
      'STAFF_ROLE_CHANGED': 'თანამშრომლის როლი შეიცვალა',
      'STAFF_PIN_CHANGED': 'თანამშრომლის PIN შეიცვალა',
      'STAFF_DELETED': 'თანამშრომელი წაიშალა',
      'RECEIVING_CREATED': 'მიღება შეიქმნა',
      'RECEIVING_UPDATED': 'მიღება შეიცვალა',
      'RECEIVING_POSTED': 'მიღება გატარდა',
      'RECEIVING_CANCELLED': 'მიღება გაუქმდა',
      'RECIPE_CREATED': 'შემადგენლობა დაემატა',
      'RECIPE_UPDATED': 'შემადგენლობა შეიცვალა',
      'RECIPE_DISABLED': 'შემადგენლობა გაითიშა',
      'CONFIRM_RESERVATION': 'რეზერვაცია დადასტურდა',
      'CREATE_RESERVATION': 'რეზერვაცია შეიქმნა',
      'UPDATE_RESERVATION': 'რეზერვაცია შეიცვალა',
      'ORDER_CREATED': 'შეკვეთა გაიხსნა',
      'PAYROLL_PAYMENT_RECORDED': 'ხელფასის გადახდა ჩაიწერა',
    }[action] ??
    GlobalAuditPresentation.actionLabel(action);
