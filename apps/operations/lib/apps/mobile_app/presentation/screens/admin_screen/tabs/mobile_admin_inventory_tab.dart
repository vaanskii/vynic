part of '../mobile_admin_screen.dart';

enum _InventorySection {
  stockItems,
  suppliers,
  receiving,
  recipes,
  home,
  payments,
}

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
  StockItemClassification? _classificationFilter;
  bool _archivedStock = false;
  String? _paymentSupplierId;
  final _scroll = ScrollController(keepScrollOffset: false);
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
    _scroll.dispose();
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

    return Material(
      color: AdminTheme.bg,
      child: Theme(
        data: inventoryTheme(context),
        child: RefreshIndicator(
          color: AdminTheme.primary,
          backgroundColor: AdminTheme.surface,
          onRefresh: _load,
          notificationPredicate: (n) =>
              _section != _InventorySection.payments && n.depth == 0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth >= 720 ? 24.0 : 16.0;
              final content = _section == _InventorySection.payments
                  ? SupplierPayablesView(supplierId: _paymentSupplierId)
                  : _section == _InventorySection.recipes
                  ? InventoryMenuBrowser(
                      items: _recipes,
                      composition: true,
                      onSelected: (selected) =>
                          _openRecipe(selected.item, selected.variant),
                    )
                  : ListView(
                      key: const Key('inventory-admin-list'),
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        12,
                        horizontal,
                        MediaQuery.paddingOf(context).bottom + 24,
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
                                  _searchAndAdd(
                                    constraints.maxWidth - horizontal * 2,
                                  ),
                                  const SizedBox(height: VynicSpacing.lg),
                                  if (_section == _InventorySection.stockItems)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            key: const Key(
                                              'inventory-consumption-history',
                                            ),
                                            onPressed: () =>
                                                Navigator.of(context).push(
                                                  MaterialPageRoute<void>(
                                                    builder: (_) =>
                                                        const ConsumptionHistoryScreen(),
                                                  ),
                                                ),
                                            icon: const Icon(Icons.history),
                                            label: const Text(
                                              'ჩამოწერების ისტორია',
                                            ),
                                          ),
                                        ),
                                        _catalogFilters(),
                                        const SizedBox(height: 12),
                                        _stockItemList(),
                                      ],
                                    )
                                  else if (_section ==
                                      _InventorySection.suppliers)
                                    _supplierList()
                                  else if (_section ==
                                      _InventorySection.receiving)
                                    _receivingList(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
              return Column(
                children: [
                  _sectionSelector(),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _navigate(_InventorySection section) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _section = section;
      if (section == _InventorySection.stockItems && _stockStatusFilter != null)
        _archivedStock = false;
      _search.clear();
      if (section == _InventorySection.home) _receivingDayFilter = null;
    });
    if (section == _InventorySection.home ||
        section == _InventorySection.receiving)
      _load();
  }

  static const _destinations = <_InventorySection, (String, IconData)>{
    _InventorySection.home: ('მიმოხილვა', Icons.home_outlined),
    _InventorySection.receiving: (
      'მიღებების ისტორია',
      Icons.receipt_long_outlined,
    ),
    _InventorySection.stockItems: ('ნაშთები', Icons.inventory_2_outlined),
    _InventorySection.payments: (
      'გადახდები და დავალიანება',
      Icons.account_balance_wallet_outlined,
    ),
    _InventorySection.suppliers: (
      'მომწოდებლები',
      Icons.local_shipping_outlined,
    ),
    _InventorySection.recipes: ('მენიუს შემადგენლობა', Icons.restaurant_menu),
  };

  Widget _sectionSelector() => Padding(
    key: const Key('inventory-section-selector'),
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
    child: Row(
      children: [
        if (_section != _InventorySection.home)
          IconButton(
            key: const Key('inventory-tab-home'),
            tooltip: 'მარაგების მიმოხილვა',
            onPressed: () => _navigate(_InventorySection.home),
            icon: const Icon(Icons.arrow_back),
          )
        else
          const SizedBox(width: 8),
        Expanded(
          child: Text(
            _section == _InventorySection.home
                ? 'მარაგები'
                : _destinations[_section]!.$1,
            style: TextStyle(
              color: AdminTheme.text,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        PopupMenuButton<_InventorySection>(
          key: const Key('inventory-navigation'),
          tooltip: 'მარაგების განყოფილებები',
          icon: const Icon(Icons.menu_open),
          color: AdminTheme.surface,
          onSelected: _navigate,
          itemBuilder: (_) => [
            for (final entry in _destinations.entries)
              PopupMenuItem(
                key: Key('inventory-tab-${entry.key.name}'),
                value: entry.key,
                child: Row(
                  children: [
                    Icon(entry.value.$2, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(entry.value.$1)),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _inventoryHome() {
    final today = _businessDate;
    final receipts = _receivings
        .where((r) => r.effectiveBusinessDate == today)
        .toList();
    final active = _stockItems.where((i) => i.isActive).toList();
    final low = active.where((i) => i.stockStatus == 'LOW').length;
    final negative = active.where((i) => i.stockStatus == 'NEGATIVE').length;
    final incomplete = _recipes.where((i) => !i.isFullyConfigured).length;
    final work = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _homeHeading('ყოველდღიური სამუშაო'),
        const SizedBox(height: 8),
        _homeDestination(
          _InventorySection.receiving,
          'შენახული მიღებები და მონახაზები',
        ),
        _homeDestination(
          _InventorySection.stockItems,
          '${active.length} პროდუქტი მარაგში',
        ),
        _homeDestination(
          _InventorySection.payments,
          'ვის რამდენი დარჩა გადასახდელი',
        ),
        const SizedBox(height: 24),
        _homeHeading('კატალოგი'),
        const SizedBox(height: 8),
        _homeDestination(
          _InventorySection.suppliers,
          'პროდუქტები და კონტაქტები',
        ),
        _homeDestination(
          _InventorySection.recipes,
          incomplete > 0
              ? '$incomplete პროდუქტის შემადგენლობა შესავსებია'
              : 'რა იხარჯება ერთი გაყიდვისას',
        ),
      ],
    );
    final recent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _homeHeading('დღევანდელი მიღებები'),
        const SizedBox(height: 8),
        if (receipts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'დღეს მიღება ჯერ არ არის',
              style: TextStyle(color: AdminTheme.textMuted),
            ),
          ),
        for (final receipt in receipts.take(3))
          _ReceivingCard(
            receiving: receipt,
            onOpen: () => _openReceiving(receipt),
          ),
      ],
    );
    return Column(
      key: const Key('inventory-home'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('inventory-add'),
          onPressed: () => _editReceiving(),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.add),
          label: const Text('ახალი მიღება'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'დღეს მივიღეთ',
                style: TextStyle(color: AdminTheme.textMuted),
              ),
            ),
            Text(
              today == null ? '—' : '${_todayTotal(today)} ₾',
              style: TextStyle(
                color: AdminTheme.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (low > 0 || negative > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final warning in [
                  ('LOW', low, 'დაბალი მარაგი'),
                  ('NEGATIVE', negative, 'უარყოფითი მარაგი'),
                ])
                  if (warning.$2 > 0)
                    ActionChip(
                      avatar: Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: AdminTheme.warn,
                      ),
                      label: Text('${warning.$3}: ${warning.$2}'),
                      onPressed: () {
                        _stockStatusFilter = warning.$1;
                        _navigate(_InventorySection.stockItems);
                      },
                    ),
              ],
            ),
          ),
        const Divider(height: 32),
        LayoutBuilder(
          builder: (_, c) => c.maxWidth >= 720
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: work),
                    const SizedBox(width: 32),
                    Expanded(child: recent),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [work, const SizedBox(height: 28), recent],
                ),
        ),
      ],
    );
  }

  Widget _homeDestination(_InventorySection section, String detail) {
    final destination = _destinations[section]!;
    return ListTile(
      key: Key('inventory-tab-${section.name}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Icon(destination.$2, color: AdminTheme.primary),
      title: Text(
        destination.$1,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        detail,
        style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _navigate(section),
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
    if (_section == _InventorySection.recipes ||
        _section == _InventorySection.stockItems)
      return search;
    final add = FilledButton.icon(
      key: const Key('inventory-add'),
      onPressed: switch (_section) {
        _InventorySection.stockItems => () => _editStockItem(),
        _InventorySection.suppliers => () => _editSupplier(),
        _InventorySection.receiving => () => _editReceiving(),
        _InventorySection.recipes => null,
        _InventorySection.home => () => _editReceiving(),
        _InventorySection.payments => null,
      },
      icon: const Icon(Icons.add_rounded),
      label: Text(switch (_section) {
        _InventorySection.stockItems => 'ახალი პროდუქტი',
        _InventorySection.suppliers => 'ახალი მომწოდებელი',
        _InventorySection.receiving => 'ახალი მიღება',
        _InventorySection.recipes => '',
        _InventorySection.home => 'ახალი მიღება',
        _InventorySection.payments => '',
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
      FilterChip(
        key: const Key('inventory-archived'),
        label: const Text('არქივი'),
        selected: _archivedStock,
        onSelected: (value) => setState(() {
          _archivedStock = value;
          _stockStatusFilter = null;
        }),
      ),
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
          if (item.isActive == _archivedStock) return false;
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
            ? (_archivedStock
                  ? 'არქივი ცარიელია'
                  : 'საწყობის პროდუქტები ჯერ არ არის')
            : 'შესაბამისი პროდუქტი ვერ მოიძებნა',
        subtitle: query.isEmpty
            ? (_archivedStock
                  ? 'არქივში გადატანილი პროდუქტები აქ გამოჩნდება.'
                  : 'ახალი მიღებისას აირჩიეთ ან შექმენით პროდუქტი.')
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

  Future<void> _openSupplier(Supplier supplier) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SupplierDetailDialog(
        supplier: supplier,
        stockItems: _stockItems,
        onPayments: () {
          Navigator.pop(context);
          setState(() => _paymentSupplierId = supplier.id);
          _navigate(_InventorySection.payments);
        },
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _editStockItem([StockItem? item]) async {
    final saved = await showDialog<StockItem>(
      context: context,
      builder: (_) => _StockItemEditorDialog(item: item),
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
    final saved = await showDialog<Supplier>(
      context: context,
      builder: (_) => _SupplierEditorDialog(supplier: supplier),
    );
    if (saved != null) {
      _adminToast(
        context,
        supplier == null ? 'მომწოდებელი დაემატა' : 'მომწოდებელი განახლდა',
      );
      await _load();
      if (supplier == null && mounted) await _openSupplier(saved);
    }
  }

  Future<void> _toggleStockItem(StockItem item) async {
    if (item.isActive) {
      final confirmed = await _confirmInventoryAction(
        context,
        title: 'პროდუქტის ამოღება სიიდან?',
        message:
            '${item.name} გადავა არქივში და მიღებისას აღარ გამოჩნდება. '
            'არსებული ნაშთი და ისტორია შენარჩუნდება. აღდგენა შეგიძლიათ არქივიდან.'
            '${(item.menuUsageCount ?? 0) > 0 ? '\nგამოიყენება მენიუს ${item.menuUsageCount} პროდუქტში — მათი შემადგენლობაც შეამოწმეთ.' : ''}',
        confirmLabel: 'არქივში გადატანა',
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await MobileApiService.setStockItemActive(item.id, !item.isActive);
      if (!mounted) return;
      _adminToast(
        context,
        item.isActive ? 'პროდუქტი გადატანილია არქივში' : 'პროდუქტი აღდგენილია',
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
                      const Text('არქივში', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: VynicSpacing.sm),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (item.menuUsageCount != null)
                      _InventoryMeta(
                        icon: Icons.restaurant_outlined,
                        label:
                            'გამოიყენება ${item.menuUsageCount} მენიუს პროდუქტში',
                      ),
                    if (item.lastPurchaseUnitCost != null)
                      _InventoryMeta(
                        icon: Icons.payments_outlined,
                        label:
                            'ბოლო ფასი: ${_quantityText(item.lastPurchaseUnitCost!)} ₾ / ${_unitShort(item.baseUnit)}',
                      ),
                    if (item.weightedUnitCost != null)
                      _InventoryMeta(
                        icon: Icons.calculate_outlined,
                        label:
                            'მიმდინარე საშუალო ფასი: ${_quantityText(item.weightedUnitCost!)} ₾ / ${_unitShort(item.baseUnit)}${item.costStatus == 'PROVISIONAL' ? ' · წინასწარი' : ''}',
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
              archive: true,
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
    required this.supplier,
    required this.onEdit,
    required this.onToggle,
  });

  final Supplier supplier;
  final VoidCallback onOpen;
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
                  label: Text('მომწოდებლის ნახვა'),
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
    this.archive = false,
  });

  final bool archive;
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
            child: Text(
              archive
                  ? (active ? 'ამოღება სიიდან' : 'აღდგენა')
                  : (active ? 'გათიშვა' : 'გააქტიურება'),
            ),
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
  const _StockItemEditorDialog({this.item});
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
                _purchaseUnitEditor(),
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
            onPressed: _saving ? null : () => Navigator.pop(context),
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
      final saved = await MobileApiService.saveSupplier(
        id: widget.supplier?.id,
        name: name,
        taxId: _fields['taxId']!.text,
        phone: _fields['phone']!.text,
        email: _fields['email']!.text,
        address: _fields['address']!.text,
        notes: _fields['notes']!.text,
        isActive: _active,
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
    this.onPayments,
  });
  final Supplier supplier;
  final List<StockItem> stockItems;
  final Future<Map<String, dynamic>> Function()? load;
  final VoidCallback? onPayments;
  @override
  State<SupplierDetailDialog> createState() => _SupplierDetailDialogState();
}

class _SupplierDetailDialogState extends State<SupplierDetailDialog> {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _busy = false;
  bool _savingProduct = false;
  late final _catalog = {for (final item in widget.stockItems) item.id: item};
  final _productSearch = TextEditingController();
  String get _productQuery => _productSearch.text;
  String? _productError;
  (StockItem, bool)? _retryProduct;
  bool _showAllProducts = false;

  List<Map<String, dynamic>> get _products =>
      (_detail?['products'] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _productSearch.dispose();
    super.dispose();
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

  Future<StockItem?> _createSuppliedProduct(String name) async {
    final item = await showDialog<StockItem>(
      context: context,
      builder: (_) =>
          IngredientQuickDialog(initialName: name, receivingProduct: true),
    );
    if (item != null && mounted) setState(() => _catalog[item.id] = item);
    return item;
  }

  Future<void> _addProduct() async {
    final linked = _products.map((row) => row['id']).toSet();
    final item = await showDialog<StockItem>(
      context: context,
      builder: (_) => InventoryIngredientPicker(
        title: 'რას გვაწვდის მომწოდებელი?',
        items: _catalog.values
            .where((item) => !linked.contains(item.id))
            .toList(),
        onCreate: _createSuppliedProduct,
      ),
    );
    if (item != null && mounted) await _setProduct(item, true);
  }

  Future<void> _setProduct(StockItem item, bool linked) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _savingProduct = true;
      _productError = null;
    });
    try {
      await MobileApiService.setSupplierProduct(
        widget.supplier.id,
        item.id,
        linked,
      );
      if (!mounted) return;
      final products = _products.where((row) => row['id'] != item.id).toList();
      if (linked)
        products.add({
          'id': item.id,
          'name': item.name,
          'baseUnit': item.baseUnit.wireValue,
        });
      setState(() {
        _detail = {...?_detail, 'products': products};
        _retryProduct = null;
        _productSearch.text = linked && products.length > 5 ? item.name : '';
      });
      await _load();
    } catch (error) {
      if (mounted)
        setState(() {
          _retryProduct = (item, linked);
          _productError =
              '${item.name}: ${linked ? 'მომწოდებელთან დამატება' : 'ასორტიმენტიდან ამოღება'} ვერ დასრულდა. ${error.toString().replaceFirst('Exception: ', '')}';
        });
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _savingProduct = false;
        });
    }
  }

  Future<void> _removeProduct(Map<String, dynamic> row) async {
    final item = _catalog[row['id']] ?? StockItem.fromJson(row);
    final confirmed = await _confirmInventoryAction(
      context,
      title: 'ასორტიმენტიდან ამოღება',
      message:
          '${item.name} ამ მომწოდებლის ასორტიმენტიდან ამოიღება. პროდუქტი, ნაშთი და მიღებების ისტორია შენარჩუნდება.',
      confirmLabel: 'ამოღება',
    );
    if (confirmed == true && mounted) await _setProduct(item, false);
  }

  String _productUnit(Map<String, dynamic> row) {
    final unit = _catalog[row['id']]?.baseUnit;
    if (unit != null) return _unitShort(unit);
    final wire = row['baseUnit'];
    return wire is String ? _unitShort(InventoryUnit.parse(wire)) : '';
  }

  Widget _assortment() {
    final products = _products;
    final shown = products
        .where(
          (row) => '${row['name']}'.toLowerCase().contains(
            _productQuery.toLowerCase(),
          ),
        )
        .toList();
    final add = _products.isEmpty
        ? FilledButton.icon(
            key: const Key('supplier-add-product'),
            onPressed: _busy ? null : _addProduct,
            icon: const Icon(Icons.add),
            label: const Text('პროდუქტის დამატება'),
          )
        : OutlinedButton.icon(
            key: const Key('supplier-add-product'),
            onPressed: _busy ? null : _addProduct,
            icon: const Icon(Icons.add),
            label: const Text('პროდუქტის დამატება'),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'რას გვაწვდის',
          style: TextStyle(
            color: AdminTheme.text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        if (products.isEmpty) ...[
          Text(
            'დაამატეთ პროდუქტები, რომლებიც ამ მომწოდებელს მოაქვს.',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
          const SizedBox(height: 12),
        ],
        add,
        if (_savingProduct) const LinearProgressIndicator(),
        if (_productError != null) ...[
          const SizedBox(height: 8),
          Text(
            _productError!,
            key: const Key('supplier-product-error'),
            style: TextStyle(color: AdminTheme.bad),
          ),
          TextButton(
            key: const Key('supplier-product-retry'),
            onPressed: _busy || _retryProduct == null
                ? null
                : () => _setProduct(_retryProduct!.$1, _retryProduct!.$2),
            child: const Text('ხელახლა ცდა'),
          ),
        ],
        if (products.length > 5) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('supplier-product-search'),
            controller: _productSearch,
            decoration: _adminInput(
              'ასორტიმენტში ძებნა',
            ).copyWith(prefixIcon: const Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
        ],
        for (final row in shown.take(
          _showAllProducts || _productQuery.isNotEmpty ? shown.length : 5,
        ))
          ListTile(
            key: ValueKey('supplier-product-${row['id']}'),
            contentPadding: EdgeInsets.zero,
            title: Text('${row['name']}'),
            subtitle: Text(
              _catalog[row['id']]?.isActive == false
                  ? 'არქივშია'
                  : _productUnit(row),
            ),
            trailing: IconButton(
              key: ValueKey('supplier-remove-product-${row['id']}'),
              tooltip: 'ასორტიმენტიდან ამოღება',
              onPressed: _busy ? null : () => _removeProduct(row),
              icon: const Icon(Icons.close, size: 20),
            ),
          ),
        if (products.length > 5 && _productQuery.isEmpty)
          TextButton(
            onPressed: () =>
                setState(() => _showAllProducts = !_showAllProducts),
            child: Text(
              _showAllProducts
                  ? 'ნაკლების ჩვენება'
                  : 'ყველა პროდუქტი (${products.length})',
            ),
          ),
        if (_productQuery.isNotEmpty && shown.isEmpty)
          const Text('პროდუქტი ვერ მოიძებნა'),
        const SizedBox(height: 8),
        Text(
          'რაოდენობა და ფასი მიღებისას ივსება.',
          style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
        ),
        const Divider(height: 24),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
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
                if (_detail != null) _assortment(),
                if (_detail?['settlement'] case final Map settlement) ...[
                  Text(
                    'დავალიანება: ${settlement['outstanding']} ₾',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'გადახდილი: ${(settlement['receivings'] as List? ?? []).cast<Map>().fold(InventoryDecimal.zero, (sum, row) => sum + InventoryDecimal.parse('${row['paid'] ?? '0'}')).toStringAsFixed(2)} ₾',
                  ),
                  if (settlement['unverified'] != '0.00')
                    Text(
                      'შესამოწმებელი ძველი მიღებები: ${settlement['unverified']} ₾',
                    ),
                  const SizedBox(height: 12),
                ],
                if (_products.isEmpty)
                  OutlinedButton.icon(
                    key: const Key('supplier-new-receiving'),
                    onPressed: _busy ? null : _newReceiving,
                    icon: const Icon(Icons.add),
                    label: const Text('ახალი მიღება'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('supplier-new-receiving'),
                    onPressed: _busy ? null : _newReceiving,
                    icon: const Icon(Icons.add),
                    label: const Text('ახალი მიღება'),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  key: const Key('supplier-payments'),
                  onPressed:
                      widget.onPayments ??
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SupplierPayablesScreen(
                            supplierId: widget.supplier.id,
                          ),
                        ),
                      ),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('გადახდები და დავალიანება'),
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
    this.embedded = false,
    this.stockStatus,
    this.businessDate,
  });
  final int section;
  final bool embedded;
  final String? stockStatus;
  final String? businessDate;
  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: embedded
          ? null
          : AppBar(
              title: const Text('მარაგები'),
              backgroundColor: AdminTheme.bg,
            ),
      body: SafeArea(
        top: embedded,
        child: InventoryAdminTab(
          initialSection: section,
          initialStockStatus: stockStatus,
          initialBusinessDate: businessDate,
        ),
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
