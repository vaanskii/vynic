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
              color: selected == filter ? Colors.white : AdminTheme.textMuted,
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
      return (color: AdminTheme.textDim, label: 'მონახაზი');
    case ReceivingStatus.posted:
      return (color: AdminTheme.good, label: 'გატარებული');
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
    return AlertDialog(
      key: const Key('receiving-detail'),
      backgroundColor: AdminTheme.surface,
      title: Row(
        children: [
          Expanded(
            child: Text(
              'მიღება',
              style: TextStyle(color: AdminTheme.text),
            ),
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
    );
  }

  Widget _body(Receiving receiving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _detailRow('მომწოდებელი', receiving.supplierName),
        if (receiving.waybillNumber != null)
          _detailRow('ზედნადები', receiving.waybillNumber!),
        if (receiving.invoiceNumber != null)
          _detailRow('ინვოისი', receiving.invoiceNumber!),
        _detailRow('თარიღი', _receivingDate(receiving.documentDate)),
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
          Text(
            _error!,
            style: TextStyle(color: AdminTheme.bad, fontSize: 12),
          ),
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
          child: Text(
            'დახურვა',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, _changed),
        child: Text(
          'დახურვა',
          style: TextStyle(color: AdminTheme.textMuted),
        ),
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
          child: const Text(
            'გატარება',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
      if (receiving.isPosted)
        FilledButton(
          key: const Key('receiving-cancel'),
          onPressed: _busy ? null : _cancel,
          style: FilledButton.styleFrom(backgroundColor: AdminTheme.warn),
          child: const Text(
            'გაუქმება',
            style: TextStyle(color: Colors.white),
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
              style: const TextStyle(color: Colors.white),
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

  double get quantityValue =>
      double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;
  double get costValue =>
      double.tryParse(cost.text.trim().replaceAll(',', '.')) ?? 0;

  /// Preview only. Cloud recomputes both exactly before anything is stored.
  double get lineTotal => quantityValue * costValue;

  /// How many base units this line delivers, using the item's own packaging.
  double? get baseQuantity {
    final item = stockItem;
    final entered = unit;
    if (item == null || entered == null) return null;
    if (entered == item.baseUnit) return quantityValue;
    for (final purchase in item.purchaseUnits) {
      if (purchase.unit == entered) return quantityValue * purchase.multiplier;
    }
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

  /// Units this item may legitimately be received in.
  List<InventoryUnit> get allowedUnits {
    final item = stockItem;
    if (item == null) return const [];
    return <InventoryUnit>{
      item.baseUnit,
      for (final purchase in item.purchaseUnits) purchase.unit,
      for (final candidate in InventoryUnit.values)
        if (candidate.dimension == item.baseUnit.dimension) candidate,
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
    this.save,
  });

  final Receiving? receiving;
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
  late DateTime _documentDate;
  late List<_ReceivingLineDraft> _lines;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final receiving = widget.receiving;
    _waybill = TextEditingController(text: receiving?.waybillNumber ?? '');
    _invoice = TextEditingController(text: receiving?.invoiceNumber ?? '');
    _notes = TextEditingController(text: receiving?.notes ?? '');
    _supplierId = receiving?.supplierId ?? widget.suppliers.first.id;
    if (widget.suppliers.every((supplier) => supplier.id != _supplierId)) {
      _supplierId = widget.suppliers.first.id;
    }
    _documentDate =
        DateTime.tryParse(receiving?.documentDate ?? '') ?? DateTime.now();
    _lines = [
      for (final line in receiving?.lines ?? const <ReceivingLine>[])
        _ReceivingLineDraft(
          stockItem: widget.stockItems
              .where((item) => item.id == line.stockItemId)
              .firstOrNull,
          unit: line.enteredUnit,
          quantity: TextEditingController(
            text: _quantityText(line.enteredQuantity),
          ),
          cost: TextEditingController(text: line.unitPurchaseCost),
        ),
    ];
    if (_lines.isEmpty) _addLine();
  }

  @override
  void dispose() {
    _waybill.dispose();
    _invoice.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    final item = widget.stockItems.firstOrNull;
    _lines.add(
      _ReceivingLineDraft(
        stockItem: item,
        unit: item?.baseUnit,
        quantity: TextEditingController(),
        cost: TextEditingController(),
      ),
    );
  }

  double get _documentTotal =>
      _lines.fold(0, (total, line) => total + line.lineTotal);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('receiving-editor'),
      backgroundColor: AdminTheme.surface,
      title: Text(
        widget.receiving == null ? 'ახალი მიღება' : 'მიღების რედაქტირება',
        style: TextStyle(color: AdminTheme.text),
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('receiving-supplier'),
                initialValue: _supplierId,
                dropdownColor: AdminTheme.surfaceElevated,
                style: TextStyle(color: AdminTheme.text),
                decoration: _adminInput('მომწოდებელი *'),
                items: [
                  for (final supplier in widget.suppliers)
                    DropdownMenuItem(
                      value: supplier.id,
                      child: Text(supplier.name),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _supplierId = value ?? _supplierId),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('receiving-date'),
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('თარიღი: ${_isoDate(_documentDate)}'),
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
              const Divider(height: 24),
              for (var index = 0; index < _lines.length; index++)
                _lineEditor(index),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('receiving-add-line'),
                  onPressed: _saving || widget.stockItems.isEmpty
                      ? null
                      : () => setState(_addLine),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('პოზიციის დამატება'),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminTheme.primary,
                  ),
                ),
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
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(
            'გაუქმება',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        ),
        FilledButton(
          key: const Key('receiving-save'),
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'შენახვა',
                  style: TextStyle(color: Colors.white),
                ),
        ),
      ],
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
                child: DropdownButtonFormField<String>(
                  key: Key('receiving-line-item-$index'),
                  initialValue: line.stockItem?.id,
                  isExpanded: true,
                  dropdownColor: AdminTheme.surfaceElevated,
                  style: TextStyle(color: AdminTheme.text, fontSize: 13),
                  decoration: _adminInput('პროდუქტი'),
                  items: [
                    for (final item in widget.stockItems)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          line.stockItem = widget.stockItems
                              .where((item) => item.id == value)
                              .firstOrNull;
                          line.unit = line.stockItem?.baseUnit;
                        }),
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
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: Key('receiving-line-quantity-$index'),
                  controller: line.quantity,
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
                flex: 3,
                child: DropdownButtonFormField<InventoryUnit>(
                  key: Key('receiving-line-unit-$index'),
                  initialValue: line.unit,
                  dropdownColor: AdminTheme.surfaceElevated,
                  style: TextStyle(color: AdminTheme.text, fontSize: 13),
                  decoration: _adminInput('ერთეული'),
                  items: [
                    for (final unit in line.allowedUnits)
                      DropdownMenuItem(
                        value: unit,
                        child: Text(_unitShort(unit)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => line.unit = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: TextField(
                  key: Key('receiving-line-cost-$index'),
                  controller: line.cost,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: TextStyle(color: AdminTheme.text),
                  decoration: _adminInput('ფასი ერთეულზე'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // The converted base quantity is shown before posting, so nobody
              // discovers that "10 box" meant 240 bottles only afterwards.
              Expanded(
                child: converted && base != null
                    ? Text(
                        'მიღებული: ${_quantity(base)} ${_unitShort(line.stockItem!.baseUnit)}',
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _documentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _documentDate = picked);
  }

  Future<void> _save() async {
    final payload = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final item = line.stockItem;
      if (item == null) {
        setState(() => _error = 'აირჩიეთ პროდუქტი ყველა პოზიციაზე');
        return;
      }
      if (line.quantityValue <= 0) {
        setState(() => _error = '${item.name}: რაოდენობა უნდა იყოს დადებითი');
        return;
      }
      if (line.costValue < 0) {
        setState(() => _error = '${item.name}: ფასი არ უნდა იყოს უარყოფითი');
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
        'unitPurchaseCost': line.cost.text.trim().replaceAll(',', '.').isEmpty
            ? '0'
            : line.cost.text.trim().replaceAll(',', '.'),
      });
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final save = widget.save;
      if (save != null) {
        await save(<String, dynamic>{
          'supplierId': _supplierId,
          'documentDate': _isoDate(_documentDate),
          'waybillNumber': _waybill.text.trim(),
          'lines': payload,
        });
      } else {
        await MobileApiService.saveReceivingDraft(
          id: widget.receiving?.id,
          supplierId: _supplierId,
          documentDate: _isoDate(_documentDate),
          waybillNumber: _waybill.text,
          invoiceNumber: _invoice.text,
          notes: _notes.text,
          lines: payload,
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

// ── Stock Item detail ───────────────────────────────────────────────────────

/// Current stock, threshold, packaging and the recent ledger rows behind them.
class StockItemDetailDialog extends StatefulWidget {
  const StockItemDetailDialog({super.key, required this.stockItemId, this.load});

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
    return AlertDialog(
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
                  color: item.isLowStock ? AdminTheme.warn : AdminTheme.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (item.isLowStock) const _LowStockBadge(),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'მიმდინარე ნაშთი მოძრაობების ჯამია',
          style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
        ),
        const SizedBox(height: 14),
        _detailRow('საბაზო ერთეული', _unitLabel(item.baseUnit)),
        _detailRow(
          'მინიმალური ნაშთი',
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
            'შესყიდვის შეფუთვა',
            '1 ${_unitShort(unit.unit)} = ${unit.baseUnitMultiplier} ${_unitShort(item.baseUnit)}',
          ),
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
                    '${_quantityText(usage.quantityPerUnit)} ${_unitShort(usage.baseUnit)}',
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
