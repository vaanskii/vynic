import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

class AdminMenuSection extends StatefulWidget {
  final User user;
  const AdminMenuSection({super.key, required this.user});

  @override
  State<AdminMenuSection> createState() => _AdminMenuSectionState();
}

class _AdminMenuSectionState extends State<AdminMenuSection> {
  static const Color _primaryColor = AdminDesign.accentDark;
  static const Color _secondaryColor = AdminDesign.accentDark;
  static const Color _surfaceColor = AdminDesign.panelSoft;
  static const Color _cardColor = AdminDesign.panel;
  static const Color _borderColor = AdminDesign.border;
  static const Color _textPrimary = AdminDesign.text;
  static const Color _textMuted = AdminDesign.muted;
  static const double _priceStep = 0.5;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _selectedCategoryIndex;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final categories = DatabaseService.getAllMenuCategories();
    final allRows = _buildMenuRows(categories);
    final effectiveCategoryIndex = categories.isEmpty
        ? null
        : (_selectedCategoryIndex != null &&
              _selectedCategoryIndex! >= 0 &&
              _selectedCategoryIndex! < categories.length)
        ? _selectedCategoryIndex
        : 0;
    final filteredRows = allRows.where((row) {
      if (effectiveCategoryIndex != null &&
          row.categoryIndex != effectiveCategoryIndex) {
        return false;
      }
      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) return true;
      return row.name.toLowerCase().contains(query) ||
          row.categoryName.toLowerCase().contains(query) ||
          (row.subcategoryName?.toLowerCase().contains(query) ?? false);
    }).toList();
    final kitchenEnabled = allRows
        .where((row) => row.item.sendToKitchen)
        .length;
    final kitchenDisabled = allRows.length - kitchenEnabled;

    return SizedBox.expand(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 22,
                isMobile ? 16 : 18,
                isMobile ? 16 : 22,
                18,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeader(isMobile, categories.length),
                    const SizedBox(height: 16),
                    _buildKpiRow(
                      totalItems: allRows.length,
                      categories: categories.length,
                      kitchenEnabled: kitchenEnabled,
                      kitchenDisabled: kitchenDisabled,
                    ),
                    const SizedBox(height: 16),
                    if (categories.isEmpty)
                      const AdminEmptyState(
                        icon: Icons.menu_book_outlined,
                        title: 'მენიუ ცარიელია',
                        message:
                            'დაამატეთ პირველი კატეგორია და შემდეგ მასში პროდუქტები.',
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final showSidePanel = constraints.maxWidth >= 700;
                          final compactTable = constraints.maxWidth < 1040;
                          final categoryPanelWidth = constraints.maxWidth < 1120
                              ? 240.0
                              : 330.0;
                          if (!showSidePanel) {
                            return Column(
                              children: [
                                _buildMenuTable(
                                  rows: filteredRows,
                                  compact: true,
                                ),
                                const SizedBox(height: 14),
                                _buildCategoryPanel(categories, allRows),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildMenuTable(
                                  rows: filteredRows,
                                  compact: compactTable,
                                ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: categoryPanelWidth,
                                child: _buildCategoryPanel(categories, allRows),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomDock(categories),
        ],
      ),
    );
  }

  Widget _buildPageHeader(bool isMobile, int categoryCount) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AdminDesign.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AdminDesign.radius),
          ),
          child: const Icon(
            Icons.restaurant_menu_outlined,
            color: AdminDesign.accentDark,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'მენიუ',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: isMobile ? 23 : 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'მართეთ კატეგორიები, პროდუქტები, ფასები და სამზარეულოს მარშრუტები.',
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (!isMobile)
          AdminStatusBadge(
            icon: Icons.folder_outlined,
            label: '$categoryCount კატეგორია',
          ),
      ],
    );
  }

  Widget _buildKpiRow({
    required int totalItems,
    required int categories,
    required int kitchenEnabled,
    required int kitchenDisabled,
  }) {
    final items = [
      _MenuKpiData(
        label: 'სულ პროდუქტები',
        value: totalItems,
        icon: Icons.room_service_outlined,
        color: const Color(0xFF0F9D58),
      ),
      _MenuKpiData(
        label: 'კატეგორიები',
        value: categories,
        icon: Icons.folder_outlined,
        color: const Color(0xFF0369A1),
      ),
      _MenuKpiData(
        label: 'სამზარეულო ჩართული',
        value: kitchenEnabled,
        icon: Icons.check_circle_outline,
        color: const Color(0xFF047857),
      ),
      _MenuKpiData(
        label: 'სამზარეულო გამორთული',
        value: kitchenDisabled,
        icon: Icons.warning_amber_outlined,
        color: const Color(0xFFEA580C),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 4
            : constraints.maxWidth >= 460
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _MenuKpiCard(data: item, compact: width < 230),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildMenuTable({
    required List<_AdminMenuRow> rows,
    bool compact = false,
  }) {
    return Container(
      decoration: AdminDesign.panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackControls = constraints.maxWidth < 640;
                final title = const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.list_alt_outlined,
                      color: _textPrimary,
                      size: 21,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'მენიუს პროდუქტები',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                );
                final search = SizedBox(
                  width: stackControls ? null : 270,
                  height: 42,
                  child: PosOnScreenTextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: const TextStyle(color: _textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ძებნა პროდუქტით ან კატეგორიით...',
                      hintStyle: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: _textMuted,
                        size: 19,
                      ),
                      filled: true,
                      fillColor: _surfaceColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                        borderSide: const BorderSide(color: _borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                        borderSide: const BorderSide(color: _borderColor),
                      ),
                    ),
                  ),
                );
                if (stackControls) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [title, const SizedBox(height: 12), search],
                  );
                }
                return Row(
                  children: [
                    title,
                    const Spacer(),
                    Flexible(child: search),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1, color: _borderColor),
          if (!compact) _buildMenuTableHeader(),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 36, color: _textMuted),
                  SizedBox(height: 10),
                  Text(
                    'პროდუქტი ვერ მოიძებნა',
                    style: TextStyle(color: _textMuted, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            ...rows.asMap().entries.map(
              (entry) => _buildMenuRow(
                entry.value,
                compact: compact,
                showDivider: entry.key < rows.length - 1,
              ),
            ),
          if (rows.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: _surfaceColor,
                border: Border(top: BorderSide(color: _borderColor)),
              ),
              child: Text(
                '${rows.length} პროდუქტი',
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: _surfaceColor,
      child: const Row(
        children: [
          Expanded(
            flex: 5,
            child: Text('დასახელება', style: _MenuTableHeader.style),
          ),
          Expanded(
            flex: 4,
            child: Text('კატეგორია', style: _MenuTableHeader.style),
          ),
          Expanded(flex: 3, child: Text('ფასი', style: _MenuTableHeader.style)),
          Expanded(
            flex: 3,
            child: Text('სამზარეულო', style: _MenuTableHeader.style),
          ),
          SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _buildMenuRow(
    _AdminMenuRow row, {
    required bool compact,
    required bool showDivider,
  }) {
    final price = _priceLabel(row.item);
    final kitchenColor = row.item.sendToKitchen
        ? const Color(0xFF047857)
        : const Color(0xFFB45309);
    final actions = PopupMenuButton<String>(
      tooltip: 'მოქმედებები',
      icon: const Icon(Icons.more_vert, color: _textPrimary, size: 20),
      onSelected: (value) {
        if (value == 'edit') {
          if (row.subcategoryIndex == null) {
            _showEditItemDialog(row.categoryIndex, row.itemIndex, row.item);
          } else {
            _showEditSubcategoryItemDialog(
              row.categoryIndex,
              row.subcategoryIndex!,
              row.itemIndex,
              row.item,
            );
          }
          return;
        }
        if (row.subcategoryIndex == null) {
          _confirmDeleteItem(
            row.categoryIndex,
            row.itemIndex,
            row.item.translationsEn['name'] ?? row.name,
          );
        } else {
          _confirmDeleteSubcategoryItem(
            row.categoryIndex,
            row.subcategoryIndex!,
            row.itemIndex,
            row.item.translationsEn['name'] ?? row.name,
          );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined),
            title: Text('რედაქტირება'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.delete_outline, color: AdminDesign.danger),
            title: Text('წაშლა', style: TextStyle(color: AdminDesign.danger)),
          ),
        ),
      ],
    );
    final decoration = BoxDecoration(
      border: showDivider
          ? const Border(bottom: BorderSide(color: _borderColor))
          : null,
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: decoration,
        child: Row(
          children: [
            _buildMenuItemIcon(row.item),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${row.categoryName} • $price',
                    style: const TextStyle(color: _textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.item.sendToKitchen
                        ? 'სამზარეულო ჩართული'
                        : 'სამზარეულო გამორთული',
                    style: TextStyle(
                      color: kitchenColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            actions,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                _buildMenuItemIcon(row.item),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              row.subcategoryName == null
                  ? row.categoryName
                  : '${row.categoryName} / ${row.subcategoryName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              price,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              row.item.sendToKitchen ? 'ჩართული' : 'გამორთული',
              style: TextStyle(
                color: kitchenColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 42, child: actions),
        ],
      ),
    );
  }

  Widget _buildMenuItemIcon(MenuItemDB item) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: item.sendToKitchen
            ? const Color(0xFFECFDF5)
            : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: _borderColor),
      ),
      child: Icon(
        item.hasVariants() ? Icons.layers_outlined : Icons.restaurant_outlined,
        color: item.sendToKitchen
            ? AdminDesign.accentDark
            : AdminDesign.warning,
        size: 19,
      ),
    );
  }

  Widget _buildCategoryPanel(
    List<MenuCategoryDB> categories,
    List<_AdminMenuRow> allRows,
  ) {
    final selectedCategoryIndex =
        _selectedCategoryIndex != null &&
            _selectedCategoryIndex! >= 0 &&
            _selectedCategoryIndex! < categories.length
        ? _selectedCategoryIndex!
        : 0;
    return Column(
      children: [
        Container(
          decoration: AdminDesign.panelDecoration(),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, color: _textPrimary, size: 21),
                    SizedBox(width: 9),
                    Text(
                      'კატეგორიები',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _borderColor),
              ...categories.asMap().entries.map((entry) {
                final categoryName = entry.value.getName('ka');
                final count = allRows
                    .where((row) => row.categoryIndex == entry.key)
                    .length;
                return _buildCategoryNavigatorRow(
                  icon: entry.value.sendToKitchen
                      ? Icons.restaurant_outlined
                      : Icons.local_cafe_outlined,
                  label: categoryName,
                  count: count,
                  selected: selectedCategoryIndex == entry.key,
                  onTap: () =>
                      setState(() => _selectedCategoryIndex = entry.key),
                  onEdit: () => _showEditCategoryDialog(entry.value, entry.key),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AdminDesign.panelDecoration(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.star_outline, color: _textPrimary, size: 21),
                  SizedBox(width: 9),
                  Text(
                    'მიმოხილვა',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...allRows
                  .take(4)
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _surfaceColor,
                          borderRadius: BorderRadius.circular(
                            AdminDesign.radius,
                          ),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Row(
                          children: [
                            _buildMenuItemIcon(row.item),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _priceLabel(row.item),
                                    style: const TextStyle(
                                      color: _textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryNavigatorRow({
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onEdit,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFECFDF5) : Colors.white,
          border: const Border(bottom: BorderSide(color: _borderColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? AdminDesign.accent.withValues(alpha: 0.14)
                    : _surfaceColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: selected ? AdminDesign.accentDark : _textMuted,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: 'კატეგორიის რედაქტირება',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                color: _textMuted,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomDock(List<MenuCategoryDB> categories) {
    final selectedIndex =
        _selectedCategoryIndex ?? (categories.isNotEmpty ? 0 : null);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 11, 22, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderColor)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 690;
          final addItem = ElevatedButton.icon(
            onPressed: selectedIndex == null
                ? null
                : () => _showAddItemDialog(selectedIndex),
            style: AdminDesign.primaryButtonStyle(),
            icon: const Icon(Icons.add_circle_outline, size: 19),
            label: const Text(
              'ახალი პროდუქტი',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          );
          final addCategory = OutlinedButton.icon(
            onPressed: () => _showCategoryManagementDialog(categories),
            style: AdminDesign.outlineButtonStyle(),
            icon: const Icon(Icons.folder_copy_outlined, size: 19),
            label: const Text('კატეგორიების მართვა'),
          );
          if (compact) {
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [addCategory, const SizedBox(height: 8), addItem],
              );
            }
            return Row(
              children: [
                Expanded(child: addCategory),
                const SizedBox(width: 10),
                Expanded(child: addItem),
              ],
            );
          }
          return Row(
            children: [
              const Icon(Icons.info_outline, color: _primaryColor, size: 20),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'ცვლილებები ინახება მენიუს რედაქტირების დასრულებისთანავე.',
                  style: TextStyle(color: _textMuted, fontSize: 12),
                ),
              ),
              addCategory,
              const SizedBox(width: 10),
              addItem,
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCategoryManagementDialog(
    List<MenuCategoryDB> categories,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final compact = MediaQuery.sizeOf(dialogContext).width < 620;
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 40,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdminDesign.radius),
            side: const BorderSide(color: _borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_copy_outlined,
                        color: _primaryColor,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'კატეგორიების მართვა',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                        color: _textMuted,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _borderColor),
                Expanded(
                  child: categories.isEmpty
                      ? const Center(
                          child: Text(
                            'კატეგორიები ჯერ არ არის',
                            style: TextStyle(color: _textMuted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: categories.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, categoryIndex) {
                            final category = categories[categoryIndex];
                            final subcategories =
                                category.subcategories ?? <MenuSubcategoryDB>[];
                            return Container(
                              decoration: BoxDecoration(
                                color: _surfaceColor,
                                borderRadius: BorderRadius.circular(
                                  AdminDesign.radius,
                                ),
                                border: Border.all(color: _borderColor),
                              ),
                              child: ExpansionTile(
                                initiallyExpanded: categoryIndex == 0,
                                title: Text(
                                  category.getName('ka'),
                                  style: const TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${subcategories.length} ქვეკატეგორია',
                                  style: const TextStyle(
                                    color: _textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    Navigator.pop(dialogContext);
                                    if (value == 'edit') {
                                      _showEditCategoryDialog(
                                        category,
                                        categoryIndex,
                                      );
                                    } else if (value == 'subcategory') {
                                      _showAddSubcategoryDialog(categoryIndex);
                                    } else {
                                      _confirmDeleteCategory(
                                        categoryIndex,
                                        category.getName('en'),
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('რედაქტირება'),
                                    ),
                                    PopupMenuItem(
                                      value: 'subcategory',
                                      child: Text('ქვეკატეგორიის დამატება'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        'წაშლა',
                                        style: TextStyle(
                                          color: AdminDesign.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                children: [
                                  if (subcategories.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(
                                        'ქვეკატეგორიები არ არის',
                                        style: TextStyle(
                                          color: _textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  else
                                    ...subcategories.asMap().entries.map((
                                      entry,
                                    ) {
                                      final subcategory = entry.value;
                                      return Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            AdminDesign.radius,
                                          ),
                                          border: Border.all(
                                            color: _borderColor,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.subdirectory_arrow_right,
                                              size: 18,
                                              color: _textMuted,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                subcategory.getName('ka'),
                                                style: const TextStyle(
                                                  color: _textPrimary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              onSelected: (value) {
                                                Navigator.pop(dialogContext);
                                                if (value == 'item') {
                                                  _showAddItemToSubcategoryDialog(
                                                    categoryIndex,
                                                    entry.key,
                                                  );
                                                } else if (value == 'edit') {
                                                  _showEditSubcategoryDialog(
                                                    categoryIndex,
                                                    entry.key,
                                                    subcategory,
                                                  );
                                                } else {
                                                  _confirmDeleteSubcategory(
                                                    categoryIndex,
                                                    entry.key,
                                                    subcategory.getName('en'),
                                                  );
                                                }
                                              },
                                              itemBuilder: (context) => const [
                                                PopupMenuItem(
                                                  value: 'item',
                                                  child: Text(
                                                    'პროდუქტის დამატება',
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('რედაქტირება'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text(
                                                    'წაშლა',
                                                    style: TextStyle(
                                                      color: AdminDesign.danger,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _borderColor)),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _showAddCategoryDialog();
                    },
                    style: AdminDesign.primaryButtonStyle(),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('ახალი კატეგორია'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_AdminMenuRow> _buildMenuRows(List<MenuCategoryDB> categories) {
    final rows = <_AdminMenuRow>[];
    for (final categoryEntry in categories.asMap().entries) {
      final category = categoryEntry.value;
      final categoryName = category.getName('ka');
      for (final itemEntry
          in (category.items ?? <MenuItemDB>[]).asMap().entries) {
        rows.add(
          _AdminMenuRow(
            categoryIndex: categoryEntry.key,
            itemIndex: itemEntry.key,
            categoryName: categoryName,
            item: itemEntry.value,
          ),
        );
      }
      for (final subEntry
          in (category.subcategories ?? <MenuSubcategoryDB>[])
              .asMap()
              .entries) {
        final subcategory = subEntry.value;
        for (final itemEntry in subcategory.items.asMap().entries) {
          rows.add(
            _AdminMenuRow(
              categoryIndex: categoryEntry.key,
              subcategoryIndex: subEntry.key,
              itemIndex: itemEntry.key,
              categoryName: categoryName,
              subcategoryName: subcategory.getName('ka'),
              item: itemEntry.value,
            ),
          );
        }
      }
    }
    return rows;
  }

  String _priceLabel(MenuItemDB item) {
    if (item.hasVariants()) {
      final prices = item.variants!.map((variant) => variant.price).toList()
        ..sort();
      return '₾${prices.first.toStringAsFixed(2)}+';
    }
    return '₾${(item.price ?? 0).toStringAsFixed(2)}';
  }

  // Kept temporarily while the existing category editor flow is migrated.
  // ignore: unused_element
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

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(AdminDesign.radius),
          border: Border.all(color: _borderColor),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AdminDesign.panelDecoration(),
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
                : '$itemCount ერთეული • სლაგი: ${category.slug} • სამზარეულო: ${category.sendToKitchen ? 'ჩართული' : 'გამორთული'}',
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
  String _keyboardLanguageForField(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('slug') ||
        lower.contains('english') ||
        lower.contains('ინგლისურ') ||
        lower.contains('სლაგ')) {
      return 'en';
    }
    if (lower.contains('georgian') || lower.contains('ქართულ')) {
      return 'ka';
    }
    return DatabaseService.getDefaultLanguage();
  }

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
    String? keyboardLanguage,
    int? numberPadMaxDigits,
    bool allowDecimalInput = false,
    int numberPadDecimalDigits = 2,
  }) {
    Future<void> openVirtualInput() async {
      final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      if (isMobile) return;

      String? updatedValue;
      final fieldTitle = keyboardTitle ?? label;

      if (enableNumberPad) {
        updatedValue = await _showFullScreenPhonePad(
          title: fieldTitle,
          initialValue: controller.text,
          maxDigits: numberPadMaxDigits ?? 9,
          allowDecimal: allowDecimalInput,
          maxDecimalPlaces: numberPadDecimalDigits,
        );
      } else if (enableTextKeyboard) {
        updatedValue = await _showFullScreenNameKeyboard(
          initialValue: controller.text,
          language: keyboardLanguage ?? _keyboardLanguageForField(fieldTitle),
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
    final useVirtualInput =
        (enableTextKeyboard || enableNumberPad) && !isMobile;

    if (!useVirtualInput) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: _textPrimary),
        decoration: _dialogInputDecoration(label),
        onChanged: onChanged,
      );
    }

    return InkWell(
      onTap: openVirtualInput,
      borderRadius: BorderRadius.circular(12),
      child: IgnorePointer(
        child: TextField(
          controller: controller,
          readOnly: true,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: _textPrimary),
          decoration: _dialogInputDecoration(label),
          onChanged: onChanged,
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: _textMuted,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _secondaryColor, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  AlertDialog _menuFormAlertDialog({
    required String title,
    required Widget content,
    required List<Widget> actions,
  }) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        side: const BorderSide(color: _borderColor),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: _textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actionsAlignment: MainAxisAlignment.end,
      content: content,
      actions: actions,
    );
  }

  Widget _dialogCancelButton({required VoidCallback onPressed}) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: _textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: const Text(
        'გაუქმება',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
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
            decoration: _dialogInputDecoration('ფასი (₾)'),
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
    required String initialValue,
    required String language,
  }) async {
    final controller = TextEditingController(text: initialValue);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );

    try {
      return await showPosKeyboardInputSheet(
        context: context,
        controller: controller,
        initialLanguage: PosKeyboardLanguage.fromCode(language),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _showFullScreenPhonePad({
    required String title,
    required String initialValue,
    int maxDigits = 15,
    bool allowDecimal = false,
    int maxDecimalPlaces = 2,
  }) async {
    return showPosNumberKeyboardInputSheet(
      context: context,
      title: title,
      initialValue: initialValue,
      maxDigits: maxDigits,
      allowDecimal: allowDecimal,
      maxDecimalPlaces: maxDecimalPlaces,
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

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'ახალი კატეგორია',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'სლაგი (მაგ. hot-drinks)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'კატეგორიის სლაგი',
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
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'კატეგორიის სახელი (ინგლისური)',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'კატეგორიის სახელი (ქართული)',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'პროდუქტები იგზავნება სამზარეულოში',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'გამორთეთ ბარის/სასმელი კატეგორიებისთვის',
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
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                    unawaited(showSuccessToast(context, 'კატეგორია დაემატა'));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('დამატება'),
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

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'კატეგორიის რედაქტირება',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'სლაგი',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'სლაგის რედაქტირება',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'სახელის რედაქტირება (ინგლისური)',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'სახელის რედაქტირება (ქართული)',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'პროდუქტები იგზავნება სამზარეულოში',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'ვრცელდება ამ კატეგორიის ყველა პროდუქტზე',
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
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                    unawaited(showSuccessToast(context, 'კატეგორია განახლდა'));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('განახლება'),
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
          'კატეგორიის წაშლა',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ „$name“ წაშლა?\nამ კატეგორიის ყველა პროდუქტიც წაიშლება.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await DatabaseService.deleteCategory(index);
      if (!mounted) return;
      if (success) {
        setState(() {});
        unawaited(showSuccessToast(context, 'კატეგორია წაიშალა'));
      }
    }
  }

  Future<void> _showAddSubcategoryDialog(int categoryIndex) async {
    final slugController = TextEditingController();
    final nameEnController = TextEditingController();
    final nameKaController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'ახალი ქვეკატეგორია',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'სლაგი (მაგ. espresso-based)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'ქვეკატეგორიის სლაგი',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'ქვეკატეგორიის სახელი (ინგლისური)',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'ქვეკატეგორიის სახელი (ქართული)',
                ),
              ],
            ),
          ),
          actions: [
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                      showSuccessToast(context, 'ქვეკატეგორია დაემატა'),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('დამატება'),
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

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'ქვეკატეგორიის რედაქტირება',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: slugController,
                  label: 'სლაგი',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'ქვეკატეგორიის სლაგის რედაქტირება',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'ქვეკატეგორიის სახელი (ინგლისური)',
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                  keyboardTitle: 'ქვეკატეგორიის სახელი (ქართული)',
                ),
              ],
            ),
          ),
          actions: [
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                      showSuccessToast(context, 'ქვეკატეგორია განახლდა'),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('განახლება'),
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
          'ქვეკატეგორიის წაშლა',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ „$name“ წაშლა?\nამ ქვეკატეგორიის ყველა პროდუქტიც წაიშლება.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('წაშლა'),
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
        unawaited(showSuccessToast(context, 'ქვეკატეგორია წაიშალა'));
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
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'ახალი პროდუქტი',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'პროდუქტი იგზავნება სამზარეულოში',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    category == null
                        ? 'აკონტროლებს სამზარეულოში გაგზავნას'
                        : 'ნაგულისხმევი: ${category.sendToKitchen ? 'ჩართული' : 'გამორთული'} (ამ კატეგორიის მიხედვით)',
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
                    'აქვს ვარიანტები?',
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
                          label: const Text('ვარიანტის დამატება'),
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
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                    unawaited(showSuccessToast(context, 'პროდუქტი დაემატა'));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('დამატება'),
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
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'ახალი პროდუქტი',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'პროდუქტი იგზავნება სამზარეულოში',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    category == null
                        ? 'აკონტროლებს სამზარეულოში გაგზავნას'
                        : 'ნაგულისხმევი: ${category.sendToKitchen ? 'ჩართული' : 'გამორთული'} (ამ კატეგორიის მიხედვით)',
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
                    'აქვს ვარიანტები?',
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
                          label: const Text('ვარიანტის დამატება'),
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
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                    unawaited(showSuccessToast(context, 'პროდუქტი დაემატა'));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('დამატება'),
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
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'პროდუქტის რედაქტირება',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'პროდუქტი იგზავნება სამზარეულოში',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'გამორთეთ ბარის პროდუქტებისთვის',
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
                    'აქვს ვარიანტები?',
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
                          label: const Text('ვარიანტის დამატება'),
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
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                    unawaited(showSuccessToast(context, 'პროდუქტი განახლდა'));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('განახლება'),
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
        title: const Text(
          'პროდუქტის წაშლა',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ „$name“ წაშლა?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('წაშლა'),
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
        unawaited(showSuccessToast(context, 'პროდუქტი წაიშალა'));
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
        builder: (context, setDialogState) => _menuFormAlertDialog(
          title: 'პროდუქტის რედაქტირება',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: nameEnController,
                  label: 'სახელი (ინგლისური)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: nameKaController,
                  label: 'სახელი (ქართული)',
                  dialogSetState: setDialogState,
                  enableTextKeyboard: true,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'პროდუქტი იგზავნება სამზარეულოში',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'გამორთეთ ბარის პროდუქტებისთვის',
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
                    'აქვს ვარიანტები?',
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
                          label: const Text('ვარიანტის დამატება'),
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
            _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
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
                    unawaited(showSuccessToast(context, 'პროდუქტი განახლდა'));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('განახლება'),
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
        title: const Text(
          'პროდუქტის წაშლა',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ „$name“ წაშლა?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('წაშლა'),
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
        unawaited(showSuccessToast(context, 'პროდუქტი წაიშალა'));
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
      builder: (context) => _menuFormAlertDialog(
        title: 'ვარიანტის დამატება',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogTextField(
              controller: sizeController,
              label: 'ზომა (მლ)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}$')),
              ],
              enableNumberPad: true,
              allowDecimalInput: true,
              keyboardTitle: 'ზომის დაყენება (მლ)',
              numberPadMaxDigits: 5,
              numberPadDecimalDigits: 3,
            ),
            const SizedBox(height: 16),
            _buildDialogTextField(
              controller: priceController,
              label: 'ფასი (₾)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
              ],
              enableNumberPad: true,
              allowDecimalInput: true,
              keyboardTitle: 'ვარიანტის ფასი',
              numberPadMaxDigits: 6,
            ),
          ],
        ),
        actions: [
          _dialogCancelButton(onPressed: () => Navigator.of(context).pop()),
          ElevatedButton(
            onPressed: () {
              final size = double.tryParse(sizeController.text);
              final price = double.tryParse(priceController.text);
              if (size != null && price != null) {
                onAdd(MenuVariantDB(size: size, price: price));
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _secondaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'დამატება',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMenuRow {
  const _AdminMenuRow({
    required this.categoryIndex,
    required this.itemIndex,
    required this.categoryName,
    required this.item,
    this.subcategoryIndex,
    this.subcategoryName,
  });

  final int categoryIndex;
  final int? subcategoryIndex;
  final int itemIndex;
  final String categoryName;
  final String? subcategoryName;
  final MenuItemDB item;

  String get name => item.getName('ka');
}

class _MenuKpiData {
  const _MenuKpiData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _MenuKpiCard extends StatelessWidget {
  const _MenuKpiCard({required this.data, required this.compact});

  final _MenuKpiData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: 12,
      ),
      decoration: AdminDesign.panelDecoration(),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, color: data.color, size: compact ? 21 : 25),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AdminDesign.muted,
                    fontSize: compact ? 10 : 11,
                  ),
                ),
                Text(
                  '${data.value}',
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _MenuTableHeader {
  static const TextStyle style = TextStyle(
    color: AdminDesign.muted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );
}
