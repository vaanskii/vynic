import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/api_config.dart';
import 'package:vynic/core/services/mobile_api_service.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_receipt_preview_dialog.dart';

part 'tabs/mobile_admin_users_tab.dart';
part 'tabs/mobile_admin_sales_tab.dart';
part 'tabs/mobile_admin_report_tab.dart';
part 'tabs/mobile_admin_audit_tab.dart';
part 'tabs/mobile_admin_settings_tab.dart';
part 'shared/mobile_admin_shared_widgets.dart';

/// Mobile admin panel with 5 tabs:
///   Users · Sales · Report · Audit · Settings
class MobileAdminScreen extends StatefulWidget {
  final User user;
  const MobileAdminScreen({super.key, required this.user});

  static const _accent = Color(0xFF2563EB);

  @override
  State<MobileAdminScreen> createState() => _MobileAdminScreenState();

  static Future<void> viewCheckPdf(BuildContext context, int orderId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ქვითრის გენერაცია ვერ მოხერხდა')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('შეცდომა: $e')),
        );
      }
    }
  }
}

class _MobileAdminScreenState extends State<MobileAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 80,
        title: const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'ადმინ პანელი',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          labelColor: MobileAdminScreen._accent,
          unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: MobileAdminScreen._accent,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'მომხ.'),
            Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'გაყიდვები'),
            Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: 'ანგარიში'),
            Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'აუდიტი'),
            Tab(icon: Icon(Icons.settings_rounded, size: 18), text: 'პარამ.'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _UsersTab(currentUser: widget.user),
          _SalesTab(),
          _ReportTab(),
          _AuditTab(),
          _SettingsTab(user: widget.user),
        ],
      ),
    );
  }
}
