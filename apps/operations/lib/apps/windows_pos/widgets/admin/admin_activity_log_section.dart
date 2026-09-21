import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/global_audit_entry.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/database_service.dart';

/// The venue-wide activity log, read from this terminal's own audit box.
///
/// The per-Order audit report answers "what happened to this table". This
/// answers the questions that have no Order: who changed a price, who changed
/// somebody's role, who recorded that expense, who closed the day, who restored
/// a backup.
///
/// It reads the same rows the POS has always written and now sends to Cloud —
/// including the ones written before entity identity existed, whose subject is
/// derived from their action rather than rewritten into them.
class AdminActivityLogSection extends StatefulWidget {
  const AdminActivityLogSection({super.key});

  @override
  State<AdminActivityLogSection> createState() =>
      _AdminActivityLogSectionState();
}

/// The entity filters offered, in the order somebody looks for them.
const List<({String? type, String label})> _activityFilters = [
  (type: null, label: 'ყველა'),
  (type: GlobalAuditEntity.staff, label: 'გუნდი'),
  (type: GlobalAuditEntity.menuItem, label: 'მენიუ'),
  (type: GlobalAuditEntity.menuCategory, label: 'კატეგორიები'),
  (type: GlobalAuditEntity.package, label: 'პაკეტები'),
  (type: GlobalAuditEntity.expense, label: 'ხარჯები'),
  (type: GlobalAuditEntity.closeDay, label: 'დღის დახურვა'),
  (type: GlobalAuditEntity.reservation, label: 'ჯავშნები'),
  (type: GlobalAuditEntity.order, label: 'შეკვეთები'),
  (type: GlobalAuditEntity.sale, label: 'გაყიდვები'),
  (type: GlobalAuditEntity.settings, label: 'პარამეტრები'),
  (type: GlobalAuditEntity.backup, label: 'ბექაფი'),
];

class _AdminActivityLogSectionState extends State<AdminActivityLogSection> {
  static const Color _surface = AdminDesign.panelSoft;
  static const Color _card = AdminDesign.panel;
  static const Color _border = AdminDesign.border;
  static const Color _text = AdminDesign.text;
  static const Color _muted = AdminDesign.muted;

  /// How many rows are rendered at once. The box holds every Order-level row
  /// too, so an unbounded list on a busy venue would be tens of thousands of
  /// widgets for a screen that shows twenty.
  static const int _pageSize = 100;

  String? _entityType;
  String _search = '';
  int _visible = _pageSize;

  /// The audit box mixes three kinds of row: per-Order reports (keyed by
  /// `reportId`), venue-wide log rows (keyed by their uuid), and legacy action
  /// rows. Only the second kind belongs in this feed, and a report is told
  /// apart by carrying `reportId`.
  List<GlobalAuditEntry> _readEntries() {
    final box = DatabaseService.getAuditLogBox();
    final entries = <GlobalAuditEntry>[];
    for (final raw in box.values) {
      if (raw is! Map) continue;
      if (raw['reportId'] != null) continue;
      if (raw['action'] == null || raw['id'] == null) continue;
      try {
        entries.add(
          GlobalAuditEntry.fromLocal(
            AuditEventLog.fromMap(Map<String, dynamic>.from(raw)),
          ),
        );
      } catch (_) {
        // A row this build cannot decode is skipped, not repaired: the store
        // is append-only history and a reader does not get to edit it.
        continue;
      }
    }
    entries.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      // Two rows written in the same instant keep a stable order rather than
      // shuffling between rebuilds.
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return entries;
  }

  bool _matches(GlobalAuditEntry entry) {
    if (_entityType != null && entry.entityType != _entityType) return false;
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      entry.action,
      GlobalAuditPresentation.actionLabel(entry.action),
      entry.subject ?? '',
      entry.actorName,
      entry.actorId,
      entry.entityId ?? '',
    ].any((value) => value.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: DatabaseService.getAuditLogBox().listenable(),
      builder: (context, _, __) {
        final all = _readEntries();
        final filtered = all.where(_matches).toList(growable: false);
        final shown = filtered.take(_visible).toList(growable: false);
        return SizedBox.expand(
          child: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: adminSectionMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminSectionHeader(
                      icon: Icons.history,
                      title: 'აქტივობის ჟურნალი',
                      subtitle:
                          'გუნდი, მენიუ, პაკეტები, ხარჯები, დღის დახურვა და '
                          'ბექაფი — ვინ, რა და როდის.',
                      badge: AdminStatusBadge(
                        icon: Icons.fact_check_outlined,
                        label: '${filtered.length} ჩანაწერი',
                        color: AdminDesign.accentDark,
                        background: AdminDesign.accentSoft,
                        border: AdminDesign.accentSoftBorder,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildFilters(),
                    const SizedBox(height: 12),
                    if (shown.isEmpty)
                      _buildEmpty()
                    else
                      ...shown.map(_buildRow),
                    if (filtered.length > shown.length) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _visible += _pageSize),
                          child: Text(
                            'კიდევ ${filtered.length - shown.length}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _activityFilters)
              _FilterChip(
                label: filter.label,
                selected: _entityType == filter.type,
                onTap: () => setState(() {
                  _entityType = filter.type;
                  _visible = _pageSize;
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 340,
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'ძებნა: ქმედება, ობიექტი, მომხმარებელი',
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (value) => setState(() {
              _search = value;
              _visible = _pageSize;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 40),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _border),
    ),
    child: const Center(
      child: Text(
        'ამ ფილტრით ჩანაწერები არ არის',
        style: TextStyle(color: _muted, fontSize: 13),
      ),
    ),
  );

  Widget _buildRow(GlobalAuditEntry entry) {
    final subject = entry.subject;
    final changes = <String>[
      for (final change in entry.changes)
        if (GlobalAuditPresentation.changeLine(change) != null)
          GlobalAuditPresentation.changeLine(change)!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  GlobalAuditPresentation.actionLabel(entry.action),
                  style: const TextStyle(
                    color: _text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _formatTimestamp(entry.createdAt),
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ],
          ),
          if (subject != null) ...[
            const SizedBox(height: 3),
            Text(
              subject,
              style: const TextStyle(
                color: _muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          for (final line in changes) ...[
            const SizedBox(height: 3),
            Text(
              line,
              style: const TextStyle(
                color: AdminDesign.accentDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _metaChip(Icons.person_outline, entry.actorName),
              if (entry.source != null)
                _metaChip(Icons.route_outlined, entry.source!),
              if (entry.entityType != null)
                _metaChip(
                  Icons.category_outlined,
                  GlobalAuditPresentation.entityLabel(entry.entityType),
                ),
              if (entry.businessDate != null)
                _metaChip(Icons.event_outlined, entry.businessDate!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: _muted),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: _muted, fontSize: 11.5)),
    ],
  );

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AdminDesign.accentSoft : AdminDesign.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? AdminDesign.accentSoftBorder
              : AdminDesign.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: selected ? AdminDesign.accentDark : AdminDesign.muted,
        ),
      ),
    ),
  );
}
