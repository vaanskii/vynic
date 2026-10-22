import 'package:flutter/material.dart';
import '../shared/pos_workflow_actions.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:flutter/widget_previews.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

typedef QuickOrderItemQuantityChanged =
    void Function(QuickOrderDraft draft, OrderItem item, int quantity);

class HomeCalculatorSection extends StatefulWidget {
  const HomeCalculatorSection({
    super.key,
    required this.quickOrderDrafts,
    required this.onStartQuickOrder,
    required this.onToggleServiceFee,
    required this.onOpenServiceFeeConfig,
    required this.onContinueDraft,
    required this.onPrintDraft,
    required this.onItemQuantityChanged,
    required this.serviceFeeAvailable,
    required this.canManageDrafts,
    this.canDeleteDrafts = false,
    required this.onConfirmDraft,
    required this.onRenameDraft,
    required this.onPreviewDraft,
    required this.onDeleteDraft,
    required this.onClearAllDrafts,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
    this.hideTitle = false,
  });

  final List<QuickOrderDraft> quickOrderDrafts;
  final VoidCallback onStartQuickOrder;
  final ValueChanged<QuickOrderDraft> onToggleServiceFee;
  final ValueChanged<QuickOrderDraft> onOpenServiceFeeConfig;
  final ValueChanged<QuickOrderDraft> onContinueDraft;
  final ValueChanged<QuickOrderDraft> onPrintDraft;
  final QuickOrderItemQuantityChanged onItemQuantityChanged;
  final bool serviceFeeAvailable;
  final bool canManageDrafts;
  final bool canDeleteDrafts;
  final ValueChanged<QuickOrderDraft> onConfirmDraft;
  final ValueChanged<QuickOrderDraft> onRenameDraft;
  final ValueChanged<QuickOrderDraft> onPreviewDraft;
  final ValueChanged<QuickOrderDraft> onDeleteDraft;
  final VoidCallback onClearAllDrafts;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;
  final bool hideTitle;

  @override
  State<HomeCalculatorSection> createState() => _HomeCalculatorSectionState();
}

class _HomeCalculatorSectionState extends State<HomeCalculatorSection> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedDraftId;
  int _narrowPane = 0;

  @override
  void initState() {
    super.initState();
    _selectedDraftId = widget.quickOrderDrafts.firstOrNull?.id;
  }

  @override
  void didUpdateWidget(covariant HomeCalculatorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quickOrderDrafts.isEmpty) {
      _selectedDraftId = null;
      return;
    }
    final selectionStillExists = widget.quickOrderDrafts.any(
      (draft) => draft.id == _selectedDraftId,
    );
    if (!selectionStillExists) {
      _selectedDraftId = widget.quickOrderDrafts.first.id;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _filteredDrafts;
    final selected = _selectedDraft(drafts);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.hideTitle) ...[
            PosPageHeading(
              title: 'დათვლა',
              subtitle: 'მენიუს შეფასებები',
              trailing: FilledButton.tonalIcon(
                style: posWorkflowButtonStyle(context),
                onPressed: widget.onStartQuickOrder,
                icon: const Icon(Icons.add, size: 22),
                label: const Text('ახალი დათვლა'),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Expanded(
            child: PosWorkspace(
              master: _browser(drafts),
              detail: _detail(selected),
              paneLabels: const ['სია', 'შეფასება'],
              selectedPane: _narrowPane,
              onPaneSelected: (value) => setState(() => _narrowPane = value),
            ),
          ),
        ],
      ),
    );
  }

  List<QuickOrderDraft> get _filteredDrafts {
    final query = _searchController.text.trim().toLowerCase();
    return widget.quickOrderDrafts
        .where((draft) => draft.matchesSearch(query))
        .toList();
  }

  QuickOrderDraft? _selectedDraft(List<QuickOrderDraft> visibleDrafts) {
    if (visibleDrafts.isEmpty) return null;
    for (final draft in visibleDrafts) {
      if (draft.id == _selectedDraftId) return draft;
    }
    return visibleDrafts.first;
  }

  Widget _browser(List<QuickOrderDraft> drafts) {
    final selectedId = _selectedDraft(drafts)?.id;
    final total = widget.quickOrderDrafts.fold<double>(
      0,
      (sum, draft) => sum + draft.total,
    );
    return ColoredBox(
      color: VynicFloorTokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: PosOnScreenTextField(
              controller: _searchController,
              keyboardLanguage: 'ka',
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ძებნა',
                helperText: 'სახელი · ტელეფონი · თანხა',
                helperStyle: const TextStyle(
                  fontSize: 12,
                  color: VynicFloorTokens.textMuted,
                ),
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: VynicFloorTokens.textMuted,
                ),
                prefixIcon: const Icon(Icons.search, size: 22),
                filled: true,
                fillColor: VynicFloorTokens.panel,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: VynicFloorTokens.panelBorder,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: VynicFloorTokens.panelBorder,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                const Text(
                  'შენახული',
                  style: TextStyle(
                    color: VynicFloorTokens.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${drafts.length}',
                  style: const TextStyle(color: VynicFloorTokens.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: drafts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.quickOrderDrafts.isEmpty
                            ? 'შენახული მენიუები ჯერ არ არსებობს'
                            : 'ძებნის შედეგი ვერ მოიძებნა',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: VynicFloorTokens.textMuted,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: drafts.length,
                    itemBuilder: (context, index) => _DraftListRow(
                      draft: drafts[index],
                      selected: drafts[index].id == selectedId,
                      onTap: () => setState(() {
                        _selectedDraftId = drafts[index].id;
                        _narrowPane = 1;
                      }),
                    ),
                  ),
          ),
          const Divider(height: 1, color: VynicFloorTokens.panelBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.quickOrderDrafts.length} შეფასება',
                        style: const TextStyle(
                          color: VynicFloorTokens.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'სრული ღირებულება · ${total.toStringAsFixed(2)} ₾',
                        style: const TextStyle(
                          color: VynicFloorTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.canDeleteDrafts &&
                    widget.quickOrderDrafts.isNotEmpty)
                  PosWorkflowIconButton(
                    label: 'ყველას წაშლა',
                    icon: Icons.delete_sweep_outlined,
                    onPressed: widget.onClearAllDrafts,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(QuickOrderDraft? draft) {
    if (draft == null)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calculate_outlined,
                size: 40,
                color: VynicFloorTokens.textMuted,
              ),
              const SizedBox(height: 20),
              Text(
                widget.quickOrderDrafts.isEmpty
                    ? 'შექმენით პირველი შეფასება'
                    : 'აირჩიეთ მენიუ დეტალების სანახავად',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (widget.quickOrderDrafts.isEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'აირჩიეთ კერძები და შეინახეთ მენიუს ღირებულება.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VynicFloorTokens.textMuted),
                ),
                const SizedBox(height: 24),
                PosWorkflowButton(
                  label: 'პირველი მენიუს შექმნა',
                  icon: Icons.add,
                  primary: true,
                  onPressed: widget.onStartQuickOrder,
                ),
              ],
            ],
          ),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'შეფასება · ${_formatDate(draft.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: VynicFloorTokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _draftTitle(draft),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: VynicFloorTokens.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (draft.customerPhone?.trim().isNotEmpty == true)
                          draft.customerPhone!,
                        '${_totalQuantity(draft)} პროდუქტი',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: VynicFloorTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.canManageDrafts)
                PosWorkflowIconButton(
                  label: 'სახელის შეცვლა',
                  icon: Icons.edit_outlined,
                  onPressed: () => widget.onRenameDraft(draft),
                ),
              if (widget.canDeleteDrafts)
                PosWorkflowIconButton(
                  label: 'შეფასების წაშლა',
                  icon: Icons.delete_outline,
                  danger: true,
                  onPressed: () => widget.onDeleteDraft(draft),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: VynicFloorTokens.panelBorder),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Expanded(child: _ColumnLabel('პროდუქტი')),
              SizedBox(
                width: 152,
                child: _ColumnLabel('რაოდენობა', align: TextAlign.center),
              ),
              SizedBox(
                width: 112,
                child: _ColumnLabel('თანხა', align: TextAlign.right),
              ),
              SizedBox(width: 56),
            ],
          ),
        ),
        Expanded(
          child: draft.items.isEmpty
              ? const Center(child: Text('ამ მენიუში პროდუქტები არ არის'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: draft.items.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    color: VynicFloorTokens.panelBorder,
                  ),
                  itemBuilder: (context, index) {
                    final item = draft.items[index];
                    return _SelectedItemRow(
                      item: item,
                      onDecrease: () => widget.onItemQuantityChanged(
                        draft,
                        item,
                        item.quantity - 1,
                      ),
                      onIncrease: () => widget.onItemQuantityChanged(
                        draft,
                        item,
                        item.quantity + 1,
                      ),
                      onDelete: () =>
                          widget.onItemQuantityChanged(draft, item, 0),
                    );
                  },
                ),
        ),
        _totals(draft),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final documents = [
                if (widget.canManageDrafts)
                  Tooltip(
                    message: 'ქვითრის ნახვა / PDF',
                    child: TextButton.icon(
                      style: posWorkflowButtonStyle(context),
                      onPressed: () => widget.onPreviewDraft(draft),
                      icon: const Icon(Icons.receipt_long_outlined, size: 22),
                      label: const Text('ნახვა'),
                    ),
                  ),
                TextButton.icon(
                  style: posWorkflowButtonStyle(context),
                  onPressed: () => widget.onPrintDraft(draft),
                  icon: const Icon(Icons.print_outlined, size: 22),
                  label: const Text('ბეჭდვა'),
                ),
              ];
              final actions = [
                PosWorkflowButton(
                  label: 'მენიუს შეცვლა',
                  icon: Icons.edit_outlined,
                  onPressed: () => widget.onContinueDraft(draft),
                ),
                if (widget.canManageDrafts)
                  PosWorkflowButton(
                    label: 'რეზერვაცია',
                    icon: Icons.event_available_outlined,
                    primary: true,
                    onPressed: () => widget.onConfirmDraft(draft),
                  ),
              ];
              if (constraints.maxWidth < 740)
                return Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [...documents, ...actions],
                );
              return Row(
                children: [
                  ...documents,
                  const Spacer(),
                  actions.first,
                  if (actions.length > 1) ...[
                    const SizedBox(width: 12),
                    actions.last,
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _totals(QuickOrderDraft draft) => Container(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
    decoration: const BoxDecoration(
      color: VynicFloorTokens.canvas,
      border: Border(top: BorderSide(color: VynicFloorTokens.panelBorder)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ქვეჯამი  ${draft.subtotal.toStringAsFixed(2)} ₾',
                style: const TextStyle(
                  color: VynicFloorTokens.textMuted,
                  fontSize: 14,
                ),
              ),
              if (widget.serviceFeeAvailable)
                Row(
                  children: [
                    Switch(
                      value: draft.includeServiceFee,
                      onChanged: (_) => widget.onToggleServiceFee(draft),
                    ),
                    Flexible(
                      child: Text(
                        draft.includeServiceFee
                            ? 'სერვისი ${(draft.serviceFeeRate * 100).toStringAsFixed(0)}%'
                            : 'სერვისი',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PosWorkflowIconButton(
                      label: 'სერვისის პროცენტი',
                      icon: Icons.expand_more,
                      onPressed: () => widget.onOpenServiceFeeConfig(draft),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'სულ',
              style: TextStyle(color: VynicFloorTokens.textMuted, fontSize: 13),
            ),
            Text(
              '${draft.total.toStringAsFixed(2)} ₾',
              style: const TextStyle(
                color: VynicFloorTokens.text,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.label, {this.align = TextAlign.left});
  final String label;
  final TextAlign align;
  @override
  Widget build(BuildContext context) => Text(
    label,
    textAlign: align,
    style: const TextStyle(
      fontSize: 12,
      color: VynicFloorTokens.textMuted,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _DraftListRow extends StatelessWidget {
  const _DraftListRow({
    required this.draft,
    required this.selected,
    required this.onTap,
  });
  final QuickOrderDraft draft;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? VynicFloorTokens.accentSoft : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(21, 20, 24, 20),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected
                  ? VynicFloorTokens.accentStrong
                  : Colors.transparent,
            ),
            bottom: const BorderSide(color: VynicFloorTokens.panelBorder),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _draftTitle(draft),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: VynicFloorTokens.text,
              ),
            ),
            if (draft.customerPhone?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text(
                draft.customerPhone!,
                style: const TextStyle(
                  fontSize: 13,
                  color: VynicFloorTokens.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '${_formatDate(draft.createdAt)} · ${draft.createdBy}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: VynicFloorTokens.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Tooltip(
                  message: draft.includeServiceFee
                      ? 'სერვისი ჩართულია'
                      : 'სერვისი გამორთულია',
                  child: Icon(
                    Icons.percent,
                    size: 17,
                    color: draft.includeServiceFee
                        ? VynicFloorTokens.accentText
                        : VynicFloorTokens.textFaint,
                  ),
                ),
                const Spacer(),
                Text(
                  '${draft.total.toStringAsFixed(2)} ₾',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? VynicFloorTokens.accentStrong
                        : VynicFloorTokens.text,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SelectedItemRow extends StatelessWidget {
  const _SelectedItemRow({
    required this.item,
    required this.onDecrease,
    required this.onIncrease,
    required this.onDelete,
  });
  final OrderItem item;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.itemName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: VynicFloorTokens.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.unitPrice.toStringAsFixed(2)} ₾ / ცალი',
                style: const TextStyle(
                  fontSize: 13,
                  color: VynicFloorTokens.textMuted,
                ),
              ),
              if (item.comment?.trim().isNotEmpty == true)
                Text(
                  item.comment!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: VynicFloorTokens.textMuted,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 152,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: VynicFloorTokens.canvas,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _QuantityButton(icon: Icons.remove, onTap: onDecrease),
                Expanded(
                  child: Text(
                    '${item.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _QuantityButton(icon: Icons.add, onTap: onIncrease),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 112,
          child: Text(
            '${item.total.toStringAsFixed(2)} ₾',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: VynicFloorTokens.text,
            ),
          ),
        ),
        PosWorkflowIconButton(
          label: 'პროდუქტის ამოღება',
          icon: Icons.delete_outline,
          onPressed: onDelete,
        ),
      ],
    ),
  );
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: icon == Icons.add ? 'რაოდენობის გაზრდა' : 'რაოდენობის შემცირება',
    style: posWorkflowButtonStyle(
      context,
    ).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.zero)),
    onPressed: onTap,
    icon: Icon(icon, size: 22),
  );
}

String _draftTitle(QuickOrderDraft draft) {
  final name = (draft.customerName ?? draft.displayName)?.trim();
  if (name != null && name.isNotEmpty) return name;
  return 'დათვლილი მენიუ';
}

int _totalQuantity(QuickOrderDraft draft) {
  return draft.items.fold<int>(0, (sum, item) => sum + item.quantity);
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day.$month.${value.year}  $hour:$minute';
}

@Preview(name: 'Counted menus desktop', group: 'Home', size: Size(1440, 900))
Widget countedMenusDesktopPreview() {
  final drafts = [
    QuickOrderDraft(
      id: 'preview-1',
      items: [
        OrderItem(
          itemKey: 'khachapuri',
          itemName: 'ხაჭაპური',
          unitPrice: 12,
          quantity: 2,
          total: 24,
        ),
        OrderItem(
          itemKey: 'caesar',
          itemName: 'ცეზარის სალათი',
          unitPrice: 18,
          quantity: 1,
          total: 18,
        ),
        OrderItem(
          itemKey: 'steak',
          itemName: 'სტეიკი',
          unitPrice: 26,
          quantity: 2,
          total: 52,
        ),
      ],
      subtotal: 94,
      serviceFeeAmount: 9.4,
      total: 103.4,
      includeServiceFee: true,
      serviceFeeRate: 0.1,
      createdAt: DateTime(2026, 6, 24, 18, 30),
      createdBy: 'ნინო',
      displayName: 'ვახშმის მენიუ',
    ),
    QuickOrderDraft(
      id: 'preview-2',
      items: [
        OrderItem(
          itemKey: 'lobio',
          itemName: 'ლობიო',
          unitPrice: 14,
          quantity: 3,
          total: 42,
        ),
      ],
      subtotal: 42,
      serviceFeeAmount: 0,
      total: 42,
      includeServiceFee: false,
      serviceFeeRate: 0,
      createdAt: DateTime(2026, 6, 23, 14),
      createdBy: 'გიორგი',
      displayName: 'სადილის მენიუ',
    ),
  ];

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'NotoSansGeorgian',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
    ),
    home: Scaffold(
      backgroundColor: VynicFloorTokens.page,
      body: HomeCalculatorSection(
        quickOrderDrafts: drafts,
        onStartQuickOrder: () {},
        onToggleServiceFee: (_) {},
        onOpenServiceFeeConfig: (_) {},
        onContinueDraft: (_) {},
        onPrintDraft: (_) {},
        onItemQuantityChanged: (_, _, _) {},
        serviceFeeAvailable: true,
        canManageDrafts: true,
        onConfirmDraft: (_) {},
        onRenameDraft: (_) {},
        onPreviewDraft: (_) {},
        onDeleteDraft: (_) {},
        onClearAllDrafts: () {},
        primaryColor: const Color(0xFF1E3A8A),
        secondaryColor: const Color(0xFF2563EB),
        textPrimary: const Color(0xFF1F2937),
        mutedText: const Color(0xFF64748B),
      ),
    ),
  );
}
