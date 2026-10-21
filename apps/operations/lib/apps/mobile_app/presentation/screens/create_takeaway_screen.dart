import 'package:vynic/core/services/manager_app/manager_operation_request.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'package:vynic/apps/mobile_app/data/repositories/takeaway_repository.dart';
import 'package:vynic/apps/mobile_app/data/services/takeaway_remote_service.dart';
import 'package:vynic/apps/mobile_app/presentation/controllers/create_takeaway_controller.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/create_takeaway_sections.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

class CreateTakeawayScreen extends StatefulWidget {
  final User user;
  const CreateTakeawayScreen({super.key, required this.user});

  @override
  State<CreateTakeawayScreen> createState() => _CreateTakeawayScreenState();
}

class _CreateTakeawayScreenState extends State<CreateTakeawayScreen> {
  late final CreateTakeawayController _controller;
  final _customerNameController = TextEditingController();
  final _pickupTimeController = TextEditingController();

  String? _operationScope;
  @override
  void initState() {
    super.initState();
    try {
      _operationScope = MobileApiService.tableRepairScope;
    } catch (_) {
      _operationScope = null;
    }
    _controller = CreateTakeawayController(
      const TakeawayRepository(TakeawayRemoteService()),
      expectedScope: _operationScope,
    );
    _controller.addListener(_onControllerChanged);
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    await _controller.initialize();
    try {
      await ManagerOperationRequests.init();
      final scope = _operationScope;
      if (!mounted ||
          scope == null ||
          !MobileApiService.isCurrentTableRepairScope(scope))
        return;
      final v = ManagerOperationRequests.read(scope, 'takeaway_create');
      if (v == null || ManagerOperationResult.fromMap(v['result']).isDone)
        return;
      _controller.newRequest = false;
      final b = v['body'] as Map;
      _controller.setCustomerName(b['customerName']);
      _controller.setPickupTime(b['pickupTime']);
      _controller.replaceCartFromSelection([
        for (final i in b['items'])
          {
            'itemName': i['itemName'],
            'unitPrice': i['unitPrice'],
            'qty': i['quantity'],
            'key':
                i['itemKey'] ??
                (i['menuItemId'] != null
                    ? 'menu:${i['menuItemId']}${i['variantId'] != null ? '/variant:${i['variantId']}' : ''}'
                    : i['itemName']),
            'menuItemId': i['menuItemId'],
            'variantId': i['variantId'],
          },
      ]);
    } catch (_) {
      if (mounted)
        ManagerToast.showSnackBar(
          context,
          'მოთხოვნის მონახაზი ვერ ჩაიტვირთა',
          isError: true,
        );
    }
  }

  void _onControllerChanged() {
    final s = _controller.state;
    if (_customerNameController.text != s.customerName) {
      _customerNameController.text = s.customerName;
    }
    if (_pickupTimeController.text != s.pickupTime) {
      _pickupTimeController.text = s.pickupTime;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _customerNameController.dispose();
    _pickupTimeController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final parts = _pickupTimeController.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts.first : '12') ?? 12,
      minute: int.tryParse(parts.length > 1 ? parts.last : '00') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      _controller.setPickupTime(
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> _submit() async {
    final result = await _controller.submit(widget.user);
    if (!mounted ||
        _operationScope == null ||
        !MobileApiService.isCurrentTableRepairScope(_operationScope!))
      return;
    if (result.success) {
      Navigator.pop(context, true);
      return;
    }
    ManagerToast.showSnackBar(
      context,
      result.message ?? 'შეცდომა',
      isError: result.isError,
    );
  }

  Future<void> _openUnifiedMenuSelector() async {
    final initial = _controller.state.cart.entries
        .map(
          (e) => MenuSelectionLine(
            key: e.key,
            itemName: e.value.itemName ?? e.key,
            unitPrice: e.value.price,
            qty: e.value.quantity,
            menuItemId: e.value.menuItemId,
            variantId: e.value.variantId,
          ),
        )
        .toList();
    final selected = await Navigator.of(context).push<List<MenuSelectionLine>>(
      MaterialPageRoute(
        builder: (_) => managerThemedPage(
          MobileCalculatorScreen(
            selectionMode: true,
            initialSelection: initial,
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _controller.replaceCartFromSelection(
      selected
          .map(
            (e) => {
              'itemName': e.itemName,
              'qty': e.qty,
              'unitPrice': e.unitPrice,
              'key': e.key,
              'menuItemId': e.menuItemId,
              'variantId': e.variantId,
            },
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _controller.state;
    return ManagerOperationBoundary(
      scope: _operationScope,
      slot: 'takeaway_create',
      child: Scaffold(
        backgroundColor: MobileGlassTheme.bg,
        appBar: AppBar(
          backgroundColor: MobileGlassTheme.surfaceCard,
          foregroundColor: MobileGlassTheme.textPrimary,
          elevation: 0,
          title: Text(
            'ახალი გატანის შეკვეთა',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: MobileGlassTheme.textPrimary,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: MobileGlassTheme.borderSubtle),
          ),
        ),
        body: s.loading
            ? Center(
                child: CircularProgressIndicator(
                  color: MobileGlassTheme.primary,
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        SectionCard(
                          title: 'მომხმარებელი',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: s.waitInPlace,
                                    onChanged: (v) =>
                                        _controller.setWaitInPlace(v ?? false),
                                    activeColor: MobileGlassTheme.primary,
                                  ),
                                  Expanded(
                                    child: Text(
                                      'აქ დაელოდება (ადგილზე ელოდება)',
                                      style: TextStyle(
                                        color: MobileGlassTheme.textPrimary,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (!s.waitInPlace) ...[
                                SizedBox(height: 8),
                                TextField(
                                  controller: _customerNameController,
                                  keyboardType: TextInputType.phone,
                                  onChanged: _controller.setCustomerName,
                                  decoration: InputDecoration(
                                    hintText: 'ტელეფონის ნომერი',
                                    prefixIcon: const Icon(
                                      Icons.phone_rounded,
                                      size: 18,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: MobileGlassTheme.borderSubtle,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: MobileGlassTheme.borderSubtle,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: MobileGlassTheme.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                        SectionCard(
                          title: 'გამოსატანი დრო',
                          child: InkWell(
                            onTap: _pickTime,
                            child: AbsorbPointer(
                              child: TextField(
                                controller: _pickupTimeController,
                                decoration: InputDecoration(
                                  hintText: '00:00',
                                  prefixIcon: const Icon(
                                    Icons.access_time_rounded,
                                    size: 18,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: MobileGlassTheme.borderSubtle,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: MobileGlassTheme.borderSubtle,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: MobileGlassTheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        CartSummarySection(
                          cart: s.cart,
                          total: s.total,
                          onInc: _controller.incrementCartItem,
                          onDec: _controller.decrementItem,
                        ),
                        if (s.cart.isNotEmpty) SizedBox(height: 12),
                        SectionCard(
                          title: 'მენიუს სრული არჩევა',
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openUnifiedMenuSelector,
                              icon: Icon(
                                Icons.menu_book_rounded,
                                color: MobileGlassTheme.primary,
                              ),
                              label: Text(
                                'მენიუს გახსნა',
                                style: TextStyle(
                                  color: MobileGlassTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: MobileGlassTheme.primary,
                                side: BorderSide(
                                  color: MobileGlassTheme.primary.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        MenuItemsSection(
                          menuItems: s.menuItems,
                          cart: s.cart,
                          onInc: _controller.incrementItem,
                          onDec: _controller.decrementItem,
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: MobileGlassTheme.surfaceCard,
                      border: Border(
                        top: BorderSide(color: MobileGlassTheme.borderSubtle),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MobileGlassTheme.data.cardShadow,
                          blurRadius: 12,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        12 + MediaQuery.of(context).padding.bottom,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: s.submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MobileGlassTheme.primary,
                            foregroundColor: MobileGlassTheme.onPrimary,
                            disabledBackgroundColor: MobileGlassTheme.primary
                                .withValues(alpha: 0.35),
                            disabledForegroundColor: MobileGlassTheme.onPrimary
                                .withValues(alpha: 0.7),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: s.submitting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: MobileGlassTheme.onPrimary,
                                  ),
                                )
                              : Text(
                                  s.cart.isEmpty
                                      ? 'შეკვეთის შექმნა'
                                      : 'შეკვეთის შექმნა — ${s.total.toStringAsFixed(2)} ₾',
                                  style: TextStyle(
                                    color: MobileGlassTheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
