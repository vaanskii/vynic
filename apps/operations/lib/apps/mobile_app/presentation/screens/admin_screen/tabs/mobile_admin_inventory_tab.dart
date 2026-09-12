part of '../mobile_admin_screen.dart';

enum _InventorySection { stockItems, suppliers, receiving, recipes, home }

class InventoryAdminTab extends StatefulWidget {
  const InventoryAdminTab({
    super.key,
    this.loadStockItems,
    this.loadSuppliers,
    this.loadReceivings,
    this.loadRecipes,
    this.initialSection,
    this.initialStockStatus,
    this.initialBusinessDate,
  });

  final Future<List<StockItem>> Function()? loadStockItems;
  final Future<List<Supplier>> Function()? loadSuppliers;
  final Future<ReceivingPage> Function()? loadReceivings;
  final Future<List<RecipeMenuItem>> Function()? loadRecipes;

  final String? initialStockStatus;
  final String? initialBusinessDate;

  /// Destination used by Dashboard and Financials deep links.
  final int? initialSection;

  @override
  State<InventoryAdminTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryAdminTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late _InventorySection _section =
      _InventorySection.values[widget.initialSection ?? 4];
  final _search = TextEditingController();
  List<StockItem> _stockItems = const [];
  List<Supplier> _suppliers = const [];
  List<Receiving> _receivings = const [];
  List<RecipeMenuItem> _recipes = const [];
  _ReceivingStatusFilter _statusFilter = _ReceivingStatusFilter.all;
  _RecipeFilter _recipeFilter = _RecipeFilter.all;
  StockItemClassification? _classificationFilter;
  String? _menuGroupFilter;
  String? _businessDate;
  late String? _receivingDayFilter = widget.initialBusinessDate;
  late String? _stockStatusFilter = widget.initialStockStatus;
  List<ReceivingDaySummary> _receivingDays = const [];
  String? _receivingCursor;
  bool _loadingMore = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.loadStockItems?.call() ?? MobileApiService.getStockItems(),
        widget.loadSuppliers?.call() ?? MobileApiService.getSuppliers(),
        widget.loadReceivings?.call() ??
            MobileApiService.getReceivings(
              from: _receivingDayFilter,
              to: _receivingDayFilter,
            ),
        widget.loadRecipes?.call() ?? MobileApiService.getRecipeMenuItems(),
      ]);
      // Daily home reads the actual business day even when future/backdated
      // documents or pagination would otherwise displace it from history.
      final currentDay = (results[2] as ReceivingPage).currentBusinessDate;
      if (_section == _InventorySection.home &&
          widget.loadReceivings == null &&
          currentDay != null) {
        results[2] = await MobileApiService.getReceivings(
          from: currentDay,
          to: currentDay,
        );
      }
      if (!mounted) return;
      setState(() {
        _stockItems = results[0] as List<StockItem>;
        _suppliers = results[1] as List<Supplier>;
        _receivings = (results[2] as ReceivingPage).receivings;
        _businessDate = (results[2] as ReceivingPage).currentBusinessDate;
        _receivingDays = (results[2] as ReceivingPage).businessDays;
        _receivingCursor = (results[2] as ReceivingPage).nextCursor;
        _recipes = results[3] as List<RecipeMenuItem>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const _AdminLoading();
    if (_error != null) return _ErrorWidget(onRetry: _load);

    return Theme(
      data: inventoryTheme(context),
      child: RefreshIndicator(
        color: AdminTheme.primary,
        backgroundColor: AdminTheme.surface,
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 720 ? 24.0 : 16.0;
            return ListView(
              key: const Key('inventory-admin-list'),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                horizontal,
                12,
                horizontal,
                MediaQuery.paddingOf(context).bottom + 108,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_section == _InventorySection.home)
                          _inventoryHome()
                        else ...[
                          _sectionSelector(),
                          const SizedBox(height: 12),
                          _searchAndAdd(constraints.maxWidth - horizontal * 2),
                          const SizedBox(height: VynicSpacing.lg),
                          if (_section == _InventorySection.stockItems)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _catalogFilters(),
                                const SizedBox(height: 12),
                                _stockItemList(),
                              ],
                            )
                          else if (_section == _InventorySection.suppliers)
                            _supplierList()
                          else if (_section == _InventorySection.receiving)
                            _receivingList()
                          else
                            _recipeList(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _navigate(_InventorySection section) {
    setState(() {
      _section = section;
      _search.clear();
      if (section == _InventorySection.home) _receivingDayFilter = null;
    });
    if (section == _InventorySection.home ||
        section == _InventorySection.receiving)
      _load();
  }

  Widget _sectionSelector() => Row(
    children: [
      IconButton(
        tooltip: 'მარაგი',
        onPressed: () => _navigate(_InventorySection.home),
        icon: const Icon(Icons.arrow_back),
      ),
      Expanded(
        child: Text(
          switch (_section) {
            _InventorySection.suppliers => 'მომწოდებლები',
            _InventorySection.receiving => 'მიღებების ისტორია',
            _InventorySection.recipes => 'მენიუს შემადგენლობა',
            _ => 'მარაგი',
          },
          style: TextStyle(
            color: AdminTheme.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  Widget _inventoryHome() {
    final today = _businessDate;
    final receipts = _receivings
        .where((r) => r.effectiveBusinessDate == today)
        .toList();
    final active = _stockItems.where((i) => i.isActive).toList()
      ..sort(
        (a, b) =>
            (a.stockStatus == 'NEGATIVE'
                    ? 0
                    : a.stockStatus == 'LOW'
                    ? 1
                    : 2)
                .compareTo(
                  b.stockStatus == 'NEGATIVE'
                      ? 0
                      : b.stockStatus == 'LOW'
                      ? 1
                      : 2,
                ),
      );
    return Column(
      key: const Key('inventory-home'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'მარაგი',
          style: TextStyle(
            color: AdminTheme.text,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('inventory-add'),
          onPressed: () => _editReceiving(),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.add),
          label: const Text('ახალი მიღება'),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth < 600
                ? box.maxWidth
                : (box.maxWidth - 32) / 3;
            return Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _homeMetric(
                  'დღეს მივიღეთ',
                  today == null
                      ? 'სამუშაო დღე უცნობია'
                      : '${_todayTotal(today)} ₾',
                  width,
                ),
                _homeMetric(
                  'დაბალი მარაგი',
                  '${active.where((i) => i.stockStatus == 'LOW').length} პროდუქტი',
                  width,
                ),
                _homeMetric(
                  'უარყოფითი მარაგი',
                  '${active.where((i) => i.stockStatus == 'NEGATIVE').length} პროდუქტი',
                  width,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _homeHeading('დღევანდელი მიღებები'),
        if (receipts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'დღეს მიღება ჯერ არ არის',
              style: TextStyle(color: AdminTheme.textMuted),
            ),
          ),
        for (final receipt in receipts)
          _ReceivingCard(
            receiving: receipt,
            onOpen: () => _openReceiving(receipt),
          ),
        TextButton(
          onPressed: () => _navigate(_InventorySection.receiving),
          child: const Text('მიღებების ისტორია'),
        ),
        const SizedBox(height: 24),
        _homeHeading('მარაგის მდგომარეობა'),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: _adminInput(
            'პროდუქტის ძებნა',
          ).copyWith(prefixIcon: const Icon(Icons.search)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (active.isEmpty)
          Text(
            'დაამატეთ საქონელი მომწოდებლის გვერდიდან ან შექმენით ნედლეული მენიუს შემადგენლობაში.',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        for (final item in active.where(
          (i) => i.name.toLowerCase().contains(_search.text.toLowerCase()),
        ))
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              onTap: () => _openStockItem(item),
              title: Text(item.name),
              subtitle: Text(
                'მარაგშია: ${_quantityText(item.currentStock)} ${_unitShort(item.baseUnit)}'
                '${item.stockStatus == 'NEGATIVE'
                    ? '\nუარყოფითი მარაგი'
                    : item.stockStatus == 'LOW'
                    ? '\nდაბალი მარაგი'
                    : ''}',
                style: TextStyle(
                  color: item.stockStatus == 'NEGATIVE'
                      ? AdminTheme.bad
                      : AdminTheme.textMuted,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        TextButton(
          onPressed: () => _navigate(_InventorySection.stockItems),
          child: const Text('მარაგის მართვა'),
        ),
        const SizedBox(height: 24),
        _homeHeading('სწრაფი მართვა'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('მომწოდებლები'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _navigate(_InventorySection.suppliers),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('მენიუს შემადგენლობა'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _navigate(_InventorySection.recipes),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('გადახდები და დავალიანება'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const SupplierPayablesDialog(),
          ),
        ),
        ListTile(
          key: const Key('inventory-consumption-history'),
          contentPadding: EdgeInsets.zero,
          title: const Text('ჩამოწერების ისტორია'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ConsumptionHistoryScreen(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _homeHeading(String title) => Text(
    title,
    style: TextStyle(
      color: AdminTheme.text,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  );
  Widget _homeMetric(String title, String value, double width) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: AdminTheme.textMuted)),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: AdminTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _searchAndAdd(double width) {
    final search = TextField(
      key: const Key('inventory-search'),
      controller: _search,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: AdminTheme.text),
      decoration:
          _adminInput(switch (_section) {
            _InventorySection.receiving => 'ძებნა ზედნადებით ან მომწოდებლით',
            _InventorySection.recipes => 'ძებნა კერძის სახელით',
            _ => 'ძებნა სახელით ან კოდით',
          }).copyWith(
            prefixIcon: Icon(Icons.search_rounded, color: AdminTheme.textDim),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'გასუფთავება',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
    );
    // Recipes have no "add": a definition always starts from a product the
    // venue already sells, so the list itself is the entry point.
    if (_section == _InventorySection.recipes) return search;
    final add = FilledButton.icon(
      key: const Key('inventory-add'),
      onPressed: switch (_section) {
        _InventorySection.stockItems => () => _editStockItem(),
        _InventorySection.suppliers => () => _editSupplier(),
        _InventorySection.receiving => () => _editReceiving(),
        _InventorySection.recipes => null,
        _InventorySection.home => () => _editReceiving(),
      },
      icon: const Icon(Icons.add_rounded),
      label: Text(switch (_section) {
        _InventorySection.stockItems => 'ახალი პროდუქტი',
        _InventorySection.suppliers => 'ახალი მომწოდებელი',
        _InventorySection.receiving => 'ახალი მიღება',
        _InventorySection.recipes => '',
        _InventorySection.home => 'ახალი მიღება',
      }),
      style: FilledButton.styleFrom(
        backgroundColor: AdminTheme.primary,
        foregroundColor: _inventoryOnPrimary,
        minimumSize: const Size(0, 52),
      ),
    );
    if (width < 620) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: VynicSpacing.sm),
          add,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 12),
        add,
      ],
    );
  }

  Widget _catalogFilters() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      ChoiceChip(
        label: const Text('ყველა'),
        selected: _classificationFilter == null,
        onSelected: (_) => setState(() => _classificationFilter = null),
      ),
      if (_stockStatusFilter != null)
        InputChip(
          label: Text(
            _stockStatusFilter == 'LOW' ? 'დაბალი მარაგი' : 'უარყოფითი მარაგი',
          ),
          onDeleted: () => setState(() => _stockStatusFilter = null),
        ),
      for (final value in StockItemClassification.values)
        ChoiceChip(
          label: Text(value.label),
          selected: _classificationFilter == value,
          onSelected: (_) => setState(() => _classificationFilter = value),
        ),
    ],
  );

  Widget _stockItemList() {
    final query = _search.text.trim().toLowerCase();
    final items = _stockItems
        .where((item) {
          if (_stockStatusFilter != null &&
              (!item.isActive || item.stockStatus != _stockStatusFilter))
            return false;
          if (_classificationFilter != null &&
              item.classification != _classificationFilter)
            return false;
          return query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              (item.sku?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    if (items.isEmpty) {
      return _InventoryEmptyState(
        icon: Icons.inventory_2_outlined,
        title: query.isEmpty
            ? 'საწყობის პროდუქტები ჯერ არ არის'
            : 'შესაბამისი პროდუქტი ვერ მოიძებნა',
        subtitle: query.isEmpty
            ? 'დაამატეთ ინგრედიენტი ან შეფუთული პროდუქტი.'
            : 'შეცვალეთ საძიებო სიტყვა.',
      );
    }
    return Column(
      key: const Key('stock-item-list'),
      children: [
        for (final item in items)
          _StockItemCard(
            item: item,
            onEdit: () => _editStockItem(item),
            onToggle: () => _toggleStockItem(item),
            onOpen: () => _openStockItem(item),
          ),
      ],
    );
  }

  Widget _supplierList() {
    final query = _search.text.trim().toLowerCase();
    final items = _suppliers
        .where((supplier) {
          return query.isEmpty ||
              supplier.name.toLowerCase().contains(query) ||
              (supplier.taxId?.toLowerCase().contains(query) ?? false) ||
              (supplier.phone?.toLowerCase().contains(query) ?? false) ||
              (supplier.email?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    if (items.isEmpty) {
      return _InventoryEmptyState(
        icon: Icons.local_shipping_outlined,
        title: query.isEmpty
            ? 'მომწოდებლები ჯერ არ არის'
            : 'შესაბამისი მომწოდებელი ვერ მოიძებნა',
        subtitle: query.isEmpty
            ? 'დაამატეთ კომპანია ან პირი, ვისგანაც პროდუქტს ყიდულობთ.'
            : 'შეცვალეთ საძიებო სიტყვა.',
      );
    }
    return Column(
      key: const Key('supplier-list'),
      children: [
        for (final supplier in items)
          _SupplierCard(
            supplier: supplier,
            onOpen: () => _openSupplier(supplier),
            onAddGoods: () => _addSupplierGoods(supplier),
            onEdit: () => _editSupplier(supplier),
            onToggle: () => _toggleSupplier(supplier),
          ),
      ],
    );
  }

  Future<void> _moreReceivings() async {
    setState(() => _loadingMore = true);
    try {
      final page = await MobileApiService.getReceivings(
        cursor: _receivingCursor,
        from: _receivingDayFilter,
        to: _receivingDayFilter,
      );
      if (!mounted) return;
      setState(() {
        _receivings = [..._receivings, ...page.receivings];
        _receivingDays = [
          ..._receivingDays.where(
            (day) => !page.businessDays.any(
              (next) => next.businessDate == day.businessDate,
            ),
          ),
          ...page.businessDays,
        ];
        _receivingCursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted) _adminToast(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _addSupplierGoods(Supplier supplier) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => SuppliedItemDialog(
        supplierId: supplier.id,
        supplierName: supplier.name,
        stockItems: _stockItems,
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openSupplier(Supplier supplier) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          SupplierDetailDialog(supplier: supplier, stockItems: _stockItems),
    );
    if (mounted) await _load();
  }

  Future<void> _editStockItem([StockItem? item]) async {
    final saved = await showDialog<StockItem>(
      context: context,
      builder: (_) => _StockItemEditorDialog(item: item, suppliers: _suppliers),
    );
    if (saved != null) {
      _adminToast(
        context,
        item == null ? 'პროდუქტი დაემატა' : 'პროდუქტი განახლდა',
      );
      await _load();
    }
  }

  Future<void> _editSupplier([Supplier? supplier]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierEditorDialog(supplier: supplier),
    );
    if (saved == true) {
      _adminToast(
        context,
        supplier == null ? 'მომწოდებელი დაემატა' : 'მომწოდებელი განახლდა',
      );
      await _load();
    }
  }

  Future<void> _toggleStockItem(StockItem item) async {
    try {
      await MobileApiService.saveStockItem(
        id: item.id,
        name: item.name,
        sku: item.sku,
        baseUnit: item.baseUnit,
        minimumStock: item.minimumStock,
        notes: item.notes,
        isActive: !item.isActive,
      );
      if (!mounted) return;
      _adminToast(
        context,
        item.isActive ? 'პროდუქტი გაითიშა' : 'პროდუქტი გააქტიურდა',
      );
      await _load();
    } catch (error) {
      if (mounted) _adminToast(context, '$error', error: true);
    }
  }

  Widget _receivingList() {
    final query = _search.text.trim().toLowerCase();
    final items = _receivings
        .where((receiving) {
          if (!_statusFilter.matches(receiving.status)) return false;
          return query.isEmpty ||
              receiving.supplierName.toLowerCase().contains(query) ||
              (receiving.waybillNumber?.toLowerCase().contains(query) ??
                  false) ||
              (receiving.invoiceNumber?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    return Column(
      key: const Key('receiving-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_businessDate != null)
          Text(
            'სამუშაო დღე: $_businessDate',
            style: TextStyle(color: AdminTheme.text),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_receivingDayFilter ?? 'სამუშაო დღის არჩევა'),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(
                        _receivingDayFilter ?? _businessDate ?? '',
                      ) ??
                      DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 366)),
                );
                if (date != null) {
                  _receivingDayFilter = _isoDate(date);
                  await _load();
                }
              },
            ),
            if (_receivingDayFilter != null)
              TextButton(
                onPressed: () {
                  _receivingDayFilter = null;
                  _load();
                },
                child: const Text('ყველა დღე'),
              ),
          ],
        ),
        _ReceivingStatusFilterBar(
          selected: _statusFilter,
          onChanged: (value) => setState(() => _statusFilter = value),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _InventoryEmptyState(
            icon: Icons.receipt_long_outlined,
            title: query.isEmpty && _statusFilter == _ReceivingStatusFilter.all
                ? 'მიღებები ჯერ არ არის'
                : 'შესაბამისი დოკუმენტი ვერ მოიძებნა',
            subtitle:
                query.isEmpty && _statusFilter == _ReceivingStatusFilter.all
                ? 'დაამატეთ ზედნადები და აღრიცხეთ მიღებული პროდუქტი.'
                : 'შეცვალეთ ფილტრი ან საძიებო სიტყვა.',
          )
        else
          for (var index = 0; index < items.length; index++) ...[
            if (index == 0 ||
                items[index - 1].effectiveBusinessDate !=
                    items[index].effectiveBusinessDate)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'სამუშაო დღე: ${items[index].effectiveBusinessDate}${_dayTotal(items[index].effectiveBusinessDate)}',
                  style: TextStyle(
                    color: AdminTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            _ReceivingCard(
              receiving: items[index],
              onOpen: () => _openReceiving(items[index]),
            ),
          ],
        if (_receivingCursor != null)
          TextButton(
            onPressed: _loadingMore ? null : _moreReceivings,
            child: Text(_loadingMore ? 'იტვირთება…' : 'მეტი მიღების ნახვა'),
          ),
      ],
    );
  }

  String _todayTotal(String date) {
    final summary = _receivingDays
        .where(
          (r) => r.businessDate == date && r.status == ReceivingStatus.posted,
        )
        .firstOrNull;
    if (summary != null) return summary.total;
    return _receivings
        .where((r) => r.effectiveBusinessDate == date && r.isPosted)
        .fold(
          InventoryDecimal.zero,
          (total, row) => total + InventoryDecimal.parse(row.documentTotal),
        )
        .toStringAsFixed(2);
  }

  String _dayTotal(String date) {
    final day = _receivingDays
        .where(
          (row) =>
              row.businessDate == date && row.status == ReceivingStatus.posted,
        )
        .firstOrNull;
    return day == null
        ? ''
        : '\nდადასტურებული: ${day.count} მიღება · ${day.total} ₾';
  }

  Widget _recipeList() {
    final query = _search.text.trim().toLowerCase();
    final items = _recipes
        .where((item) {
          if (!_recipeFilter.matches(item)) return false;
          if (_menuGroupFilter != null && item.menuGroup != _menuGroupFilter)
            return false;
          return query.isEmpty || item.name.toLowerCase().contains(query);
        })
        .toList(growable: false);
    return Column(
      key: const Key('recipe-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in const <String, String>{
              '': 'ყველა',
              'FOOD': 'კერძები',
              'BEVERAGE': 'სასმელები',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: (_menuGroupFilter ?? '') == entry.key,
                onSelected: (_) => setState(
                  () => _menuGroupFilter = entry.key.isEmpty ? null : entry.key,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Expansion booleans must not share the ancestor's scroll-offset entry.
        ExpansionTile(
          key: const PageStorageKey('inventory-composition-status'),
          tilePadding: EdgeInsets.zero,
          title: const Text('შემადგენლობის სტატუსი'),
          children: [
            _InventoryExpansionContents(
              children: [
                _RecipeFilterBar(
                  selected: _recipeFilter,
                  onChanged: (value) => setState(() => _recipeFilter = value),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _InventoryEmptyState(
            icon: Icons.menu_book_outlined,
            title: query.isEmpty && _recipeFilter == _RecipeFilter.all
                ? 'მენიუ ჯერ არ არის'
                : 'შესაბამისი კერძი ვერ მოიძებნა',
            subtitle: query.isEmpty && _recipeFilter == _RecipeFilter.all
                ? 'აირჩიეთ მენიუს პროდუქტი.'
                : 'შეცვალეთ ფილტრი ან საძიებო სიტყვა.',
          )
        else
          for (final item in items)
            _RecipeCard(
              item: item,
              onOpen: (variant) => _openRecipe(item, variant),
            ),
      ],
    );
  }

  Future<void> _openRecipe(
    RecipeMenuItem item,
    RecipeMenuVariant? variant,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RecipeEditorDialog(
        menuItemId: item.menuItemId,
        menuItemName: item.name,
        menuGroup: item.menuGroup,
        variantId: variant?.variantId,
        variantLabel: variant?.label,
        stockItems: _stockItems,
        onCreateStockItem: (name) => _createStockItemFor(
          name,
          item.menuGroup == 'BEVERAGE'
              ? StockItemClassification.beverage
              : StockItemClassification.food,
        ),
      ),
    );
    if (saved == true) {
      if (mounted) _adminToast(context, 'შემადგენლობა შენახულია');
      await _load();
    }
  }

  /// Opens the Stock Item editor pre-filled with the Menu Item's name and
  /// nothing else. Unit, packaging and threshold stay real decisions, and the
  /// created row gets its own identity — a Menu Item is never a Stock Item.
  Future<StockItem?> _createStockItemFor(
    String prefillName,
    StockItemClassification initialClassification,
  ) async {
    final created = await showDialog<StockItem>(
      context: context,
      builder: (_) => IngredientQuickDialog(
        initialName: prefillName,
        classification: initialClassification,
      ),
    );
    if (created != null) {
      setState(() => _stockItems = [..._stockItems, created]);
    }
    return created;
  }

  Future<void> _editReceiving([Receiving? receiving]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ReceivingEditorDialog(
        receiving: receiving,
        businessDate: _businessDate,
        suppliers: _suppliers.where((supplier) => supplier.isActive).toList(),
        stockItems: _stockItems.where((item) => item.isActive).toList(),
      ),
    );
    if (saved == true) {
      if (mounted) {
        _adminToast(
          context,
          receiving == null ? 'მიღება შეიქმნა' : 'მიღება განახლდა',
        );
      }
    }
    if (mounted) await _load();
  }

  Future<void> _openReceiving(Receiving receiving) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ReceivingDetailDialog(
        receivingId: receiving.id,
        onEditDraft: (draft) async {
          Navigator.pop(context, false);
          await _editReceiving(draft);
        },
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openStockItem(StockItem item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StockItemDetailDialog(stockItemId: item.id),
    );
  }

  Future<void> _toggleSupplier(Supplier supplier) async {
    try {
      await MobileApiService.saveSupplier(
        id: supplier.id,
        name: supplier.name,
        taxId: supplier.taxId,
        phone: supplier.phone,
        email: supplier.email,
        address: supplier.address,
        notes: supplier.notes,
        isActive: !supplier.isActive,
      );
      if (!mounted) return;
      _adminToast(
        context,
        supplier.isActive ? 'მომწოდებელი გაითიშა' : 'მომწოდებელი გააქტიურდა',
      );
      await _load();
    } catch (error) {
      if (mounted) _adminToast(context, '$error', error: true);
    }
  }
}

class _StockItemCard extends StatelessWidget {
  const _StockItemCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onOpen,
  });

  final StockItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VynicSpacing.sm),
      child: _AdminPanel(
        padding: const EdgeInsets.all(VynicSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: AdminTheme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: VynicSpacing.xs),
                Wrap(
                  spacing: VynicSpacing.xs,
                  runSpacing: VynicSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'მარაგშია: ${_quantityText(item.currentStock)} ${_unitShort(item.baseUnit)}',
                      style: TextStyle(
                        color: item.isNegativeStock
                            ? AdminTheme.bad
                            : AdminTheme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.isNegativeStock)
                      Text(
                        'უარყოფითი მარაგი',
                        style: TextStyle(
                          color: AdminTheme.bad,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else if (item.isLowStock)
                      const _LowStockBadge(),
                    if (!item.isActive)
                      const _InventoryStateBadge(active: false),
                  ],
                ),
                const SizedBox(height: VynicSpacing.sm),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _InventoryMeta(
                      icon: Icons.local_shipping_outlined,
                      label: 'მომწოდებლები: ${item.supplierIds.length}',
                    ),
                    if (item.lastPurchaseUnitCost != null)
                      _InventoryMeta(
                        icon: Icons.payments_outlined,
                        label:
                            'ბოლო ფასი: ${_quantityText(item.lastPurchaseUnitCost!)} ₾ / ${item.baseUnit.label}',
                      ),
                    if (item.minimumStock != null)
                      _InventoryMeta(
                        icon: Icons.notification_important_outlined,
                        label:
                            'მინიმალური მარაგი: ${_quantity(item.minimumStock!)} ${_unitShort(item.baseUnit)}',
                      ),
                    if (item.sku != null)
                      _InventoryMeta(
                        icon: Icons.qr_code_rounded,
                        label: 'კოდი: ${item.sku}',
                      ),
                  ],
                ),
              ],
            );
            final actions = _InventoryActions(
              active: item.isActive,
              onEdit: onEdit,
              onToggle: onToggle,
              onOpen: onOpen,
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: VynicSpacing.sm),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.onOpen,
    required this.onAddGoods,
    required this.supplier,
    required this.onEdit,
    required this.onToggle,
  });

  final Supplier supplier;
  final VoidCallback onOpen;
  final VoidCallback onAddGoods;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (supplier.taxId != null) 'ს/კ ${supplier.taxId}',
      if (supplier.phone != null) supplier.phone!,
      if (supplier.email != null) supplier.email!,
      if (supplier.address != null) supplier.address!,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: VynicSpacing.sm),
      child: _AdminPanel(
        padding: const EdgeInsets.all(VynicSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        supplier.name,
                        style: TextStyle(
                          color: AdminTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _InventoryStateBadge(active: supplier.isActive),
                  ],
                ),
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(
                    'მისი პროდუქტები (${supplier.stockItemIds.length})',
                  ),
                ),
                OutlinedButton.icon(
                  key: Key('supplier-add-goods-${supplier.id}'),
                  onPressed: supplier.isActive ? onAddGoods : null,
                  icon: const Icon(Icons.add),
                  label: const Text('საქონლის დამატება'),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    details.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
                  ),
                ],
              ],
            );
            final actions = _InventoryActions(
              active: supplier.isActive,
              onEdit: onEdit,
              onToggle: onToggle,
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: VynicSpacing.sm),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InventoryActions extends StatelessWidget {
  const _InventoryActions({
    required this.active,
    required this.onEdit,
    required this.onToggle,
    this.onOpen,
  });

  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    // Bounded so the row beside it keeps its width: three actions would
    // otherwise take their full intrinsic line and overflow a wide card.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.end,
        children: [
          if (onOpen != null)
            TextButton.icon(
              key: const Key('stock-item-open'),
              onPressed: onOpen,
              icon: const Icon(Icons.history_rounded, size: 17),
              label: const Text('მოძრაობები'),
              style: TextButton.styleFrom(
                foregroundColor: AdminTheme.textMuted,
              ),
            ),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('რედაქტირება'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminTheme.text,
              side: BorderSide(color: AdminTheme.border),
            ),
          ),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              foregroundColor: active ? AdminTheme.warn : AdminTheme.good,
            ),
            child: Text(active ? 'გათიშვა' : 'გააქტიურება'),
          ),
        ],
      ),
    );
  }
}

class _InventoryStateBadge extends StatelessWidget {
  const _InventoryStateBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AdminTheme.good : AdminTheme.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'აქტიური' : 'გათიშული',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InventoryMeta extends StatelessWidget {
  const _InventoryMeta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = AdminTheme.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AdminTheme.textDim),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown only when a threshold is configured and Cloud says it is reached.
class _LowStockBadge extends StatelessWidget {
  const _LowStockBadge();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('low-stock-badge'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AdminTheme.warn.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'მარაგი მცირდება',
      style: TextStyle(
        color: AdminTheme.warn,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _InventoryEmptyState extends StatelessWidget {
  const _InventoryEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => _AdminPanel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AdminTheme.textDim),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AdminTheme.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _StockItemEditorDialog extends StatefulWidget {
  const _StockItemEditorDialog({this.item, this.suppliers = const []});
  final List<Supplier> suppliers;
  final StockItem? item;

  @override
  State<_StockItemEditorDialog> createState() => _StockItemEditorDialogState();
}

class _StockItemEditorDialogState extends State<_StockItemEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _minimum;
  late final TextEditingController _notes;
  late InventoryUnit _unit;
  late StockItemClassification _classification;
  late Set<String> _supplierIds;
  late bool _active;
  late List<_PurchaseUnitDraft> _purchaseUnits;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _sku = TextEditingController(text: item?.sku ?? '');
    _minimum = TextEditingController(
      text: item?.minimumStock == null ? '' : _quantity(item!.minimumStock!),
    );
    _notes = TextEditingController(text: item?.notes ?? '');
    _unit = item?.baseUnit ?? InventoryUnit.kg;
    _classification = item?.classification ?? StockItemClassification.food;
    _supplierIds = {...?item?.supplierIds};
    _active = item?.isActive ?? true;
    _purchaseUnits = [
      for (final unit in item?.purchaseUnits ?? const <StockItemPurchaseUnit>[])
        _PurchaseUnitDraft(
          unit: unit.unit,
          multiplier: TextEditingController(text: unit.baseUnitMultiplier),
        ),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _minimum.dispose();
    _notes.dispose();
    for (final draft in _purchaseUnits) {
      draft.multiplier.dispose();
    }
    super.dispose();
  }

  /// Item-specific packaging: "1 box = 24 bottle" for this product only.
  Widget _purchaseUnitEditor() {
    return Column(
      key: const Key('purchase-unit-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'როგორ მოდის მომწოდებლისგან?',
            style: TextStyle(
              color: AdminTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'მაგ. 1 ყუთი = 24 ${_unitShort(_unit)}. ეს რაოდენობა მხოლოდ ამ პროდუქტს ეხება.',
            style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < _purchaseUnits.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<InventoryUnit>(
                    initialValue: _purchaseUnits[index].unit,
                    isExpanded: true,
                    dropdownColor: AdminTheme.surfaceElevated,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: AdminTheme.text,
                      fontSize: 13,
                    ),
                    decoration: _adminInput('ერთეული'),
                    items: [
                      for (final unit in InventoryUnit.values)
                        if (unit != _unit)
                          DropdownMenuItem(
                            value: unit,
                            child: Text(_unitShort(unit)),
                          ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            if (value != null) {
                              _purchaseUnits[index].unit = value;
                            }
                          }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _purchaseUnits[index].multiplier,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: AdminTheme.text),
                    decoration: _adminInput(
                      '1 ${_purchaseUnits[index].unit.label} =',
                    ).copyWith(suffixText: _unit.label),
                  ),
                ),
                IconButton(
                  tooltip: 'წაშლა',
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _purchaseUnits.removeAt(index).multiplier.dispose();
                        }),
                  icon: Icon(Icons.close_rounded, color: AdminTheme.textDim),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('purchase-unit-add'),
            onPressed: _saving || _availablePurchaseUnit() == null
                ? null
                : () => setState(() {
                    _purchaseUnits.add(
                      _PurchaseUnitDraft(
                        unit: _availablePurchaseUnit()!,
                        multiplier: TextEditingController(),
                      ),
                    );
                  }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('შეფუთვის დამატება'),
            style: TextButton.styleFrom(foregroundColor: AdminTheme.primary),
          ),
        ),
      ],
    );
  }

  InventoryUnit? _availablePurchaseUnit() {
    final used = _purchaseUnits.map((draft) => draft.unit).toSet()..add(_unit);
    for (final unit in [
      InventoryUnit.pack,
      InventoryUnit.box,
      InventoryUnit.keg,
      InventoryUnit.bottle,
      InventoryUnit.piece,
      InventoryUnit.kg,
      InventoryUnit.g,
      InventoryUnit.liter,
      InventoryUnit.ml,
    ]) {
      if (!used.contains(unit)) return unit;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(VynicSpacing.md),
        contentPadding: const EdgeInsets.all(VynicSpacing.md),
        key: const Key('stock-item-editor'),
        backgroundColor: AdminTheme.surface,
        title: Text(
          widget.item == null ? 'ახალი პროდუქტი' : 'პროდუქტის რედაქტირება',
          style: TextStyle(color: AdminTheme.text),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: (MediaQuery.sizeOf(context).width - 64).clamp(0, 520),
            maxWidth: 520,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(
                  _name,
                  'დასახელება *',
                  key: const Key('stock-name'),
                ),
                DropdownButtonFormField<StockItemClassification>(
                  key: const Key('stock-classification'),
                  initialValue: _classification,
                  isExpanded: true,
                  decoration: _adminInput('ტიპი'),
                  dropdownColor: AdminTheme.surfaceElevated,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: AdminTheme.text),
                  items: [
                    for (final value in StockItemClassification.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          value == StockItemClassification.food
                              ? 'საკვები'
                              : 'სასმელი',
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _classification = value!),
                ),
                const SizedBox(height: VynicSpacing.sm),
                _dialogField(_sku, 'პროდუქტის კოდი'),
                DropdownButtonFormField<InventoryUnit>(
                  initialValue: _unit,
                  dropdownColor: AdminTheme.surfaceElevated,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: AdminTheme.text),
                  decoration: _adminInput('როგორ ვითვლით საწყობში?'),
                  items: [
                    for (final unit in InventoryUnit.values.where(
                      (unit) => unit != InventoryUnit.keg,
                    ))
                      DropdownMenuItem(
                        value: unit,
                        child: Text(_unitLabel(unit)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _unit = value ?? _unit),
                ),
                _dialogField(
                  _minimum,
                  'მინიმალური მარაგი',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                // A threshold, not a balance. Said plainly, because the two are
                // easy to confuse and one of them is derived from the ledger.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: VynicSpacing.sm),
                    child: Text(
                      'ამ რაოდენობაზე ნაკლების შემთხვევაში გამოჩნდება '
                      'დაბალი მარაგის გაფრთხილება.',
                      key: const Key('minimum-stock-help'),
                      style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
                    ),
                  ),
                ),
                _dialogField(_notes, 'შენიშვნა', maxLines: 3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'მომწოდებლები',
                    style: TextStyle(color: AdminTheme.textMuted),
                  ),
                ),
                if (widget.suppliers.isEmpty)
                  Text(
                    'ჯერ დაამატეთ მომწოდებელი მომწოდებლების განყოფილებაში.',
                    style: TextStyle(color: AdminTheme.textMuted),
                  ),
                for (final supplier in widget.suppliers)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      supplier.name,
                      style: TextStyle(color: AdminTheme.text),
                    ),
                    value: _supplierIds.contains(supplier.id),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _supplierIds.add(supplier.id);
                            } else {
                              _supplierIds.remove(supplier.id);
                            }
                          }),
                  ),
                _purchaseUnitEditor(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'აქტიური',
                    style: TextStyle(color: AdminTheme.text),
                  ),
                  value: _active,
                  activeTrackColor: AdminTheme.primary,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _active = value),
                ),
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(color: AdminTheme.bad, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            // No result: this dialog answers with the saved Stock Item or with
            // nothing at all.
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(
              'გაუქმება',
              style: TextStyle(color: AdminTheme.textMuted),
            ),
          ),
          FilledButton(
            key: const Key('stock-save'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
            child: _saving
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _inventoryOnPrimary,
                    ),
                  )
                : Text('შენახვა', style: TextStyle(color: _inventoryOnPrimary)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final minimumText = _minimum.text.trim().replaceAll(',', '.');
    final minimum = minimumText.isEmpty ? null : double.tryParse(minimumText);
    if (name.isEmpty) {
      setState(() => _error = 'სახელი სავალდებულოა');
      return;
    }
    if (minimumText.isNotEmpty && (minimum == null || minimum < 0)) {
      setState(
        () => _error = 'მინიმალური მარაგი უნდა იყოს არაუარყოფითი რიცხვი',
      );
      return;
    }
    final purchaseUnits = <StockItemPurchaseUnit>[];
    for (final draft in _purchaseUnits) {
      final text = draft.multiplier.text.trim().replaceAll(',', '.');
      final value = double.tryParse(text);
      if (value == null || value <= 0) {
        setState(
          () => _error =
              '${draft.unit.label}: შეფუთვაში რაოდენობა უნდა იყოს დადებითი',
        );
        return;
      }
      purchaseUnits.add(
        StockItemPurchaseUnit(
          id: '',
          unit: draft.unit,
          baseUnitMultiplier: text,
        ),
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await MobileApiService.saveStockItem(
        id: widget.item?.id,
        name: name,
        sku: _sku.text,
        baseUnit: _unit,
        classification: _classification,
        supplierIds: _supplierIds.toList(),
        minimumStock: minimum,
        notes: _notes.text,
        isActive: _active,
        purchaseUnits: purchaseUnits,
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

class _SupplierEditorDialog extends StatefulWidget {
  const _SupplierEditorDialog({this.supplier});
  final Supplier? supplier;

  @override
  State<_SupplierEditorDialog> createState() => _SupplierEditorDialogState();
}

class _SupplierEditorDialogState extends State<_SupplierEditorDialog> {
  late final Map<String, TextEditingController> _fields;
  late bool _active;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _fields = {
      'name': TextEditingController(text: supplier?.name ?? ''),
      'taxId': TextEditingController(text: supplier?.taxId ?? ''),
      'phone': TextEditingController(text: supplier?.phone ?? ''),
      'email': TextEditingController(text: supplier?.email ?? ''),
      'address': TextEditingController(text: supplier?.address ?? ''),
      'notes': TextEditingController(text: supplier?.notes ?? ''),
    };
    _active = supplier?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(VynicSpacing.md),
        contentPadding: const EdgeInsets.all(VynicSpacing.md),
        key: const Key('supplier-editor'),
        backgroundColor: AdminTheme.surface,
        title: Text(
          widget.supplier == null
              ? 'ახალი მომწოდებელი'
              : 'მომწოდებლის რედაქტირება',
          style: TextStyle(color: AdminTheme.text),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: (MediaQuery.sizeOf(context).width - 64).clamp(0, 520),
            maxWidth: 520,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(
                  _fields['name']!,
                  'სახელი *',
                  key: const Key('supplier-name'),
                ),
                _dialogField(_fields['taxId']!, 'საგადასახადო კოდი'),
                _dialogField(
                  _fields['phone']!,
                  'ტელეფონი',
                  keyboardType: TextInputType.phone,
                ),
                _dialogField(
                  _fields['email']!,
                  'ელფოსტა',
                  keyboardType: TextInputType.emailAddress,
                ),
                _dialogField(_fields['address']!, 'მისამართი'),
                _dialogField(_fields['notes']!, 'შენიშვნა', maxLines: 3),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'აქტიური',
                    style: TextStyle(color: AdminTheme.text),
                  ),
                  value: _active,
                  activeTrackColor: AdminTheme.primary,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _active = value),
                ),
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(color: AdminTheme.bad, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(
              'გაუქმება',
              style: TextStyle(color: AdminTheme.textMuted),
            ),
          ),
          FilledButton(
            key: const Key('supplier-save'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
            child: _saving
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _inventoryOnPrimary,
                    ),
                  )
                : Text('შენახვა', style: TextStyle(color: _inventoryOnPrimary)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _fields['name']!.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'სახელი სავალდებულოა');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await MobileApiService.saveSupplier(
        id: widget.supplier?.id,
        name: name,
        taxId: _fields['taxId']!.text,
        phone: _fields['phone']!.text,
        email: _fields['email']!.text,
        address: _fields['address']!.text,
        notes: _fields['notes']!.text,
        isActive: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

Widget _dialogField(
  TextEditingController controller,
  String label, {
  Key? key,
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: VynicSpacing.sm),
    child: TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: AdminTheme.text),
      decoration: _adminInput(label),
    ),
  );
}

/// Trims Cloud's fixed-scale decimal text for display without re-rounding it.
String _quantityText(String exact) {
  if (!exact.contains('.')) return exact;
  final trimmed = exact.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

String _quantity(double value) {
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// One packaging row being edited, before it is validated into a ratio.
class _PurchaseUnitDraft {
  _PurchaseUnitDraft({required this.unit, required this.multiplier});

  InventoryUnit unit;
  final TextEditingController multiplier;
}

/// What restaurant staff read. Storage and the wire keep the stable English
/// codes; only the label is translated, so no enum value depends on language.
String _unitShort(InventoryUnit unit) => unit.label;

/// The long form, for a dropdown where the choice needs spelling out.
String _unitLabel(InventoryUnit unit) {
  switch (unit) {
    case InventoryUnit.kg:
      return 'კილოგრამი (კგ)';
    case InventoryUnit.g:
      return 'გრამი (გ)';
    case InventoryUnit.liter:
      return 'ლიტრი (ლ)';
    case InventoryUnit.ml:
      return 'მილილიტრი (მლ)';
    case InventoryUnit.piece:
      return 'ცალი';
    case InventoryUnit.bottle:
      return 'ბოთლი';
    case InventoryUnit.pack:
      return 'შეკვრა';
    case InventoryUnit.keg:
      return 'კეგი';
    case InventoryUnit.box:
      return 'ყუთი';
  }
}

class SupplierDetailDialog extends StatefulWidget {
  const SupplierDetailDialog({
    super.key,
    required this.supplier,
    required this.stockItems,
    this.load,
    this.setLink,
  });
  final Supplier supplier;
  final List<StockItem> stockItems;
  final Future<Map<String, dynamic>> Function()? load;
  final Future<void> Function(String stockItemId, bool linked)? setLink;
  @override
  State<SupplierDetailDialog> createState() => _SupplierDetailDialogState();
}

class _SupplierDetailDialogState extends State<SupplierDetailDialog> {
  Map<String, dynamic>? _detail;
  String? _error;
  String _search = '';
  bool _busy = false;
  bool _selecting = false;
  List<StockItem>? _freshStock;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await (widget.load?.call() ??
              MobileApiService.getSupplierDetail(widget.supplier.id));
      if (mounted)
        setState(() {
          _detail = detail;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _link(String id, bool linked) async {
    setState(() => _busy = true);
    try {
      await (widget.setLink?.call(id, linked) ??
          MobileApiService.setSupplierProduct(widget.supplier.id, id, linked));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newReceiving() async {
    setState(() => _busy = true);
    try {
      final stock = await MobileApiService.getStockItems();
      final suppliers = await MobileApiService.getSuppliers();
      final page = await MobileApiService.getReceivings();
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (_) => ReceivingEditorDialog(
          suppliers: suppliers
              .where((s) => s.id == widget.supplier.id)
              .toList(),
          stockItems: stock,
          businessDate: page.currentBusinessDate,
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGoods() async {
    setState(() => _busy = true);
    try {
      final changed = await showDialog<bool>(
        context: context,
        builder: (_) => SuppliedItemDialog(
          supplierId: widget.supplier.id,
          supplierName: widget.supplier.name,
          stockItems: _freshStock ?? widget.stockItems,
        ),
      );
      if (changed == true) {
        _freshStock = await MobileApiService.getStockItems();
        await _load();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useInDish(String stockId) async {
    setState(() => _busy = true);
    try {
      final stock = _freshStock ?? await MobileApiService.getStockItems();
      if (!mounted) return;
      final selected = await Navigator.of(context).push<InventoryMenuSelection>(
        MaterialPageRoute(
          builder: (_) =>
              const InventoryMenuPicker(title: 'რომელ კერძში ვიყენებთ?'),
        ),
      );
      if (selected == null || !mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (_) => RecipeEditorDialog(
          menuItemId: selected.item.menuItemId,
          menuItemName: selected.item.name,
          menuGroup: selected.item.menuGroup,
          variantId: selected.variant?.variantId,
          variantLabel: selected.variant?.label,
          stockItems: stock,
          initialIngredientId: stockId,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = (_detail?['products'] as List? ?? []).cast<Map>();
    final ids = products.map((row) => row['id']).toSet();
    final receivings = (_detail?['recentReceivings'] as List? ?? [])
        .cast<Map>();
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(VynicSpacing.md),
        contentPadding: const EdgeInsets.all(VynicSpacing.md),
        key: const Key('supplier-detail'),
        backgroundColor: AdminTheme.surface,
        title: Text(
          widget.supplier.name,
          style: TextStyle(color: AdminTheme.text),
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: AdminTheme.bad)),
                  TextButton(
                    onPressed: _load,
                    child: const Text('ხელახლა ცდა'),
                  ),
                ],
                if (_detail == null && _error == null)
                  const Center(child: CircularProgressIndicator()),
                if (_detail?['settlement'] case final Map settlement) ...[
                  Text(
                    'დავალიანება: ${settlement['outstanding']} ₾',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (settlement['unverified'] != '0.00')
                    Text(
                      'შესამოწმებელი ძველი მარაგშია: ${settlement['unverified']} ₾',
                    ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  key: const Key('supplier-new-receiving'),
                  onPressed: _busy ? null : _newReceiving,
                  icon: const Icon(Icons.add),
                  label: const Text('ახალი მიღება'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        SupplierPayablesDialog(supplierId: widget.supplier.id),
                  ),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('გადახდები და დავალიანება'),
                ),
                OutlinedButton.icon(
                  key: const Key('supplier-add-item'),
                  onPressed: _busy ? null : _addGoods,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('საქონლის დამატება'),
                ),
                const SizedBox(height: 16),
                Text(
                  'რას გვაწვდის',
                  style: TextStyle(
                    color: AdminTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (products.isEmpty && _detail != null)
                  Text(
                    'პროდუქტი ჯერ არ არის მიბმული.',
                    style: TextStyle(color: AdminTheme.textMuted),
                  ),
                for (final product in products)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => StockItemDetailDialog(
                        stockItemId: product['id'] as String,
                      ),
                    ),
                    title: Text(
                      '${product['name']}',
                      style: TextStyle(color: AdminTheme.text),
                    ),
                    subtitle: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _useInDish(product['id'] as String),
                        icon: const Icon(Icons.restaurant_outlined, size: 18),
                        label: const Text('გამოყენება კერძში'),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'მიბმის მოხსნა',
                      onPressed: _busy
                          ? null
                          : () => _link(product['id'] as String, false),
                      icon: const Icon(Icons.link_off),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _selecting = !_selecting),
                  icon: const Icon(Icons.add),
                  label: const Text('არსებული საქონლის არჩევა'),
                ),
                if (_selecting) ...[
                  TextField(
                    decoration: _adminInput('პროდუქტის ძებნა'),
                    style: TextStyle(color: AdminTheme.text),
                    onChanged: (value) =>
                        setState(() => _search = value.toLowerCase()),
                  ),
                  for (final item in widget.stockItems.where(
                    (item) =>
                        item.isActive &&
                        !ids.contains(item.id) &&
                        item.name.toLowerCase().contains(_search),
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.name,
                        style: TextStyle(color: AdminTheme.text),
                      ),
                      trailing: IconButton(
                        tooltip: 'მიბმა',
                        onPressed: _busy ? null : () => _link(item.id, true),
                        icon: const Icon(Icons.add_link),
                      ),
                    ),
                ],
                const Divider(height: 24),
                Text(
                  'ბოლო მიღებები',
                  style: TextStyle(
                    color: AdminTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (receivings.isEmpty && _detail != null)
                  Text(
                    'მიღებები ჯერ არ არის.',
                    style: TextStyle(color: AdminTheme.textMuted),
                  ),
                for (final row in receivings)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${row['businessDate']} · ${row['documentTotal']} ₾',
                      style: TextStyle(color: AdminTheme.text),
                    ),
                    subtitle: Text(
                      '${row['supplierNameSnapshot']}',
                      style: TextStyle(color: AdminTheme.textMuted),
                    ),
                    trailing: _ReceivingStatusBadge(
                      status: ReceivingStatus.parse(row['status'] as String?),
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => ReceivingDetailDialog(
                        receivingId: row['id'] as String,
                        onEditDraft: (draft) async {
                          Navigator.pop(context);
                          await showDialog<bool>(
                            context: context,
                            builder: (_) => ReceivingEditorDialog(
                              receiving: draft,
                              suppliers: [widget.supplier],
                              stockItems: widget.stockItems,
                            ),
                          );
                          await _load();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('დახურვა'),
          ),
        ],
      ),
    );
  }
}

/// Inventory controls share the existing spacing scale and Manager palette.
// Use the existing neutral palette against each action surface. Dark mode's
// lighter blue needs dark ink; white on it fails normal-text contrast.
Color _inventoryInk(Color background) => background.computeLuminance() <= .183
    ? Colors.white
    : (AdminTheme.bg.computeLuminance() < AdminTheme.text.computeLuminance()
          ? AdminTheme.bg
          : AdminTheme.text);
Color get _inventoryOnPrimary => _inventoryInk(AdminTheme.primary);

ThemeData inventoryTheme(BuildContext context) {
  final theme = Theme.of(context);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final style = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    shape: WidgetStatePropertyAll(shape),
  );
  return theme.copyWith(
    scaffoldBackgroundColor: AdminTheme.bg,
    canvasColor: AdminTheme.surface,
    textTheme: theme.textTheme.apply(
      bodyColor: AdminTheme.text,
      displayColor: AdminTheme.text,
    ),
    colorScheme: theme.colorScheme.copyWith(
      brightness: ThemeData.estimateBrightnessForColor(AdminTheme.bg),
      primary: AdminTheme.primary,
      onPrimary: _inventoryOnPrimary,
      surface: AdminTheme.surface,
      onSurface: AdminTheme.text,
      onSurfaceVariant: AdminTheme.textMuted,
      surfaceContainerHighest: AdminTheme.surfaceElevated,
      secondaryContainer: AdminTheme.surfaceElevated,
      onSecondaryContainer: AdminTheme.text,
      outline: AdminTheme.border,
      error: AdminTheme.bad,
    ),
    chipTheme: theme.chipTheme.copyWith(
      backgroundColor: AdminTheme.surfaceElevated,
      selectedColor: AdminTheme.primary.withValues(alpha: .12),
      disabledColor: AdminTheme.surfaceElevated,
      labelStyle: theme.textTheme.labelLarge!.copyWith(color: AdminTheme.text),
      secondaryLabelStyle: theme.textTheme.labelLarge!.copyWith(
        color: AdminTheme.text,
      ),
      checkmarkColor: AdminTheme.primary,
      side: BorderSide(color: AdminTheme.border),
    ),
    iconTheme: theme.iconTheme.copyWith(color: AdminTheme.textMuted),
    cardTheme: theme.cardTheme.copyWith(
      color: AdminTheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AdminTheme.border),
      ),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      backgroundColor: AdminTheme.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(style: style),
    outlinedButtonTheme: OutlinedButtonThemeData(style: style),
    textButtonTheme: TextButtonThemeData(style: style),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
    ),
  );
}

/// One navigable Inventory destination shared by Dashboard and Financials.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({
    super.key,
    this.section = 4,
    this.stockStatus,
    this.businessDate,
  });
  final int section;
  final String? stockStatus;
  final String? businessDate;
  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        title: const Text('მარაგები'),
        backgroundColor: AdminTheme.bg,
      ),
      body: InventoryAdminTab(
        initialSection: section,
        initialStockStatus: stockStatus,
        initialBusinessDate: businessDate,
      ),
    ),
  );
}

/// Expanded form fields have scroll positions of their own. Keep them outside
/// the tile's boolean PageStorage entry, including after collapse/reopen.
class _InventoryExpansionContents extends StatefulWidget {
  const _InventoryExpansionContents({required this.children});
  final List<Widget> children;
  @override
  State<_InventoryExpansionContents> createState() =>
      _InventoryExpansionContentsState();
}

class _InventoryExpansionContentsState
    extends State<_InventoryExpansionContents> {
  final _bucket = PageStorageBucket();
  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _bucket,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.children,
    ),
  );
}
