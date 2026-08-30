import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/data/models/takeaway_models.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const SectionCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MobileGlassTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MobileGlassTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: MobileGlassTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class QtyButton extends StatelessWidget {
  final int qty;
  final VoidCallback onInc;
  final VoidCallback onDec;

  const QtyButton({
    super.key,
    required this.qty,
    required this.onInc,
    required this.onDec,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (qty > 0) ...[
          GestureDetector(
            onTap: onDec,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: MobileGlassTheme.bad.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.remove, size: 16, color: MobileGlassTheme.bad),
            ),
          ),
          SizedBox(width: 8),
          Text(
            '$qty',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: MobileGlassTheme.textPrimary,
            ),
          ),
          SizedBox(width: 8),
        ],
        GestureDetector(
          onTap: onInc,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: MobileGlassTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add, size: 16, color: MobileGlassTheme.primary),
          ),
        ),
      ],
    );
  }
}

class CartSummarySection extends StatelessWidget {
  final Map<String, TakeawayCartEntry> cart;
  final double total;
  final void Function(String itemName) onInc;
  final void Function(String itemName) onDec;

  const CartSummarySection({
    super.key,
    required this.cart,
    required this.total,
    required this.onInc,
    required this.onDec,
  });

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: 'კალათა',
      child: Column(
        children: [
          ...cart.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: TextStyle(
                        fontSize: 13,
                        color: MobileGlassTheme.textPrimary,
                      ),
                    ),
                  ),
                  QtyButton(
                    qty: e.value.quantity,
                    onInc: () => onInc(e.key),
                    onDec: () => onDec(e.key),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'სულ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: MobileGlassTheme.textPrimary,
                ),
              ),
              Text(
                '${total.toStringAsFixed(2)} ₾',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: MobileGlassTheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MenuItemsSection extends StatelessWidget {
  final List<TakeawayMenuItem> menuItems;
  final Map<String, TakeawayCartEntry> cart;
  final void Function(TakeawayMenuItem item) onInc;
  final void Function(String itemName) onDec;

  const MenuItemsSection({
    super.key,
    required this.menuItems,
    required this.cart,
    required this.onInc,
    required this.onDec,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'მენიუ',
      child: Column(
        children: menuItems.map((item) {
          final qty = cart[item.name]?.quantity ?? 0;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              item.name,
              style: TextStyle(
                fontSize: 13,
                color: MobileGlassTheme.textPrimary,
              ),
            ),
            subtitle: Text(
              '${item.price.toStringAsFixed(2)} ₾',
              style: TextStyle(
                color: MobileGlassTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            trailing: QtyButton(
              qty: qty,
              onInc: () => onInc(item),
              onDec: () => onDec(item.name),
            ),
          );
        }).toList(),
      ),
    );
  }
}
