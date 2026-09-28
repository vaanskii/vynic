import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';
import 'package:vynic/core/services/menu/pos_menu_sync_service.dart';

/// Operator decisions about the canonical Cloud Menu (docs/CANONICAL_MENU_SYNC.md).
///
/// Routine sync stays silent (pending edits while offline are normal). This
/// appears only when a person must decide: another device changed the same
/// product, Cloud refused a change, or this POS holds a different local menu.
/// Nothing here overwrites anything by itself.
class MenuSyncBanner extends StatelessWidget {
  const MenuSyncBanner({super.key, this.service});

  final PosMenuSyncService? service;

  @override
  Widget build(BuildContext context) {
    final sync = service ?? PosMenuSyncService.instance;
    return ValueListenableBuilder<MenuSyncStatus>(
      valueListenable: sync.status,
      builder: (context, status, _) {
        final cards = <Widget>[
          if (status.mode == MenuSyncMode.adoptionBlocked)
            _AdoptCard(sync: sync),
          for (final entry in status.attention)
            MenuConflictCard(entry: entry, sync: sync),
        ];
        if (cards.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card,
                ),
            ],
          ),
        );
      },
    );
  }
}

const _labels = <String, String>{
  'nameKa': 'სახელი',
  'nameEn': 'სახელი (EN)',
  'price': 'ფასი',
  'size': 'ზომა',
  'sendToKitchen': 'სამზარეულოში გაგზავნა',
  'slug': 'კოდი',
};

String _value(String field, Object? value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'კი' : 'არა';
  if (field == 'price' && value is num) return '${value.toStringAsFixed(2)} ₾';
  return value.toString();
}

class MenuConflictCard extends StatelessWidget {
  const MenuConflictCard({super.key, required this.entry, required this.sync});

  final MenuMutationEntry entry;
  final PosMenuSyncService sync;

  @override
  Widget build(BuildContext context) {
    final conflict = entry.conflict;
    final deleted = conflict?['deleted'] == true;
    final current = conflict?['current'] is Map
        ? Map<String, dynamic>.from(conflict!['current'] as Map)
        : const <String, dynamic>{};
    final isConflict = entry.status == MenuMutationStatus.conflict;
    final name =
        (current['nameKa'] as String?) ??
        (entry.patch['nameKa'] as String?) ??
        (entry.patch['nameEn'] as String?) ??
        'პროდუქტი';
    final title = !isConflict
        ? 'ცვლილება ვერ მიიღო Cloud-მა'
        : deleted
        ? 'ეს პროდუქტი სხვა მოწყობილობაზე წაიშალა.'
        : 'ეს პროდუქტი სხვა მოწყობილობაზე შეიცვალა.';
    final fields = entry.patch.keys.where(_labels.containsKey).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminDesign.panel,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: AdminDesign.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AdminDesign.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(color: AdminDesign.muted)),
          if (!isConflict)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _reason(entry.lastError),
                style: const TextStyle(color: AdminDesign.muted),
              ),
            ),
          if (isConflict && fields.isNotEmpty) ...[
            const SizedBox(height: 10),
            Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              children: [
                const TableRow(
                  children: [
                    SizedBox(),
                    Text(
                      'მიმდინარე',
                      style: TextStyle(color: AdminDesign.muted),
                    ),
                    Text(
                      'თქვენი ცვლილება',
                      style: TextStyle(color: AdminDesign.muted),
                    ),
                  ],
                ),
                for (final field in fields)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12, top: 4),
                        child: Text(_labels[field]!),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          deleted ? '—' : _value(field, current[field]),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _value(field, entry.patch[field]),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => sync.useCurrent(entry.mutationId),
                child: Text(isConflict ? 'მიმდინარეს გამოყენება' : 'გაუქმება'),
              ),
              if (isConflict && !deleted)
                OutlinedButton(
                  onPressed: () => sync.reapply(entry.mutationId),
                  child: const Text('ჩემი ცვლილების ხელახლა გამოყენება'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _reason(String? code) => switch (code) {
    'PARENT_MISSING' => 'კატეგორია სხვა მოწყობილობაზე წაიშალა.',
    'NOT_EMPTY' => 'კატეგორიაში ჯერ კიდევ არის პროდუქტები.',
    _ => 'ცვლილება ამ მოწყობილობაზე დარჩა; შეგიძლიათ გააუქმოთ.',
  };
}

class _AdoptCard extends StatelessWidget {
  const _AdoptCard({required this.sync});
  final PosMenuSyncService sync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminDesign.panel,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: AdminDesign.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ამ POS-ის მენიუ განსხვავდება რესტორნის Cloud მენიუსგან.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'არსებული მენიუ უცვლელად მუშაობს. Cloud მენიუზე გადასვლა მხოლოდ თქვენი დადასტურებით მოხდება.',
            style: TextStyle(color: AdminDesign.muted),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cloud მენიუს გამოყენება'),
                  content: const Text(
                    'ამ POS-ის ლოკალური მენიუ ჩანაცვლდება რესტორნის Cloud მენიუთი. გავაგრძელოთ?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('გაუქმება'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('ჩანაცვლება'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await sync.adoptCloudMenu();
            },
            child: const Text('Cloud მენიუს გამოყენება'),
          ),
        ],
      ),
    );
  }
}
