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
  List<Map<String, dynamic>> _rows(Object? raw) => raw is List
      ? raw.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
      : [];

  @override
  Widget build(BuildContext context) {
    final box = DatabaseCore.inventoryBox;
    if (box == null)
      return const Center(child: Text('მარაგები ჯერ არ ჩამოტვირთულა'));
    return ValueListenableBuilder(
      valueListenable: box.listenable(keys: [InventoryRepository.catalogKey]),
      builder: (context, _, child) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
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
        Text('მარაგები', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: VynicSpacing.xs),
        Text(
          refreshed == null
              ? 'მარაგები ჯერ არ ჩამოტვირთულა'
              : 'ბოლო განახლება: ${refreshed.toLocal().toString().split(".").first}',
        ),
        const Text(
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
              label: const Text('ყველა პროდუქტი'),
              selected: _status == null,
              onSelected: (_) => setState(() => _status = null),
            ),
            for (final status in ['LOW', 'NEGATIVE'])
              ChoiceChip(
                labelStyle: Theme.of(context).textTheme.bodyMedium,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(
                  '${status == 'LOW' ? 'დაბალი მარაგი' : 'უარყოფითი მარაგი'} (${items.where((i) => i.isActive && i.stockStatus == status).length})',
                ),
                selected: _status == status,
                onSelected: (_) => setState(() => _status = status),
              ),
          ],
        ),
        const SizedBox(height: VynicSpacing.sm),
        TextField(
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
              label: const Text('ყველა'),
              selected: _classification == null,
              onSelected: (_) => setState(() => _classification = null),
            ),
            for (final value in StockItemClassification.values)
              ChoiceChip(
                labelStyle: Theme.of(context).textTheme.bodyMedium,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(value.label),
                selected: _classification == value,
                onSelected: (_) => setState(() => _classification = value),
              ),
          ],
        ),
        const SizedBox(height: VynicSpacing.md),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('შესაბამისი პროდუქტი ვერ მოიძებნა'),
          ),
        for (final item in filtered)
          Card(
            child: ListTile(
              key: ValueKey('pos-stock-${item.id}'),
              contentPadding: const EdgeInsets.all(VynicSpacing.md),
              title: Text(item.name),
              subtitle: Text(
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
                          Text(
                            '${item.currentStock} ${item.baseUnit.label}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(_statusLabel(item)),
                          const SizedBox(height: 24),
                          const Text('გამოიყენება მენიუში'),
                          if (!recipes.any(
                            (r) => r.components.any(
                              (c) => c.stockItemId == item.id,
                            ),
                          ))
                            const Text('აქტიური მიბმა არ არის'),
                          for (final recipe in recipes.where(
                            (r) => r.components.any(
                              (c) => c.stockItemId == item.id,
                            ),
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${recipe.menuItemName}${recipe.variantLabel == null ? '' : ' · ${recipe.variantLabel}'}',
                              ),
                              subtitle: const Text('აქტიური რეცეპტი / მიბმა'),
                            ),
                          const SizedBox(height: 24),
                          const Text('ბოლო მოძრაობები (მაქს. 20)'),
                          if (inspection == null)
                            const Text(
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
                                  title: Text(
                                    '${m.quantityDeltaBase} ${m.baseUnit.label} · ${m.movementType.label}',
                                  ),
                                  subtitle: Text(
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
                      child: Text(
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
          title: const Text('დღის მიღებები'),
          subtitle: Text(
            day == null
                ? 'განახლება საჭიროა'
                : '${procurement?['businessDate']} · ${day['total']} ₾ · ${day['count']} მიღება',
          ),
          children: [
            const ListTile(title: Text('ბოლო 100 დადასტურებული მიღება')),
            for (final r in _rows(inspection?['receivings']))
              ListTile(
                title: Text('${r['supplierNameSnapshot']}'),
                subtitle: Text('${r['documentTotal']} ₾'),
              ),
          ],
        ),
        ExpansionTile(
          title: const Text('რეცეპტები და მიბმები'),
          children: [
            if (inspection == null)
              const ListTile(
                title: Text(
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
                        subtitle: Text(
                          item.recipe?.isActive == true
                              ? 'მიბმულია'
                              : 'მიბმა არ არის',
                        ),
                      ),
                      for (final variant in item.variants)
                        ListTile(
                          title: Text('${item.name} · ${variant.size}'),
                          subtitle: Text(
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
          title: const Text('მიუბმელი გაყიდული პროდუქტები'),
          subtitle: Text(
            inspection == null
                ? 'განახლება საჭიროა'
                : '${inspection['unmappedCount']} პროდუქტი · გაყიდვის დროს მიბმა არ ჰქონდა',
          ),
          children: [
            for (final row in _rows(inspection?['unmapped']))
              ListTile(
                title: Text(
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
