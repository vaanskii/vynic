import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';

/// A single variant option passed to [showMobileMenuPinSheet].
class MenuPinVariant {
  final String label;
  final double price;

  /// Caller-supplied tag to recover the original model after the sheet returns.
  final dynamic tag;

  const MenuPinVariant({
    required this.label,
    required this.price,
    this.tag,
  });
}

/// Result returned from [showMobileMenuPinSheet].
class MenuPinResult {
  final int qty;
  final MenuPinVariant? variant;
  const MenuPinResult({required this.qty, this.variant});
}

/// Shows a PIN-pad bottom sheet for selecting an item quantity.
///
/// Returns [MenuPinResult] when confirmed, or `null` when dismissed.
///
/// [inCartQty] – current quantity already in the cart (shown in the display).
/// [addMode]   – when true the label says "დამატება +qty → total"; when false
///               it says "დამატება ×qty".
Future<MenuPinResult?> showMobileMenuPinSheet(
  BuildContext context, {
  required String itemName,
  required double unitPrice,
  required List<MenuPinVariant> variants,
  int inCartQty = 0,
  bool addMode = false,
}) {
  return showModalBottomSheet<MenuPinResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MobileMenuPinSheet(
      itemName: itemName,
      unitPrice: unitPrice,
      variants: variants,
      inCartQty: inCartQty,
      addMode: addMode,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _MobileMenuPinSheet extends StatefulWidget {
  final String itemName;
  final double unitPrice;
  final List<MenuPinVariant> variants;
  final int inCartQty;
  final bool addMode;

  const _MobileMenuPinSheet({
    required this.itemName,
    required this.unitPrice,
    required this.variants,
    required this.inCartQty,
    required this.addMode,
  });

  @override
  State<_MobileMenuPinSheet> createState() => _MobileMenuPinSheetState();
}

class _MobileMenuPinSheetState extends State<_MobileMenuPinSheet> {
  String _input = '';
  late MenuPinVariant? _selectedVariant;

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.variants.isNotEmpty ? widget.variants.first : null;
  }

  double get _effectiveUnitPrice =>
      _selectedVariant?.price ?? widget.unitPrice;

  int get _qty => int.tryParse(_input) ?? 0;

  void _onKey(String key) {
    setState(() {
      if (key == 'C') {
        _input = '';
      } else if (key == '⌫') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else {
        if (_input.length < 4) _input += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final qty = _qty;
    final total = qty > 0 ? (qty * _effectiveUnitPrice) : 0.0;
    final cartAfter = widget.inCartQty + qty;

    return Container(
      decoration: BoxDecoration(
        color: MobileGlassTheme.surfaceCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: MobileGlassTheme.border(0.12)),
      ),
      padding: EdgeInsets.fromLTRB(
        16, 16, 16, 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MobileGlassTheme.border(0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Item header
          Text(
            widget.itemName,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: MobileGlassTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '${_effectiveUnitPrice.toStringAsFixed(1)} ₾ / ცალი',
            style: TextStyle(color: MobileGlassTheme.muted(0.65), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          if (widget.addMode && widget.inCartQty > 0) ...[
            const SizedBox(height: 4),
            Text(
              'კალათაში: ${widget.inCartQty}',
              style: TextStyle(
                color: MobileGlassTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          // Variant chips
          if (widget.variants.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: widget.variants.map((v) {
                final isSel = _selectedVariant == v;
                return ChoiceChip(
                  label: Text(v.label),
                  selected: isSel,
                  onSelected: (val) {
                    if (val) setState(() => _selectedVariant = v);
                  },
                  selectedColor: MobileGlassTheme.primary,
                  backgroundColor: MobileGlassTheme.surface(0.08),
                  labelStyle: TextStyle(
                    color: isSel ? Colors.white : MobileGlassTheme.muted(0.75),
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),

          // Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: MobileGlassTheme.surface(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MobileGlassTheme.border(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _input.isEmpty ? '0' : _input,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: _input.isEmpty
                        ? MobileGlassTheme.muted(0.3)
                        : MobileGlassTheme.textPrimary,
                  ),
                ),
                if (total > 0)
                  Text(
                    '${total.toStringAsFixed(1)} ₾',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: MobileGlassTheme.good,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // PIN pad grid
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['C', '0', '⌫'],
          ])
            Row(
              children: row.map((k) => _pinBtn(k)).toList(),
            ),

          const SizedBox(height: 12),

          // Confirm button
          MobileGlassPrimaryButton(
            label: _confirmLabel(qty, cartAfter),
            icon: Icons.add_shopping_cart_rounded,
            onPressed: qty > 0
                ? () => Navigator.pop(
                      context,
                      MenuPinResult(qty: qty, variant: _selectedVariant),
                    )
                : null,
          ),
        ],
      ),
    );
  }

  String _confirmLabel(int qty, int cartAfter) {
    if (qty <= 0) return 'დამატება';
    if (widget.addMode && widget.inCartQty > 0) {
      return 'დამატება  +$qty → $cartAfter';
    }
    return 'დამატება  ×$qty';
  }

  Widget _pinBtn(String label) {
    Color? fg;
    Color? bg;
    if (label == 'C') {
      fg = MobileGlassTheme.bad;
      bg = MobileGlassTheme.bad.withValues(alpha: 0.1);
    } else if (label == '⌫') {
      fg = MobileGlassTheme.muted(0.8);
      bg = MobileGlassTheme.surface(0.08);
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: bg ?? MobileGlassTheme.surface(0.08),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _onKey(label),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 58,
              child: Center(
                child: label == '⌫'
                    ? Icon(Icons.backspace_outlined,
                        color: fg ?? MobileGlassTheme.muted(0.8), size: 22)
                    : Text(
                        label,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: fg ?? MobileGlassTheme.textPrimary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
