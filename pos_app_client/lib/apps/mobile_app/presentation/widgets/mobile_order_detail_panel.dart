import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';

/// Full-screen cart panel for order editing (dark glass).
class MobileOrderDetailPanel extends StatelessWidget {
  const MobileOrderDetailPanel({
    super.key,
    required this.order,
    required this.highlightKeys,
    required this.onClose,
    required this.onQtyDelta,
    required this.onToggleServiceFee,
    this.serviceFeeAvailable = false,
    this.serviceFeePercentLabel = '10',
    this.onSave,
    this.hasChanges = false,
    this.orderIdLabel,
    this.tableLabel,
  });

  final Order order;
  final Set<String> highlightKeys;
  final VoidCallback onClose;
  final void Function(int index, int delta) onQtyDelta;
  final VoidCallback onToggleServiceFee;
  final bool serviceFeeAvailable;
  final String serviceFeePercentLabel;
  final VoidCallback? onSave;
  final bool hasChanges;
  final String? orderIdLabel;
  final String? tableLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MobileGlassTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          if (highlightKeys.isNotEmpty) _buildChangeBanner(),
          Expanded(
            child: order.items.isEmpty
                ? Center(
                    child: Text(
                      'შეკვეთა ცარიელია',
                      style: TextStyle(color: MobileGlassTheme.muted()),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: order.items.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _buildLine(context, order.items[i], i),
                  ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MobileGlassTheme.border(0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: MobileGlassTheme.textPrimary,
            ),
            tooltip: 'უკან',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'შეკვეთის კალათა',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: MobileGlassTheme.textPrimary,
                  ),
                ),
                if (tableLabel != null && tableLabel!.isNotEmpty)
                  Text(
                    tableLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      color: MobileGlassTheme.muted(),
                    ),
                  ),
                if (orderIdLabel != null)
                  Text(
                    orderIdLabel!,
                    style: TextStyle(
                      fontSize: 10,
                      color: MobileGlassTheme.muted(0.4),
                    ),
                  ),
              ],
            ),
          ),
          if (hasChanges && onSave != null)
            TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('შენახვა'),
              style: TextButton.styleFrom(
                foregroundColor: MobileGlassTheme.good,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChangeBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: MobileGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 12,
        borderColor: MobileGlassTheme.highlightBorder.withValues(alpha: 0.5),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              color: MobileGlassTheme.warn,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'POS-დან განახლება (${highlightKeys.length})',
                style: TextStyle(
                  color: MobileGlassTheme.muted(0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(BuildContext context, OrderItem item, int index) {
    final highlighted = PosChangeHighlightService.shouldHighlightItem(
      highlightKeys,
      item.itemKey,
      item.itemName,
    );
    return MobileGlassCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      borderColor: highlighted
          ? MobileGlassTheme.highlightBorder.withValues(alpha: 0.65)
          : MobileGlassTheme.border(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: highlighted
                        ? MobileGlassTheme.warn
                        : MobileGlassTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${item.unitPrice.toStringAsFixed(1)} ₾ × ${item.quantity}',
                  style: TextStyle(
                    fontSize: 13,
                    color: MobileGlassTheme.muted(),
                  ),
                ),
                if (item.comment != null && item.comment!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.comment!,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: MobileGlassTheme.muted(0.45),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _qtyBtn(Icons.remove_rounded, () => onQtyDelta(index, -1)),
              SizedBox(
                width: 32,
                child: Text(
                  '${item.quantity}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: MobileGlassTheme.textPrimary,
                  ),
                ),
              ),
              _qtyBtn(Icons.add_rounded, () => onQtyDelta(index, 1)),
            ],
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 68,
            child: Text(
              '${item.total.toStringAsFixed(2)} ₾',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: highlighted
                    ? MobileGlassTheme.warn
                    : MobileGlassTheme.good,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: MobileGlassTheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: MobileGlassTheme.primary),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: MobileGlassTheme.surface(0.08),
        border: Border(top: BorderSide(color: MobileGlassTheme.border(0.08))),
      ),
      child: Column(
        children: [
          if (serviceFeeAvailable) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'სერვისი ($serviceFeePercentLabel%)',
                    style: TextStyle(
                      fontSize: 14,
                      color: MobileGlassTheme.muted(),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: order.includeServiceFee,
                  activeColor: MobileGlassTheme.primary,
                  onChanged: (_) => onToggleServiceFee(),
                ),
              ],
            ),
            SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'სულ',
                style: TextStyle(fontSize: 13, color: MobileGlassTheme.muted()),
              ),
              Text(
                '${order.totalAmount.toStringAsFixed(2)} ₾',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: MobileGlassTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
