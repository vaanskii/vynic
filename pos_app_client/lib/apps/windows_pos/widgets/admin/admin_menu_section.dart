import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';

class AdminMenuSection extends StatefulWidget {
  final User user;
  const AdminMenuSection({super.key, required this.user});

  @override
  State<AdminMenuSection> createState() => _AdminMenuSectionState();
}

class _AdminMenuSectionState extends State<AdminMenuSection> {
  // Theme constants copied from AdminScreen
  static const Color _primaryColor = Color(0xFF1E3A8A);
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _surfaceColor = Color(0xFFF4F6FF);
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _inputBorderColor = Color(0xFF94A3B8);
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF64748B);
  static const double _priceStep = 0.5;

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final categories = DatabaseService.getAllMenuCategories();

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'მენიუს მართვა',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: isMobile ? 22 : 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showAddCategoryDialog(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('კატეგორიის დამატება'),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'მენიუს მართვა',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddCategoryDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _secondaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('კატეგორიის დამატება'),
                    ),
                  ],
                ),
              SizedBox(height: isMobile ? 24 : 32),

              // Categories list
              if (categories.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Text(
                      'ჯერ არ არის კატეგორიები. დაამატეთ ახალი კატეგორია დასაწყებად.',
                      style: TextStyle(color: _textMuted, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...categories.asMap().entries.map((entry) {
                  final index = entry.key;
                  final category = entry.value;
                  return _buildCategoryCard(category, index, isMobile);
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    MenuCategoryDB category,
    int categoryIndex,
    bool isMobile,
  ) {
    final nameEn = category.translationsEn['name'] ?? '';
    final nameKa = category.translationsKa['name'] ?? '';
    final categoryItems = category.items ?? [];
    final subcategories = category.subcategories ?? <MenuSubcategoryDB>[];
    final subcategoryItemCount = subcategories.fold<int>(
      0,
      (sum, sub) => sum + sub.items.length,
    );
    final itemCount = categoryItems.length + subcategoryItemCount;
    final hasCategoryItems = categoryItems.isNotEmpty;
    final hasSubcategoryItems = subcategoryItemCount > 0;
    final hasAnyItems = hasCategoryItems || hasSubcategoryItems;

    Widget buildItemTile(
      MenuItemDB item, {
      int? itemIndex,
      bool showActions = false,
      VoidCallback? onEdit,
      VoidCallback? onDelete,
    }) {
      final itemNameEn = item.translationsEn['name'] ?? '';
      final itemNameKa = item.translationsKa['name'] ?? '';
      final hasVariants = item.variants != null && item.variants!.isNotEmpty;

      return Card(
        color: _cardColor,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _borderColor),
        ),
        child: ListTile(
          leading: Icon(
            hasVariants ? Icons.layers : Icons.restaurant,
            color: _primaryColor,
          ),
          title: Text(
            itemNameKa.isNotEmpty ? itemNameKa : itemNameEn,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 15 : 16,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (itemNameEn.isNotEmpty)
                Text(itemNameEn, style: const TextStyle(color: _textMuted)),
              if (hasVariants)
                Text(
                  '${item.variants!.length} ვარიანტი',
                  style: const TextStyle(color: _primaryColor, fontSize: 12),
                )
              else if (item.price != null)
                Text(
                  '₾${item.price!.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              Text(
                item.sendToKitchen
                    ? 'იგზავნება სამზარეულოში'
                    : 'სამზარეულო გამორთულია',
                style: TextStyle(
                  color: item.sendToKitchen
                      ? const Color(0xFF047857)
                      : const Color(0xFFB45309),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          trailing: showActions
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.edit,
                        color: _primaryColor,
                        size: isMobile ? 18 : 20,
                      ),
                      onPressed: onEdit,
                      padding: isMobile
                          ? EdgeInsets.zero
                          : const EdgeInsets.all(8),
                      constraints: isMobile ? const BoxConstraints() : null,
                    ),
                    if (isMobile) const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.delete,
                        color: Colors.red,
                        size: isMobile ? 18 : 20,
                      ),
                      onPressed: onDelete,
                      padding: isMobile
                          ? EdgeInsets.zero
                          : const EdgeInsets.all(8),
                      constraints: isMobile ? const BoxConstraints() : null,
                    ),
                  ],
                )
              : null,
        ),
      );
    }

    return Card(
      color: _cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: 8,
        ),
        childrenPadding: EdgeInsets.all(isMobile ? 12 : 24),
        iconColor: _primaryColor,
        collapsedIconColor: _textMuted,
        textColor: _textPrimary,
        collapsedTextColor: _textPrimary,
        leading: const Icon(Icons.category, color: _primaryColor, size: 28),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nameKa.isNotEmpty ? nameKa : nameEn,
              style: TextStyle(
                color: _textPrimary,
                fontSize: isMobile ? 17 : 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (nameEn.isNotEmpty)
              Text(
                nameEn,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            isMobile
                ? '$itemCount ერთეული'
                : '$itemCount ერთეული • Slug: ${category.slug} • სამზარეულო: ${category.sendToKitchen ? 'ჩართული' : 'გამორთული'}',
            style: const TextStyle(color: _textMuted, fontSize: 13),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.edit,
                color: _primaryColor,
                size: isMobile ? 20 : 24,
              ),
              onPressed: () => _showEditCategoryDialog(category, categoryIndex),
              tooltip: 'კატეგორიის რედაქტირება',
              padding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(8),
              constraints: isMobile ? const BoxConstraints() : null,
            ),
            if (isMobile) const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.delete,
                color: Colors.red,
                size: isMobile ? 20 : 24,
              ),
              onPressed: () => _confirmDeleteCategory(categoryIndex, nameEn),
              tooltip: 'კატეგორიის წაშლა',
              padding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(8),
              constraints: isMobile ? const BoxConstraints() : null,
            ),
          ],
        ),
        children: [
          if (isMobile)
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddItemDialog(categoryIndex),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _secondaryColor,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('პროდუქტის დამატება'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddSubcategoryDialog(categoryIndex),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: const BorderSide(color: _borderColor),
                    ),
                    icon: const Icon(Icons.category),
                    label: const Text('ქვეკატეგორიის დამატება'),
                  ),
                ),
              ],
            )
          else ...[
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showAddItemDialog(categoryIndex),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _secondaryColor,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                label: const Text('პროდუქტის დამატება'),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _showAddSubcategoryDialog(categoryIndex),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _borderColor),
                ),
                icon: const Icon(Icons.category),
                label: const Text('ქვეკატეგორიის დამატება'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!hasAnyItems)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'ამ კატეგორიაში ჯერ არ არის პროდუქტები',
                style: TextStyle(color: _textMuted),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            if (hasCategoryItems) ...[
              const Text(
                'ძირითადი პროდუქტები',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...categoryItems.asMap().entries.map((entry) {
                final itemIndex = entry.key;
                final item = entry.value;
                return buildItemTile(
                  item,
                  itemIndex: itemIndex,
                  showActions: true,
                  onEdit: () =>
                      _showEditItemDialog(categoryIndex, itemIndex, item),
                  onDelete: () => _confirmDeleteItem(
                    categoryIndex,
                    itemIndex,
                    item.translationsEn['name'] ?? '',
                  ),
                );
              }),
            ],
            if (hasSubcategoryItems) ...[
              if (hasCategoryItems) const SizedBox(height: 16),
              const Text(
                'ქვეკატეგორიები',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...subcategories.asMap().entries.map((entry) {
                final subcategoryIndex = entry.key;
                final subcategory = entry.value;
                final subNameEn = subcategory.translationsEn['name'] ?? '';
                final subNameKa = subcategory.translationsKa['name'] ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 8 : 16,
                      vertical: 4,
                    ),
                    childrenPadding: EdgeInsets.fromLTRB(
                      isMobile ? 8 : 16,
                      0,
                      isMobile ? 8 : 16,
                      16,
                    ),
                    iconColor: _primaryColor,
                    collapsedIconColor: _textMuted,
                    title: Text(
                      subNameKa.isNotEmpty ? subNameKa : subNameEn,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: isMobile ? 15 : 16,
                      ),
                    ),
                    subtitle: subNameEn.isNotEmpty
                        ? Text(
                            subNameEn,
                            style: const TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                            ),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit,
                            color: _primaryColor,
                            size: isMobile ? 18 : 20,
                          ),
                          onPressed: () => _showEditSubcategoryDialog(
                            categoryIndex,
                            subcategoryIndex,
                            subcategory,
                          ),
                          tooltip: 'ქვეკატეგორიის რედაქტირება',
                          padding: isMobile
                              ? EdgeInsets.zero
                              : const EdgeInsets.all(8),
                          constraints: isMobile ? const BoxConstraints() : null,
                        ),
                        if (isMobile) const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: isMobile ? 18 : 20,
                          ),
                          onPressed: () => _confirmDeleteSubcategory(
                            categoryIndex,
                            subcategoryIndex,
                            subNameEn,
                          ),
                          tooltip: 'ქვეკატეგორიის წაშლა',
                          padding: isMobile
                              ? EdgeInsets.zero
                              : const EdgeInsets.all(8),
                          constraints: isMobile ? const BoxConstraints() : null,
                        ),
                      ],
                    ),
                    children: [
                      Align(
                        alignment: isMobile
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: SizedBox(
                          width: isMobile ? double.infinity : null,
                          child: ElevatedButton.icon(
                            onPressed: () => _showAddItemToSubcategoryDialog(
                              categoryIndex,
                              subcategoryIndex,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _secondaryColor,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('პროდუქტის დამატება'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (subcategory.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'ქვეკატეგორიაში პროდუქტები არ არის',
                            style: TextStyle(color: _textMuted),
                          ),
                        )
                      else
                        ...subcategory.items.asMap().entries.map((itemEntry) {
                          final itemIndex = itemEntry.key;
                          final item = itemEntry.value;
                          return buildItemTile(
                            item,
                            itemIndex: itemIndex,
                            showActions: true,
                            onEdit: () => _showEditSubcategoryItemDialog(
                              categoryIndex,
                              subcategoryIndex,
                              itemIndex,
                              item,
                            ),
                            onDelete: () => _confirmDeleteSubcategoryItem(
                              categoryIndex,
                              subcategoryIndex,
                              itemIndex,
                              item.translationsEn['name'] ?? '',
                            ),
                          );
                        }),
                    ],
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  // Common Helper Methods copied from AdminScreen
  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    StateSetter? dialogSetState,
    bool enableTextKeyboard = false,
    bool enableNumberPad = false,
    String? keyboardTitle,
    int? numberPadMaxDigits,
    bool allowDecimalInput = false,
    int numberPadDecimalDigits = 2,
  }) {
    Future<void> openVirtualInput() async {
      final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      if (isMobile) return;

      String? updatedValue;

      if (enableNumberPad) {
        updatedValue = await _showFullScreenPhonePad(
          title: keyboardTitle ?? label,
          initialValue: controller.text,
          maxDigits: numberPadMaxDigits ?? 9,
          allowDecimal: allowDecimalInput,
          maxDecimalPlaces: numberPadDecimalDigits,
        );
      } else if (enableTextKeyboard) {
        updatedValue = await _showFullScreenNameKeyboard(
          title: keyboardTitle ?? label,
          initialValue: controller.text,
        );
      }

      if (updatedValue != null) {
        controller.text = updatedValue;
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        onChanged?.call(updatedValue);
        dialogSetState?.call(() {});
      }
    }

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final bool showSuffixIcon =
        (enableTextKeyboard || enableNumberPad) && !isMobile;
    final suffixIcon = showSuffixIcon
        ? IconButton(
            icon: Icon(
              enableNumberPad ? Icons.dialpad : Icons.keyboard,
              color: _secondaryColor,
            ),
            tooltip: enableNumberPad ? 'Open keypad' : 'Open keyboard',
            onPressed: openVirtualInput,
          )
        : null;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: _dialogInputDecoration(
        label,
      ).copyWith(suffixIcon: suffixIcon),
      onChanged: onChanged,
    );
  }

  InputDecoration _dialogInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _inputBorderColor, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _inputBorderColor, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _secondaryColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildPriceInput({
    required TextEditingController controller,
    required StateSetter setState,
  }) {
    double parsePrice() {
      final normalized = controller.text.replaceAll(',', '.');
      return double.tryParse(normalized) ?? 0.0;
    }

    void updatePrice(double value) {
      final sanitized = value < 0 ? 0 : value;
      controller.text = sanitized.toStringAsFixed(2);
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    }

    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: _textPrimary,
      side: const BorderSide(color: _borderColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: OutlinedButton(
            style: buttonStyle,
            onPressed: () => setState(() {
              updatePrice(parsePrice() - _priceStep);
            }),
            child: const Icon(Icons.remove, size: 20),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
            ],
            decoration: _dialogInputDecoration('პერსონალური ფასი'),
            onChanged: (value) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: OutlinedButton(
            style: buttonStyle,
            onPressed: () => setState(() {
              updatePrice(parsePrice() + _priceStep);
            }),
            child: const Icon(Icons.add, size: 20),
          ),
        ),
      ],
    );
  }

  Future<String?> _showFullScreenNameKeyboard({
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    String keyboardLanguage = DatabaseService.getDefaultLanguage();

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.7),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return FractionallySizedBox(
              heightFactor: 0.78,
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F9FC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 64,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD2E0),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.keyboard_alt,
                              color: Color(0xFFB48A57),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Color(0xFF1F2430),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFB48A57),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () {
                                sheetSetState(() {
                                  keyboardLanguage = keyboardLanguage == 'ka'
                                      ? 'en'
                                      : 'ka';
                                });
                              },
                              icon: const Icon(Icons.language),
                              label: Text(
                                keyboardLanguage.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF2D6A4F),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                controller.text.trim(),
                              ),
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Done'),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF1F7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFCBD3E1)),
                          ),
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: controller,
                            builder: (context, value, _) {
                              final displayText = value.text.isEmpty
                                  ? 'Use keyboard below to type'
                                  : value.text;
                              return Text(
                                displayText,
                                style: TextStyle(
                                  color: value.text.isEmpty
                                      ? const Color(0xFF9AA1B5)
                                      : const Color(0xFF1F2430),
                                  fontSize: 20,
                                  fontWeight: value.text.isEmpty
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OnScreenKeyboard(
                            controller: controller,
                            language: keyboardLanguage,
                            onClose: () => Navigator.pop(sheetContext),
                            onEnter: () => Navigator.pop(
                              sheetContext,
                              controller.text.trim(),
                            ),
                            showHeader: false,
                          ),
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
  }

  Future<String?> _showFullScreenPhonePad({
    required String title,
    required String initialValue,
    int maxDigits = 15,
    bool allowDecimal = false,
    int maxDecimalPlaces = 2,
  }) async {
    String phoneValue = initialValue.trim();

    String? nextValueAfterDigit(String currentValue, String digit) {
      String sanitized = currentValue;

      if (digit == '.') {
        if (!allowDecimal ||
            maxDecimalPlaces == 0 ||
            currentValue.contains('.')) {
          return null;
        }
        if (currentValue.isEmpty) {
          sanitized = '0.';
        } else {
          sanitized = '$currentValue.';
        }
        return sanitized;
      }

      final proposed = currentValue.isEmpty || currentValue == '0'
          ? digit
          : '$currentValue$digit';

      final digitsOnly = proposed.replaceAll('.', '');
      if (digitsOnly.length > maxDigits) {
        return null;
      }

      if (allowDecimal && proposed.contains('.')) {
        final parts = proposed.split('.');
        if (parts.length > 1 &&
            parts[parts.length - 1].length > maxDecimalPlaces) {
          return null;
        }
      }

      return proposed;
    }

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.7),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return FractionallySizedBox(
              heightFactor: 0.8,
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF1a1a1a),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 64,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                        child: Row(
                          children: [
                            const Icon(Icons.dialpad, color: Color(0xFFC0AD7B)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                phoneValue.trim(),
                              ),
                              icon: const Icon(
                                Icons.check_circle,
                                color: Color(0xFFC0AD7B),
                              ),
                              label: const Text(
                                'Done',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2B2B2B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            phoneValue.isEmpty
                                ? 'Tap digits to enter number'
                                : phoneValue,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: PinPad(
                          onDigitPressed: (digit) {
                            sheetSetState(() {
                              final next = nextValueAfterDigit(
                                phoneValue,
                                digit,
                              );
                              if (next != null) {
                                phoneValue = next;
                              }
                            });
                          },
                          onClearPressed: () {
                            sheetSetState(() {
                              phoneValue = '';
                            });
                          },
                          onDeletePressed: () {
                            sheetSetState(() {
                              if (phoneValue.isNotEmpty) {
                                phoneValue = phoneValue.substring(
                                  0,
                                  phoneValue.length - 1,
                                );
                              }
                            });
                          },
                          showDecimalButton: allowDecimal,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Dialog methods for menu management
  Future<void> _showAddCategoryDialog() async {
    final slugController = TextEditingController();
    final nameEnController = TextEditingController();
    final nameKaController = TextEditingController();
    bool sendToKitchen = DatabaseService.shouldCategorySendToKitchenByDefault(
      null,
    );
    bool sendToKitchenModified = false;

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          title: const Text('Add New Category'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'Slug (e.g., hot-drinks)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Category Slug',
                  onChanged: (value) {
                    if (sendToKitchenModified) return;
                    final suggested =
                        DatabaseService.shouldCategorySendToKitchenByDefault(
                          value,
                        );
                    setDialogState(() {
                      sendToKitchen = suggested;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Category Name (English)',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Category Name (Georgian)',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Send items to kitchen printer',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Turn off for bar-only categories',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  activeThumbColor: _secondaryColor,
                  value: sendToKitchen,
                  onChanged: (value) => setDialogState(() {
                    sendToKitchenModified = true;
                    sendToKitchen = value;
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (slugController.text.isNotEmpty &&
                    nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.addCategory(
                    slug: slugController.text,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                    sendToKitchen: sendToKitchen,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(context, 'Category added successfully'),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditCategoryDialog(
    MenuCategoryDB category,
    int index,
  ) async {
    final slugController = TextEditingController(text: category.slug);
    final nameEnController = TextEditingController(
      text: category.translationsEn['name'],
    );
    final nameKaController = TextEditingController(
      text: category.translationsKa['name'],
    );
    bool sendToKitchen = category.sendToKitchen;

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          title: const Text('Edit Category'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'Slug',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Edit Slug',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Edit English Name',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Edit Georgian Name',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Send items to kitchen printer',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Applies to every item in this category',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  activeThumbColor: _secondaryColor,
                  value: sendToKitchen,
                  onChanged: (value) => setDialogState(() {
                    sendToKitchen = value;
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (slugController.text.isNotEmpty &&
                    nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.updateCategory(
                    index: index,
                    slug: slugController.text,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                    sendToKitchen: sendToKitchen,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(
                        context,
                        'Category updated successfully',
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCategory(int index, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: const Text(
          'Delete Category',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "$name"?\nAll items in this category will also be deleted.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await DatabaseService.deleteCategory(index);
      if (!mounted) return;
      if (success) {
        setState(() {});
        unawaited(showSuccessToast(context, 'Category deleted successfully'));
      }
    }
  }

  Future<void> _showAddSubcategoryDialog(int categoryIndex) async {
    final slugController = TextEditingController();
    final nameEnController = TextEditingController();
    final nameKaController = TextEditingController();

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          title: const Text('Add Subcategory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'Slug (e.g., espresso-based)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Subcategory Slug',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Subcategory Name (English)',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Subcategory Name (Georgian)',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (slugController.text.isNotEmpty &&
                    nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.addSubcategory(
                    categoryIndex: categoryIndex,
                    slug: slugController.text,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(
                        context,
                        'Subcategory added successfully',
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditSubcategoryDialog(
    int categoryIndex,
    int subcategoryIndex,
    MenuSubcategoryDB subcategory,
  ) async {
    final slugController = TextEditingController(text: subcategory.slug);
    final nameEnController = TextEditingController(
      text: subcategory.translationsEn['name'],
    );
    final nameKaController = TextEditingController(
      text: subcategory.translationsKa['name'],
    );

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          title: const Text('Edit Subcategory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'Slug',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Edit Subcategory Slug',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Edit Subcategory English Name',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'Edit Subcategory Georgian Name',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (slugController.text.isNotEmpty &&
                    nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.updateSubcategory(
                    categoryIndex: categoryIndex,
                    subcategoryIndex: subcategoryIndex,
                    slug: slugController.text,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(
                        context,
                        'Subcategory updated successfully',
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSubcategory(
    int categoryIndex,
    int subcategoryIndex,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: const Text(
          'Delete Subcategory',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete subcategory "$name"?\nAll items in this subcategory will also be deleted.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await DatabaseService.deleteSubcategory(
        categoryIndex: categoryIndex,
        subcategoryIndex: subcategoryIndex,
      );
      if (!mounted) return;
      if (success) {
        setState(() {});
        unawaited(
          showSuccessToast(context, 'Subcategory deleted successfully'),
        );
      }
    }
  }

  Future<void> _showAddItemDialog(int categoryIndex) async {
    final nameEnController = TextEditingController();
    final nameKaController = TextEditingController();
    final priceController = TextEditingController();
    bool hasVariants = false;
    List<MenuVariantDB> variants = [];
    final categories = DatabaseService.getAllMenuCategories();
    final category = categoryIndex < categories.length
        ? categories[categoryIndex]
        : null;
    bool sendToKitchen = category?.sendToKitchen ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Send this item to the kitchen printer',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    category == null
                        ? 'Controls kitchen routing'
                        : 'Defaults to ${category.sendToKitchen ? 'On' : 'Off'} for this category',
                    style: const TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  activeThumbColor: _secondaryColor,
                  value: sendToKitchen,
                  onChanged: (value) {
                    setDialogState(() {
                      sendToKitchen = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Has Variants?',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: hasVariants,
                  onChanged: (value) {
                    setDialogState(() {
                      hasVariants = value;
                      if (!value) {
                        variants.clear();
                      }
                    });
                  },
                  activeThumbColor: _secondaryColor,
                ),
                const SizedBox(height: 16),
                if (!hasVariants)
                  _buildPriceInput(
                    controller: priceController,
                    setState: setDialogState,
                  )
                else
                  Column(
                    children: [
                      ...variants.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final variant = entry.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${variant.size}ml - ₾${variant.price.toStringAsFixed(2)}',
                            style: const TextStyle(color: _textPrimary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                variants.removeAt(idx);
                              });
                            },
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              _showAddVariantDialog(context, (variant) {
                                setDialogState(() {
                                  variants.add(variant);
                                });
                              }),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Variant'),
                          style: TextButton.styleFrom(
                            foregroundColor: _secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.addItemToCategory(
                    categoryIndex: categoryIndex,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                    price: hasVariants
                        ? null
                        : double.tryParse(priceController.text),
                    variants: hasVariants && variants.isNotEmpty
                        ? variants
                        : null,
                    sendToKitchen: sendToKitchen,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(context, 'Item added successfully'),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddItemToSubcategoryDialog(
    int categoryIndex,
    int subcategoryIndex,
  ) async {
    final nameEnController = TextEditingController();
    final nameKaController = TextEditingController();
    final priceController = TextEditingController();
    bool hasVariants = false;
    List<MenuVariantDB> variants = [];
    final categories = DatabaseService.getAllMenuCategories();
    final category = categoryIndex < categories.length
        ? categories[categoryIndex]
        : null;
    bool sendToKitchen = category?.sendToKitchen ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Send this item to the kitchen printer',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    category == null
                        ? 'Controls kitchen routing'
                        : 'Defaults to ${category.sendToKitchen ? 'On' : 'Off'} for this category',
                    style: const TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  activeThumbColor: _secondaryColor,
                  value: sendToKitchen,
                  onChanged: (value) {
                    setDialogState(() {
                      sendToKitchen = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Has Variants?',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: hasVariants,
                  onChanged: (value) {
                    setDialogState(() {
                      hasVariants = value;
                      if (!value) {
                        variants.clear();
                      }
                    });
                  },
                  activeThumbColor: _secondaryColor,
                ),
                const SizedBox(height: 16),
                if (!hasVariants)
                  _buildPriceInput(
                    controller: priceController,
                    setState: setDialogState,
                  )
                else
                  Column(
                    children: [
                      ...variants.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final variant = entry.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${variant.size}ml - ₾${variant.price.toStringAsFixed(2)}',
                            style: const TextStyle(color: _textPrimary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                variants.removeAt(idx);
                              });
                            },
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              _showAddVariantDialog(context, (variant) {
                                setDialogState(() {
                                  variants.add(variant);
                                });
                              }),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Variant'),
                          style: TextButton.styleFrom(
                            foregroundColor: _secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.addItemToSubcategory(
                    categoryIndex: categoryIndex,
                    subcategoryIndex: subcategoryIndex,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                    price: hasVariants
                        ? null
                        : double.tryParse(priceController.text),
                    variants: hasVariants && variants.isNotEmpty
                        ? variants
                        : null,
                    sendToKitchen: sendToKitchen,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(context, 'Item added successfully'),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditSubcategoryItemDialog(
    int categoryIndex,
    int subcategoryIndex,
    int itemIndex,
    MenuItemDB item,
  ) async {
    final nameEnController = TextEditingController(
      text: item.translationsEn['name'],
    );
    final nameKaController = TextEditingController(
      text: item.translationsKa['name'],
    );
    final priceController = TextEditingController(
      text: item.price?.toString() ?? '',
    );
    bool hasVariants = item.variants != null && item.variants!.isNotEmpty;
    List<MenuVariantDB> variants = List.from(item.variants ?? []);
    bool sendToKitchen = item.sendToKitchen;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Send this item to the kitchen printer',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Disable for drinks or desserts handled at the bar',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  activeThumbColor: _secondaryColor,
                  value: sendToKitchen,
                  onChanged: (value) {
                    setDialogState(() {
                      sendToKitchen = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Has Variants?',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: hasVariants,
                  onChanged: (value) {
                    setDialogState(() {
                      hasVariants = value;
                      if (!value) {
                        variants.clear();
                      }
                    });
                  },
                  activeThumbColor: _secondaryColor,
                ),
                const SizedBox(height: 16),
                if (!hasVariants)
                  _buildPriceInput(
                    controller: priceController,
                    setState: setDialogState,
                  )
                else
                  Column(
                    children: [
                      ...variants.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final variant = entry.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${variant.size}ml - ₾${variant.price.toStringAsFixed(2)}',
                            style: const TextStyle(color: _textPrimary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                variants.removeAt(idx);
                              });
                            },
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              _showAddVariantDialog(context, (variant) {
                                setDialogState(() {
                                  variants.add(variant);
                                });
                              }),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Variant'),
                          style: TextButton.styleFrom(
                            foregroundColor: _secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.updateItemInSubcategory(
                    categoryIndex: categoryIndex,
                    subcategoryIndex: subcategoryIndex,
                    itemIndex: itemIndex,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                    price: hasVariants
                        ? null
                        : double.tryParse(priceController.text),
                    variants: hasVariants && variants.isNotEmpty
                        ? variants
                        : null,
                    sendToKitchen: sendToKitchen,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(context, 'Item updated successfully'),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSubcategoryItem(
    int categoryIndex,
    int subcategoryIndex,
    int itemIndex,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: const Text('Delete Item', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "$name"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await DatabaseService.deleteItemFromSubcategory(
        categoryIndex: categoryIndex,
        subcategoryIndex: subcategoryIndex,
        itemIndex: itemIndex,
      );
      if (!mounted) return;
      if (success) {
        setState(() {});
        unawaited(showSuccessToast(context, 'Item deleted successfully'));
      }
    }
  }

  Future<void> _showEditItemDialog(
    int categoryIndex,
    int itemIndex,
    MenuItemDB item,
  ) async {
    final nameEnController = TextEditingController(
      text: item.translationsEn['name'],
    );
    final nameKaController = TextEditingController(
      text: item.translationsKa['name'],
    );
    final priceController = TextEditingController(
      text: item.price?.toString() ?? '',
    );
    bool hasVariants = item.variants != null && item.variants!.isNotEmpty;
    List<MenuVariantDB> variants = List.from(item.variants ?? []);
    bool sendToKitchen = item.sendToKitchen;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'Name (English)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'Name (Georgian)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Send this item to the kitchen printer',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Disable for drinks or desserts handled at the bar',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  activeThumbColor: _secondaryColor,
                  value: sendToKitchen,
                  onChanged: (value) {
                    setDialogState(() {
                      sendToKitchen = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Has Variants?',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: hasVariants,
                  onChanged: (value) {
                    setDialogState(() {
                      hasVariants = value;
                      if (!value) {
                        variants.clear();
                      }
                    });
                  },
                  activeThumbColor: _secondaryColor,
                ),
                const SizedBox(height: 16),
                if (!hasVariants)
                  _buildPriceInput(
                    controller: priceController,
                    setState: setDialogState,
                  )
                else
                  Column(
                    children: [
                      ...variants.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final variant = entry.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${variant.size}ml - ₾${variant.price.toStringAsFixed(2)}',
                            style: const TextStyle(color: _textPrimary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                variants.removeAt(idx);
                              });
                            },
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              _showAddVariantDialog(context, (variant) {
                                setDialogState(() {
                                  variants.add(variant);
                                });
                              }),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Variant'),
                          style: TextButton.styleFrom(
                            foregroundColor: _secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameEnController.text.isNotEmpty &&
                    nameKaController.text.isNotEmpty) {
                  final success = await DatabaseService.updateItemInCategory(
                    categoryIndex: categoryIndex,
                    itemIndex: itemIndex,
                    nameEn: nameEnController.text,
                    nameKa: nameKaController.text,
                    price: hasVariants
                        ? null
                        : double.tryParse(priceController.text),
                    variants: hasVariants && variants.isNotEmpty
                        ? variants
                        : null,
                    sendToKitchen: sendToKitchen,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    unawaited(
                      showSuccessToast(context, 'Item updated successfully'),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteItem(
    int categoryIndex,
    int itemIndex,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: const Text('Delete Item', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "$name"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await DatabaseService.deleteItemFromCategory(
        categoryIndex: categoryIndex,
        itemIndex: itemIndex,
      );
      if (!mounted) return;
      if (success) {
        setState(() {});
        unawaited(showSuccessToast(context, 'Item deleted successfully'));
      }
    }
  }

  void _showAddVariantDialog(
    BuildContext parentContext,
    Function(MenuVariantDB) onAdd,
  ) {
    final sizeController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: parentContext,
      builder: (context) => AlertDialog(
        title: const Text('Add Variant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogTextField(
              controller: sizeController,
              label: 'Size (ml)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}$')),
              ],
              enableNumberPad: true,
              allowDecimalInput: true,
              keyboardTitle: 'Set Size (ml)',
              numberPadMaxDigits: 5,
              numberPadDecimalDigits: 3,
            ),
            const SizedBox(height: 16),
            _buildDialogTextField(
              controller: priceController,
              label: 'Price (₾)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
              ],
              enableNumberPad: true,
              allowDecimalInput: true,
              keyboardTitle: 'Set Variant Price',
              numberPadMaxDigits: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final size = double.tryParse(sizeController.text);
              final price = double.tryParse(priceController.text);
              if (size != null && price != null) {
                onAdd(MenuVariantDB(size: size, price: price));
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
