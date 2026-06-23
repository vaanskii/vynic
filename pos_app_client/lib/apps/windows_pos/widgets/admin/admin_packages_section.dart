import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/apps/windows_pos/screens/order_detail_screen.dart';

class AdminPackagesSection extends StatefulWidget {
  const AdminPackagesSection({super.key, required this.user});

  final User user;

  @override
  State<AdminPackagesSection> createState() => _AdminPackagesSectionState();
}

class _AdminPackagesSectionState extends State<AdminPackagesSection> {
  List<Package> _packages = <Package>[];
  late final List<_MenuItemOption> _menuItemOptions;
  late final Map<String, List<String>> _tableLayout;
  late final List<String> _tableFloors;
  bool _isProcessing = false;
  final ScrollController _packagesScrollController = ScrollController();

  static const Color _primaryColor = Color(0xFF1D4ED8);
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _surfaceColor = Color(0xFFF8FAFC);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _textSoft = Color(0xFF94A3B8);

  static const Map<String, Color> _tableColorOverrides = {
    '1': Color(0xFF81C784),
    '2': Color(0xFF81C784),
    '3': Color(0xFF81C784),
  };

  static const List<Color> _tablePalette = [
    Color(0xFF64B5F6),
    Color(0xFFF06292),
    Color(0xFFFFB74D),
    Color(0xFF4DB6AC),
    Color(0xFFBA68C8),
    Color(0xFFA1887F),
    Color(0xFF90A4AE),
    Color(0xFFAED581),
  ];

  @override
  void initState() {
    super.initState();
    _menuItemOptions = _buildMenuItemOptions();
    _tableLayout = DatabaseService.getTableLayout();
    _tableFloors = _tableLayout.keys.toList()..sort();
    _refreshPackages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPackagesToTop(immediate: true);
    });
  }

  @override
  void dispose() {
    _packagesScrollController.dispose();
    super.dispose();
  }

  void _refreshPackages() {
    final packages = DatabaseService.getAllPackages()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() {
      _packages = packages;
    });
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

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        controller: _packagesScrollController,
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'პაკეტები',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => _openPackageEditor(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _secondaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('პაკეტის შექმნა'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_packages.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: const Text(
                    'ჯერ არ არის პაკეტები. შექმენით პაკეტი პოპულარული პროდუქტებისთვის.',
                    style: TextStyle(color: _textMuted, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Column(children: _packages.map(_buildPackageCard).toList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackageCard(Package pkg) {
    return Card(
      color: _cardColor,
      elevation: 2,
      shadowColor: const Color(0x1F0F172A),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCE7FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    pkg.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.workspace_premium_outlined,
                        size: 18,
                        color: _primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${pkg.pricePerPerson.toStringAsFixed(2)} GEL / სტუმარზე',
                        style: const TextStyle(
                          color: _primaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _applyPackageToTables(pkg),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _secondaryColor,
                    foregroundColor: Colors.white,
                    elevation: 1.5,
                    shadowColor: const Color(0x40000000),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.table_bar),
                  label: const Text('მაგიდებზე დამატება'),
                ),
                OutlinedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _showPackageDetails(pkg),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: Color(0xFFBFD2FF)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('დეტალები'),
                ),
                OutlinedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _openPackageEditor(existing: pkg),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: Color(0xFFBFD2FF)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.edit),
                  label: const Text('რედაქტირება'),
                ),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _confirmDelete(pkg),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('წაშლა'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageItemRow(PackageItem item) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        item.itemName,
        style: const TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        'რაოდენობა: ${item.quantity}',
        style: const TextStyle(color: _textMuted),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${item.unitPrice.toStringAsFixed(2)} GEL',
            style: const TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'ჯამი: ${item.total.toStringAsFixed(2)} GEL',
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForTable(String tableNumber) {
    final override = _tableColorOverrides[tableNumber];
    if (override != null) {
      return override;
    }
    final normalized = tableNumber.toLowerCase();
    final hash = normalized.codeUnits.fold<int>(0, (sum, code) => sum + code);
    return _tablePalette[hash % _tablePalette.length];
  }

  Widget _buildStaticTableChip(String tableNumber) {
    final color = _colorForTable(tableNumber);
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        'მაგიდა $tableNumber',
        style: const TextStyle(color: _textPrimary, fontSize: 13),
      ),
    );
  }

  String _formatFloorLabel(String floorKey) {
    switch (floorKey.toLowerCase()) {
      case 'first':
        return 'პირველი სართული';
      case 'second':
        return 'მეორე სართული';
      case 'third':
        return 'მესამე სართული';
      default:
        if (floorKey.isEmpty) {
          return 'უცნობი';
        }
        return floorKey[0].toUpperCase() + floorKey.substring(1);
    }
  }

  Future<void> _openPackageEditor({Package? existing}) async {
    final result = await _showPackageEditorDialog(existing: existing);
    if (result == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      if (existing == null) {
        await DatabaseService.createPackage(
          name: result.name,
          description: result.description,
          items: result.items,
          pricePerPerson: result.pricePerPerson,
          servingSize: result.servingSize,
          createdBy: widget.user.username,
          allowedTables: result.allowedTables,
        );
      } else {
        await DatabaseService.updatePackage(
          packageId: existing.packageId,
          name: result.name,
          description: result.description,
          items: result.items,
          pricePerPerson: result.pricePerPerson,
          servingSize: result.servingSize,
          allowedTables: result.allowedTables,
        );
      }
      _refreshPackages();
      _scrollPackagesToTop();
      if (!mounted) {
        return;
      }
      final message = existing == null
          ? 'პაკეტი შექმნილია'
          : 'პაკეტი განახლებულია';
      unawaited(showSuccessToast(context, message));
    } catch (error) {
      if (!mounted) {
        return;
      }
      unawaited(showErrorToast(context, 'შენახვა ვერ შესრულდა: $error'));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _scrollPackagesToTop({bool immediate = false}) {
    if (!_packagesScrollController.hasClients) {
      return;
    }
    if (immediate) {
      _packagesScrollController.jumpTo(0);
      return;
    }
    unawaited(
      _packagesScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _showPackageDetails(Package pkg) async {
    final itemsSubtotal = pkg.items.fold<double>(
      0,
      (sum, item) => sum + (item.unitPrice * item.quantity),
    );
    final packageTotal = pkg.pricePerPerson * pkg.servingSize;
    final difference = packageTotal - itemsSubtotal;
    final differenceLabel = difference >= 0
        ? '+${difference.toStringAsFixed(2)} GEL'
        : '${difference.toStringAsFixed(2)} GEL';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cardColor,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 28,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          title: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: _primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pkg.name,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 760,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      'სტატუსი',
                      pkg.isActive ? 'აქტიური' : 'არააქტიური',
                    ),
                    _buildInfoChip(
                      'ერთ ადამიანზე',
                      '${pkg.pricePerPerson.toStringAsFixed(2)} GEL',
                    ),
                    _buildInfoChip('სტუმრები', '${pkg.servingSize} ადამიანი'),
                    _buildInfoChip(
                      'შედის ღირებულება',
                      '${itemsSubtotal.toStringAsFixed(2)} GEL',
                    ),
                    _buildInfoChip(
                      'პაკეტის ჯამი',
                      '${packageTotal.toStringAsFixed(2)} GEL',
                    ),
                    _buildInfoChip('განსხვავება', differenceLabel),
                    _buildInfoChip('შექმნა', pkg.createdBy),
                    _buildInfoChip('თარიღი', _formatDate(pkg.createdAt)),
                  ],
                ),
                if (pkg.allowedTables.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'ჩართული მაგიდები',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    children: pkg.allowedTables
                        .map(_buildStaticTableChip)
                        .toList(),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'მენიუს პოზიციები',
                  style: TextStyle(
                    color: _textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pkg.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _buildPackageItemRow(pkg.items[index]),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      unawaited(_duplicatePackage(pkg));
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                side: const BorderSide(color: Color(0xFFFCD9A4)),
              ),
              icon: const Icon(Icons.copy),
              label: const Text('დუბლირება'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('დახურვა'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _duplicatePackage(Package pkg) async {
    final nameController = TextEditingController(
      text: '${pkg.name} პაკეტის ასლი',
    );
    String? errorMessage;

    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: _cardColor,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              title: const Text(
                'პაკეტის დუბლირება',
                style: TextStyle(color: _textPrimary),
              ),
              content: SizedBox(
                width: 760,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'შეიყვანეთ ახალი პაკეტის სახელი.',
                      style: TextStyle(color: _textMuted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: _textPrimary),
                      readOnly: true,
                      onTap: () async {
                        await showPosKeyboardInputSheet(
                          context: dialogContext,
                          controller: nameController,
                          initialLanguage: PosKeyboardLanguage.georgian,
                          title: 'პაკეტის ასლი',
                        );
                        if (!dialogContext.mounted) return;
                        setStateDialog(() {
                          errorMessage = null;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'პაკეტის ასლი',
                        labelStyle: TextStyle(color: _textMuted),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _borderColor),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _primaryColor),
                        ),
                      ),
                      onChanged: (_) {
                        if (errorMessage != null) {
                          setStateDialog(() {
                            errorMessage = null;
                          });
                        }
                      },
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('გაუქმება'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final trimmed = nameController.text.trim();
                    if (trimmed.isEmpty) {
                      setStateDialog(() {
                        errorMessage = 'სახელი აუცილებელია';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(trimmed);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _secondaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('დუბლირების შექმნა'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    if (newName == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await DatabaseService.createPackage(
        name: newName,
        description: pkg.description,
        items: pkg.items
            .map(
              (item) => PackageItem(
                itemKey: item.itemKey,
                itemName: item.itemName,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
              ),
            )
            .toList(),
        pricePerPerson: pkg.pricePerPerson,
        servingSize: pkg.servingSize,
        createdBy: widget.user.username,
        allowedTables: pkg.allowedTables,
      );
      _refreshPackages();
      if (!mounted) {
        return;
      }
      unawaited(showSuccessToast(context, 'პაკეტი "$newName" შექმნილია'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      unawaited(showErrorToast(context, 'დუბლირება ვერ შესრულდა: $error'));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _applyPackageToTables(Package pkg) async {
    if (!pkg.isActive) {
      if (mounted) {
        unawaited(
          showPosToast(
            context: context,
            message: 'გთხოვთ ჯერ ჩართეთ პაკეტი, შემდეგ დაამატეთ მაგიდებზე',
            style: PosToastStyle.info,
          ),
        );
      }
      return;
    }

    final deployment = await _showApplyPackageDialog(pkg);
    if (deployment == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final createdOrder = await DatabaseService.createOrderForPackage(
        package: pkg,
        tableNumbers: deployment.tableNumbers,
        floor: deployment.floor,
        guestCount: pkg.servingSize > 0 ? pkg.servingSize : 1,
        createdBy: widget.user.username,
      );
      if (!mounted) {
        return;
      }
      unawaited(
        showSuccessToast(
          context,
          'პაკეტი დამატებულია მაგიდებზე: ${deployment.tableNumbers.join(", ")}',
        ),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OrderDetailScreen(
            user: widget.user,
            orderId: createdOrder.orderId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      unawaited(
        showErrorToast(context, 'მაგიდებზე დამატება ვერ შესრულდა: $error'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _confirmDelete(Package pkg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          'პაკეტის წაშლა',
          style: TextStyle(color: _textPrimary),
        ),
        content: Text(
          'გსურთ "${pkg.name}"-ის წაშლა?\nარსებული შეკვეთები ცვლილების გარეშე დარჩება.',
          style: const TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await DatabaseService.deletePackage(pkg.packageId);
      _refreshPackages();
      if (!mounted) {
        return;
      }
      unawaited(showSuccessToast(context, 'პაკეტი წაშლილია'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      unawaited(showErrorToast(context, 'წაშლა ვერ შესრულდა: $error'));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<_PackageDeploymentResult?> _showApplyPackageDialog(Package pkg) async {
    final candidateFloors = _tableFloors
        .where(
          (floor) => (_tableLayout[floor] ?? const []).any(
            (table) =>
                pkg.allowedTables.isEmpty || pkg.allowedTables.contains(table),
          ),
        )
        .toList();

    final floorsToUse = candidateFloors.isNotEmpty
        ? candidateFloors
        : _tableFloors;
    if (floorsToUse.isEmpty) {
      if (mounted) {
        unawaited(
          showPosToast(
            context: context,
            message: 'სართული არ არის კონფიგურირებული',
            style: PosToastStyle.info,
          ),
        );
      }
      return null;
    }

    final busyTablesByFloor = <String, Set<String>>{};
    for (final order in DatabaseService.getActiveOrders()) {
      busyTablesByFloor.putIfAbsent(order.floor, () => <String>{});
      busyTablesByFloor[order.floor]!.addAll(order.tableNumbers);
    }

    String selectedFloor = floorsToUse.first;
    final initialFloor = selectedFloor;
    final Set<String> selectedTables = <String>{};
    String? errorMessage;

    final result = await showDialog<_PackageDeploymentResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final tablesForFloor = () {
              final base = List<String>.from(
                _tableLayout[selectedFloor] ?? const [],
              );
              if (pkg.allowedTables.isNotEmpty) {
                base.retainWhere(pkg.allowedTables.contains);
                final extras = pkg.allowedTables
                    .where((table) => !base.contains(table))
                    .toList();
                base.addAll(extras);
              }
              base.sort();
              return base;
            }();

            final busyTables =
                busyTablesByFloor[selectedFloor] ?? const <String>{};

            bool hasUnsavedChanges() {
              if (selectedFloor != initialFloor) {
                return true;
              }
              return selectedTables.isNotEmpty;
            }

            Future<bool> confirmDiscardIfNeeded() async {
              if (!hasUnsavedChanges()) {
                return true;
              }

              final confirmed = await showDialog<bool>(
                context: dialogContext,
                barrierDismissible: false,
                builder: (confirmContext) => AlertDialog(
                  backgroundColor: _cardColor,
                  title: const Text(
                    'დახურვის დადასტურება',
                    style: TextStyle(color: _textPrimary),
                  ),
                  content: const Text(
                    'ცვლილებები არ არის შენახული. ნამდვილად გსურთ დახურვა?',
                    style: TextStyle(color: _textMuted),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                      child: const Text('გაგრძელება'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(confirmContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('დახურვა'),
                    ),
                  ],
                ),
              );

              return confirmed == true;
            }

            return WillPopScope(
              onWillPop: () async {
                return confirmDiscardIfNeeded();
              },
              child: AlertDialog(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                insetPadding: EdgeInsets.zero,
                titlePadding: EdgeInsets.zero,
                contentPadding: EdgeInsets.zero,
                backgroundColor: _cardColor,
                title: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _borderColor)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'დაამატეთ "${pkg.name}" მაგიდებზე',
                        style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () async {
                          final shouldClose = await confirmDiscardIfNeeded();
                          if (!shouldClose) {
                            return;
                          }
                          if (!dialogContext.mounted) {
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                        },
                        icon: const Icon(Icons.close),
                        color: _textMuted,
                        tooltip: 'დახურვა',
                      ),
                    ],
                  ),
                ),
                content: SizedBox(
                  width: MediaQuery.of(dialogContext).size.width,
                  height: MediaQuery.of(dialogContext).size.height,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'სართულის არჩევა',
                                style: TextStyle(
                                  color: _textMuted,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: selectedFloor,
                                items: floorsToUse
                                    .map(
                                      (floor) => DropdownMenuItem<String>(
                                        value: floor,
                                        child: Text(_formatFloorLabel(floor)),
                                      ),
                                    )
                                    .toList(),
                                dropdownColor: _cardColor,
                                style: const TextStyle(color: _textPrimary),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: _surfaceColor,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: _borderColor,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: _primaryColor,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setDialogState(() {
                                    selectedFloor = value;
                                    selectedTables.clear();
                                    errorMessage = null;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'მაგიდების არჩევა',
                                style: TextStyle(
                                  color: _textMuted,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (tablesForFloor.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _surfaceColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _borderColor),
                                  ),
                                  child: Text(
                                    pkg.allowedTables.isEmpty
                                        ? '${_formatFloorLabel(selectedFloor)}-ზე მაგიდები არ არის.'
                                        : 'ეს პაკეტი ${_formatFloorLabel(selectedFloor)}-ზე მიუწვდომელია.',
                                    style: const TextStyle(color: _textMuted),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: tablesForFloor.map((tableNumber) {
                                    final isSelected = selectedTables.contains(
                                      tableNumber,
                                    );
                                    final isBusy = busyTables.contains(
                                      tableNumber,
                                    );
                                    final color = _colorForTable(tableNumber);

                                    return ChoiceChip(
                                      label: Text(
                                        isBusy
                                            ? 'მაგიდა $tableNumber (დაკავებულია)'
                                            : 'მაგიდა $tableNumber',
                                      ),
                                      selected: isSelected,
                                      onSelected: isBusy
                                          ? null
                                          : (value) {
                                              setDialogState(() {
                                                errorMessage = null;
                                                if (value) {
                                                  selectedTables.add(
                                                    tableNumber,
                                                  );
                                                } else {
                                                  selectedTables.remove(
                                                    tableNumber,
                                                  );
                                                }
                                              });
                                            },
                                      backgroundColor: color.withValues(
                                        alpha: isSelected ? 0.45 : 0.18,
                                      ),
                                      selectedColor: color.withValues(
                                        alpha: 0.7,
                                      ),
                                      labelStyle: TextStyle(
                                        color: isBusy
                                            ? _textSoft
                                            : _textPrimary,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      side: BorderSide(
                                        color: color.withValues(
                                          alpha: isBusy ? 0.3 : 0.6,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              if (busyTables.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'დაკავებული მაგიდები ვერ აირჩევა.',
                                  style: TextStyle(color: Color(0xFFB45309)),
                                ),
                              ],
                              if (errorMessage != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: _borderColor)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                final shouldClose =
                                    await confirmDiscardIfNeeded();
                                if (!shouldClose) {
                                  return;
                                }
                                if (!dialogContext.mounted) {
                                  return;
                                }
                                Navigator.of(dialogContext).pop();
                              },
                              child: const Text('გაუქმება'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: selectedTables.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(dialogContext).pop(
                                        _PackageDeploymentResult(
                                          tableNumbers: selectedTables.toList()
                                            ..sort(),
                                          floor: selectedFloor,
                                        ),
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _secondaryColor,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('პაკეტის დამატება'),
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

    return result;
  }

  Future<_PackageEditorResult?> _showPackageEditorDialog({Package? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final priceController = TextEditingController(
      text: existing != null ? existing.pricePerPerson.toStringAsFixed(2) : '',
    );
    final servingSizeController = TextEditingController(
      text: existing != null ? existing.servingSize.toString() : '',
    );
    final workingItems = existing != null
        ? existing.items
              .map(
                (item) => PackageItem(
                  itemKey: item.itemKey,
                  itemName: item.itemName,
                  quantity: item.quantity,
                  unitPrice: item.unitPrice,
                ),
              )
              .toList()
        : <PackageItem>[];
    final initialName = (existing?.name ?? '').trim();
    final initialDescription = (existing?.description ?? '').trim();
    final initialPriceText = existing != null
        ? existing.pricePerPerson.toStringAsFixed(2)
        : '';
    final initialGuestsText = existing != null
        ? existing.servingSize.toString()
        : '';
    final initialItems = existing != null
        ? existing.items
              .map(
                (item) =>
                    '${item.itemKey}|${item.itemName}|${item.quantity}|${item.unitPrice.toStringAsFixed(4)}',
              )
              .toList()
        : <String>[];

    return showDialog<_PackageEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        String? errorMessage;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            InputDecoration buildFieldDecoration({
              required String label,
              required IconData icon,
            }) {
              return InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon, color: _textMuted, size: 20),
                labelStyle: const TextStyle(color: _textMuted),
                filled: true,
                fillColor: const Color(0xFFF8FAFF),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: _primaryColor,
                    width: 1.5,
                  ),
                ),
              );
            }

            Future<void> openTextKeyboard({
              required TextEditingController controller,
              required String title,
            }) async {
              await showPosKeyboardInputSheet(
                context: dialogContext,
                controller: controller,
                initialLanguage: PosKeyboardLanguage.georgian,
                title: title,
              );
              if (!dialogContext.mounted) return;
              setDialogState(() {});
            }

            Future<void> openNumberKeyboard({
              required TextEditingController controller,
              required String title,
              required bool allowDecimal,
              required int maxDecimalPlaces,
            }) async {
              final updated = await showPosNumberKeyboardInputSheet(
                context: dialogContext,
                title: title,
                initialValue: controller.text,
                allowDecimal: allowDecimal,
                maxDecimalPlaces: maxDecimalPlaces,
                maxDigits: 9,
              );
              if (updated == null || !dialogContext.mounted) return;
              controller.text = updated;
              controller.selection = TextSelection.collapsed(
                offset: controller.text.length,
              );
              setDialogState(() {});
            }

            double calculateSubtotal() {
              return workingItems.fold<double>(
                0,
                (sum, item) => sum + (item.unitPrice * item.quantity),
              );
            }

            double? parsePackageTotal() {
              final rawPrice = priceController.text.trim().replaceAll(',', '.');
              final rawServingSize = servingSizeController.text.trim();
              final parsedPrice = double.tryParse(rawPrice);
              final parsedGuests = int.tryParse(rawServingSize);
              if (parsedPrice == null || parsedGuests == null) return null;
              return parsedPrice * parsedGuests;
            }

            Future<void> onAddItem() async {
              final selectedItems = await _showItemPicker(dialogContext);
              if (selectedItems == null || selectedItems.isEmpty) return;

              final optionsByKey = {
                for (final option in _menuItemOptions) option.key: option,
              };

              setDialogState(() {
                errorMessage = null;
                for (final entry in selectedItems.entries) {
                  final option = optionsByKey[entry.key];
                  if (option == null || entry.value <= 0) {
                    continue;
                  }
                  final existingIndex = workingItems.indexWhere(
                    (item) => item.itemKey == option.key,
                  );
                  if (existingIndex != -1) {
                    workingItems[existingIndex].quantity += entry.value;
                  } else {
                    workingItems.add(
                      PackageItem(
                        itemKey: option.key,
                        itemName: option.displayName,
                        quantity: entry.value,
                        unitPrice: option.unitPrice,
                      ),
                    );
                  }
                }
              });
            }

            void onRemoveItem(int index) {
              setDialogState(() {
                errorMessage = null;
                workingItems.removeAt(index);
              });
            }

            void onUpdateQuantity(int index, int delta) {
              setDialogState(() {
                errorMessage = null;
                final item = workingItems[index];
                final nextQuantity = item.quantity + delta;
                if (nextQuantity <= 0) {
                  workingItems.removeAt(index);
                } else {
                  item.quantity = nextQuantity;
                }
              });
            }

            Future<void> onSave() async {
              final trimmedName = nameController.text.trim();
              final parsedPrice = double.tryParse(
                priceController.text.trim().replaceAll(',', '.'),
              );
              final parsedServingSize = int.tryParse(
                servingSizeController.text.trim(),
              );

              if (trimmedName.isEmpty) {
                setDialogState(() => errorMessage = 'სახელი აუცილებელია');
                return;
              }
              if (workingItems.isEmpty) {
                setDialogState(
                  () => errorMessage = 'დაამატეთ მინიმუმ ერთი პროდუქტი',
                );
                return;
              }
              if (parsedPrice == null || parsedPrice <= 0) {
                setDialogState(() => errorMessage = 'მიუთითეთ სწორი ფასი');
                return;
              }
              if (parsedServingSize == null || parsedServingSize <= 0) {
                setDialogState(
                  () => errorMessage = 'მიუთითეთ სტუმრების რაოდენობა',
                );
                return;
              }

              Navigator.of(dialogContext).pop(
                _PackageEditorResult(
                  name: trimmedName,
                  description: descriptionController.text.trim().isEmpty
                      ? null
                      : descriptionController.text.trim(),
                  pricePerPerson: double.parse(parsedPrice.toStringAsFixed(2)),
                  servingSize: parsedServingSize,
                  items: workingItems
                      .map(
                        (item) => PackageItem(
                          itemKey: item.itemKey,
                          itemName: item.itemName,
                          quantity: item.quantity,
                          unitPrice: item.unitPrice,
                        ),
                      )
                      .toList(),
                  allowedTables: const <String>[],
                ),
              );
            }

            bool hasUnsavedChanges() {
              final currentName = nameController.text.trim();
              final currentDescription = descriptionController.text.trim();
              final currentPrice = priceController.text.trim();
              final currentGuests = servingSizeController.text.trim();
              final currentItems = workingItems
                  .map(
                    (item) =>
                        '${item.itemKey}|${item.itemName}|${item.quantity}|${item.unitPrice.toStringAsFixed(4)}',
                  )
                  .toList();

              if (currentName != initialName) return true;
              if (currentDescription != initialDescription) return true;
              if (currentPrice != initialPriceText) return true;
              if (currentGuests != initialGuestsText) return true;
              if (currentItems.length != initialItems.length) return true;

              for (var i = 0; i < currentItems.length; i++) {
                if (currentItems[i] != initialItems[i]) {
                  return true;
                }
              }
              return false;
            }

            Future<bool> confirmDiscardIfNeeded() async {
              if (!hasUnsavedChanges()) {
                return true;
              }

              final confirmed = await showDialog<bool>(
                context: dialogContext,
                barrierDismissible: false,
                builder: (confirmContext) => AlertDialog(
                  backgroundColor: _cardColor,
                  title: const Text(
                    'დახურვის დადასტურება',
                    style: TextStyle(color: _textPrimary),
                  ),
                  content: const Text(
                    'ცვლილებები არ არის შენახული. ნამდვილად გსურთ დახურვა?',
                    style: TextStyle(color: _textMuted),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                      child: const Text('გაგრძელება რედაქტირებაში'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(confirmContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('დახურვა'),
                    ),
                  ],
                ),
              );

              return confirmed == true;
            }

            return WillPopScope(
              onWillPop: () async => false,
              child: AlertDialog(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                insetPadding: EdgeInsets.zero,
                titlePadding: EdgeInsets.zero,
                contentPadding: EdgeInsets.zero,
                backgroundColor: _cardColor,
                title: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _borderColor)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        existing == null
                            ? 'პაკეტის შექმნა'
                            : 'პაკეტის რედაქტირება',
                        style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () async {
                          final shouldClose = await confirmDiscardIfNeeded();
                          if (!shouldClose) {
                            return;
                          }
                          if (!dialogContext.mounted) {
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                        },
                        icon: const Icon(Icons.close),
                        color: _textMuted,
                        tooltip: 'დახურვა',
                      ),
                    ],
                  ),
                ),
                content: SizedBox(
                  width: MediaQuery.of(dialogContext).size.width,
                  height: MediaQuery.of(dialogContext).size.height,
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                20,
                                24,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: nameController,
                                    readOnly: true,
                                    onTap: () => openTextKeyboard(
                                      controller: nameController,
                                      title: 'პაკეტის სახელი',
                                    ),
                                    style: const TextStyle(color: _textPrimary),
                                    decoration: buildFieldDecoration(
                                      label: 'პაკეტის სახელი',
                                      icon: Icons.inventory_2_outlined,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: descriptionController,
                                    readOnly: true,
                                    onTap: () => openTextKeyboard(
                                      controller: descriptionController,
                                      title: 'აღწერა',
                                    ),
                                    style: const TextStyle(color: _textPrimary),
                                    maxLines: 2,
                                    decoration: buildFieldDecoration(
                                      label: 'აღწერა (სურვილისამებრ)',
                                      icon: Icons.notes_outlined,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: priceController,
                                          readOnly: true,
                                          onTap: () => openNumberKeyboard(
                                            controller: priceController,
                                            title: 'ერთ ადამიანზე ფასი',
                                            allowDecimal: true,
                                            maxDecimalPlaces: 2,
                                          ),
                                          style: const TextStyle(
                                            color: _textPrimary,
                                          ),
                                          decoration: buildFieldDecoration(
                                            label: 'ერთ ადამიანზე ფასი (GEL)',
                                            icon: Icons.payments_outlined,
                                          ),
                                          onChanged: (_) =>
                                              setDialogState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextField(
                                          controller: servingSizeController,
                                          readOnly: true,
                                          onTap: () => openNumberKeyboard(
                                            controller: servingSizeController,
                                            title: 'სტუმრების რაოდენობა',
                                            allowDecimal: false,
                                            maxDecimalPlaces: 0,
                                          ),
                                          style: const TextStyle(
                                            color: _textPrimary,
                                          ),
                                          decoration: buildFieldDecoration(
                                            label: 'სტუმრების რაოდენობა',
                                            icon: Icons.groups_2_outlined,
                                          ),
                                          onChanged: (_) =>
                                              setDialogState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'პროდუქტების ჯამი',
                                            style: TextStyle(
                                              color: _textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '${calculateSubtotal().toStringAsFixed(2)} GEL',
                                            style: const TextStyle(
                                              color: _textPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 16),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'პაკეტის ჯამი',
                                            style: TextStyle(
                                              color: _textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            () {
                                              final total = parsePackageTotal();
                                              return total == null
                                                  ? '—'
                                                  : '${total.toStringAsFixed(2)} GEL';
                                            }(),
                                            style: const TextStyle(
                                              color: _textPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'პაკეტის პროდუქტები',
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: onAddItem,
                                        icon: const Icon(
                                          Icons.add,
                                          color: _primaryColor,
                                        ),
                                        label: const Text('პროდუქტის დამატება'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (workingItems.isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: _surfaceColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: _borderColor),
                                      ),
                                      child: const Text(
                                        'პროდუქტები ჯერ არ არის დამატებული.',
                                        style: TextStyle(color: _textMuted),
                                      ),
                                    )
                                  else
                                    Container(
                                      decoration: BoxDecoration(
                                        color: _surfaceColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: _borderColor),
                                      ),
                                      child: Column(
                                        children: workingItems.asMap().entries.map((
                                          entry,
                                        ) {
                                          final index = entry.key;
                                          final item = entry.value;
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: _borderColor,
                                                  width: 0.7,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item.itemName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: _textPrimary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${item.unitPrice.toStringAsFixed(2)} GEL x ${item.quantity} = ${(item.unitPrice * item.quantity).toStringAsFixed(2)} GEL',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: _textMuted,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.remove_circle_outline,
                                                    color: _textMuted,
                                                  ),
                                                  onPressed: () =>
                                                      onUpdateQuantity(
                                                        index,
                                                        -1,
                                                      ),
                                                ),
                                                Container(
                                                  width: 34,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '${item.quantity}',
                                                    style: const TextStyle(
                                                      color: _textPrimary,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.add_circle_outline,
                                                    color: _textMuted,
                                                  ),
                                                  onPressed: () =>
                                                      onUpdateQuantity(
                                                        index,
                                                        1,
                                                      ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                  ),
                                                  onPressed: () =>
                                                      onRemoveItem(index),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  if (errorMessage != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      errorMessage!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: _borderColor)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                final shouldClose =
                                    await confirmDiscardIfNeeded();
                                if (!shouldClose) {
                                  return;
                                }
                                if (!dialogContext.mounted) {
                                  return;
                                }
                                Navigator.of(dialogContext).pop();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: _textMuted,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('გაუქმება'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: onSave,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _secondaryColor,
                                foregroundColor: Colors.white,
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
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
    ).whenComplete(() {
      nameController.dispose();
      descriptionController.dispose();
      priceController.dispose();
      servingSizeController.dispose();
    });
  }

  Future<Map<String, int>?> _showItemPicker(BuildContext context) async {
    final searchController = TextEditingController();
    String selectedCategory = 'ყველა';
    String selectedSubcategory = 'ყველა';
    final selectedQuantities = <String, int>{};

    return showDialog<Map<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> requestClosePicker() async {
              if (selectedQuantities.isEmpty) {
                Navigator.of(dialogContext).pop();
                return;
              }

              final shouldClose = await showDialog<bool>(
                context: dialogContext,
                barrierDismissible: false,
                builder: (confirmContext) => AlertDialog(
                  backgroundColor: _cardColor,
                  title: const Text(
                    'დახურვის დადასტურება',
                    style: TextStyle(color: _textPrimary),
                  ),
                  content: const Text(
                    'არჩეული პროდუქტები ჯერ არ დამატებულა. ნამდვილად გსურთ დახურვა?',
                    style: TextStyle(color: _textMuted),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                      child: const Text('დაბრუნება'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(confirmContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
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
                                    final option = _menuItemOptions.firstWhere(
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
                                                  color: _textMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            setDialogState(() {
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
                                          ),
                                        ),
                                        Text('$qty'),
                                        IconButton(
                                          onPressed: () {
                                            setDialogState(() {
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
            for (final option in _menuItemOptions) {
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
              for (final option in _menuItemOptions.where(
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
            final filtered = _menuItemOptions.where((option) {
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

            return WillPopScope(
              onWillPop: () async => false,
              child: AlertDialog(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                insetPadding: EdgeInsets.zero,
                titlePadding: EdgeInsets.zero,
                contentPadding: EdgeInsets.zero,
                backgroundColor: _cardColor,
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
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: requestClosePicker,
                        icon: const Icon(Icons.close),
                        color: _textMuted,
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
                              onTap: () async {
                                await showPosKeyboardInputSheet(
                                  context: dialogContext,
                                  controller: searchController,
                                  initialLanguage: PosKeyboardLanguage.georgian,
                                  title: 'პროდუქტების ძიება',
                                );
                                if (!dialogContext.mounted) return;
                                setDialogState(() {});
                              },
                              style: const TextStyle(color: _textPrimary),
                              decoration: InputDecoration(
                                labelText: 'პროდუქტების ძიება',
                                labelStyle: const TextStyle(color: _textMuted),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: _textMuted,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFF),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _borderColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _borderColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              children: sortedCategories.map((category) {
                                final selected = category == selectedCategory;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(category),
                                    selected: selected,
                                    onSelected: (_) {
                                      setDialogState(() {
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
                                children: sortedSubcategories.map((
                                  subcategory,
                                ) {
                                  final selected =
                                      subcategory == selectedSubcategory;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(subcategory),
                                      selected: selected,
                                      onSelected: (_) {
                                        setDialogState(() {
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
                                      style: TextStyle(color: _textMuted),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                                            color: _textPrimary,
                                          ),
                                        ),
                                        subtitle: Text(
                                          subtitle,
                                          style: const TextStyle(
                                            color: _textMuted,
                                          ),
                                        ),
                                        trailing: Text(
                                          '${option.unitPrice.toStringAsFixed(2)} GEL',
                                          style: const TextStyle(
                                            color: _primaryColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onTap: () {
                                          setDialogState(() {
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
                                                  color: _secondaryColor,
                                                  borderRadius:
                                                      BorderRadius.circular(13),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '$selectedQty',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.add_circle_outline,
                                                color: _textMuted,
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
                                  icon: const Icon(Icons.checklist_outlined),
                                  label: const Text('არჩეულების მართვა'),
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: requestClosePicker,
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
                                        backgroundColor: _secondaryColor,
                                        foregroundColor: Colors.white,
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
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(searchController.dispose);
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _MenuItemOption {
  const _MenuItemOption({
    required this.key,
    required this.displayName,
    required this.unitPrice,
    required this.categoryKey,
    required this.categoryLabel,
    required this.subcategoryLabel,
    required this.orderIndex,
  });

  final String key;
  final String displayName;
  final double unitPrice;
  final String categoryKey;
  final String categoryLabel;
  final String? subcategoryLabel;
  final int orderIndex;
}

class _PackageDeploymentResult {
  const _PackageDeploymentResult({
    required this.tableNumbers,
    required this.floor,
  });

  final List<String> tableNumbers;
  final String floor;
}

class _PackageEditorResult {
  const _PackageEditorResult({
    required this.name,
    required this.description,
    required this.pricePerPerson,
    required this.servingSize,
    required this.items,
    required this.allowedTables,
  });

  final String name;
  final String? description;
  final double pricePerPerson;
  final int servingSize;
  final List<PackageItem> items;
  final List<String> allowedTables;
}
