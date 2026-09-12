part of '../mobile_admin_screen.dart';

/// Which documents the Receiving list is showing.
enum _ReceivingStatusFilter {
  all(null, 'ყველა'),
  draft(ReceivingStatus.draft, 'მონახაზი'),
  posted(ReceivingStatus.posted, 'გატარებული'),
  cancelled(ReceivingStatus.cancelled, 'გაუქმებული');

  const _ReceivingStatusFilter(this.status, this.label);

  final ReceivingStatus? status;
  final String label;

  bool matches(ReceivingStatus value) => status == null || status == value;
}

class _ReceivingStatusFilterBar extends StatelessWidget {
  const _ReceivingStatusFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final _ReceivingStatusFilter selected;
  final ValueChanged<_ReceivingStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in _ReceivingStatusFilter.values)
          ChoiceChip(
            key: Key('receiving-filter-${filter.name}'),
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: (_) => onChanged(filter),
            backgroundColor: AdminTheme.surface,
            selectedColor: AdminTheme.primary,
            side: BorderSide(color: AdminTheme.border),
            labelStyle: TextStyle(
              color: selected == filter
                  ? _inventoryOnPrimary
                  : AdminTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// Status colour and label in one place, so the list, the detail and the
/// confirmations never disagree about what POSTED looks like.
({Color color, String label}) _receivingStatusStyle(ReceivingStatus status) {
  switch (status) {
    case ReceivingStatus.draft:
      return (color: AdminTheme.textMuted, label: 'მარაგში ჯერ არ დამატებულა');
    case ReceivingStatus.posted:
      return (color: AdminTheme.good, label: 'მარაგში დაემატა');
    case ReceivingStatus.cancelled:
      return (color: AdminTheme.warn, label: 'გაუქმებული');
  }
}

class _ReceivingStatusBadge extends StatelessWidget {
  const _ReceivingStatusBadge({required this.status});

  final ReceivingStatus status;

  @override
  Widget build(BuildContext context) {
    final style = _receivingStatusStyle(status);
    return Container(
      key: Key('receiving-status-${status.wireValue}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReceivingCard extends StatelessWidget {
  const _ReceivingCard({required this.receiving, required this.onOpen});

  final Receiving receiving;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AdminPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          key: Key('receiving-card-${receiving.id}'),
          onTap: onOpen,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            receiving.supplierName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AdminTheme.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _ReceivingStatusBadge(status: receiving.status),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _InventoryMeta(
                          icon: Icons.event_rounded,
                          label: _receivingDate(receiving.documentDate),
                        ),
                        if (receiving.waybillNumber != null)
                          _InventoryMeta(
                            icon: Icons.description_outlined,
                            label: 'ზედნადები ${receiving.waybillNumber}',
                          ),
                        _InventoryMeta(
                          icon: Icons.format_list_numbered_rounded,
                          label: '${receiving.lineCount} პოზიცია',
                        ),
                        _InventoryMeta(
                          icon: Icons.person_outline_rounded,
                          label: receiving.createdByName,
                        ),
                      ],
                    ),
                  ],
                );
                final total = Text(
                  '${receiving.documentTotal} ₾',
                  style: TextStyle(
                    color: receiving.isCancelled
                        ? AdminTheme.textDim
                        : AdminTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    decoration: receiving.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [content, const SizedBox(height: 10), total],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 12),
                    total,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Detail ──────────────────────────────────────────────────────────────────

/// The document as it stands: frozen once posted, and never hiding a
/// cancellation behind a deletion.
class ReceivingDetailDialog extends StatefulWidget {
  const ReceivingDetailDialog({
    super.key,
    required this.receivingId,
    required this.onEditDraft,
    this.load,
  });

  final String receivingId;
  final Future<void> Function(Receiving draft) onEditDraft;
  final Future<Receiving> Function()? load;

  @override
  State<ReceivingDetailDialog> createState() => _ReceivingDetailDialogState();
}

class _ReceivingDetailDialogState extends State<ReceivingDetailDialog> {
  Receiving? _receiving;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final receiving =
          await (widget.load?.call() ??
              MobileApiService.getReceiving(widget.receivingId));
      if (!mounted) return;
      setState(() {
        _receiving = receiving;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiving = _receiving;
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(VynicSpacing.md),
        contentPadding: const EdgeInsets.all(VynicSpacing.md),
        key: const Key('receiving-detail'),
        backgroundColor: AdminTheme.surface,
        title: Row(
          children: [
            Expanded(
              child: Text('მიღება', style: TextStyle(color: AdminTheme.text)),
            ),
            if (receiving != null)
              _ReceivingStatusBadge(status: receiving.status),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : receiving == null
              ? Text(
                  _error ?? 'ვერ ჩაიტვირთა',
                  style: TextStyle(color: AdminTheme.bad, fontSize: 12),
                )
              : SingleChildScrollView(child: _body(receiving)),
        ),
        actions: _actions(receiving),
      ),
    );
  }

  Widget _body(Receiving receiving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _detailRow('მომწოდებელი', receiving.supplierName),
        if (receiving.isPosted) ...[
          _detailRow('გადახდილი', '${receiving.paid} ₾'),
          _detailRow(
            'დარჩენილი',
            '${receiving.remaining} ₾ · ${_paymentLabel(receiving.paymentStatus)}',
          ),
          if (receiving.dueDate != null)
            _detailRow('გადახდის ვადა', receiving.dueDate!),
          OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  SupplierPayablesDialog(supplierId: receiving.supplierId),
            ).then((_) => _load()),
            child: const Text('გადახდის დაფიქსირება'),
          ),
        ],
        if (receiving.waybillNumber != null)
          _detailRow('ზედნადები', receiving.waybillNumber!),
        if (receiving.invoiceNumber != null)
          _detailRow('ინვოისი', receiving.invoiceNumber!),
        _detailRow('სამუშაო დღე', receiving.effectiveBusinessDate),
        _detailRow('დოკუმენტის თარიღი', _receivingDate(receiving.documentDate)),
        if (receiving.notes != null) _detailRow('შენიშვნა', receiving.notes!),
        const SizedBox(height: 12),
        for (final line in receiving.lines) _lineTile(line),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'დოკუმენტის ჯამი',
                style: TextStyle(
                  color: AdminTheme.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${receiving.documentTotal} ₾',
              key: const Key('receiving-document-total'),
              style: TextStyle(
                color: AdminTheme.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        if (receiving.originalMovements.isNotEmpty) ...[
          const SizedBox(height: 16),
          _impactBlock(
            key: const Key('receiving-original-impact'),
            title: receiving.isCancelled
                ? 'საწყისი გავლენა მარაგზე'
                : 'გავლენა მარაგზე',
            movements: receiving.originalMovements,
            lines: receiving.lines,
          ),
        ],
        if (receiving.reversalMovements.isNotEmpty) ...[
          const SizedBox(height: 12),
          _impactBlock(
            key: const Key('receiving-reversal-impact'),
            title: 'რევერსი',
            movements: receiving.reversalMovements,
            lines: receiving.lines,
          ),
        ],
        if (receiving.isCancelled) ...[
          const SizedBox(height: 12),
          Text(
            'გაუქმებულია${receiving.cancelledByName == null ? '' : ' · ${receiving.cancelledByName}'}'
            '${receiving.cancellationReason == null ? '' : '\n${receiving.cancellationReason}'}',
            style: TextStyle(color: AdminTheme.warn, fontSize: 12),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: AdminTheme.bad, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _lineTile(ReceivingLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.stockItemName,
                  style: TextStyle(
                    color: AdminTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${line.lineTotal} ₾',
                style: TextStyle(color: AdminTheme.text),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_quantityText(line.enteredQuantity)} ${_unitShort(line.enteredUnit)}'
            ' · ${line.unitPurchaseCost} ₾ / ${_unitShort(line.enteredUnit)}',
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
          ),
          if (line.isConverted)
            Text(
              'მიღებული: ${_quantityText(line.baseQuantity)} ${_unitShort(line.baseUnit)}'
              ' (${line.effectiveBaseUnitCost} ₾ / ${_unitShort(line.baseUnit)})',
              key: Key('receiving-line-converted-${line.lineSequence}'),
              style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _impactBlock({
    required Key key,
    required String title,
    required List<StockMovement> movements,
    required List<ReceivingLine> lines,
  }) {
    String nameFor(StockMovement movement) {
      for (final line in lines) {
        if (line.stockItemId == movement.stockItemId) {
          return line.stockItemName;
        }
      }
      return movement.stockItemId;
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AdminTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (final movement in movements)
          Text(
            '${movement.isNegative ? '' : '+'}${_quantityText(movement.quantityDeltaBase)}'
            ' ${_unitShort(movement.baseUnit)} · ${nameFor(movement)}',
            style: TextStyle(
              color: movement.isNegative ? AdminTheme.warn : AdminTheme.good,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  List<Widget> _actions(Receiving? receiving) {
    if (receiving == null) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: Text('დახურვა', style: TextStyle(color: AdminTheme.textMuted)),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, _changed),
        child: Text('დახურვა', style: TextStyle(color: AdminTheme.textMuted)),
      ),
      if (receiving.isDraft) ...[
        TextButton(
          key: const Key('receiving-delete'),
          onPressed: _busy ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: AdminTheme.bad),
          child: const Text('წაშლა'),
        ),
        OutlinedButton(
          key: const Key('receiving-edit'),
          onPressed: _busy ? null : () => widget.onEditDraft(receiving),
          style: OutlinedButton.styleFrom(
            foregroundColor: AdminTheme.text,
            side: BorderSide(color: AdminTheme.border),
          ),
          child: const Text('რედაქტირება'),
        ),
        FilledButton(
          key: const Key('receiving-post'),
          onPressed: _busy ? null : _post,
          style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
          child: Text(
            'მიღების დადასტურება',
            style: TextStyle(color: _inventoryOnPrimary),
          ),
        ),
      ],
      if (receiving.isPosted)
        FilledButton(
          key: const Key('receiving-cancel'),
          onPressed: _busy ? null : _cancel,
          style: FilledButton.styleFrom(backgroundColor: AdminTheme.warn),
          child: Text(
            'გაუქმება',
            style: TextStyle(color: _inventoryInk(AdminTheme.warn)),
          ),
        ),
    ];
  }

  Future<void> _post() async {
    final receiving = _receiving!;
    final confirmed = await _confirm(
      title: 'გატარდეს მიღება?',
      message:
          'დოკუმენტი გაიყინება და მარაგს დაემატება ${receiving.lineCount} პოზიცია. '
          'შემდეგ რედაქტირება აღარ იქნება შესაძლებელი — მხოლოდ გაუქმება რევერსით.',
      confirmLabel: 'გატარება',
      confirmKey: const Key('receiving-post-confirm'),
    );
    if (confirmed != true) return;
    await _run(() => MobileApiService.postReceiving(receiving.id));
  }

  Future<void> _cancel() async {
    final receiving = _receiving!;
    final confirmed = await _confirm(
      title: 'გაუქმდეს მიღება?',
      message:
          'დოკუმენტი და მისი საწყისი მოძრაობები რჩება. მარაგს დაემატება '
          'საპირისპირო მოძრაობები, რომლებიც ${receiving.documentTotal} ₾-ის მიღებას აბრუნებს.',
      confirmLabel: 'გაუქმება',
      confirmKey: const Key('receiving-cancel-confirm'),
    );
    if (confirmed != true) return;
    await _run(() => MobileApiService.cancelReceiving(receiving.id));
  }

  Future<void> _delete() async {
    final receiving = _receiving!;
    final confirmed = await _confirm(
      title: 'წაიშალოს მონახაზი?',
      message: 'მონახაზს მარაგზე გავლენა არ მოუხდენია და წაშლა უსაფრთხოა.',
      confirmLabel: 'წაშლა',
      confirmKey: const Key('receiving-delete-confirm'),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MobileApiService.deleteReceivingDraft(receiving.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _run(Future<Receiving> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _receiving = updated;
        _busy = false;
        _changed = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Key confirmKey,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        title: Text(title, style: TextStyle(color: AdminTheme.text)),
        content: Text(
          message,
          style: TextStyle(color: AdminTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'დახურვა',
              style: TextStyle(color: AdminTheme.textMuted),
            ),
          ),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
            child: Text(
              confirmLabel,
              style: TextStyle(color: _inventoryOnPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(color: AdminTheme.textDim, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: AdminTheme.text, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

// ── Editor ──────────────────────────────────────────────────────────────────

/// One line being entered, before Cloud validates and freezes it.
class _ReceivingLineDraft {
  _ReceivingLineDraft({
    required this.stockItem,
    required this.unit,
    required this.quantity,
    required this.cost,
  });

  StockItem? stockItem;
  InventoryUnit? unit;
  final TextEditingController quantity;
  final TextEditingController cost;
  String priceMode = "base";

  double get quantityValue =>
      double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;
  double get costValue =>
      double.tryParse(cost.text.trim().replaceAll(',', '.')) ?? 0;

  /// Preview only. Cloud recomputes both exactly before anything is stored.
  InventoryDecimal get lineTotal {
    try {
      final price = InventoryDecimal.parse(
        cost.text,
      ).round(priceMode == "total" ? 2 : 4);
      if (priceMode == 'total') return price;
      return ((priceMode == 'base'
                  ? (exactBaseQuantity ?? InventoryDecimal.zero)
                  : InventoryDecimal.parse(quantity.text).round(3)) *
              price)
          .round(2);
    } on FormatException {
      return InventoryDecimal.zero;
    }
  }

  String? get effectiveCost {
    final base = exactBaseQuantity;
    if (base == null || base.raw <= BigInt.zero) return null;
    return (lineTotal / base).toStringAsFixed(6);
  }

  InventoryDecimal? get exactBaseQuantity {
    final item = stockItem, entered = unit;
    if (item == null || entered == null) return null;
    try {
      final q = InventoryDecimal.parse(quantity.text).round(3);
      if (entered == item.baseUnit) return q;
      for (final p in item.purchaseUnits) {
        if (p.unit == entered)
          return (q * InventoryDecimal.parse(p.baseUnitMultiplier)).round(3);
      }
      if (entered.dimension != item.baseUnit.dimension) return null;
      const ratios = {'kg': '1000', 'g': '1', 'L': '1000', 'ml': '1'};
      if (!ratios.containsKey(entered.wireValue) ||
          !ratios.containsKey(item.baseUnit.wireValue))
        return null;
      return (q *
              InventoryDecimal.parse(ratios[entered.wireValue]!) /
              InventoryDecimal.parse(ratios[item.baseUnit.wireValue]!))
          .round(3);
    } on FormatException {
      return null;
    }
  }

  /// How many base units this line delivers, using the item's own packaging.
  double? get baseQuantity => exactBaseQuantity == null
      ? null
      : double.parse(exactBaseQuantity!.toStringAsFixed(3));

  /// Units this item may legitimately be received in.
  List<InventoryUnit> get allowedUnits {
    final item = stockItem;
    if (item == null) return const [];
    return <InventoryUnit>{
      item.baseUnit,
      for (final purchase in item.purchaseUnits) purchase.unit,
      for (final candidate in InventoryUnit.values)
        if (candidate.dimension != InventoryUnitDimension.count &&
            candidate.dimension == item.baseUnit.dimension)
          candidate,
    }.toList(growable: false);
  }

  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class ReceivingEditorDialog extends StatefulWidget {
  const ReceivingEditorDialog({
    super.key,
    required this.suppliers,
    required this.stockItems,
    this.receiving,
    this.businessDate,
    this.save,
    this.saveDraft,
    this.loadReceiving,
    this.postReceiving,
    this.recordPayment,
  });

  final Future<Receiving> Function(Map<String, dynamic>)? saveDraft;
  final Future<Receiving> Function(String)? loadReceiving, postReceiving;
  final Future<void> Function(String, Map<String, dynamic>)? recordPayment;
  final Receiving? receiving;
  final String? businessDate;
  final List<Supplier> suppliers;
  final List<StockItem> stockItems;

  /// Test seam. Production always goes through the Manager API.
  final Future<void> Function(Map<String, dynamic> payload)? save;

  @override
  State<ReceivingEditorDialog> createState() => _ReceivingEditorDialogState();
}

class _ReceivingEditorDialogState extends State<ReceivingEditorDialog> {
  late final TextEditingController _waybill;
  late final TextEditingController _invoice;
  late final TextEditingController _notes;
  late String _supplierId;
  String _sourceType = 'SUPPLIER',
      _paymentMode = 'unpaid',
      _paymentMethod = 'cash';
  final _sourceLabel = TextEditingController(),
      _paidNow = TextEditingController();
  final _paymentRequestId = const Uuid().v4();
  final _paymentDate = _isoDate(DateTime.now());
  bool _posted = false, _attempted = false;
  late DateTime _documentDate;
  DateTime? _businessDate;
  late List<_ReceivingLineDraft> _lines;
  late List<StockItem> _availableStock;
  bool _saving = false;
  String? _savedDraftId;
  final _requestId = const Uuid().v4();
  final _dueDate = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _availableStock = [...widget.stockItems];
    final receiving = widget.receiving;
    _dueDate.text = receiving?.dueDate ?? "";
    _waybill = TextEditingController(text: receiving?.waybillNumber ?? '');
    _invoice = TextEditingController(text: receiving?.invoiceNumber ?? '');
    _notes = TextEditingController(text: receiving?.notes ?? '');
    _supplierId =
        receiving?.supplierId ?? widget.suppliers.firstOrNull?.id ?? '';
    _sourceType =
        receiving?.sourceType ??
        (widget.suppliers.isEmpty ? 'SELF_PURCHASE' : 'SUPPLIER');
    if (_sourceType == 'SELF_PURCHASE')
      _sourceLabel.text = receiving?.supplierName ?? '';
    if (widget.suppliers.every((supplier) => supplier.id != _supplierId)) {
      _supplierId = widget.suppliers.firstOrNull?.id ?? '';
    }
    _documentDate =
        DateTime.tryParse(receiving?.documentDate ?? '') ?? DateTime.now();
    _businessDate = DateTime.tryParse(
      receiving?.effectiveBusinessDate ?? widget.businessDate ?? '',
    );
    _lines = [
      for (final line in receiving?.lines ?? const <ReceivingLine>[])
        _ReceivingLineDraft(
          stockItem: _availableStock
              .where((item) => item.id == line.stockItemId)
              .firstOrNull,
          unit: line.enteredUnit,
          quantity: TextEditingController(
            text: _quantityText(line.enteredQuantity),
          ),
          cost: TextEditingController(text: line.lineTotal),
        )..priceMode = "total",
    ];
    if (_lines.isEmpty) _seedSupplierLines();
  }

  @override
  void dispose() {
    _sourceLabel.dispose();
    _paidNow.dispose();
    _dueDate.dispose();
    _waybill.dispose();
    _invoice.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  List<StockItem> get _prioritizedItems {
    final linked =
        widget.suppliers
            .where((s) => s.id == _supplierId)
            .firstOrNull
            ?.stockItemIds ??
        const <String>[];
    return [
      ..._availableStock.where((item) => linked.contains(item.id)),
      ..._availableStock.where((item) => !linked.contains(item.id)),
    ];
  }

  void _seedSupplierLines() {
    final ids =
        widget.suppliers
            .where((s) => s.id == _supplierId)
            .firstOrNull
            ?.stockItemIds ??
        <String>[];
    for (final item in _availableStock.where((i) => ids.contains(i.id))) {
      _lines.add(
        _ReceivingLineDraft(
          stockItem: item,
          unit: item.purchaseUnits.firstOrNull?.unit ?? item.baseUnit,
          quantity: TextEditingController(),
          cost: TextEditingController(),
        ),
      );
    }
    if (_lines.isEmpty) _addLine();
  }

  Future<void> _newIngredient() async {
    final item = await showDialog<StockItem>(
      context: context,
      builder: (_) => const IngredientQuickDialog(),
    );
    if (item == null || !mounted) return;
    setState(() {
      _availableStock.add(item);
      final blank = _lines.where((l) => l.stockItem == null).firstOrNull;
      if (blank != null) {
        blank.stockItem = item;
        blank.unit = item.baseUnit;
      } else {
        _lines.add(
          _ReceivingLineDraft(
            stockItem: item,
            unit: item.baseUnit,
            quantity: TextEditingController(),
            cost: TextEditingController(),
          ),
        );
      }
    });
  }

  void _addLine() {
    final item = _prioritizedItems.firstOrNull;
    _lines.add(
      _ReceivingLineDraft(
        stockItem: item,
        unit: item?.baseUnit,
        quantity: TextEditingController(),
        cost: TextEditingController(),
      ),
    );
  }

  InventoryDecimal get _documentTotal => _lines.fold(
    InventoryDecimal.zero,
    (total, line) => total + line.lineTotal,
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(VynicSpacing.md),
        contentPadding: const EdgeInsets.all(VynicSpacing.md),
        key: const Key('receiving-editor'),
        backgroundColor: AdminTheme.surface,
        title: Text(
          widget.receiving == null ? 'ახალი მიღება' : 'მიღების რედაქტირება',
          style: TextStyle(color: AdminTheme.text),
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: AbsorbPointer(
              absorbing: _saving || _attempted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  if (_posted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'მარაგში დაემატა. გადახდის ჩაწერა ჯერ არ დასრულებულა — ხელახლა სცადეთ.',
                        style: TextStyle(color: AdminTheme.warn),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    key: const Key('receiving-source'),
                    initialValue: _sourceType,
                    isExpanded: true,
                    decoration: _adminInput('მომწოდებელი / წყარო'),
                    items: const [
                      DropdownMenuItem(
                        value: 'SUPPLIER',
                        child: Text('მომწოდებელი'),
                      ),
                      DropdownMenuItem(
                        value: 'SELF_PURCHASE',
                        child: Text('ჩემით / ბაზრიდან'),
                      ),
                    ],
                    onChanged: _saving || _attempted
                        ? null
                        : (v) => setState(() => _sourceType = v!),
                  ),
                  const SizedBox(height: 16),
                  if (_sourceType == 'SELF_PURCHASE')
                    TextField(
                      key: const Key('receiving-source-label'),
                      controller: _sourceLabel,
                      enabled: !_attempted,
                      decoration: _adminInput('საიდან? (არასავალდებულო)'),
                    ),
                  if (_sourceType == 'SUPPLIER')
                    DropdownButtonFormField<String>(
                      key: const Key('receiving-supplier'),
                      initialValue: _supplierId.isEmpty ? null : _supplierId,
                      isExpanded: true,
                      dropdownColor: AdminTheme.surfaceElevated,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.copyWith(color: AdminTheme.text),
                      decoration: _adminInput('ვისგან / საიდან?'),
                      items: [
                        for (final supplier in widget.suppliers)
                          DropdownMenuItem(
                            value: supplier.id,
                            child: Text(
                              supplier.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _supplierId = value ?? _supplierId;
                              if (_lines.every(
                                (l) =>
                                    l.quantity.text.isEmpty &&
                                    l.cost.text.isEmpty,
                              )) {
                                for (final line in _lines) {
                                  line.dispose();
                                }
                                _lines.clear();
                                _seedSupplierLines();
                              }
                            }),
                    ),
                  const SizedBox(height: 10),
                  ExpansionTile(
                    key: const PageStorageKey(
                      'inventory-receiving-document-details',
                    ),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('თარიღი და დოკუმენტის დეტალები'),
                    children: [
                      _InventoryExpansionContents(
                        children: [
                          OutlinedButton.icon(
                            key: const Key('receiving-business-date'),
                            icon: const Icon(Icons.today),
                            label: Text(
                              _businessDate == null
                                  ? 'აირჩიეთ სამუშაო დღე'
                                  : 'სამუშაო დღე: ${_isoDate(_businessDate!)}',
                            ),
                            onPressed: _saving
                                ? null
                                : () async {
                                    final selected = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _businessDate ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 366),
                                      ),
                                    );
                                    if (selected != null)
                                      setState(() => _businessDate = selected);
                                  },
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            key: const Key('receiving-date'),
                            onPressed: _saving ? null : _pickDate,
                            icon: const Icon(Icons.event_rounded, size: 18),
                            label: Text(
                              'დოკუმენტის თარიღი: ${_isoDate(_documentDate)}',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AdminTheme.text,
                              side: BorderSide(color: AdminTheme.border),
                              minimumSize: const Size(0, 52),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _dialogField(
                            _waybill,
                            'ზედნადების ნომერი',
                            key: const Key('receiving-waybill'),
                          ),
                          _dialogField(_invoice, 'ინვოისის ნომერი'),
                          _dialogField(_notes, 'შენიშვნა', maxLines: 2),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    'რას ვიღებთ დღეს?',
                    style: TextStyle(
                      color: AdminTheme.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var index = 0; index < _lines.length; index++)
                    _lineEditor(index),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('receiving-add-line'),
                      onPressed: _saving || _availableStock.isEmpty
                          ? null
                          : () => setState(_addLine),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('საქონლის დამატება'),
                      style: TextButton.styleFrom(
                        foregroundColor: AdminTheme.primary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : _newIngredient,
                    icon: const Icon(Icons.add),
                    label: const Text('ახალი ნედლეულის შექმნა'),
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ჯამი',
                          style: TextStyle(
                            color: AdminTheme.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_documentTotal.toStringAsFixed(2)} ₾',
                        key: const Key('receiving-editor-total'),
                        style: TextStyle(
                          color: AdminTheme.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'გადახდა',
                    style: TextStyle(
                      color: AdminTheme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    key: const Key('receiving-payment-mode'),
                    children: [
                      for (final mode in const {
                        'unpaid': 'ჯერ არ გადამიხდია',
                        'full': 'სრულად გადავიხადე',
                        'partial': 'ნაწილობრივ გადავიხადე',
                      }.entries)
                        ListTile(
                          key: Key('receiving-payment-${mode.key}'),
                          selected: _paymentMode == mode.key,
                          selectedColor: AdminTheme.primary,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _paymentMode == mode.key
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(mode.value),
                          onTap: _saving || _attempted
                              ? null
                              : () => setState(() => _paymentMode = mode.key),
                        ),
                    ],
                  ),
                  if (_paymentMode == 'partial') ...[
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('receiving-paid-now'),
                      controller: _paidNow,
                      enabled: !_attempted,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: _adminInput('ახლა გადავიხადე ₾'),
                    ),
                    const SizedBox(height: 8),
                    Text('დარჩა: ${_remainingPreview()} ₾'),
                  ],
                  if (_paymentMode != 'unpaid') ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: _adminInput('როგორ გადაიხადეთ?'),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('ნაღდი')),
                        DropdownMenuItem(value: 'bank', child: Text('ბანკი')),
                      ],
                      onChanged: _attempted
                          ? null
                          : (v) => setState(() => _paymentMethod = v!),
                    ),
                    const SizedBox(height: 8),
                    Text('გადახდის თარიღი: $_paymentDate'),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _dueDate,
                    decoration: _adminInput(
                      'გადახდის ვადა',
                    ).copyWith(helperText: 'არასავალდებულო · YYYY-MM-DD'),
                  ),
                  const SizedBox(height: 16),
                  _confirmationSummary(),
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
              ),
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  key: const Key('receiving-save'),
                  onPressed: _saving ? null : () => _save(post: true),
                  child: Text(
                    _saving
                        ? 'ინახება…'
                        : _posted
                        ? 'გადახდის ჩაწერის გამეორება'
                        : 'მიღების დადასტურება',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, _attempted),
                      child: const Text('დახურვა'),
                    ),
                    TextButton(
                      key: const Key('receiving-save-draft'),
                      onPressed: _saving || _attempted ? null : () => _save(),
                      child: const Text('მონახაზად შენახვა'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineEditor(int index) {
    final line = _lines[index];
    final base = line.baseQuantity;
    final converted =
        line.stockItem != null &&
        line.unit != null &&
        line.unit != line.stockItem!.baseUnit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey(
                    'receiving-line-item-$index-${line.stockItem?.id}',
                  ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                  ),
                  icon: const Icon(Icons.search),
                  label: Text(line.stockItem?.name ?? 'საქონლის არჩევა'),
                  onPressed: _saving
                      ? null
                      : () async {
                          final item = await showDialog<StockItem>(
                            context: context,
                            builder: (_) => InventoryIngredientPicker(
                              title: 'რას ვიღებთ?',
                              items: _prioritizedItems,
                            ),
                          );
                          if (item != null && mounted)
                            setState(() {
                              line.stockItem = item;
                              line.unit =
                                  item.purchaseUnits.firstOrNull?.unit ??
                                  item.baseUnit;
                            });
                        },
                ),
              ),
              IconButton(
                tooltip: 'წაშლა',
                onPressed: _saving || _lines.length == 1
                    ? null
                    : () => setState(() => _lines.removeAt(index).dispose()),
                icon: Icon(Icons.close_rounded, color: AdminTheme.textDim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _amountFields(line, index),
          if (line.effectiveCost != null && line.stockItem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${line.effectiveCost} ₾ / ${_unitShort(line.stockItem!.baseUnit)}',
                style: TextStyle(color: AdminTheme.textMuted),
              ),
            ),
          const SizedBox(height: 6),
          if (converted &&
              line.stockItem!.purchaseUnits.any((p) => p.unit == line.unit))
            Text(
              '1 ${_unitShort(line.unit!)} = ${_quantityText(line.stockItem!.purchaseUnits.firstWhere((p) => p.unit == line.unit).baseUnitMultiplier)} ${_unitShort(line.stockItem!.baseUnit)}',
              style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
            ),
          Row(
            children: [
              // The converted base quantity is shown before posting, so nobody
              // discovers that "10 box" meant 240 bottles only afterwards.
              Expanded(
                child: converted && base != null
                    ? Text(
                        'მიღებული: ${line.exactBaseQuantity?.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '') ?? '—'} ${_unitShort(line.stockItem!.baseUnit)}',
                        key: Key('receiving-line-base-$index'),
                        style: TextStyle(
                          color: AdminTheme.textMuted,
                          fontSize: 12,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Text(
                '${line.lineTotal.toStringAsFixed(2)} ₾',
                key: Key('receiving-line-total-$index'),
                style: TextStyle(
                  color: AdminTheme.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amountFields(_ReceivingLineDraft line, int index) {
    final quantity = TextField(
      key: Key('receiving-line-quantity-$index'),
      controller: line.quantity,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: AdminTheme.text),
      decoration: _adminInput('რაოდენობა'),
    );
    final unit = DropdownButtonFormField<InventoryUnit>(
      key: Key('receiving-line-unit-$index'),
      initialValue: line.unit,
      isExpanded: true,
      dropdownColor: AdminTheme.surfaceElevated,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: AdminTheme.text),
      decoration: _adminInput('ერთეული'),
      items: [
        for (final unit in line.allowedUnits)
          DropdownMenuItem(value: unit, child: Text(_unitShort(unit))),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(() {
              line.unit = value;
              if (value == line.stockItem?.baseUnit &&
                  line.priceMode == 'entered')
                line.priceMode = 'base';
            }),
    );
    final price = TextField(
      key: Key('receiving-line-cost-$index'),
      controller: line.cost,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: AdminTheme.text),
      decoration: _adminInput(
        line.priceMode == 'total'
            ? 'მთლიანად გადავიხადე / გადავიხდი ₾'
            : 'ფასი ₾ / ${line.priceMode == 'base'
                  ? line.stockItem == null
                        ? ''
                        : _unitShort(line.stockItem!.baseUnit)
                  : line.unit == null
                  ? ''
                  : _unitShort(line.unit!)}',
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: quantity),
            const SizedBox(width: 12),
            Expanded(child: unit),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'როგორ უთითებთ ფასს?',
          style: TextStyle(color: AdminTheme.textMuted),
        ),
        Wrap(
          key: Key('receiving-price-mode-$index'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in <String, String>{
              'base':
                  'ფასი / ${_unitShort(line.stockItem?.baseUnit ?? InventoryUnit.piece)}',
              if (line.unit != line.stockItem?.baseUnit)
                'entered':
                    'ფასი / ${_unitShort(line.unit ?? InventoryUnit.piece)}',
              'total': 'მთლიანი თანხა',
            }.entries)
              ChoiceChip(
                key: Key('receiving-price-$index-${mode.key}'),
                label: Text(mode.value),
                selected: line.priceMode == mode.key,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => line.priceMode = mode.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        price,
      ],
    );
  }

  Widget _confirmationSummary() => Card(
    key: const Key('receiving-confirmation-summary'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'დაემატება მარაგში:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final line in _lines.where(
            (l) => l.stockItem != null && l.quantity.text.trim().isNotEmpty,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${line.stockItem!.name} +${line.exactBaseQuantity?.toStringAsFixed(3) ?? '—'} ${_unitShort(line.stockItem!.baseUnit)}',
              ),
            ),
          const Divider(height: 24),
          Text('მიღების ღირებულება: ${_documentTotal.toStringAsFixed(2)} ₾'),
          const SizedBox(height: 8),
          Text(
            'ახლა გადახდილი: ${_paymentMode == 'unpaid' ? '0.00' : _paymentAmount} ₾',
          ),
          const SizedBox(height: 8),
          Text('დავალიანება: ${_remainingPreview()} ₾'),
          const SizedBox(height: 12),
          Text(
            'მონახაზი: მარაგში ჯერ არ დამატებულა',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _documentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _documentDate = picked);
  }

  String get _paymentAmount => _paymentMode == 'unpaid'
      ? '0.00'
      : _paymentMode == 'full'
      ? _documentTotal.toStringAsFixed(2)
      : _paidNow.text.trim().replaceAll(',', '.');
  Map<String, dynamic> get _paymentPayload => {
    'requestId': _paymentRequestId,
    'amount': _paymentAmount,
    'paymentDate': _paymentDate,
    'businessDate': _isoDate(_businessDate!),
    'method': _paymentMethod,
  };
  String _remainingPreview() {
    try {
      final paid = InventoryDecimal.parse(_paymentAmount);
      if (paid.raw > _documentTotal.raw) return 'თანხა აღემატება ჯამს';
      final cents = (_documentTotal.raw - paid.raw) ~/ BigInt.from(10000000000);
      return '${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
    } on FormatException {
      return _documentTotal.toStringAsFixed(2);
    }
  }

  Future<void> _save({bool post = false}) async {
    if (_businessDate == null) {
      setState(() => _error = 'აირჩიეთ რესტორნის სამუშაო დღე');
      return;
    }
    if (_sourceType == 'SUPPLIER' && _supplierId.isEmpty) {
      setState(() => _error = 'აირჩიეთ მომწოდებელი ან ჩემით / ბაზრიდან');
      return;
    }
    if (post && _paymentMode != 'unpaid') {
      try {
        final amount = InventoryDecimal.parse(_paymentAmount);
        if (amount.raw <= BigInt.zero ||
            amount.raw > _documentTotal.raw ||
            amount.round(2).raw != amount.raw)
          throw const FormatException();
      } on FormatException {
        setState(
          () => _error =
              'შეიყვანეთ გადახდილი თანხა ჯამის ფარგლებში (თეთრების სიზუსტით)',
        );
        return;
      }
    }
    final payload = <Map<String, dynamic>>[];
    for (final line in _lines) {
      if (line.quantity.text.trim().isEmpty &&
          line.cost.text.trim().isEmpty &&
          _lines.length > 1)
        continue;
      final item = line.stockItem;
      if (item == null) {
        setState(() => _error = 'აირჩიეთ პროდუქტი ყველა პოზიციაზე');
        return;
      }
      if (line.quantityValue <= 0) {
        setState(() => _error = '${item.name}: რაოდენობა უნდა იყოს დადებითი');
        return;
      }
      final price = double.tryParse(line.cost.text.trim().replaceAll(',', '.'));
      if (price == null || !price.isFinite || price < 0) {
        setState(
          () => _error = '${item.name}: ჩაწერეთ დღევანდელი შესყიდვის ფასი',
        );
        return;
      }
      if (line.baseQuantity == null) {
        setState(
          () => _error =
              '${item.name}: ${line.unit == null ? '' : _unitShort(line.unit!)} '
              'ვერ გადაიყვანება ${_unitShort(item.baseUnit)}-ში',
        );
        return;
      }
      payload.add(<String, dynamic>{
        'stockItemId': item.id,
        'enteredQuantity': line.quantity.text.trim().replaceAll(',', '.'),
        'enteredUnit': (line.unit ?? item.baseUnit).wireValue,
        if (line.priceMode != 'total') 'priceBasis': line.priceMode,
        line.priceMode == 'total' ? 'lineTotal' : 'unitPurchaseCost': line
            .cost
            .text
            .trim()
            .replaceAll(',', '.'),
      });
    }
    if (payload.isEmpty) {
      setState(() => _error = 'შეიყვანეთ მიღებული საქონელი');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final save = widget.save;
      if (save != null) {
        await save(<String, dynamic>{
          'post': post,
          'supplierId': _sourceType == 'SELF_PURCHASE' ? null : _supplierId,
          'sourceType': _sourceType,
          'sourceLabel': _sourceLabel.text.trim(),
          if (post && _paymentMode != 'unpaid') 'payment': _paymentPayload,
          'documentDate': _isoDate(_documentDate),
          if (_businessDate != null) 'businessDate': _isoDate(_businessDate!),
          'waybillNumber': _waybill.text.trim(),
          'lines': payload,
        });
      } else {
        _attempted = true;
        Receiving? saved;
        if (_savedDraftId != null)
          saved = await (widget.loadReceiving ?? MobileApiService.getReceiving)(
            _savedDraftId!,
          );
        if (saved?.isPosted != true) {
          saved = widget.saveDraft != null
              ? await widget.saveDraft!({
                  'requestId': _requestId,
                  'supplierId': _supplierId,
                  'sourceType': _sourceType,
                  'sourceLabel': _sourceLabel.text,
                  'lines': payload,
                })
              : await MobileApiService.saveReceivingDraft(
                  id: _savedDraftId ?? widget.receiving?.id,
                  requestId: _requestId,
                  dueDate: _dueDate.text.trim(),
                  supplierId: _supplierId,
                  sourceType: _sourceType,
                  sourceLabel: _sourceLabel.text.trim(),
                  documentDate: _isoDate(_documentDate),
                  businessDate: _isoDate(_businessDate!),
                  waybillNumber: _waybill.text,
                  invoiceNumber: _invoice.text,
                  notes: _notes.text,
                  lines: payload,
                );
          _savedDraftId = saved.id;
          if (post && !saved.isPosted)
            saved =
                await (widget.postReceiving ?? MobileApiService.postReceiving)(
                  saved.id,
                );
        }
        _posted = saved!.isPosted;
        if (post && _paymentMode != 'unpaid') {
          if (widget.recordPayment != null) {
            await widget.recordPayment!(saved.id, _paymentPayload);
          } else {
            await MobileApiService.procurementRequest(
              'receivings/${saved.id}/payments',
              _paymentPayload,
            );
          }
        }
      }
      if (mounted) {
        _adminToast(
          context,
          post
              ? 'მარაგში დაემატა'
              : 'მონახაზი შენახულია — მარაგში ჯერ არ დამატებულა',
        );
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }
}

// ── Stock Item detail ───────────────────────────────────────────────────────

/// Current stock, threshold, packaging and the recent ledger rows behind them.
class StockItemDetailDialog extends StatefulWidget {
  const StockItemDetailDialog({
    super.key,
    required this.stockItemId,
    this.load,
  });

  final String stockItemId;
  final Future<StockItemDetail> Function()? load;

  @override
  State<StockItemDetailDialog> createState() => _StockItemDetailDialogState();
}

class _StockItemDetailDialogState extends State<StockItemDetailDialog> {
  StockItemDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await (widget.load?.call() ??
              MobileApiService.getStockItem(widget.stockItemId));
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(VynicSpacing.md),
        contentPadding: const EdgeInsets.all(VynicSpacing.md),
        key: const Key('stock-item-detail'),
        backgroundColor: AdminTheme.surface,
        title: Text(
          detail?.item.name ?? 'პროდუქტი',
          style: TextStyle(color: AdminTheme.text),
        ),
        content: SizedBox(
          width: 520,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : detail == null
              ? Text(
                  _error ?? 'ვერ ჩაიტვირთა',
                  style: TextStyle(color: AdminTheme.bad, fontSize: 12),
                )
              : SingleChildScrollView(child: _body(detail)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'დახურვა',
              style: TextStyle(color: AdminTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(StockItemDetail detail) {
    final item = detail.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_quantityText(item.currentStock)} ${_unitShort(item.baseUnit)}',
                key: const Key('stock-detail-current'),
                style: TextStyle(
                  color: item.isNegativeStock
                      ? AdminTheme.bad
                      : item.isLowStock
                      ? AdminTheme.warn
                      : AdminTheme.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (item.isNegativeStock)
              const Text(
                'უარყოფითი მარაგი',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (item.isLowStock)
              const _LowStockBadge(),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'მიმდინარე საშუალო ფასი: ${detail.weightedUnitCost == null ? 'ისტორია არ არის' : '${_quantityText(detail.weightedUnitCost!)} ₾ / ${_unitShort(item.baseUnit)}'}',
          style: TextStyle(color: AdminTheme.text),
        ),
        if (detail.costStatus == 'PROVISIONAL')
          Text(
            'შეფასება წინასწარია — შეამოწმეთ უარყოფითი მარაგის ისტორია',
            style: TextStyle(color: AdminTheme.bad),
          ),
        if (detail.inventoryValue != null)
          Text('მარაგის ღირებულება: ${detail.inventoryValue} ₾'),
        for (final row in detail.purchaseHistory)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${row['businessDate']} · ${row['supplierName']}'),
            subtitle: Text(
              '${row['quantity']} ${_unitShort(InventoryUnit.parse('${row['baseUnit']}'))} · ${row['total']} ₾ · ${row['unitCost']} ₾ / ${_unitShort(InventoryUnit.parse('${row['baseUnit']}'))}',
            ),
          ),
        if (detail.lastPurchaseUnitCost != null)
          Text(
            'ბოლო შესყიდვის ფასი: ${_quantityText(detail.lastPurchaseUnitCost!)} ₾ / ${_unitShort(item.baseUnit)}',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        const SizedBox(height: 4),
        Text(
          'მარაგშია',
          style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
        ),
        const SizedBox(height: 14),
        _detailRow('როგორ ვითვლით საწყობში?', _unitLabel(item.baseUnit)),
        _detailRow(
          'მინიმალური მარაგი',
          item.minimumStock == null
              ? 'არ არის მითითებული'
              : '${_quantity(item.minimumStock!)} ${_unitShort(item.baseUnit)}',
        ),
        if (item.minimumStock != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'ამ რაოდენობაზე ნაკლების შემთხვევაში სისტემა გაგაფრთხილებთ.',
              key: const Key('stock-detail-minimum-help'),
              style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
            ),
          ),
        for (final unit in item.purchaseUnits)
          _detailRow(
            'როგორ მოდის მომწოდებლისგან?',
            '1 ${_unitShort(unit.unit)} = ${unit.baseUnitMultiplier} ${_unitShort(item.baseUnit)}',
          ),
        if (detail.suppliers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'მომწოდებლები',
            style: TextStyle(
              color: AdminTheme.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final supplier in detail.suppliers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('${supplier['name']}'),
            ),
        ],
        if (detail.usedBy.isNotEmpty) ...[
          const Divider(height: 24),
          Text(
            'გამოიყენება პროდუქტებში',
            style: TextStyle(
              color: AdminTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // The reverse of the recipe editor, and the question inventory
          // administration actually asks before renaming or disabling an item.
          for (final usage in detail.usedBy)
            Padding(
              key: Key('stock-detail-usage-${usage.recipeId}'),
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      usage.variantLabel == null
                          ? usage.menuItemName
                          : '${usage.menuItemName} · ${usage.variantLabel}',
                      style: TextStyle(color: AdminTheme.text, fontSize: 13),
                    ),
                  ),
                  Text(
                    usage.baseUnit == InventoryUnit.kg
                        ? '${_quantityText((InventoryDecimal.parse(usage.quantityPerUnit) * InventoryDecimal.parse('1000')).toStringAsFixed(3))} გ'
                        : '${_quantityText(usage.quantityPerUnit)} ${_unitShort(usage.baseUnit)}',
                    style: TextStyle(
                      color: AdminTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
        const Divider(height: 24),
        Text(
          'ბოლო მოძრაობები',
          style: TextStyle(
            color: AdminTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (detail.recentMovements.isEmpty)
          Text(
            'მოძრაობები ჯერ არ არის',
            key: const Key('stock-detail-no-movements'),
            style: TextStyle(color: AdminTheme.textDim, fontSize: 12),
          )
        else
          for (final movement in detail.recentMovements)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _movementLabel(movement),
                          style: TextStyle(
                            color: AdminTheme.text,
                            fontSize: 13,
                          ),
                        ),
                        if (movement.consumptionId != null)
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ConsumptionHistoryScreen(
                                  consumptionId: movement.consumptionId,
                                ),
                              ),
                            ),
                            child: const Text('დეტალები'),
                          ),
                        Text(
                          '${movement.businessDate} · ${movement.actorName}',
                          style: TextStyle(
                            color: AdminTheme.textDim,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${movement.isNegative ? '' : '+'}${_quantityText(movement.quantityDeltaBase)}'
                    ' ${_unitShort(movement.baseUnit)}',
                    style: TextStyle(
                      color: movement.isNegative
                          ? AdminTheme.warn
                          : AdminTheme.good,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

String _movementLabel(StockMovement movement) {
  final waybill = movement.receivingWaybillNumber;
  switch (movement.movementType) {
    case StockMovementType.receiving:
      return waybill == null ? 'მიღება' : 'მიღება #$waybill';
    case StockMovementType.receivingReversal:
      return waybill == null ? 'მიღების რევერსი' : 'მიღების რევერსი #$waybill';
    case StockMovementType.consumption:
      return 'ჩამოწერა · შეკვეთა #${movement.orderId ?? "—"}';
    case StockMovementType.consumptionReversal:
      return 'აღდგენა · შეკვეთა #${movement.orderId ?? "—"}';
    case StockMovementType.unknown:
      return 'მოძრაობა';
  }
}

String _isoDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

const List<String> _monthLabelsKa = [
  'იან',
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

/// `2026-09-05` reads as `05 სექ`. Falls back to the raw text if it is not a
/// date, so a malformed value is shown rather than swallowed.
String _receivingDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return '${parsed.day.toString().padLeft(2, '0')} ${_monthLabelsKa[parsed.month - 1]}';
}
