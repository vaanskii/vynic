import 'package:flutter/material.dart';

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
    required this.onOpenDraftManage,
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
  final ValueChanged<QuickOrderDraft> onOpenDraftManage;
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
    final filteredDrafts = _filteredDrafts;
    final selectedDraft = _selectedDraft(filteredDrafts);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.hideTitle) _buildPageHeading(),
          if (!widget.hideTitle) const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 860;
                final draftListWidth = constraints.maxWidth < 1120
                    ? 320.0
                    : 360.0;

                if (isCompact) {
                  return ListView(
                    children: [
                      SizedBox(
                        height: 420,
                        child: _buildDraftBrowser(filteredDrafts),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 560,
                        child: _buildSelectedDraftPanel(selectedDraft),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: draftListWidth,
                      child: _buildDraftBrowser(filteredDrafts),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: _buildSelectedDraftPanel(selectedDraft)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<QuickOrderDraft> get _filteredDrafts {
    final query = _searchController.text.trim().toLowerCase();
    return widget.quickOrderDrafts.where((draft) {
      final matchesSearch =
          query.isEmpty ||
          (draft.displayName ?? '').toLowerCase().contains(query) ||
          draft.createdBy.toLowerCase().contains(query) ||
          draft.items.any(
            (item) => item.itemName.toLowerCase().contains(query),
          );
      return matchesSearch;
    }).toList();
  }

  QuickOrderDraft? _selectedDraft(List<QuickOrderDraft> visibleDrafts) {
    if (visibleDrafts.isEmpty) return null;
    for (final draft in visibleDrafts) {
      if (draft.id == _selectedDraftId) return draft;
    }
    return visibleDrafts.first;
  }

  Widget _buildPageHeading() {
    return PosPageHeading(
      title: 'დათვლილი მენიუ',
      subtitle:
          'აირჩიეთ შენახული მენიუ და მართეთ მისი პროდუქტები მარჯვენა '
          'პანელიდან.',
      trailing: PosPrimaryButton(
        label: 'ახალი დათვლა',
        icon: Icons.add_rounded,
        onTap: widget.onStartQuickOrder,
      ),
    );
  }

  Widget _buildStats() {
    final drafts = widget.quickOrderDrafts;
    final totalItems = drafts.fold<int>(
      0,
      (sum, draft) => sum + _totalQuantity(draft),
    );
    final totalValue = drafts.fold<double>(
      0,
      (sum, draft) => sum + draft.total,
    );
    final serviceCount = drafts
        .where((draft) => draft.includeServiceFee)
        .length;

    return Row(
      children: [
        Expanded(
          child: PosMetricCard(
            label: 'შენახული მენიუ',
            value: '${drafts.length}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PosMetricCard(label: 'პროდუქტები', value: '$totalItems'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PosMetricCard(label: 'სერვისით', value: '$serviceCount'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PosMetricCard(
            label: 'სრული ღირებულება',
            value: '${totalValue.toStringAsFixed(2)} ₾',
          ),
        ),
      ],
    );
  }

  Widget _buildDraftBrowser(List<QuickOrderDraft> drafts) {
    final visibleSelectionId = _selectedDraft(drafts)?.id;
    return _Panel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: PosOnScreenTextField(
                    controller: _searchController,
                    keyboardLanguage: 'ka',
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'ძებნა მენიუში...',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (widget.canManageDrafts &&
                    widget.quickOrderDrafts.isNotEmpty)
                  IconButton(
                    tooltip: 'ყველას წაშლა',
                    onPressed: widget.onClearAllDrafts,
                    color: VynicFloorTokens.dangerText,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: drafts.isEmpty
                ? _buildEmptyList()
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: drafts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      return _DraftListCard(
                        draft: draft,
                        selected: draft.id == visibleSelectionId,
                        textPrimary: widget.textPrimary,
                        mutedText: widget.mutedText,
                        onTap: () {
                          setState(() => _selectedDraftId = draft.id);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: widget.mutedText.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            Text(
              widget.quickOrderDrafts.isEmpty
                  ? 'შენახული მენიუები ჯერ არ არსებობს'
                  : 'ძებნის შედეგი ვერ მოიძებნა',
              style: TextStyle(
                color: widget.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.quickOrderDrafts.isEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onStartQuickOrder,
                icon: const Icon(Icons.add_rounded),
                label: const Text('პირველი მენიუს შექმნა'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedDraftPanel(QuickOrderDraft? draft) {
    if (draft == null) {
      return _Panel(
        child: Center(
          child: Text(
            'აირჩიეთ მენიუ დეტალების სანახავად',
            style: TextStyle(color: widget.mutedText),
          ),
        ),
      );
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'არჩეული პროდუქტები (${draft.items.length})',
                    style: TextStyle(
                      color: widget.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_totalQuantity(draft)} ცალი',
                  style: TextStyle(
                    color: widget.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${draft.total.toStringAsFixed(2)} ₾',
                  style: TextStyle(
                    color: widget.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: draft.items.isEmpty
                ? Center(
                    child: Text(
                      'ამ მენიუში პროდუქტები არ არის',
                      style: TextStyle(color: widget.mutedText),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: draft.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = draft.items[index];
                      return _SelectedItemRow(
                        item: item,
                        textPrimary: widget.textPrimary,
                        mutedText: widget.mutedText,
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
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: const BoxDecoration(
              color: VynicFloorTokens.metricFill,
              border: Border(
                top: BorderSide(color: VynicFloorTokens.panelBorder),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _CompactTotal(
                      label: 'ქვეჯამი',
                      value: draft.subtotal,
                      muted: true,
                    ),
                    if (widget.serviceFeeAvailable) ...[
                      const SizedBox(width: 14),
                      Tooltip(
                        message:
                            'დააჭირეთ ჩასართავად/გამოსართავად • გეჭიროთ პროცენტის შესაცვლელად',
                        child: OutlinedButton.icon(
                          onPressed: () => widget.onToggleServiceFee(draft),
                          onLongPress: () =>
                              widget.onOpenServiceFeeConfig(draft),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: draft.includeServiceFee
                                ? VynicFloorTokens.accentText
                                : VynicFloorTokens.textMuted,
                            backgroundColor: draft.includeServiceFee
                                ? VynicFloorTokens.accentSoft
                                : Colors.white,
                            side: BorderSide(
                              color: draft.includeServiceFee
                                  ? VynicFloorTokens.accentBadgeText
                                  : VynicFloorTokens.panelBorder,
                            ),
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: Icon(
                            draft.includeServiceFee
                                ? Icons.toggle_on_rounded
                                : Icons.toggle_off_rounded,
                            size: 19,
                          ),
                          label: Text(
                            draft.includeServiceFee
                                ? 'სერვისი ${(draft.serviceFeeRate * 100).toStringAsFixed(0)}%'
                                : 'სერვისი',
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    _CompactTotal(label: 'ჯამი', value: draft.total),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onPrintDraft(draft),
                        style: _compactActionStyle(),
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text('ბეჭდვა'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => widget.onContinueDraft(draft),
                        style: FilledButton.styleFrom(
                          backgroundColor: VynicFloorTokens.accentStrong,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('მენიუს შეცვლა'),
                      ),
                    ),
                    if (widget.canManageDrafts) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => widget.onOpenDraftManage(draft),
                          style: FilledButton.styleFrom(
                            backgroundColor: VynicFloorTokens.accentText,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                          ),
                          label: const Text('მართვა'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B0F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        child: child,
      ),
    );
  }
}

class _DraftListCard extends StatelessWidget {
  const _DraftListCard({
    required this.draft,
    required this.selected,
    required this.textPrimary,
    required this.mutedText,
    required this.onTap,
  });

  final QuickOrderDraft draft;
  final bool selected;
  final Color textPrimary;
  final Color mutedText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? VynicFloorTokens.accentSoft : VynicFloorTokens.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? VynicFloorTokens.accentBadgeText
              : VynicFloorTokens.panelBorder,
          width: selected ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _draftTitle(draft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: _ServiceBadge(active: draft.includeServiceFee),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 92,
                    child: Text(
                      '${draft.total.toStringAsFixed(2)} ₾',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: const TextStyle(
                        color: VynicFloorTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${_formatDate(draft.createdAt)}  •  ${draft.createdBy}',
                style: TextStyle(color: mutedText, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'სერვისი ჩართულია' : 'სერვისი გამორთულია',
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? VynicFloorTokens.accentSoft
              : VynicFloorTokens.metricFill,
          border: Border.all(
            color: active
                ? VynicFloorTokens.accentBadgeText
                : VynicFloorTokens.panelBorder,
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          Icons.percent_rounded,
          size: 15,
          color: active
              ? VynicFloorTokens.accentText
              : VynicFloorTokens.textFaint,
        ),
      ),
    );
  }
}

class _SelectedItemRow extends StatelessWidget {
  const _SelectedItemRow({
    required this.item,
    required this.textPrimary,
    required this.mutedText,
    required this.onDecrease,
    required this.onIncrease,
    required this.onDelete,
  });

  final OrderItem item;
  final Color textPrimary;
  final Color mutedText;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.comment?.trim().isNotEmpty == true)
                  Text(
                    item.comment!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedText, fontSize: 10),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Center(
              child: Container(
                height: 27,
                decoration: BoxDecoration(
                  border: Border.all(color: VynicFloorTokens.panelBorder),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QuantityButton(icon: Icons.remove, onTap: onDecrease),
                    Container(
                      width: 34,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border.symmetric(
                          vertical: BorderSide(
                            color: VynicFloorTokens.panelBorder,
                          ),
                        ),
                      ),
                      child: Text(
                        '${item.quantity}',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _QuantityButton(icon: Icons.add, onTap: onIncrease),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${item.unitPrice.toStringAsFixed(2)} ₾',
              textAlign: TextAlign.right,
              style: TextStyle(color: mutedText, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${item.total.toStringAsFixed(2)} ₾',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'წაშლა',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            color: mutedText,
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 27,
        height: 26,
        child: Icon(icon, size: 14, color: VynicFloorTokens.text),
      ),
    );
  }
}

ButtonStyle _compactActionStyle() {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
  );
}

class _CompactTotal extends StatelessWidget {
  const _CompactTotal({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final double value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: muted ? VynicFloorTokens.textMuted : VynicFloorTokens.text,
            fontSize: muted ? 10 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${value.toStringAsFixed(2)} ₾',
          style: TextStyle(
            color: VynicFloorTokens.text,
            fontSize: muted ? 11 : 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

String _draftTitle(QuickOrderDraft draft) {
  final name = draft.displayName?.trim();
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
        onOpenDraftManage: (_) {},
        onClearAllDrafts: () {},
        primaryColor: const Color(0xFF1E3A8A),
        secondaryColor: const Color(0xFF2563EB),
        textPrimary: const Color(0xFF1F2937),
        mutedText: const Color(0xFF64748B),
      ),
    ),
  );
}
