import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/apps/mobile_app/core/theme/manager_dashboard_theme.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_receipt_preview_dialog.dart';
import 'package:vynic/core/widgets/manager_toast.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

part 'tabs/mobile_admin_users_tab.dart';
part 'tabs/mobile_admin_sales_tab.dart';
part 'tabs/mobile_admin_report_tab.dart';
part 'tabs/mobile_admin_audit_tab.dart';
part 'tabs/mobile_admin_settings_tab.dart';
part 'shared/mobile_admin_shared_widgets.dart';

/// Manager console (მართვა) — flat POS-style layout for mobile.
class MobileAdminScreen extends StatefulWidget {
  final User user;
  final VoidCallback onLogout;

  const MobileAdminScreen({super.key, required this.user, required this.onLogout});

  @override
  State<MobileAdminScreen> createState() => _MobileAdminScreenState();

  static Future<void> viewCheckPdf(BuildContext context, int orderId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(color: AdminTheme.primary),
      ),
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

  static const _tabDefs = <({String label, IconData icon})>[
    (label: 'ანგარიში', icon: Icons.analytics_outlined),
    (label: 'გაყიდვები', icon: Icons.receipt_long_outlined),
    (label: 'აუდიტი', icon: Icons.fact_check_outlined),
    (label: 'გუნდი', icon: Icons.people_outline),
    (label: 'პარამეტრები', icon: Icons.settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabDefs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel =
        widget.user.roleLabelKa;

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
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
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '$roleLabel · ${widget.user.username}',
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
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AdminTheme.border, width: 1),
                ),
              ),
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                indicatorColor: AdminTheme.primary,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
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
                  for (final t in _tabDefs)
                    Tab(
                      height: 48,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(t.icon, size: 18),
                          SizedBox(width: 6),
                          Text(t.label),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _ReportTab(),
                  _SalesTab(),
                  _AuditTab(),
                  _UsersTab(currentUser: widget.user),
                  _SettingsTab(user: widget.user, onLogout: widget.onLogout),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
