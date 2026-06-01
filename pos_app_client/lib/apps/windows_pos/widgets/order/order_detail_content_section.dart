import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos_change_highlight_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';

class OrderDetailContentSection extends StatefulWidget {
  const OrderDetailContentSection({
    super.key,
    required this.order,
    required this.canModify,
    required this.isAdmin,
    this.highlightItemKeys,
    this.onOrderUpdated,
  });

  final Order order;
  final bool canModify;
  final bool isAdmin;
  final Set<String>? highlightItemKeys;
  final Future<void> Function()? onOrderUpdated;

  @override
  State<OrderDetailContentSection> createState() =>
      _OrderDetailContentSectionState();
}

class _OrderDetailContentSectionState extends State<OrderDetailContentSection> {
  static const Color _surfaceColor = Color(0xFFF5F7FB);
  static const Color _panelColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _titleColor = Color(0xFF1E293B);
  static const Color _mutedTextColor = Color(0xFF64748B);
  static const Color _accentColor = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final canModify = widget.canModify;
    final hasPackage =
        (order.packageId != null && order.packageId!.isNotEmpty) ||
        order.packagePrice > 0 ||
        order.packageItems.isNotEmpty ||
        order.packageGuestCount > 0;

    if (!hasPackage && order.items.isEmpty) {
      return const Center(
        child: Text(
          'შეკვეთაში პოზიციები არ არის',
          style: TextStyle(color: _mutedTextColor, fontSize: 16),
        ),
      );
    }

    final children = _buildOrderItemsChildren(
      order,
      canModify,
      hasPackage,
      includePackageItems: false,
    );
    final fullMenuChildren = _buildOrderItemsChildren(
      order,
      canModify,
      hasPackage,
      includePackageItems: true,
    );
    final packageCount = order.packageItems
        .where((item) => item.quantity > 0)
        .length;
    final itemsCount = order.items.where((item) => item.quantity > 0).length;
    final totalCount = packageCount + itemsCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _showOrderItemsDialog(fullMenuChildren),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accentColor,
              side: BorderSide(color: _accentColor.withValues(alpha: 0.35)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.menu_book, size: 18),
            label: Text('მენიუს სრულად ნახვა ($totalCount)'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: children,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildOrderItemsChildren(
    Order order,
    bool canModify,
    bool hasPackage, {
    required bool includePackageItems,
  }) {
    final children = <Widget>[];

    if (hasPackage) {
      children.add(_buildPackageSummary(order, canModify));
      if (includePackageItems && order.packageItems.isNotEmpty) {
        children.add(const SizedBox(height: 16));
        children.add(_buildSectionLabel('პაკეტში შემავალი'));
        children.add(const SizedBox(height: 8));
        children.addAll(
          order.packageItems.map(
            (item) => _buildOrderItemTile(item, isPackageItem: true),
          ),
        );
      }
      children.add(const SizedBox(height: 24));
    }

    if (order.items.isEmpty) {
      children.add(_buildNoAdditionalItemsNotice());
    } else {
      final sectionLabel = hasPackage
          ? 'დამატებითი პოზიციები'
          : 'შეკვეთის პოზიციები';
      children.add(_buildSectionLabel(sectionLabel));
      children.add(const SizedBox(height: 8));
      children.addAll(order.items.map((item) => _buildOrderItemTile(item)));
    }

    return children;
  }

  Future<void> _showOrderItemsDialog(List<Widget> children) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: size.width * 0.95,
              maxHeight: size.height * 0.95,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: _panelColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.restaurant_menu, color: _accentColor),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'შეკვეთის მენიუ',
                            style: TextStyle(
                              color: _titleColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, color: _mutedTextColor),
                          tooltip: 'დახურვა',
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: _borderColor.withValues(alpha: 0.7),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPackageAdjustmentDialog(Order order) async {
    if (_isFinalizedStatus(order.status)) {
      return;
    }
    final packageId = order.packageId;
    if (packageId == null || packageId.isEmpty) {
      if (mounted) {
        unawaited(showErrorToast(context, 'პაკეტის დეტალები ვერ მოიძებნა'));
      }
      return;
    }

    final package = DatabaseService.getPackageById(packageId);
    if (package == null) {
      if (mounted) {
        unawaited(showErrorToast(context, 'პაკეტი აღარ არსებობს'));
      }
      return;
    }

    final result = await _showPackageAdjustmentDialog(
      order: order,
      package: package,
    );

    if (result == null) {
      return;
    }

    if (!_havePackageAdjustmentsChanged(order, result)) {
      return;
    }

    order.packageGuestCount = result.guestCount;
    order.packageUnitPrice = package.pricePerPerson;
    order.packagePrice = package.pricePerPerson * result.guestCount;
    order.packageName = package.name;
    order.packageId = package.packageId;
    order.packageItems
      ..clear()
      ..addAll(result.items);
    order.updatedAt = DatabaseService.getCurrentDateTime();

    await DatabaseService.updateOrder(order);
    if (!mounted) {
      return;
    }

    if (widget.onOrderUpdated != null) {
      await widget.onOrderUpdated!();
    }
    if (!mounted) {
      return;
    }

    unawaited(showSuccessToast(context, 'პაკეტი განახლდა'));
  }

  Future<_PackageAdjustmentResult?> _showPackageAdjustmentDialog({
    required Order order,
    required Package package,
  }) async {
    final initialGuestCount = order.packageGuestCount > 0
        ? order.packageGuestCount
        : (package.servingSize > 0 ? package.servingSize : 1);
    int guestCount = initialGuestCount;
    final guestController = TextEditingController(
      text: initialGuestCount.toString(),
    );

    final orderItemsByKey = {
      for (final item in order.packageItems) item.itemKey: item,
    };

    final packageItemsByKey = {
      for (final item in package.items) item.itemKey: item,
    };

    final List<_AdjustablePackageItem> adjustableItems = [
      for (final pkgItem in package.items)
        _AdjustablePackageItem(
          itemKey: pkgItem.itemKey,
          itemName: pkgItem.itemName,
          unitPrice: pkgItem.unitPrice,
          baseQuantity: pkgItem.quantity,
          quantity:
              orderItemsByKey[pkgItem.itemKey]?.quantity ??
              _calculateScaledQuantity(
                baseQuantity: pkgItem.quantity,
                guestCount: guestCount,
                servingSize: package.servingSize,
              ),
        ),
    ];

    for (final orderItem in order.packageItems) {
      if (!packageItemsByKey.containsKey(orderItem.itemKey)) {
        adjustableItems.add(
          _AdjustablePackageItem(
            itemKey: orderItem.itemKey,
            itemName: orderItem.itemName,
            unitPrice: orderItem.unitPrice,
            baseQuantity: null,
            quantity: orderItem.quantity,
          ),
        );
      }
    }

    void applyRecommendedQuantities(int targetGuestCount) {
      for (final item in adjustableItems) {
        if (item.baseQuantity != null) {
          item.quantity = _calculateScaledQuantity(
            baseQuantity: item.baseQuantity!,
            guestCount: targetGuestCount,
            servingSize: package.servingSize,
          );
        }
      }
    }

    final menuItemOptions = _buildMenuItemOptions();
    final initialItemsByKey = {
      for (final item in order.packageItems)
        if (item.quantity > 0) item.itemKey: item.quantity,
    };

    try {
      return await showDialog<_PackageAdjustmentResult>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final packageTotal = package.pricePerPerson * guestCount;
              final itemsSubtotal = adjustableItems.fold<double>(
                0,
                (sum, item) => sum + item.total,
              );

              void decreaseGuestCount() {
                if (guestCount <= 1) {
                  return;
                }
                setDialogState(() {
                  guestCount -= 1;
                  applyRecommendedQuantities(guestCount);
                  guestController.text = guestCount.toString();
                });
              }

              void increaseGuestCount() {
                setDialogState(() {
                  guestCount += 1;
                  applyRecommendedQuantities(guestCount);
                  guestController.text = guestCount.toString();
                });
              }

              void resetToRecommended() {
                setDialogState(() {
                  applyRecommendedQuantities(guestCount);
                });
              }

              Map<String, int> collectCurrentItemsByKey() {
                return {
                  for (final item in adjustableItems)
                    if (item.quantity > 0) item.itemKey: item.quantity,
                };
              }

              bool hasUnsavedChanges() {
                if (guestCount != initialGuestCount) {
                  return true;
                }
                final current = collectCurrentItemsByKey();
                if (current.length != initialItemsByKey.length) {
                  return true;
                }
                for (final entry in current.entries) {
                  if (initialItemsByKey[entry.key] != entry.value) {
                    return true;
                  }
                }
                return false;
              }

              Future<void> requestCloseAdjustment() async {
                if (!hasUnsavedChanges()) {
                  Navigator.of(dialogContext).pop();
                  return;
                }

                final shouldClose = await showDialog<bool>(
                  context: dialogContext,
                  barrierDismissible: false,
                  builder: (confirmContext) => AlertDialog(
                    backgroundColor: Colors.white,
                    surfaceTintColor: Colors.white,
                    title: const Text('დაუმახსოვრებელი ცვლილებები'),
                    content: const Text(
                      'პაკეტში ცვლილებები არ არის შენახული. ნამდვილად გსურთ დახურვა?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(confirmContext).pop(false),
                        child: const Text('დაბრუნება'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(confirmContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black26),
                        ),
                        child: const Text('დახურვა'),
                      ),
                    ],
                  ),
                );

                if (shouldClose == true && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }

              Future<void> addItemsFromMenu() async {
                final selectedItems = await _showMenuItemPicker(
                  dialogContext,
                  menuItemOptions,
                );
                if (selectedItems == null || selectedItems.isEmpty) {
                  return;
                }

                final optionsByKey = {
                  for (final option in menuItemOptions) option.key: option,
                };

                setDialogState(() {
                  for (final entry in selectedItems.entries) {
                    final option = optionsByKey[entry.key];
                    if (option == null || entry.value <= 0) {
                      continue;
                    }
                    final existingIndex = adjustableItems.indexWhere(
                      (item) => item.itemKey == option.key,
                    );
                    if (existingIndex != -1) {
                      adjustableItems[existingIndex].quantity += entry.value;
                    } else {
                      adjustableItems.add(
                        _AdjustablePackageItem(
                          itemKey: option.key,
                          itemName: option.displayName,
                          unitPrice: option.unitPrice,
                          baseQuantity: null,
                          quantity: entry.value,
                        ),
                      );
                    }
                  }
                });
              }

              Future<void> showPackageItemsDialog() async {
                final currentItems = adjustableItems
                    .where((item) => item.quantity > 0)
                    .toList();

                await showDialog<void>(
                  context: dialogContext,
                  builder: (itemsDialogContext) {
                    return AlertDialog(
                      backgroundColor: Colors.white,
                      surfaceTintColor: Colors.white,
                      title: const Text('პაკეტის პოზიციები'),
                      content: SizedBox(
                        width: 520,
                        child: currentItems.isEmpty
                            ? const Text('პაკეტში პოზიციები არ არის.')
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: currentItems.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (context, index) {
                                  final item = currentItems[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(item.itemName),
                                    subtitle: Text(
                                      'რაოდენობა: ${item.quantity} • ერთეული: ${item.unitPrice.toStringAsFixed(2)} GEL',
                                    ),
                                    trailing: Text(
                                      '${item.total.toStringAsFixed(2)} GEL',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(itemsDialogContext).pop(),
                          child: const Text('დახურვა'),
                        ),
                      ],
                    );
                  },
                );
              }

              Widget buildQuantityTile(_AdjustablePackageItem item) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.itemName,
                              style: const TextStyle(
                                color: _titleColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (item.baseQuantity == null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF59E0B,
                                ).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'მენიუდან დამატებული',
                                style: TextStyle(
                                  color: Color(0xFFB45309),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            color: _mutedTextColor,
                            splashRadius: 20,
                            onPressed: item.quantity <= 0
                                ? null
                                : () {
                                    setDialogState(() {
                                      item.quantity = item.quantity - 1;
                                    });
                                  },
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${item.quantity}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _titleColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: _mutedTextColor,
                            splashRadius: 20,
                            onPressed: () {
                              setDialogState(() {
                                item.quantity = item.quantity + 1;
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'ერთეული: ${item.unitPrice.toStringAsFixed(2)} GEL',
                            style: const TextStyle(
                              color: _mutedTextColor,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${item.total.toStringAsFixed(2)} GEL',
                            style: const TextStyle(
                              color: _accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (item.baseQuantity != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'საბაზისო: ${item.baseQuantity} / ${package.servingSize} სტუმარი',
                            style: const TextStyle(
                              color: _mutedTextColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }

              final size = MediaQuery.of(dialogContext).size;

              return Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Container(
                    color: const Color(0xFFF1F5F9),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(color: _borderColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.tune, color: _accentColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'პაკეტის კორექტირება - ${package.name}',
                                  style: const TextStyle(
                                    color: _titleColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: requestCloseAdjustment,
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('გაუქმება'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'დაარეგულირეთ სტუმრების რაოდენობა და პაკეტის პოზიციები. ცვლილება მხოლოდ ამ შეკვეთაზე გავრცელდება.',
                                  style: TextStyle(
                                    color: _mutedTextColor,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      const Text(
                                        'სტუმრები:',
                                        style: TextStyle(
                                          color: _titleColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                        onPressed: guestCount > 1
                                            ? decreaseGuestCount
                                            : null,
                                      ),
                                      SizedBox(
                                        width: 56,
                                        child: TextField(
                                          controller: guestController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          textAlign: TextAlign.center,
                                          onChanged: (value) {
                                            final parsed = int.tryParse(value);
                                            if (parsed == null || parsed <= 0) {
                                              return;
                                            }
                                            setDialogState(() {
                                              guestCount = parsed;
                                              applyRecommendedQuantities(
                                                guestCount,
                                              );
                                            });
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                        onPressed: increaseGuestCount,
                                      ),
                                      const Spacer(),
                                      OutlinedButton.icon(
                                        onPressed: addItemsFromMenu,
                                        icon: const Icon(
                                          Icons.add_shopping_cart,
                                        ),
                                        label: const Text('მენიუდან დამატება'),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: adjustableItems.isEmpty
                                            ? null
                                            : resetToRecommended,
                                        child: const Text(
                                          'რეკომენდებულზე დაბრუნება',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                for (final item in adjustableItems)
                                  buildQuantityTile(item),
                                if (adjustableItems.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _borderColor),
                                    ),
                                    child: const Text(
                                      'პაკეტში პოზიციები არ არის. დაამატეთ მენიუდან.',
                                      style: TextStyle(
                                        color: _mutedTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _borderColor),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            'პაკეტის ფასი',
                                            style: TextStyle(
                                              color: _mutedTextColor,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${packageTotal.toStringAsFixed(2)} GEL',
                                            style: const TextStyle(
                                              color: _titleColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Text(
                                            'პოზიციების ჯამი',
                                            style: TextStyle(
                                              color: _mutedTextColor,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${itemsSubtotal.toStringAsFixed(2)} GEL',
                                            style: const TextStyle(
                                              color: _accentColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(color: _borderColor),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              OutlinedButton.icon(
                                onPressed: showPackageItemsDialog,
                                icon: const Icon(Icons.list_alt),
                                label: const Text('პაკეტის პოზიციები'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  if (guestCount <= 0) {
                                    return;
                                  }

                                  final updatedItems = adjustableItems
                                      .where((item) => item.quantity > 0)
                                      .map(
                                        (item) => OrderItem(
                                          itemKey: item.itemKey,
                                          itemName: item.itemName,
                                          unitPrice: item.unitPrice,
                                          quantity: item.quantity,
                                          total: item.unitPrice * item.quantity,
                                        ),
                                      )
                                      .toList();

                                  Navigator.of(dialogContext).pop(
                                    _PackageAdjustmentResult(
                                      guestCount: guestCount,
                                      items: updatedItems,
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('შენახვა'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      guestController.dispose();
    }
  }

  List<_MenuItemOption> _buildMenuItemOptions() {
    final categories = DatabaseService.getAllMenuCategories();
    final options = <_MenuItemOption>[];
    var orderIndex = 0;

    for (final category in categories) {
      final categorySlug = category.slug;
      final categoryLabel =
          category.translationsKa['name'] ??
          category.translationsEn['name'] ??
          categorySlug;

      void addOption({
        required MenuItemDB item,
        MenuVariantDB? variant,
        String? subcategoryLabel,
      }) {
        final itemName =
            item.translationsKa['name']?.trim() ??
            item.translationsEn['name']?.trim();
        if (itemName == null || itemName.isEmpty) {
          return;
        }
        final unitPrice = variant?.price ?? item.price;
        if (unitPrice == null || unitPrice <= 0) {
          return;
        }

        final keyBuffer = StringBuffer()
          ..write(categorySlug)
          ..write('|')
          ..write(itemName);
        final displayBuffer = StringBuffer(itemName);
        if (variant != null) {
          keyBuffer
            ..write('|')
            ..write(variant.size.toString());
          displayBuffer
            ..write(' (')
            ..write(variant.getSizeLabel())
            ..write(')');
        }

        options.add(
          _MenuItemOption(
            key: keyBuffer.toString(),
            displayName: displayBuffer.toString(),
            unitPrice: unitPrice,
            categoryKey: categorySlug,
            categoryLabel: categoryLabel,
            subcategoryLabel: subcategoryLabel,
            orderIndex: orderIndex++,
          ),
        );
      }

      if (category.items != null) {
        for (final item in category.items!) {
          if (item.variants != null && item.variants!.isNotEmpty) {
            for (final variant in item.variants!) {
              addOption(item: item, variant: variant);
            }
          } else {
            addOption(item: item);
          }
        }
      }

      if (category.subcategories != null) {
        for (final subcategory in category.subcategories!) {
          final subcategoryLabel =
              subcategory.translationsKa['name'] ??
              subcategory.translationsEn['name'] ??
              subcategory.slug;
          for (final item in subcategory.items) {
            if (item.variants != null && item.variants!.isNotEmpty) {
              for (final variant in item.variants!) {
                addOption(
                  item: item,
                  variant: variant,
                  subcategoryLabel: subcategoryLabel,
                );
              }
            } else {
              addOption(item: item, subcategoryLabel: subcategoryLabel);
            }
          }
        }
      }
    }

    return options;
  }

  Future<Map<String, int>?> _showMenuItemPicker(
    BuildContext context,
    List<_MenuItemOption> options,
  ) async {
    final searchController = TextEditingController();
    String selectedCategory = 'ყველა';
    String selectedSubcategory = 'ყველა';
    bool keyboardVisible = false;
    final selectedQuantities = <String, int>{};

    return showDialog<Map<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> requestClosePicker() async {
              if (selectedQuantities.isEmpty) {
                Navigator.of(dialogContext).pop();
                return;
              }

              final shouldClose = await showDialog<bool>(
                context: dialogContext,
                barrierDismissible: false,
                builder: (confirmContext) => AlertDialog(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  title: const Text('დახურვის დადასტურება'),
                  content: const Text(
                    'არჩეული პროდუქტები ჯერ არ დამატებულა. ნამდვილად გსურთ დახურვა?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                      child: const Text('დაბრუნება'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(confirmContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black26),
                      ),
                      child: const Text('დახურვა'),
                    ),
                  ],
                ),
              );

              if (shouldClose == true && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            }

            Future<void> openSelectedProductsModal() async {
              await showDialog<void>(
                context: dialogContext,
                barrierDismissible: false,
                builder: (manageContext) {
                  return StatefulBuilder(
                    builder: (context, setManageState) {
                      final selectedEntries =
                          selectedQuantities.entries
                              .where((entry) => entry.value > 0)
                              .toList()
                            ..sort((a, b) => a.key.compareTo(b.key));

                      return AlertDialog(
                        backgroundColor: Colors.white,
                        surfaceTintColor: Colors.white,
                        title: const Text('არჩეული პროდუქტების მართვა'),
                        content: SizedBox(
                          width: 560,
                          child: selectedEntries.isEmpty
                              ? const Text('ჯერ არაფერი არის არჩეული.')
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: selectedEntries.length,
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemBuilder: (context, index) {
                                    final entry = selectedEntries[index];
                                    final option = options.firstWhere(
                                      (o) => o.key == entry.key,
                                    );
                                    final qty = entry.value;
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                option.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${option.unitPrice.toStringAsFixed(2)} GEL',
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            setStateDialog(() {
                                              final next =
                                                  (selectedQuantities[entry
                                                          .key] ??
                                                      0) -
                                                  1;
                                              if (next <= 0) {
                                                selectedQuantities.remove(
                                                  entry.key,
                                                );
                                              } else {
                                                selectedQuantities[entry.key] =
                                                    next;
                                              }
                                            });
                                            setManageState(() {});
                                          },
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text('$qty'),
                                        IconButton(
                                          onPressed: () {
                                            setStateDialog(() {
                                              selectedQuantities.update(
                                                entry.key,
                                                (value) => value + 1,
                                                ifAbsent: () => 1,
                                              );
                                            });
                                            setManageState(() {});
                                          },
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(manageContext).pop(),
                            child: const Text('დახურვა'),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            }

            final categoryOrder = <String, int>{};
            for (final option in options) {
              categoryOrder.putIfAbsent(
                option.categoryLabel,
                () => option.orderIndex,
              );
            }
            final sortedCategories = <String>[
              'ყველა',
              ...categoryOrder.keys.toList()..sort(
                (a, b) =>
                    (categoryOrder[a] ?? 0).compareTo(categoryOrder[b] ?? 0),
              ),
            ];

            final subcategoryOrder = <String, int>{};
            if (selectedCategory != 'ყველა') {
              for (final option in options.where(
                (e) => e.categoryLabel == selectedCategory,
              )) {
                final label = option.subcategoryLabel;
                if (label != null) {
                  subcategoryOrder.putIfAbsent(label, () => option.orderIndex);
                }
              }
            }
            final sortedSubcategories = <String>[
              'ყველა',
              ...subcategoryOrder.keys.toList()..sort(
                (a, b) => (subcategoryOrder[a] ?? 0).compareTo(
                  subcategoryOrder[b] ?? 0,
                ),
              ),
            ];

            final searchTerm = searchController.text.trim().toLowerCase();
            final filtered = options.where((option) {
              final categoryMatch =
                  selectedCategory == 'ყველა' ||
                  option.categoryLabel == selectedCategory;
              final subcategoryMatch =
                  selectedSubcategory == 'ყველა' ||
                  option.subcategoryLabel == selectedSubcategory;
              final searchMatch =
                  searchTerm.isEmpty ||
                  option.displayName.toLowerCase().contains(searchTerm) ||
                  option.categoryLabel.toLowerCase().contains(searchTerm) ||
                  (option.subcategoryLabel?.toLowerCase().contains(
                        searchTerm,
                      ) ??
                      false);
              return categoryMatch && subcategoryMatch && searchMatch;
            }).toList()..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

            return AlertDialog(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              insetPadding: EdgeInsets.zero,
              titlePadding: EdgeInsets.zero,
              contentPadding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _borderColor)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'პროდუქტის არჩევა',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: requestClosePicker,
                      icon: const Icon(Icons.close),
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: MediaQuery.of(dialogContext).size.width,
                height: MediaQuery.of(dialogContext).size.height,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: TextField(
                            controller: searchController,
                            readOnly: true,
                            onTap: () {
                              setStateDialog(() {
                                keyboardVisible = true;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: 'პროდუქტების ძიება',
                              labelStyle: const TextStyle(color: Colors.black),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.black,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.black26,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.black26,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: sortedCategories.map((category) {
                              final selected = category == selectedCategory;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(category),
                                  selected: selected,
                                  backgroundColor: Colors.white,
                                  selectedColor: Colors.white,
                                  side: const BorderSide(color: Colors.black26),
                                  showCheckmark: false,
                                  labelStyle: const TextStyle(
                                    color: Colors.black,
                                  ),
                                  onSelected: (_) {
                                    setStateDialog(() {
                                      selectedCategory = category;
                                      selectedSubcategory = 'ყველა';
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        if (selectedCategory != 'ყველა')
                          SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              children: sortedSubcategories.map((subcategory) {
                                final selected =
                                    subcategory == selectedSubcategory;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(subcategory),
                                    selected: selected,
                                    backgroundColor: Colors.white,
                                    selectedColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.black26,
                                    ),
                                    showCheckmark: false,
                                    labelStyle: const TextStyle(
                                      color: Colors.black,
                                    ),
                                    onSelected: (_) {
                                      setStateDialog(() {
                                        selectedSubcategory = subcategory;
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text(
                                    'პროდუქტები ვერ მოიძებნა',
                                    style: TextStyle(color: Colors.black),
                                  ),
                                )
                              : ListView.separated(
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    keyboardVisible ? 280 : 8,
                                  ),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: _borderColor,
                                  ),
                                  itemBuilder: (context, index) {
                                    final option = filtered[index];
                                    final selectedQty =
                                        selectedQuantities[option.key] ?? 0;
                                    final subtitle =
                                        option.subcategoryLabel == null
                                        ? option.categoryLabel
                                        : '${option.categoryLabel} • ${option.subcategoryLabel}';
                                    return ListTile(
                                      title: Text(
                                        option.displayName,
                                        style: const TextStyle(
                                          color: Colors.black,
                                        ),
                                      ),
                                      subtitle: Text(
                                        subtitle,
                                        style: const TextStyle(
                                          color: Colors.black,
                                        ),
                                      ),
                                      trailing: Text(
                                        '${option.unitPrice.toStringAsFixed(2)} GEL',
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onTap: () {
                                        setStateDialog(() {
                                          selectedQuantities.update(
                                            option.key,
                                            (value) => value + 1,
                                            ifAbsent: () => 1,
                                          );
                                        });
                                      },
                                      leading: selectedQty > 0
                                          ? Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: Colors.black26,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(13),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                '$selectedQty',
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.add_circle_outline,
                                              color: Colors.black,
                                            ),
                                    );
                                  },
                                ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: _borderColor),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              OutlinedButton.icon(
                                onPressed: selectedQuantities.isEmpty
                                    ? null
                                    : openSelectedProductsModal,
                                icon: const Icon(
                                  Icons.checklist_outlined,
                                  color: Colors.black,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  side: const BorderSide(color: Colors.black26),
                                ),
                                label: const Text('არჩეულების მართვა'),
                              ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: requestClosePicker,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.black,
                                    ),
                                    child: const Text('გაუქმება'),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: selectedQuantities.isEmpty
                                        ? null
                                        : () {
                                            Navigator.of(dialogContext).pop(
                                              Map<String, int>.from(
                                                selectedQuantities,
                                              ),
                                            );
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      side: const BorderSide(
                                        color: Colors.black26,
                                      ),
                                    ),
                                    child: Text(
                                      'დამატება (${selectedQuantities.values.fold<int>(0, (sum, qty) => sum + qty)})',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (keyboardVisible)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 76,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: OnScreenKeyboard(
                            controller: searchController,
                            language: 'ka',
                            onClose: () {
                              setStateDialog(() {
                                keyboardVisible = false;
                              });
                            },
                            showHeader: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(searchController.dispose);
  }

  int _calculateScaledQuantity({
    required int baseQuantity,
    required int guestCount,
    required int servingSize,
  }) {
    if (baseQuantity <= 0) {
      return 0;
    }
    if (guestCount <= 0) {
      return 0;
    }
    if (servingSize <= 0) {
      return baseQuantity;
    }

    final multiplier = guestCount / servingSize;
    final scaled = (baseQuantity * multiplier).ceil();
    if (scaled <= 0) {
      return 0;
    }
    return scaled;
  }

  Widget _buildPackageSummary(Order order, bool canModify) {
    final hasPackageName =
        order.packageName != null && order.packageName!.trim().isNotEmpty;
    final packageLabel = hasPackageName ? order.packageName!.trim() : 'პაკეტი';
    final includedCount = order.packageItems.length;
    final guests = order.packageGuestCount > 0 ? order.packageGuestCount : null;
    final unitPrice = order.packageUnitPrice > 0
        ? order.packageUnitPrice
        : (guests != null && order.packagePrice > 0
              ? order.packagePrice / guests
              : order.packagePrice);
    final packageTotal = order.packageUnitPrice > 0 && guests != null
        ? order.packageUnitPrice * guests
        : order.packagePrice;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            packageLabel,
            style: const TextStyle(
              color: _titleColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.people_outline, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                guests == null ? 'სტუმრები: -' : 'სტუმრები: $guests',
                style: const TextStyle(color: _mutedTextColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.attach_money, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'ერთ სტუმარზე: ${unitPrice.toStringAsFixed(2)} GEL',
                style: const TextStyle(color: _mutedTextColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.inventory_2, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'პაკეტის ჯამი: ${packageTotal.toStringAsFixed(2)} GEL',
                style: const TextStyle(color: _mutedTextColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.lock, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'სერვისი პაკეტის ჯამში არ შედის',
                  style: TextStyle(color: _mutedTextColor, fontSize: 14),
                ),
              ),
            ],
          ),
          if (includedCount > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.list_alt, color: _accentColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  '$includedCount პოზიცია შედის',
                  style: const TextStyle(color: _mutedTextColor, fontSize: 14),
                ),
              ],
            ),
          ],
          if (canModify && widget.isAdmin) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () => _openPackageAdjustmentDialog(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text(
                  'პაკეტის კორექტირება',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _titleColor,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildOrderItemTile(OrderItem item, {bool isPackageItem = false}) {
    final comment = item.comment?.trim();
    final highlighted = PosChangeHighlightService.shouldHighlightItem(
      widget.highlightItemKeys,
      item.itemKey,
      item.itemName,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFFFF7ED)
            : _panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? const Color(0xFFF59E0B) : _borderColor,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${item.quantity}x',
                    style: const TextStyle(
                      color: _accentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      style: const TextStyle(
                        color: _titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ერთეული: ${item.unitPrice.toStringAsFixed(2)} GEL',
                      style: const TextStyle(
                        color: _mutedTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isPackageItem
                    ? 'შედის პაკეტში'
                    : '${item.total.toStringAsFixed(2)} GEL',
                style: TextStyle(
                  color: isPackageItem ? _mutedTextColor : _accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(
                color: _mutedTextColor,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoAdditionalItemsNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: const Text(
        'ამ შეკვეთას დამატებითი პოზიციები არ აქვს',
        style: TextStyle(color: _mutedTextColor, fontSize: 14),
      ),
    );
  }

  bool _havePackageAdjustmentsChanged(
    Order order,
    _PackageAdjustmentResult result,
  ) {
    if (order.packageGuestCount != result.guestCount) {
      return true;
    }

    final currentItemsByKey = {
      for (final item in order.packageItems)
        if (item.quantity > 0) item.itemKey: item.quantity,
    };
    final resultItemsByKey = {
      for (final item in result.items)
        if (item.quantity > 0) item.itemKey: item.quantity,
    };

    if (currentItemsByKey.length != resultItemsByKey.length) {
      return true;
    }

    for (final entry in resultItemsByKey.entries) {
      if (currentItemsByKey[entry.key] != entry.value) {
        return true;
      }
    }

    return false;
  }

  bool _isFinalizedStatus(String status) {
    return status == 'paid' || status == 'cancelled' || status == 'closed';
  }
}

class _PackageAdjustmentResult {
  const _PackageAdjustmentResult({
    required this.guestCount,
    required this.items,
  });

  final int guestCount;
  final List<OrderItem> items;
}

class _AdjustablePackageItem {
  _AdjustablePackageItem({
    required this.itemKey,
    required this.itemName,
    required this.unitPrice,
    this.baseQuantity,
    required this.quantity,
  });

  final String itemKey;
  final String itemName;
  final double unitPrice;
  final int? baseQuantity;
  int quantity;

  double get total => unitPrice * quantity;
}

class _MenuItemOption {
  const _MenuItemOption({
    required this.key,
    required this.displayName,
    required this.unitPrice,
    required this.categoryKey,
    required this.categoryLabel,
    required this.orderIndex,
    this.subcategoryLabel,
  });

  final String key;
  final String displayName;
  final double unitPrice;
  final String categoryKey;
  final String categoryLabel;
  final String? subcategoryLabel;
  final int orderIndex;
}
