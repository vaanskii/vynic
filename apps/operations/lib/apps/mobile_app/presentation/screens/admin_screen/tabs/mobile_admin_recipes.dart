part of '../mobile_admin_screen.dart';

/// Which products the Recipes list is showing.
enum _RecipeFilter {
  all(null, 'ყველა'),
  linked(true, 'შევსებული'),
  unlinked(false, 'მიუბმელი');

  const _RecipeFilter(this.wanted, this.label);

  /// `null` shows everything; otherwise the configured state to match.
  final bool? wanted;
  final String label;

  bool matches(RecipeMenuItem item) =>
      wanted == null || wanted == item.isConfigured;
}

class _RecipeFilterBar extends StatelessWidget {
  const _RecipeFilterBar({required this.selected, required this.onChanged});

  final _RecipeFilter selected;
  final ValueChanged<_RecipeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in _RecipeFilter.values)
          ChoiceChip(
            key: Key('recipe-filter-${filter.name}'),
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: (_) => onChanged(filter),
            backgroundColor: AdminTheme.surface,
            selectedColor: AdminTheme.surfaceElevated,
            checkmarkColor: AdminTheme.primary,
            side: BorderSide(color: AdminTheme.border),
            labelStyle: TextStyle(
              color: selected == filter
                  ? AdminTheme.primary
                  : AdminTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _RecipeStatusBadge extends StatelessWidget {
  const _RecipeStatusBadge({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final color = configured ? AdminTheme.good : AdminTheme.textMuted;
    return Container(
      key: Key('recipe-status-${configured ? 'configured' : 'unconfigured'}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        configured ? 'შევსებულია' : 'შესავსებია',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One Menu Item in the recipe list.
///
/// A product with no definition is shown as prominently as one with a card:
/// the gap is exactly what a Manager opens this section to find.
class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.item, required this.onOpen});

  final RecipeMenuItem item;

  /// `null` variant means the Menu Item itself.
  final void Function(RecipeMenuVariant? variant) onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AdminPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          key: Key('recipe-card-${item.menuItemId}'),
          onTap: item.hasVariants ? null : () => onOpen(null),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AdminTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _RecipeStatusBadge(configured: item.isConfigured),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (item.categoryName != null)
                      _InventoryMeta(
                        icon: Icons.folder_outlined,
                        label: item.categoryName!,
                      ),
                    _InventoryMeta(
                      icon: Icons.payments_outlined,
                      label: '${item.price.toStringAsFixed(2)} ₾',
                    ),
                    _InventoryMeta(
                      icon: Icons.blender_outlined,
                      label: item.isConfigured
                          ? '${item.componentCount} ინგრედიენტი'
                          : 'შემადგენლობა შესავსებია',
                    ),
                  ],
                ),
                if (item.hasVariants) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final variant in item.variants)
                        OutlinedButton(
                          key: Key('recipe-variant-${variant.variantId}'),
                          onPressed: () => onOpen(variant),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: variant.recipe?.isActive == true
                                ? AdminTheme.good
                                : AdminTheme.textMuted,
                            side: BorderSide(color: AdminTheme.border),
                          ),
                          child: Text(
                            '${variant.label} · '
                            '${variant.recipe?.isActive == true ? '${variant.recipe!.componentCount} ინგრედიენტი' : 'შემადგენლობა შესავსებია'}',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Editor ──────────────────────────────────────────────────────────────────

/// One component being edited, before Cloud validates and normalizes it.
class _RecipeComponentDraft {
  _RecipeComponentDraft({
    required this.stockItem,
    required this.unit,
    required this.quantity,
  });

  StockItem? stockItem;
  InventoryUnit? unit;
  final TextEditingController quantity;

  double get quantityValue =>
      double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;

  /// Preview only, and deliberately as narrow as Cloud: the base unit itself
  /// or a global mass/volume conversion. Purchase packaging is not a
  /// consumption unit, so it never appears here either.
  double? get baseQuantity {
    final item = stockItem;
    final entered = unit;
    if (item == null || entered == null) return null;
    if (entered == item.baseUnit) return quantityValue;
    if (entered.dimension != item.baseUnit.dimension) return null;
    try {
      return convertInventoryQuantity(
        quantityValue,
        from: entered,
        to: item.baseUnit,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() => quantity.dispose();
}

/// The technological card for one Menu Item, or one of its variants.
///
/// Two presentation modes over one model: a bottled product is "link to
/// stock, 1 bottle", and everything else is an ingredient list. The payload
/// they save is identical.
class RecipeEditorDialog extends StatefulWidget {
  const RecipeEditorDialog({
    super.key,
    required this.menuItemId,
    required this.menuItemName,
    this.menuGroup = 'OTHER',
    required this.stockItems,
    this.variantId,
    this.variantLabel,
    this.load,
    this.save,
    this.disable,
    this.onCreateStockItem,
    this.initialIngredientId,
  });

  final String? initialIngredientId;
  final String menuItemId;
  final String menuItemName;
  final String menuGroup;
  final String? variantId;
  final String? variantLabel;
  final List<StockItem> stockItems;

  /// Test seams. Production always goes through the Manager API.
  final Future<MenuRecipeDetail> Function()? load;
  final Future<void> Function(Map<String, dynamic> payload)? save;
  final Future<void> Function(String recipeId)? disable;

  /// Opens the Stock Item editor pre-filled from this Menu Item, and returns
  /// whatever was created. Nothing but the name is assumed.
  final Future<StockItem?> Function(String prefillName)? onCreateStockItem;

  @override
  State<RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<RecipeEditorDialog> {
  final _yield = TextEditingController(text: '1');
  List<_RecipeComponentDraft> _components = [];
  List<StockItem> _stockItems = const [];
  MenuRecipeDetail? _detail;
  bool _directMode = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stockItems = widget.stockItems;
    _load();
  }

  @override
  void dispose() {
    _yield.dispose();
    for (final component in _components) {
      component.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail =
          await (widget.load?.call() ??
              MobileApiService.getRecipe(
                widget.menuItemId,
                variantId: widget.variantId,
              ));
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        for (final component in _components) {
          component.dispose();
        }
        final recipe = detail.recipe;
        if (recipe == null) {
          _directMode = widget.menuGroup != 'FOOD';
          _components = [_emptyComponent()];
        } else {
          _yield.text = _quantityText(recipe.yieldQuantity);
          _components = [
            for (final component in recipe.components)
              _RecipeComponentDraft(
                stockItem: _stockItems
                    .where((item) => item.id == component.stockItemId)
                    .firstOrNull,
                unit: component.unit,
                quantity: TextEditingController(
                  text: _quantityText(component.quantity),
                ),
              ),
          ];
          // A single component with a yield of one is a direct stock link;
          // the Manager should not have to read it as a recipe.
          _directMode =
              widget.menuGroup != 'FOOD' &&
              recipe.isDirectLink &&
              recipe.yieldValue == 1;
        }
        final ingredient = _stockItems
            .where((i) => i.id == widget.initialIngredientId && i.isActive)
            .firstOrNull;
        if (ingredient != null) {
          _directMode = false;
          if (recipe == null) {
            for (final component in _components) {
              component.dispose();
            }
            _components = [];
          }
          if (!_components.any((c) => c.stockItem?.id == ingredient.id)) {
            _components.add(
              _RecipeComponentDraft(
                stockItem: ingredient,
                unit: ingredient.consumptionUnits.contains(InventoryUnit.g)
                    ? InventoryUnit.g
                    : ingredient.baseUnit,
                quantity: TextEditingController(),
              ),
            );
          }
          _directMode =
              widget.menuGroup != 'FOOD' &&
              _components.length == 1 &&
              (recipe == null || recipe.yieldValue == 1);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
        _components = [_emptyComponent()];
      });
    }
  }

  _RecipeComponentDraft _emptyComponent() {
    final item = _stockItems.where((row) => row.isActive).firstOrNull;
    return _RecipeComponentDraft(
      stockItem: item,
      unit:
          !_directMode &&
              item?.consumptionUnits.contains(InventoryUnit.g) == true
          ? InventoryUnit.g
          : item?.consumptionUnits.first,
      quantity: TextEditingController(text: _directMode ? '1' : ''),
    );
  }

  String get _title {
    final variant = widget.variantLabel;
    return variant == null
        ? widget.menuItemName
        : '${widget.menuItemName} · $variant';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(VynicSpacing.md),
        contentPadding: const EdgeInsets.all(VynicSpacing.md),
        key: const Key('recipe-editor'),
        backgroundColor: AdminTheme.surface,
        title: Text(_title, style: TextStyle(color: AdminTheme.text)),
        content: SizedBox(
          width: 620,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(child: _body()),
        ),
        actions: _actions(),
      ),
    );
  }

  Widget _body() {
    final detail = _detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (detail != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  'გასაყიდი ფასი: ${detail.price.toStringAsFixed(2)} ₾',
                  key: const Key('recipe-price'),
                  style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
                ),
              ),
              _RecipeStatusBadge(configured: detail.recipe?.isActive == true),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          _directMode
              ? '1 გაყიდვა = მარაგიდან'
              : '${_yield.text} ცალზე საჭიროა:',
          style: TextStyle(
            color: AdminTheme.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (widget.menuGroup != 'FOOD')
          TextButton(
            key: const Key('recipe-mode'),
            onPressed: _saving
                ? null
                : () => setState(() {
                    // Switching to a simple drink must never discard ingredients.
                    if (_components.length <= 1) {
                      if (!_directMode && _components.isNotEmpty) {
                        try {
                          _components.single.quantity.text =
                              (InventoryDecimal.parse(
                                        _components.single.quantity.text,
                                      ) /
                                      InventoryDecimal.parse(_yield.text))
                                  .toStringAsFixed(6);
                          _yield.text = '1';
                        } on FormatException {
                          _error = 'შეამოწმეთ რაოდენობა და პორციების რიცხვი';
                          return;
                        }
                      }
                      _directMode = !_directMode;
                    } else {
                      _error =
                          'ერთ საქონელზე გადასასვლელად ჯერ გადაამოწმეთ ინგრედიენტები.';
                    }
                  }),
            child: Text(
              _directMode
                  ? 'რამდენიმე ინგრედიენტის დამატება'
                  : 'ერთი საქონლიდან ჩამოწერა',
            ),
          ),
        const Divider(height: 24),
        for (var index = 0; index < _components.length; index++)
          _componentEditor(index),
        if (!_directMode) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('recipe-add-component'),
              onPressed: _saving ? null : _pickIngredient,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('ინგრედიენტის დამატება'),
              style: TextButton.styleFrom(foregroundColor: AdminTheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            key: PageStorageKey(
              'inventory-recipe-batch-${widget.menuItemId}-${widget.variantId ?? ''}',
            ),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _yield.text != '1',
            title: const Text('რამდენიმე პორციაზე მომზადება'),
            children: [
              _InventoryExpansionContents(
                children: [
                  TextField(
                    key: const Key('recipe-yield'),
                    controller: _yield,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: AdminTheme.text),
                    decoration: _adminInput('რამდენ პორციაზეა გაწერილი'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'დატოვეთ 1, თუ რაოდენობები ერთ პორციაზეა. მაგ. 100 ხინკლის '
                    'ცომი და ხორცი შეიყვანეთ ერთად და მიუთითეთ 100.',
                    style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ],
        if (widget.onCreateStockItem != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('recipe-create-stock-item'),
              onPressed: _saving ? null : _createStockItem,
              icon: const Icon(Icons.add_box_outlined, size: 18),
              label: const Text('ახალი ნედლეულის შექმნა'),
              style: TextButton.styleFrom(foregroundColor: AdminTheme.primary),
            ),
          ),
        ],
        if (detail != null &&
            ManagerEntitlements.has(FeatureKeys.profitability))
          CurrentRecipeCostPanel(cost: detail.currentCost),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: TextStyle(color: AdminTheme.bad, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _componentEditor(int index) {
    final component = _components[index];
    final base = component.baseQuantity;
    final item = component.stockItem;
    final converted =
        item != null &&
        component.unit != null &&
        component.unit != item.baseUnit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: Key('recipe-component-item-$index'),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                  ),
                  icon: const Icon(Icons.search),
                  label: Text(
                    item?.name ??
                        (_directMode ? 'მარაგიდან' : 'ინგრედიენტის არჩევა'),
                  ),
                  onPressed: _saving
                      ? null
                      : () async {
                          final selected = await showDialog<StockItem>(
                            context: context,
                            builder: (_) =>
                                InventoryIngredientPicker(items: _stockItems),
                          );
                          if (selected != null && mounted)
                            setState(() {
                              component.stockItem = selected;
                              component.unit =
                                  !_directMode &&
                                      selected.consumptionUnits.contains(
                                        InventoryUnit.g,
                                      )
                                  ? InventoryUnit.g
                                  : selected.consumptionUnits.first;
                            });
                        },
                ),
              ),
              if (!_directMode)
                IconButton(
                  tooltip: 'წაშლა',
                  onPressed: _saving || _components.length == 1
                      ? null
                      : () => setState(
                          () => _components.removeAt(index).dispose(),
                        ),
                  icon: Icon(Icons.close_rounded, color: AdminTheme.textDim),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  key: Key('recipe-component-quantity-$index'),
                  controller: component.quantity,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: TextStyle(color: AdminTheme.text),
                  decoration: _adminInput('რაოდენობა'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<InventoryUnit>(
                  key: Key('recipe-component-unit-$index'),
                  initialValue: component.unit,
                  dropdownColor: AdminTheme.surfaceElevated,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: AdminTheme.text,
                    fontSize: 13,
                  ),
                  decoration: _adminInput('ერთეული'),
                  items: [
                    // Only natural consumption units. Purchase packaging such
                    // as a box is how the venue buys, never how it serves.
                    for (final unit in item?.consumptionUnits ?? const [])
                      DropdownMenuItem(
                        value: unit,
                        child: Text(_unitShort(unit)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => component.unit = value),
                ),
              ),
            ],
          ),
          if (converted && base != null) ...[
            const SizedBox(height: 6),
            // The normalized amount is shown while it is still editable, so
            // "500 ml" is visibly "0.5 ლ" of the tank before anything is saved.
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_quantity(component.quantityValue)} ${_unitShort(component.unit!)}'
                ' = ${_quantity(base)} ${_unitShort(item.baseUnit)}',
                key: Key('recipe-component-base-$index'),
                style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions() {
    final recipe = _detail?.recipe;
    return [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: Text('დახურვა', style: TextStyle(color: AdminTheme.textMuted)),
      ),
      if (recipe != null && recipe.isActive)
        TextButton(
          key: const Key('recipe-disable'),
          onPressed: _saving ? null : _disable,
          style: TextButton.styleFrom(foregroundColor: AdminTheme.warn),
          child: const Text('გათიშვა'),
        ),
      if (!_loading && _detail == null)
        TextButton(onPressed: _load, child: const Text('ხელახლა ცდა')),
      FilledButton(
        key: const Key('recipe-save'),
        onPressed: _saving || _loading || _detail == null ? null : _save,
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
    ];
  }

  /// §O: pre-fill the name and nothing else. Unit, packaging and threshold are
  /// real decisions, and the new Stock Item gets its own identity — a Menu
  /// Item and a Stock Item are never the same row.
  Future<void> _pickIngredient() async {
    final picked = await showDialog<StockItem>(
      context: context,
      builder: (_) => InventoryIngredientPicker(items: _stockItems),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _components.add(
        _RecipeComponentDraft(
          stockItem: picked,
          unit: picked.consumptionUnits.contains(InventoryUnit.g)
              ? InventoryUnit.g
              : picked.consumptionUnits.first,
          quantity: TextEditingController(),
        ),
      ),
    );
  }

  Future<void> _createStockItem() async {
    final created = await widget.onCreateStockItem!(
      _directMode ? widget.menuItemName : '',
    );
    if (created == null || !mounted) return;
    setState(() {
      _stockItems = [..._stockItems, created];
      final target = _components.firstOrNull;
      if (target != null && target.stockItem == null) {
        target.stockItem = created;
        target.unit = created.consumptionUnits.first;
      } else {
        _components.add(
          _RecipeComponentDraft(
            stockItem: created,
            unit: created.consumptionUnits.contains(InventoryUnit.g)
                ? InventoryUnit.g
                : created.consumptionUnits.first,
            quantity: TextEditingController(),
          ),
        );
        _directMode = false;
      }
    });
  }

  Future<void> _disable() async {
    final recipe = _detail!.recipe!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.disable?.call(recipe.id) ??
          MobileApiService.disableRecipe(recipe.id));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    final payload = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final component in _components) {
      final item = component.stockItem;
      if (item == null) {
        setState(() => _error = 'აირჩიეთ მარაგის პროდუქტი');
        return;
      }
      if (!seen.add(item.id)) {
        setState(() => _error = '${item.name} ორჯერ არის ჩამატებული');
        return;
      }
      if (component.quantityValue <= 0) {
        setState(() => _error = '${item.name}: რაოდენობა უნდა იყოს დადებითი');
        return;
      }
      if (component.baseQuantity == null) {
        setState(
          () => _error =
              '${item.name}: ${component.unit == null ? '' : _unitShort(component.unit!)} '
              'ვერ გადაიყვანება ${_unitShort(item.baseUnit)}-ში',
        );
        return;
      }
      payload.add(<String, dynamic>{
        'stockItemId': item.id,
        'quantity': component.quantity.text.trim().replaceAll(',', '.'),
        'unit': (component.unit ?? item.baseUnit).wireValue,
      });
    }
    final yieldText = _directMode
        ? '1'
        : _yield.text.trim().replaceAll(',', '.');
    if ((double.tryParse(yieldText) ?? 0) <= 0) {
      setState(() => _error = 'პორციების რაოდენობა უნდა იყოს დადებითი');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final save = widget.save;
      final body = <String, dynamic>{
        'menuItemId': widget.menuItemId,
        'variantId': widget.variantId,
        'yieldQuantity': yieldText,
        'components': payload,
      };
      if (save != null) {
        await save(body);
      } else {
        await MobileApiService.saveRecipe(
          menuItemId: widget.menuItemId,
          variantId: widget.variantId,
          yieldQuantity: yieldText,
          components: payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }
}

/// Current procurement costs of the saved definition; never a sale profit figure.
class CurrentRecipeCostPanel extends StatelessWidget {
  const CurrentRecipeCostPanel({super.key, required this.cost});
  final CurrentRecipeCost? cost;
  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('recipe-current-cost'),
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'მიმდინარე თვითღირებულება: ${cost?.total == null ? 'ვერ გამოითვლება' : '${cost!.total} ₾'}',
          style: TextStyle(color: AdminTheme.text, fontWeight: FontWeight.w700),
        ),
        if (cost == null || cost!.status == 'NO_ACTIVE_RECIPE')
          Text(
            'შეინახეთ შემადგენლობა ღირებულების სანახავად.',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        if (cost?.status == 'MISSING_COMPONENT_COST')
          Text(
            'ზოგი ინგრედიენტის შესყიდვის ფასი ჯერ არ გვაქვს.',
            style: TextStyle(color: AdminTheme.warn),
          ),
        if (cost != null && cost!.components.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('inventory-recipe-cost-details'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              'შენახული შემადგენლობით · საშუალო შესყიდვის ფასი',
              style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
            ),
            children: [
              _InventoryExpansionContents(
                children: [
                  for (final component in cost!.components)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        component.name,
                        style: TextStyle(color: AdminTheme.text),
                      ),
                      subtitle: Text(
                        component.unitCost == null
                            ? 'შესყიდვის ისტორია არ არის'
                            : '${_quantityText(component.quantity)} ${_unitShort(component.baseUnit)} × ${_quantityText(component.unitCost!)} ₾ / ${_unitShort(component.baseUnit)} = ${_quantityText(component.cost!)} ₾',
                        style: TextStyle(color: AdminTheme.textMuted),
                      ),
                    ),
                  Text(
                    'დათვლილია დადასტურებული მიღებებიდან. გაუქმებული მიღებები არ შედის. შემადგენლობის ცვლილება გამოჩნდება შენახვის შემდეგ.',
                    style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
      ],
    ),
  );
}
