import 'package:vynic/core/widgets/pos_text.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/models/feature_keys.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

/// A local inspection surface. Opening it never requests a network connection.
class AdminInventorySection extends StatefulWidget {
  const AdminInventorySection({super.key});
  @override
  State<AdminInventorySection> createState() => _AdminInventoryState();
}

class _AdminInventoryState extends State<AdminInventorySection> {
  String? _status;
  StockItemClassification? _classification;
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(Object? raw) => raw is List
      ? raw.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
      : [];

  @override
  Widget build(BuildContext context) {
    final box = DatabaseCore.inventoryBox;
    if (box == null)
      return const Center(child: PosText('მარაგები ჯერ არ ჩამოტვირთულა'));
    return ValueListenableBuilder(
      valueListenable: box.listenable(keys: [InventoryRepository.catalogKey]),
      builder: (context, _, child) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (!InventoryRepository.hasFeature(FeatureKeys.inventory))
      return const SizedBox.shrink();
    final items = InventoryRepository.getStockItems();
    final inspection =
        InventoryRepository.exportCatalog()['inspection'] as Map?;
    final procurement = inspection?['procurement'] as Map?;
    final day = procurement?['businessDay'] as Map?;
    final recipes = InventoryRepository.getRecipes();
    final refreshed = InventoryRepository.lastRefreshedAt;
    final filtered = items.where(
      (item) =>
          (_status == null || (item.isActive && item.stockStatus == _status)) &&
          (_classification == null || item.classification == _classification) &&
          item.name.toLowerCase().contains(_query.toLowerCase()),
    );
    return ListView(
      key: const Key('pos-inventory'),
      padding: const EdgeInsets.all(VynicSpacing.lg),
      children: [
        PosText('მარაგები', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: VynicSpacing.xs),
        PosText(
          refreshed == null
              ? 'მარაგები ჯერ არ ჩამოტვირთულა'
              : 'ბოლო განახლება: ${refreshed.toLocal().toString().split(".").first}',
        ),
        const PosText(
          'მონაცემები ბოლო განახლების დროისთვის. ცვლილებები შეიტანეთ მენეჯერის აპში.',
        ),
        const SizedBox(height: VynicSpacing.md),
        Wrap(
          spacing: VynicSpacing.xs,
          runSpacing: VynicSpacing.xs,
          children: [
            ChoiceChip(
              labelStyle: Theme.of(context).textTheme.bodyMedium,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              label: const PosText('ყველა პროდუქტი'),
              selected: _status == null,
              onSelected: (_) => setState(() => _status = null),
            ),
            for (final status in ['LOW', 'NEGATIVE'])
              ChoiceChip(
                labelStyle: Theme.of(context).textTheme.bodyMedium,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: PosText(
                  '${status == 'LOW' ? 'დაბალი მარაგი' : 'უარყოფითი მარაგი'} (${items.where((i) => i.isActive && i.stockStatus == status).length})',
                ),
                selected: _status == status,
                onSelected: (_) => setState(() => _status = status),
              ),
          ],
        ),
        const SizedBox(height: VynicSpacing.sm),
        PosOnScreenTextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'პროდუქტის ძებნა',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: VynicSpacing.sm),
        Wrap(
          spacing: VynicSpacing.xs,
          runSpacing: VynicSpacing.xs,
          children: [
            ChoiceChip(
              labelStyle: Theme.of(context).textTheme.bodyMedium,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              label: const PosText('ყველა'),
              selected: _classification == null,
              onSelected: (_) => setState(() => _classification = null),
            ),
            for (final value in StockItemClassification.values)
              ChoiceChip(
                labelStyle: Theme.of(context).textTheme.bodyMedium,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: PosText(value.label),
                selected: _classification == value,
                onSelected: (_) => setState(() => _classification = value),
              ),
          ],
        ),
        const SizedBox(height: VynicSpacing.md),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: PosText('შესაბამისი პროდუქტი ვერ მოიძებნა'),
          ),
        for (final item in filtered)
          Card(
            child: ListTile(
              key: ValueKey('pos-stock-${item.id}'),
              contentPadding: const EdgeInsets.all(VynicSpacing.md),
              title: Text(item.name),
              subtitle: PosText(
                '${item.currentStock} ${item.baseUnit.label} · ${_statusLabel(item)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(item.name),
                  titleTextStyle: Theme.of(context).textTheme.titleLarge,
                  contentTextStyle: Theme.of(context).textTheme.bodyMedium,
                  content: SizedBox(
                    width: 600,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PosText(
                            '${item.currentStock} ${item.baseUnit.label}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          PosText(_statusLabel(item)),
                          if ((inspection?['costsByItem'] as Map?)?[item.id]
                              case final Map cost) ...[
                            PosText(
                              'მარაგის საშუალო ფასი: ${cost['unitCost'] ?? '—'} ₾ / ${item.baseUnit.label}',
                            ),
                            PosText(
                              'მარაგის ღირებულება: ${cost['inventoryValue'] ?? '—'} ₾',
                            ),
                            if (cost['status'] == 'PROVISIONAL')
                              const PosText('შეფასება წინასწარია'),
                          ],
                          const SizedBox(height: 24),
                          const PosText('გამოიყენება მენიუში'),
                          if (!recipes.any(
                            (r) => r.components.any(
                              (c) => c.stockItemId == item.id,
                            ),
                          ))
                            const PosText('აქტიური მიბმა არ არის'),
                          for (final recipe in recipes.where(
                            (r) => r.components.any(
                              (c) => c.stockItemId == item.id,
                            ),
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: PosText(
                                '${recipe.menuItemName}${recipe.variantLabel == null ? '' : ' · ${recipe.variantLabel}'}',
                              ),
                              subtitle: const PosText(
                                'აქტიური რეცეპტი / მიბმა',
                              ),
                            ),
                          const SizedBox(height: 24),
                          const PosText('ბოლო მოძრაობები (მაქს. 20)'),
                          if (inspection == null)
                            const PosText(
                              'მოძრაობების ჩასატვირთად საჭიროა განახლება',
                            ),
                          for (final row in _rows(
                            (inspection?['movementsByItem'] as Map?)?[item.id],
                          ))
                            Builder(
                              builder: (_) {
                                final m = StockMovement.fromJson(row);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: PosText(
                                    '${m.quantityDeltaBase} ${m.baseUnit.label} · ${m.movementType.label}',
                                  ),
                                  subtitle: PosText(
                                    '${m.businessDate} · ${m.actorName}',
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: PosText(
                        'დახურვა',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: VynicSpacing.lg),
        ExpansionTile(
          title: const PosText('დღის მიღებები'),
          subtitle: PosText(
            day == null
                ? 'განახლება საჭიროა'
                : '${procurement?['businessDate']} · ${day['total']} ₾ · ${day['count']} მიღება',
          ),
          children: [
            const ListTile(title: PosText('ბოლო 100 დადასტურებული მიღება')),
            if (procurement != null) ...[
              PosText(
                'მომწოდებლებს გადახდილი: ${((procurement['supplierPayments'] as Map?)?['businessDay'] as Map?)?['total'] ?? '—'} ₾',
              ),
              PosText(
                'დღის მიღებების დავალიანება: ${procurement['newUnpaidBalance'] ?? '—'} ₾',
              ),
            ],
            for (final r in _rows(inspection?['receivings']))
              ListTile(
                title: PosText('${r['supplierNameSnapshot']}'),
                subtitle: PosText('${r['documentTotal']} ₾'),
              ),
          ],
        ),
        ExpansionTile(
          title: const PosText('რეცეპტები და მიბმები'),
          children: [
            if (inspection == null)
              const ListTile(
                title: PosText(
                  'რეცეპტების სტატუსის ჩასატვირთად საჭიროა განახლება',
                ),
              ),
            for (final row in _rows(inspection?['menuItems']))
              Builder(
                builder: (_) {
                  final item = RecipeMenuItem.fromJson(row);
                  return Column(
                    children: [
                      ListTile(
                        title: Text(item.name),
                        subtitle: PosText(
                          item.recipe?.isActive == true
                              ? 'მიბმულია'
                              : 'მიბმა არ არის',
                        ),
                      ),
                      for (final variant in item.variants)
                        ListTile(
                          title: PosText('${item.name} · ${variant.size}'),
                          subtitle: PosText(
                            variant.recipe?.isActive == true
                                ? 'მიბმულია'
                                : 'მიბმა არ არის',
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
        ExpansionTile(
          title: const PosText('მიუბმელი გაყიდული პროდუქტები'),
          subtitle: PosText(
            inspection == null
                ? 'განახლება საჭიროა'
                : '${inspection['unmappedCount']} პროდუქტი · გაყიდვის დროს მიბმა არ ჰქონდა',
          ),
          children: [
            for (final row in _rows(inspection?['unmapped']))
              ListTile(
                title: PosText(
                  '${row['itemName']}${row['variantName'] == null ? '' : ' · ${row['variantName']}'}',
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _statusLabel(StockItem item) => !item.isActive
      ? 'გათიშული'
      : switch (item.stockStatus) {
          'LOW' => 'დაბალი მარაგი',
          'NEGATIVE' => 'უარყოფითი მარაგი',
          _ => 'ნორმალური',
        };
}
