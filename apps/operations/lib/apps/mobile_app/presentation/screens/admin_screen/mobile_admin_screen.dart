import '../../widgets/manager_design_components.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_modal.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/core/models/sale_visibility.dart';
import '../../widgets/venue_profile_card.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:vynic/core/models/inventory_decimal.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/consumption_history_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/inventory_movement_value.dart';
import '../stock_movement_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/audit/close_event_presentation.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/global_audit_entry.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_receipt_preview_dialog.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

part 'tabs/mobile_admin_users_tab.dart';
part 'tabs/mobile_admin_sales_tab.dart';
part 'tabs/mobile_admin_report_tab.dart';
part 'tabs/mobile_admin_audit_tab.dart';
part 'tabs/mobile_admin_activity_tab.dart';
part 'tabs/mobile_admin_inventory_tab.dart';
part 'tabs/mobile_admin_receiving.dart';
part 'tabs/mobile_admin_procurement.dart';
part 'tabs/mobile_admin_payables.dart';
part 'tabs/mobile_admin_recipes.dart';
part 'tabs/mobile_admin_settings_tab.dart';
part 'shared/mobile_admin_shared_widgets.dart';

/// Manager workspace with adaptive, bounded report and administration surfaces.
class MobileAdminScreen extends StatefulWidget {
  final User user;
  final VoidCallback onLogout;

  const MobileAdminScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  static const adminTabs = <({String label, IconData icon})>[
    (label: 'გუნდი', icon: Icons.people_outline),
    (label: 'ანგარიშები', icon: Icons.analytics_outlined),
    (label: 'აუდიტი', icon: Icons.fact_check_outlined),
    (label: 'პარამეტრები', icon: Icons.settings_outlined),
  ];

  @override
  State<MobileAdminScreen> createState() => _MobileAdminScreenState();

  static Future<void> viewCheckPdf(BuildContext context, int orderId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: AdminTheme.primary)),
    );

    try {
      final order = await MobileApiService.getOrder(orderId);
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

      if (context.mounted) {
        Navigator.of(context).pop();
        if (pngBytes != null) {
          MobileReceiptPreviewDialog.show(
            context,
            pngBytes,
            title: 'ქვითარი #${order.orderId}',
          );
        } else {
          _adminToast(context, 'ქვითრის გენერაცია ვერ მოხერხდა', error: true);
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _adminToast(context, 'შეცდომა: $e', error: true);
      }
    }
  }
}

class _MobileAdminScreenState extends State<MobileAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _activeTab = 0;
  final _visibleTabs = MobileAdminScreen.adminTabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _visibleTabs.length, vsync: this);
    _tabs.addListener(() {
      if (_activeTab != _tabs.index) setState(() => _activeTab = _tabs.index);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = widget.user.roleLabelKa;

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1424),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    MediaQuery.sizeOf(context).width < 700 ? 20 : 32,
                    20,
                    MediaQuery.sizeOf(context).width < 700 ? 20 : 32,
                    0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'მართვა',
                              style: TextStyle(
                                color: AdminTheme.text,
                                fontSize: MediaQuery.sizeOf(context).width < 700
                                    ? 25
                                    : 30,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'გუნდი, ანგარიშები და პარამეტრები · $roleLabel',
                              style: TextStyle(
                                color: AdminTheme.textDim,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _AdminConnectionDot(size: 12),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: MediaQuery.sizeOf(context).width < 700
                        ? 20
                        : 32,
                  ),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                    indicator: BoxDecoration(
                      color: AdminTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: AdminTheme.text,
                    unselectedLabelColor: AdminTheme.textDim,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: [
                      for (final t in _visibleTabs)
                        Tab(
                          key: ValueKey('manager-top-tab-${t.label}'),
                          height: 44,
                          text: t.label,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      for (final entry in <Widget>[
                        _UsersTab(currentUser: widget.user),
                        const _ManagerReportsDirectory(),
                        if (ManagerEntitlements.has(FeatureKeys.advancedAudit))
                          _ActivityTab(
                            onOpenOperationalAudit: () => showDialog<void>(
                              context: context,
                              builder: (_) => ManagerPageDialog(
                                title: 'ოპერაციული აუდიტი',
                                child: _AuditTab(),
                              ),
                            ),
                          )
                        else
                          _AuditTab(),
                        _SettingsTab(
                          user: widget.user,
                          onLogout: widget.onLogout,
                        ),
                      ].indexed)
                        AdminTabViewport(
                          active: _activeTab == entry.$1,
                          child: entry.$2,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Preserve loaded tab state while returning every vertical viewport to its start.
class AdminTabViewport extends StatefulWidget {
  const AdminTabViewport({
    super.key,
    required this.active,
    required this.child,
  });
  final bool active;
  final Widget child;
  @override
  State<AdminTabViewport> createState() => _AdminTabViewportState();
}

class _AdminTabViewportState extends State<AdminTabViewport> {
  @override
  void didUpdateWidget(AdminTabViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.active) return;
        void reset(Element element) {
          if (element is StatefulElement && element.state is ScrollableState) {
            final position = (element.state as ScrollableState).position;
            if (axisDirectionToAxis(position.axisDirection) == Axis.vertical &&
                position.hasContentDimensions)
              position.jumpTo(position.minScrollExtent);
          }
          element.visitChildren(reset);
        }

        context.visitChildElements(reset);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The reference directory opens existing reports in the shared detail frame.
class _ManagerReportsDirectory extends StatelessWidget {
  const _ManagerReportsDirectory();
  @override
  Widget build(BuildContext context) => ListView(
    padding: _adminScrollPadding(context),
    children: [
      ManagerPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ManagerSectionHeading('ანგარიშები და გაყიდვები'),
            for (final entry in <(String, Widget)>[
              ('დღის ანგარიში', _ReportTab()),
              ('თვიური გაყიდვები', _SalesTab()),
              (
                'პროდუქტების შედეგები',
                _ReportTab(focus: _ReportFocus.products),
              ),
              (
                'თანამშრომლების შედეგები',
                _ReportTab(focus: _ReportFocus.staff),
              ),
            ])
              ManagerDetailLink(
                entry.$1,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      ManagerPageDialog(title: entry.$1, child: entry.$2),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
