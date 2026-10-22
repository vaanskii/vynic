import '../widgets/manager_design_components.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_operations_panel.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/order_edit_request.dart';
import 'package:vynic/core/services/manager_app/pos_command_delivery.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/order_editor_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_receipt_preview_dialog.dart';
import 'package:vynic/core/widgets/service_fee_adjust_dialog.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/utils/table_group_style.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

/// Read-only order view (Windows [OrderDetailScreen] flow) — edit via menu screen.
class MobileOrderDetailScreen extends StatefulWidget {
  const MobileOrderDetailScreen({
    super.key,
    required this.user,
    required this.orderId,
    this.tableNumber,
    this.floor,
    this.highlightItemKeys,
    this.onClose,
  });

  final ValueChanged<Object?>? onClose;
  final User user;
  final int orderId;
  final String? tableNumber;
  final String? floor;
  final Set<String>? highlightItemKeys;

  @override
  State<MobileOrderDetailScreen> createState() =>
      _MobileOrderDetailScreenState();
}

class _MobileOrderDetailScreenState extends State<MobileOrderDetailScreen> {
  Order? _order;
  String? _displayedEditScope;
  OrderEditResult? _editResult;
  bool get _sameEditSession =>
      _displayedEditScope != null &&
      MobileApiService.isCurrentTableRepairScope(_displayedEditScope!);
  bool get _canEditFee =>
      _canEdit &&
      _sameEditSession &&
      _order?.managerEditProjection != null &&
      (_editResult == null || _editResult!.isDone);
  bool _isLoading = true;
  bool _isTogglingServiceFee = false;
  bool _serviceFeeAvailable = false;
  bool _printingCheck = false;
  int _serviceFeePercent = 10;
  late Set<String> _highlightKeys;

  void _close([Object? result]) {
    if (widget.onClose != null) {
      widget.onClose!(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      _displayedEditScope = MobileApiService.tableRepairScope;
    } catch (_) {
      _displayedEditScope = null;
    }
    _highlightKeys =
        widget.highlightItemKeys ??
        PosChangeHighlightService.takeForOrder(widget.orderId) ??
        {};
    MonitoringSocketService.updateCounter.addListener(_onRemoteChange);
    _loadOrder();
  }

  @override
  void dispose() {
    MonitoringSocketService.updateCounter.removeListener(_onRemoteChange);
    super.dispose();
  }

  void _onRemoteChange() {
    if (mounted) _loadOrder();
  }

  Future<void> _loadOrder() async {
    try {
      final results = await Future.wait([
        MobileApiService.getOrder(widget.orderId),
        MobileApiService.getRestaurantSettings(),
        MobileApiService.getTables(),
      ]);
      await OrderEditRequests.init();
      if (!mounted) return;
      if (!_sameEditSession) {
        setState(() => _isLoading = false);
        return;
      }
      final retained = OrderEditRequests.read(
        _displayedEditScope!,
        widget.orderId,
      );
      var order = results[0] as Order;
      final settings = results[1] as Map<String, dynamic>;
      final tables = results[2] as List<TableModel>;
      order = _enrichOrderTables(order, tables);
      final pending = PosChangeHighlightService.takeForOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _editResult = retained == null
            ? null
            : OrderEditResult.fromMap(retained['result']);
        _serviceFeeAvailable = settings['serviceFeeAvailable'] == true;
        _serviceFeePercent =
            (settings['serviceFeePercent'] as num?)?.round() ?? 10;
        if (pending != null && pending.isNotEmpty) {
          _highlightKeys = pending;
        } else if (_highlightKeys.isEmpty &&
            widget.highlightItemKeys != null &&
            widget.highlightItemKeys!.isNotEmpty) {
          _highlightKeys = widget.highlightItemKeys!;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ManagerToast.show(
        context,
        'შეკვეთის ჩატვირთვა ვერ მოხერხდა',
        isError: true,
      );
    }
  }

  bool get _canEdit {
    final order = _order;
    if (order == null) return false;
    final s = order.status;
    return s != 'paid' && s != 'cancelled' && s != 'closed';
  }

  Order _enrichOrderTables(Order order, List<TableModel> tables) {
    if (order.tableNumbers.isNotEmpty) return order;
    final linked = tables
        .where((t) => t.activeOrderId == order.orderId)
        .toList();
    if (linked.isEmpty) return order;
    order.tableNumbers = linked.map((t) => t.tableNumber).toList();
    if (order.floor.trim().isEmpty) {
      order.floor = linked.first.floor;
    }
    return order;
  }

  String _tableLabel(Order order) {
    if (order.tableNumbers.isNotEmpty) {
      return TableGroupStyle.formatOrderTablesLabel(order);
    }
    if (widget.tableNumber != null && widget.tableNumber!.trim().isNotEmpty) {
      return TableGroupStyle.formatTableNumbersList([
        widget.tableNumber!,
      ], widget.floor ?? order.floor);
    }
    return '—';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return MobileGlassTheme.warn;
      case 'confirmed':
        return MobileGlassTheme.accent;
      case 'preparing':
        return MobileGlassTheme.primary;
      case 'served':
        return MobileGlassTheme.good;
      case 'paid':
      case 'closed':
        return MobileGlassTheme.muted(0.4);
      case 'cancelled':
        return MobileGlassTheme.bad;
      default:
        return MobileGlassTheme.muted();
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'მოლოდინში';
      case 'confirmed':
        return 'დადასტურებული';
      case 'preparing':
        return 'მზადდება';
      case 'served':
        return 'მიტანილი';
      case 'paid':
        return 'გადახდილი';
      case 'closed':
        return 'დახურული';
      case 'cancelled':
        return 'გაუქმებული';
      default:
        return status;
    }
  }

  Future<void> _toggleServiceFee() async {
    final current = _order;
    final order = current?.managerEditProjection == null
        ? null
        : OrderEditProjection.read(current!.managerEditProjection!);
    if (order == null ||
        !_canEditFee ||
        !_serviceFeeAvailable ||
        _isTogglingServiceFee) {
      return;
    }

    setState(() => _isTogglingServiceFee = true);
    try {
      final turningOn = !order.includeServiceFee;
      final rate =
          order.getEffectiveServiceFeePercentage(
            globalDefaultPercentage: _serviceFeePercent.toDouble(),
          ) /
          100;
      order.includeServiceFee = turningOn;
      order.recalculateTotal(serviceFeeRate: turningOn ? rate : 0);
      final delivery = await MobileApiService.updateOrder(
        order,
        expectedScope: _displayedEditScope,
      );
      if (!mounted || !_sameEditSession) return;
      setState(() => _editResult = delivery);
      await _loadOrder();
      if (!mounted || !_sameEditSession) return;
      if (!delivery.isDone) {
        ManagerToast.show(
          context,
          delivery.message,
          isError: !delivery.needsCheck,
        );
        return;
      }
      ManagerToast.show(
        context,
        turningOn
            ? 'სერვისის საფასური ჩართულია'
            : 'სერვისის საფასური გამორთულია',
      );
    } catch (e) {
      if (mounted) {
        ManagerToast.show(
          context,
          'სერვისის საფასურის განახლება ვერ მოხერხდა',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingServiceFee = false);
    }
  }

  Future<void> _openServiceFeeConfig() async {
    final current = _order;
    final order = current?.managerEditProjection == null
        ? null
        : OrderEditProjection.read(current!.managerEditProjection!);
    if (order == null || !_canEditFee || !_serviceFeeAvailable) return;

    final defaultPercent = _serviceFeePercent.toDouble();
    final initialPercent = order.getEffectiveServiceFeePercentage(
      globalDefaultPercentage: defaultPercent,
    );

    final result = await showDialog<ServiceFeeAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceFeeAdjustDialog(
        initialIncludeServiceFee: order.includeServiceFee,
        initialPercentage: initialPercent,
        defaultPercentage: defaultPercent,
        showQuickValues: false,
        showSteppers: true,
      ),
    );

    if (result == null || !mounted || !_sameEditSession) return;

    setState(() => _isTogglingServiceFee = true);
    try {
      final normalizedPercent = double.parse(
        result.percentage.clamp(0.0, 100.0).toStringAsFixed(2),
      );
      final useGlobalDefault =
          (normalizedPercent - defaultPercent).abs() < 0.01;
      order.includeServiceFee = result.includeServiceFee;
      order.customServiceFeePercentage = useGlobalDefault
          ? null
          : normalizedPercent;
      order.recalculateTotal(serviceFeeRate: normalizedPercent / 100);
      final delivery = await MobileApiService.updateOrder(
        order,
        expectedScope: _displayedEditScope,
      );
      if (!mounted || !_sameEditSession) return;
      setState(() => _editResult = delivery);
      await _loadOrder();
      if (!mounted || !_sameEditSession) return;
      if (!delivery.isDone) {
        ManagerToast.show(
          context,
          delivery.message,
          isError: !delivery.needsCheck,
        );
        return;
      }
      ManagerToast.show(context, 'სერვისი განახლდა');
    } catch (e) {
      if (mounted) {
        ManagerToast.show(
          context,
          'სერვისის განახლება ვერ მოხერხდა',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingServiceFee = false);
    }
  }

  String _serviceFeeLabelForOrder(Order order) {
    return order
        .getEffectiveServiceFeePercentage(
          globalDefaultPercentage: _serviceFeePercent.toDouble(),
        )
        .round()
        .toString();
  }

  Future<void> _editOrder() async {
    final order = _order;
    if (order == null || !_canEdit) return;

    final tableNum = order.tableNumbers.isNotEmpty
        ? order.tableNumbers.first.replaceAll('Table ', '').trim()
        : (widget.tableNumber ?? '?');

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => managerThemedPage(
          OrderEditorScreen(
            user: widget.user,
            orderId: widget.orderId,
            tableNumber: tableNum,
            floor: order.floor.isNotEmpty
                ? order.floor
                : (widget.floor ?? 'first'),
          ),
        ),
      ),
    );

    await _loadOrder();
    if (!mounted) return;
    if (result != null) {
      _close(result);
    }
  }

  Future<void> _cancelOrder() async {
    final order = _order;
    if (order == null || !_canEdit) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MobileGlassTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'მაგიდის გაუქმება?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: MobileGlassTheme.textPrimary,
          ),
        ),
        content: Text(
          'შეკვეთა #${order.orderId} (${_tableLabel(order)}) '
          'სამუდამოდ გაუქმდება და მაგიდა გათავისუფლდება.\n'
          'ეს ქმედება ვერ დაბრუნდება.',
          style: TextStyle(color: MobileGlassTheme.muted(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'უკან',
              style: TextStyle(color: MobileGlassTheme.muted()),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: MobileGlassTheme.bad,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('გაუქმება'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final result = await MobileApiService.cancelOrder(
        order.orderId,
        expectedScope: _displayedEditScope,
      );
      if (!mounted || !_sameEditSession) return;
      ManagerToast.show(
        context,
        result.message,
        isError: result.delivery.name == 'failed',
      );
      if (result.isDone) _close('cancelled');
    } catch (e) {
      if (!mounted) return;
      ManagerToast.show(context, 'გაუქმება ვერ მოხერხდა: $e', isError: true);
    }
  }

  Future<void> _viewReceipt() async {
    final order = _order;
    if (order == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(child: CircularProgressIndicator()),
    );

    try {
      final itemsList = order.items
          .map((i) => '${i.quantity}x ${i.itemName} - ${i.unitPrice}')
          .toList();
      final pngBytes = await PrinterService.generateReceiptPngBytes(
        items: itemsList,
        total: order.totalAmount,
        subtotal: order.getItemsSubtotal(),
        serviceFee: order.getServiceFee(),
        includeServiceFee: order.includeServiceFee,
        tableNumber: order.tableNumbers.join(', '),
        orderNumber: order.orderId.toString(),
        language: 'ka',
        packageSubtotal: order.packagePrice,
        discountAmount: order.discountAmount,
        manualAdjustment: order.manualAdjustmentAmount,
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (pngBytes != null) {
        MobileReceiptPreviewDialog.show(
          context,
          pngBytes,
          title: 'ქვითარი #${order.orderId}',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ManagerToast.show(context, 'ქვითარი ვერ გენერირდა', isError: true);
      }
    }
  }

  /// Print the order/table check (customer pre-bill) on the Windows POS — the
  /// only print host. The manager client never prints directly: the backend
  /// relays this to the POS callback path. Owns its own loading flag so the
  /// user cannot trigger repeated prints with rapid taps.
  Future<void> _printOrderCheck() async {
    final order = _order;
    if (order == null || _printingCheck) return;
    setState(() => _printingCheck = true);
    try {
      final delivery = await MobileApiService.printOrderCheck(order.orderId);
      if (!mounted) return;
      // Only the POS can say a check printed. A queued request means the
      // terminal has not asked for it yet, and saying "printed" then would send
      // somebody to an empty printer.
      ManagerToast.show(
        context,
        delivery.printMessage,
        isError: delivery.name == 'failed' || delivery.name == 'unavailable',
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      if (message.contains('404')) {
        ManagerToast.show(
          context,
          'შეკვეთა ვერ მოიძებნა POS-ზე',
          isError: true,
        );
      } else {
        ManagerToast.show(
          context,
          'ბეჭდვა ვერ მოხერხდა — POS მიუწვდომელია',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _printingCheck = false);
    }
  }

  Future<void> _checkEditResult() async {
    if (!_sameEditSession || _isTogglingServiceFee) return;
    final draft = OrderEditRequests.draft(_displayedEditScope!, widget.orderId);
    if (draft == null) return;
    setState(() => _isTogglingServiceFee = true);
    try {
      final result = await MobileApiService.updateOrder(
        draft,
        expectedScope: _displayedEditScope,
      );
      if (!mounted || !_sameEditSession) return;
      setState(() => _editResult = result);
      if (result.isDone) await _loadOrder();
    } catch (e) {
      if (mounted && _sameEditSession)
        ManagerToast.show(
          context,
          'შედეგის გადამოწმება ვერ მოხერხდა',
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _isTogglingServiceFee = false);
    }
  }

  Future<void> _discardEditResult() async {
    if (!_sameEditSession || _editResult?.needsCheck == true) return;
    try {
      await OrderEditRequests.discard(_displayedEditScope!, widget.orderId);
    } catch (e) {
      if (mounted)
        ManagerToast.show(
          context,
          'მონახაზის გაუქმება ვერ მოხერხდა — სცადეთ ხელახლა',
          isError: true,
        );
      return;
    }
    if (!mounted || !_sameEditSession) return;
    await _loadOrder();
  }

  Widget _editDeliveryPanel() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _editResult!.message,
          key: const ValueKey('manager-order-detail-edit-status'),
        ),
        if (!_editResult!.isDone)
          Wrap(
            spacing: 12,
            children: [
              if (_editResult!.delivery != PosCommandDelivery.failed)
                TextButton(
                  onPressed: _isTogglingServiceFee ? null : _checkEditResult,
                  child: const Text('შედეგის გადამოწმება'),
                ),
              if (!_editResult!.needsCheck)
                TextButton(
                  onPressed: _discardEditResult,
                  child: const Text('განახლება და მონახაზის გაუქმება'),
                ),
            ],
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_sameEditSession)
      return ManagerOperationBoundary(
        scope: _displayedEditScope,
        slot: 'order_cancel:${widget.orderId}',
        child: MobileGlassScreen(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('სესია შეიცვალა — გახსენით შეკვეთა თავიდან'),
                TextButton(
                  onPressed: () => _close(),
                  child: const Text('უკან'),
                ),
              ],
            ),
          ),
        ),
      );
    if (_isLoading) {
      return ManagerOperationBoundary(
        scope: _displayedEditScope,
        slot: 'order_cancel:${widget.orderId}',
        child: MobileGlassScreen(
          orbs: [
            Positioned(
              top: -80,
              right: -60,
              child: MobileGlowOrb(color: MobileGlassTheme.primary, size: 220),
            ),
            Positioned(
              bottom: 80,
              left: -80,
              child: MobileGlowOrb(color: MobileGlassTheme.accent, size: 260),
            ),
          ],
          body: Column(
            children: [
              MobileGlassHeader(
                title: 'შეკვეთა #${widget.orderId}',
                onBack: () => _close(),
              ),
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: MobileGlassTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_order == null) {
      return ManagerOperationBoundary(
        scope: _displayedEditScope,
        slot: 'order_cancel:${widget.orderId}',
        child: MobileGlassScreen(
          orbs: [
            Positioned(
              top: -80,
              right: -60,
              child: MobileGlowOrb(color: MobileGlassTheme.warn, size: 220),
            ),
          ],
          body: Column(
            children: [
              MobileGlassHeader(
                title: 'შეკვეთა #${widget.orderId}',
                onBack: () => _close(),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: MobileGlassCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 48,
                            color: MobileGlassTheme.warn,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'შეკვეთა ვერ მოიძებნა',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: MobileGlassTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 16),
                          MobileGlassPrimaryButton(
                            label: 'თავიდან',
                            icon: Icons.refresh_rounded,
                            onPressed: () {
                              setState(() => _isLoading = true);
                              _loadOrder();
                            },
                          ),
                        ],
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

    final order = _order!;
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm');

    return ManagerOperationBoundary(
      scope: _displayedEditScope,
      slot: 'order_cancel:${widget.orderId}',
      child: MobileGlassScreen(
        orbs: [
          Positioned(
            top: -90,
            right: -70,
            child: MobileGlowOrb(color: MobileGlassTheme.primary, size: 240),
          ),
          Positioned(
            bottom: 100,
            left: -90,
            child: MobileGlowOrb(color: MobileGlassTheme.accent, size: 280),
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileGlassHeader(
              title: 'შეკვეთა #${order.orderId}',
              subtitle: _tableLabel(order),
              onBack: () => _close(),
              actions: [
                IconButton(
                  onPressed: _viewReceipt,
                  icon: Icon(
                    Icons.receipt_long_rounded,
                    color: MobileGlassTheme.muted(0.85),
                  ),
                  tooltip: 'ქვითარი',
                ),
              ],
            ),
            if (_editResult != null) _editDeliveryPanel(),
            if (_highlightKeys.isNotEmpty) _buildChangeBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ManagerPanel(
                      padding: 22,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeaderCard(order, dateFmt),
                          const Divider(height: 36),
                          _buildItemsList(order),
                          const Divider(height: 24),
                          _buildTotalsFooter(order),
                          if (_canEdit &&
                              _serviceFeeAvailable &&
                              widget.floor != 'takeaway')
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'მომსახურების პარამეტრები',
                                style: managerDesignText(
                                  context,
                                  12,
                                  muted: true,
                                ),
                              ),
                              children: [_buildServiceFeeRow(order)],
                            ),
                          const SizedBox(height: 18),
                          if (_canEdit) _buildActionBar(),
                          _buildPrintCheckBar(),
                          if (_canEdit)
                            TextButton(
                              onPressed: _cancelOrder,
                              style: TextButton.styleFrom(
                                foregroundColor: MobileGlassTheme.bad,
                              ),
                              child: const Text('შეკვეთის გაუქმება'),
                            ),
                        ],
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

  Widget _buildChangeBanner() {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8));
  }

  Widget _buildHeaderCard(Order order, DateFormat dateFmt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              _tableLabel(order),
              style: managerDesignText(context, 22, weight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _statusColor(order.status).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _statusLabel(order.status),
              style: managerDesignText(
                context,
                11,
              ).copyWith(color: _statusColor(order.status)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'შეკვეთა #${order.orderId}',
        style: managerDesignText(context, 11, muted: true),
      ),
      const SizedBox(height: 18),
      if (order.createdBy.isNotEmpty)
        ManagerKeyValue('ოპერატორი', order.createdBy),
      ManagerKeyValue('შექმნილია', dateFmt.format(order.createdAt)),
    ],
  );

  Widget _buildItemsList(Order order) => order.items.isEmpty
      ? const ManagerHelpCallout('შეკვეთაში პოზიციები არ არის')
      : Column(
          children: [for (final item in order.items) _buildItemTile(item)],
        );

  Widget _buildItemTile(OrderItem item) {
    final highlighted = PosChangeHighlightService.shouldHighlightItem(
      _highlightKeys,
      item.itemKey,
      item.itemName,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: highlighted
          ? BoxDecoration(
              color: MobileGlassTheme.highlightBorder.withValues(alpha: 0.1),
              border: Border(
                left: BorderSide(
                  color: MobileGlassTheme.highlightBorder,
                  width: 3,
                ),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: managerDesignText(
                    context,
                    12,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.quantity} × ${item.unitPrice.toStringAsFixed(2)} ₾',
                  style: managerDesignText(context, 10, muted: true),
                ),
                if (item.comment?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.comment!,
                      style: managerDesignText(context, 11, muted: true),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.total.toStringAsFixed(2)} ₾',
            style: managerDesignText(context, 12, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsFooter(Order order) {
    final subtotal = order.getItemsSubtotal();
    final serviceFee = order.getServiceFee(
      serviceFeeRate: order.includeServiceFee && _serviceFeeAvailable
          ? order.getEffectiveServiceFeePercentage(
                  globalDefaultPercentage: _serviceFeePercent.toDouble(),
                ) /
                100
          : 0,
    );
    final feeLabel = order
        .getEffectiveServiceFeePercentage(
          globalDefaultPercentage: _serviceFeePercent.toDouble(),
        )
        .round();

    return Column(
      children: [
        ManagerKeyValue('პროდუქტების ჯამი', '${subtotal.toStringAsFixed(2)} ₾'),
        if (_serviceFeeAvailable &&
            widget.floor != 'takeaway' &&
            order.includeServiceFee &&
            serviceFee > 0)
          ManagerKeyValue(
            'მომსახურება · $feeLabel%',
            '${serviceFee.toStringAsFixed(2)} ₾',
          ),
        if (order.discountAmount > 0)
          ManagerKeyValue(
            'ფასდაკლება',
            '-${order.discountAmount.toStringAsFixed(2)} ₾',
          ),
        ManagerKeyValue(
          'გადასახდელი',
          '${order.totalAmount.toStringAsFixed(2)} ₾',
          emphasis: true,
        ),
      ],
    );
  }

  Widget _buildServiceFeeRow(Order order) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: MobileGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        radius: 14,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'სერვისის საფასური (${_serviceFeeLabelForOrder(order)}%)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MobileGlassTheme.textPrimary,
                ),
              ),
            ),
            if (_isTogglingServiceFee)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MobileGlassTheme.primary,
                ),
              )
            else ...[
              IconButton(
                onPressed: _canEditFee ? _openServiceFeeConfig : null,
                icon: Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: _canEdit
                      ? MobileGlassTheme.muted(0.85)
                      : MobileGlassTheme.muted(0.35),
                ),
                tooltip: 'კონფიგურაცია',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Switch.adaptive(
                value: order.includeServiceFee,
                activeColor: MobileGlassTheme.primary,
                onChanged: _canEditFee ? (_) => _toggleServiceFee() : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Full-width "ჩეკის ბეჭდვა" button. Always visible (even when the order is
  /// not editable) so a manager can print a pre-bill on any open order. Disabled
  /// while a print is in flight so rapid taps can't fire repeated prints.
  Widget _buildPrintCheckBar() => OutlinedButton.icon(
    onPressed: _printingCheck ? null : _printOrderCheck,
    icon: const Icon(Icons.print_outlined, size: 18),
    label: Text(_printingCheck ? 'იბეჭდება…' : 'ჩეკის ბეჭდვა'),
  );

  Widget _buildActionBar() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: FilledButton.icon(
      onPressed: _editOrder,
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: const Text('შეკვეთის რედაქტირება'),
    ),
  );
}
