import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_menu_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_packages_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_close_day_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_sales_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_sales_report_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_audit_log_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_error_log_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_settings_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_reservations_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_staff_section.dart';
import 'package:vynic/core/utils/payment_utils.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/screens/login_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/core/services/monthly_report_service.dart';
import 'package:vynic/core/services/manager_sync_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.user});

  final User user;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String _selectedSection = 'staff'; // Default section

  static const Color _surfaceColor = Color(0xFFF4F6FF);

  final TextEditingController _kitchenPrinterController =
      TextEditingController();
  final TextEditingController _receiptPrinterController =
      TextEditingController();
  final TextEditingController _printerPortController = TextEditingController();

  // Multiple printers support
  late List<Map<String, dynamic>> _printersList = [];
  final List<TextEditingController> _printerNameControllers = [];
  final List<TextEditingController> _printerIpControllers = [];
  final List<TextEditingController> _printerPortControllers = [];

  String _normalizePrinterRole(dynamic rawRole, int index) {
    final role = (rawRole as String? ?? '').trim().toLowerCase();
    if (role == 'kitchen' ||
        role == 'receipt' ||
        role == 'both' ||
        role == 'none') {
      return role;
    }
    if (index == 0) {
      return 'kitchen';
    }
    if (index == 1) {
      return 'receipt';
    }
    return 'none';
  }

  String _getPrinterRoleAt(int index) {
    if (index < 0 || index >= _printersList.length) {
      return 'none';
    }
    return _normalizePrinterRole(_printersList[index]['role'], index);
  }

  void _setPrinterRoleAt(int index, String role) {
    if (index < 0 || index >= _printersList.length) {
      return;
    }
    setState(() {
      _printersList[index]['role'] = _normalizePrinterRole(role, index);
    });
  }

  void _rebuildPrinterControllers() {
    // Clear existing controllers
    for (final controller in _printerNameControllers) {
      controller.dispose();
    }
    _printerNameControllers.clear();
    for (final controller in _printerIpControllers) {
      controller.dispose();
    }
    _printerIpControllers.clear();
    for (final controller in _printerPortControllers) {
      controller.dispose();
    }
    _printerPortControllers.clear();

    // Create new controllers for each printer
    for (int i = 0; i < _printersList.length; i++) {
      final printer = _printersList[i];
      printer['role'] = _normalizePrinterRole(printer['role'], i);
      final nameController = TextEditingController(
        text: (printer['name'] as String?)?.trim().isNotEmpty == true
            ? (printer['name'] as String).trim()
            : 'პრინტერი ${i + 1}',
      );
      final ipController = TextEditingController(
        text: printer['ip'] as String? ?? '',
      );
      final portController = TextEditingController(
        text: (printer['port'] as int? ?? 9100).toString(),
      );
      _printerNameControllers.add(nameController);
      _printerIpControllers.add(ipController);
      _printerPortControllers.add(portController);
    }
  }

  void _addPrinter() {
    setState(() {
      _printersList.add({
        'name': 'პრინტერი ${_printersList.length + 1}',
        'ip': '',
        'port': 9100,
        'role': _printersList.isEmpty
            ? 'kitchen'
            : (_printersList.length == 1 ? 'receipt' : 'none'),
      });
      _rebuildPrinterControllers();
    });
  }

  void _removePrinter(int index) {
    if (index < 0 || index >= _printersList.length) return;
    setState(() {
      _printersList.removeAt(index);
      _rebuildPrinterControllers();
    });
  }

  final TextEditingController _serviceFeeController = TextEditingController();
  final TextEditingController _currentCancellationPasswordController =
      TextEditingController();
  final TextEditingController _newCancellationPasswordController =
      TextEditingController();
  final TextEditingController _confirmCancellationPasswordController =
      TextEditingController();
  final TextEditingController _cancellationPasswordHintController =
      TextEditingController();
  final TextEditingController _monthlyReportLeaseController =
      TextEditingController();
  final TextEditingController _monthlyReportStaffDailyController =
      TextEditingController();
  final TextEditingController _monthlyReportManualSalesController =
      TextEditingController();

  bool _serviceFeeEnabledByDefault = false;
  double _serviceFeePercent = 10.0;
  String _defaultLanguageSetting = 'ka';
  String? _lastBackupPath;
  String? _lastRestorePath;
  bool _isCancellationPasswordSet = false;
  bool _isSavingCancellationPassword = false;
  DateTime? _cancellationPasswordUpdatedAt;
  String _lastSavedCancellationHint = '';
  bool _restrictTableCloseToOwner = false;
  bool _isSavingTableOwnershipSettings = false;

  late int _selectedSalesYear;
  late int _selectedSalesMonth;
  late int _selectedAuditYear;
  late int _selectedAuditMonth;

  bool _isSavingPrinterSettings = false;
  bool _isTestingPrinters = false;
  bool _isSavingServiceFee = false;
  bool _isSavingLocalization = false;
  bool _isCreatingBackup = false;
  bool _isRestoringBackup = false;
  double _monthlyReportProfitRatio = 0.5;
  bool _isSavingMonthlyReportConfig = false;
  bool _isGeneratingMonthlyReport = false;
  bool _isGeneratingFullReport = false;
  DateTime _selectedMonthlyReportMonth = DateTime.now();
  int _monthlyReportStartDay = 1;
  int _monthlyReportEndDay = 1;
  List<DateTime> _monthlyReportMonthOptions = <DateTime>[];
  MonthlyReportSummary? _monthlyReportPreview;
  String? _monthlyReportInputError;
  DateTime _fullReportStartMonth = DateTime.now();
  DateTime _fullReportEndMonth = DateTime.now();
  List<DateTime> _fullReportMonthOptions = <DateTime>[];
  List<MonthlyReportSummary> _fullReportPreviewMonths = <MonthlyReportSummary>[];
  double _fullReportTotalSalesAllTime = 0.0;
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'ka_GE',
    symbol: '₾',
    decimalDigits: 2,
  );

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  late bool _isSidebarExpanded;

  /// Supervisor: only პერსონალი (waiters) + დღის დახურვა.
  bool get _isLimitedAdmin => widget.user.isSupervisor;

  static const _limitedAdminSections = {
    'staff',
    'waiters',
    'users',
    'closeday',
    'reservations',
  };

  @override
  void initState() {
    super.initState();
    _isSidebarExpanded = !_isMobile;
    if (_isLimitedAdmin) {
      _selectedSection = 'staff';
    }
    final currentBusinessDate = DatabaseService.getCurrentDate();
    _selectedSalesYear = currentBusinessDate.year;
    _selectedSalesMonth = currentBusinessDate.month;
    _selectedAuditYear = currentBusinessDate.year;
    _selectedAuditMonth = currentBusinessDate.month;
    _initializeSettingsState();
  }

  @override
  void dispose() {
    _kitchenPrinterController.dispose();
    _receiptPrinterController.dispose();
    _printerPortController.dispose();
    _serviceFeeController.dispose();
    for (final controller in _printerNameControllers) {
      controller.dispose();
    }
    for (final controller in _printerIpControllers) {
      controller.dispose();
    }
    for (final controller in _printerPortControllers) {
      controller.dispose();
    }
    _currentCancellationPasswordController.dispose();
    _newCancellationPasswordController.dispose();
    _confirmCancellationPasswordController.dispose();
    _cancellationPasswordHintController.dispose();
    _monthlyReportLeaseController.dispose();
    _monthlyReportStaffDailyController.dispose();
    _monthlyReportManualSalesController.dispose();
    super.dispose();
  }

  void _initializeSettingsState() {
    final currentBusinessDate = DatabaseService.getCurrentDate();
    _kitchenPrinterController.text = DatabaseService.getKitchenPrinterIp();
    _receiptPrinterController.text = DatabaseService.getReceiptPrinterIp();
    _printerPortController.text = DatabaseService.getPrinterPort().toString();

    // Initialize multiple printers list
    _printersList = DatabaseService.getPrintersList();
    if (_printersList.isEmpty) {
      // If no printers in new format, create from old format
      final kitchenIp = DatabaseService.getKitchenPrinterIp();
      final receiptIp = DatabaseService.getReceiptPrinterIp();
      final port = DatabaseService.getPrinterPort();

      if (kitchenIp.isNotEmpty) {
        _printersList.add({
          'name': 'სამზარეულოს პრინტერი',
          'ip': kitchenIp,
          'port': port,
          'role': 'kitchen',
        });
      }
      if (receiptIp.isNotEmpty) {
        _printersList.add({
          'name': 'ჩეკის პრინტერი',
          'ip': receiptIp,
          'port': port,
          'role': 'receipt',
        });
      }
    }
    _rebuildPrinterControllers();

    _serviceFeePercent = DatabaseService.getServiceFeePercentage();
    _serviceFeeEnabledByDefault =
        DatabaseService.isServiceFeeEnabledByDefault();
    _serviceFeeController.text = _formatServiceFeeField(_serviceFeePercent);

    _defaultLanguageSetting = DatabaseService.getDefaultLanguage();
    _isCancellationPasswordSet = DatabaseService.hasDestructiveActionPassword();
    _cancellationPasswordUpdatedAt =
        DatabaseService.getDestructiveActionPasswordUpdatedAt();
    _restrictTableCloseToOwner =
        DatabaseService.isTableCloseRestrictedToOwner();
    _lastSavedCancellationHint =
        DatabaseService.getDestructiveActionPasswordHint();
    _cancellationPasswordHintController.text = _lastSavedCancellationHint;

    final monthlyConfig = MonthlyReportService.getConfig();
    _monthlyReportLeaseController.text = _formatMoneyField(
      monthlyConfig.leaseCost,
    );
    _monthlyReportStaffDailyController.text = _formatMoneyField(
      monthlyConfig.staffDailyCost,
    );
    _monthlyReportProfitRatio = monthlyConfig.foodProfitRatio.clamp(0.0, 1.0);

    _selectedMonthlyReportMonth = DateTime(
      currentBusinessDate.year,
      currentBusinessDate.month,
    );
    final daysInSelectedMonth = _getDaysInMonth(_selectedMonthlyReportMonth);
    _monthlyReportStartDay = 1;
    _monthlyReportEndDay = _maxReportEndDayForMonth(
      _selectedMonthlyReportMonth,
      daysInSelectedMonth,
    );
    _monthlyReportMonthOptions = _buildRecentMonths(
      _selectedMonthlyReportMonth,
      12,
    );
    _syncMonthlyManualSalesField();
    _refreshMonthlyReportPreview();
    _initializeFullReportState();
  }

  void _initializeFullReportState() {
    // Build month options from sales history + manual adjustments.
    final months = <DateTime>{};
    for (final sale in DatabaseService.getAllSales()) {
      final closedAtRaw = sale['closedAt'] as String?;
      final dateRaw = sale['date'] as String?;
      final dt = closedAtRaw != null
          ? DateTime.tryParse(closedAtRaw)
          : (dateRaw != null ? DateTime.tryParse('${dateRaw}T00:00:00') : null);
      if (dt != null) {
        months.add(DateTime(dt.year, dt.month));
      }
    }
    // Also include months with manual sales even if there are no sales.
    for (var y = DateTime.now().year - 3; y <= DateTime.now().year + 1; y++) {
      for (var m = 1; m <= 12; m++) {
        final manual = DatabaseService.getMonthlyReportManualSalesForMonth(y, m);
        final leaseOverride =
            DatabaseService.getMonthlyReportLeaseCostOverrideForMonth(y, m);
        final staffOverride =
            DatabaseService.getMonthlyReportStaffDailyCostOverrideForMonth(y, m);
        if (manual > 0 || leaseOverride != null || staffOverride != null) {
          months.add(DateTime(y, m));
        }
      }
    }
    final list = months.toList()..sort((a, b) => a.compareTo(b));
    final nowMonth = DateTime(DateTime.now().year, DateTime.now().month);
    if (!list.any((m) => m.year == nowMonth.year && m.month == nowMonth.month)) {
      list.add(nowMonth);
      list.sort((a, b) => a.compareTo(b));
    }
    _fullReportMonthOptions = list.isEmpty ? [DateTime.now()] : list;
    _fullReportStartMonth = _fullReportMonthOptions.first;
    _fullReportEndMonth = _fullReportMonthOptions.last;
    _refreshFullReportPreview();
  }

  List<DateTime> _monthsBetween(DateTime start, DateTime end) {
    final a = DateTime(start.year, start.month);
    final b = DateTime(end.year, end.month);
    if (a.isAfter(b)) return _monthsBetween(b, a);
    final months = <DateTime>[];
    var cur = a;
    while (!cur.isAfter(b)) {
      months.add(cur);
      cur = DateTime(cur.year, cur.month + 1);
    }
    return months;
  }

  DateTime _monthPeriodStart(DateTime month) => DateTime(month.year, month.month, 1);

  DateTime _monthPeriodEnd(DateTime month) {
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final now = DateTime.now();
    if (month.year == now.year && month.month == now.month) {
      final today = DateTime(now.year, now.month, now.day);
      if (today.isBefore(monthEnd)) return today;
    }
    return monthEnd;
  }

  void _refreshFullReportPreview() {
    final config = _tryBuildMonthlyReportConfig();
    if (config == null) {
      _fullReportPreviewMonths = <MonthlyReportSummary>[];
      _fullReportTotalSalesAllTime = 0.0;
      return;
    }
    final rangeMonths = _monthsBetween(_fullReportStartMonth, _fullReportEndMonth);
    final previews = <MonthlyReportSummary>[];
    double totalAll = 0;
    for (final m in rangeMonths) {
      final manual = DatabaseService.getMonthlyReportManualSalesForMonth(m.year, m.month);
      final leaseOverride =
          DatabaseService.getMonthlyReportLeaseCostOverrideForMonth(m.year, m.month);
      final staffOverride =
          DatabaseService.getMonthlyReportStaffDailyCostOverrideForMonth(m.year, m.month);
      final monthConfig = config.copyWith(
        leaseCost: leaseOverride ?? config.leaseCost,
        staffDailyCost: staffOverride ?? config.staffDailyCost,
      );
      final summary = MonthlyReportService.calculateSummary(
        year: m.year,
        month: m.month,
        overrideConfig: monthConfig,
        periodStart: _monthPeriodStart(m),
        periodEnd: _monthPeriodEnd(m),
        manualSalesAdjustment: manual,
      );
      if (summary.totalSales <= 0) continue; // hide 0 months
      previews.add(summary);
      totalAll += summary.totalSales;
    }
    _fullReportPreviewMonths = previews;
    _fullReportTotalSalesAllTime = double.parse(totalAll.toStringAsFixed(2));
    if (mounted) setState(() {});
  }

  Future<Map<String, Map<String, double>>?> _promptManualSalesForMonths(
    List<DateTime> months,
    MonthlyReportConfig config,
  ) async {
    final manualControllers = <String, TextEditingController>{};
    final leaseControllers = <String, TextEditingController>{};
    final staffControllers = <String, TextEditingController>{};
    for (final m in months) {
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      final existing = DatabaseService.getMonthlyReportManualSalesForMonth(m.year, m.month);
      final leaseOverride =
          DatabaseService.getMonthlyReportLeaseCostOverrideForMonth(m.year, m.month);
      final staffOverride =
          DatabaseService.getMonthlyReportStaffDailyCostOverrideForMonth(m.year, m.month);
      manualControllers[key] = TextEditingController(
        text: _formatMoneyField(existing),
      );
      leaseControllers[key] = TextEditingController(
        text: _formatMoneyField(leaseOverride ?? config.leaseCost),
      );
      staffControllers[key] = TextEditingController(
        text: _formatMoneyField(staffOverride ?? config.staffDailyCost),
      );
    }
    final result = await showDialog<Map<String, Map<String, double>>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('თვეების კორექცია'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...months.map((m) {
                        final key =
                            '${m.year}-${m.month.toString().padLeft(2, '0')}';
                        final manual =
                            _tryParseMoney(manualControllers[key]?.text ?? '') ?? 0.0;
                        final lease =
                            _tryParseMoney(leaseControllers[key]?.text ?? '') ??
                                config.leaseCost;
                        final staffDaily =
                            _tryParseMoney(staffControllers[key]?.text ?? '') ??
                                config.staffDailyCost;
                        final monthConfig = config.copyWith(
                          leaseCost: lease,
                          staffDailyCost: staffDaily,
                        );
                        final summary = MonthlyReportService.calculateSummary(
                          year: m.year,
                          month: m.month,
                          overrideConfig: monthConfig,
                          periodStart: _monthPeriodStart(m),
                          periodEnd: _monthPeriodEnd(m),
                          manualSalesAdjustment: manual,
                        );
                        final isProfit = summary.netProfit >= 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: manualControllers[key],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setLocalState(() {}),
                                decoration: InputDecoration(
                                  labelText:
                                      '${_getGeorgianMonthName(m.month)} ${m.year} (Cash-ში დაემატება)',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: leaseControllers[key],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      onChanged: (_) => setLocalState(() {}),
                                      decoration: const InputDecoration(
                                        labelText: 'ქირის ხარჯი',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: staffControllers[key],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      onChanged: (_) => setLocalState(() {}),
                                      decoration: const InputDecoration(
                                        labelText: 'თანამშრომლების ხარჯი',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${isProfit ? 'წმინდა მოგება' : 'წმინდა ზარალი'}: ${_currencyFormatter.format(summary.netProfit)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: isProfit
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFC62828),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('გაუქმება'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final manualMap = <String, double>{};
                    final leaseMap = <String, double>{};
                    final staffMap = <String, double>{};
                    for (final m in months) {
                      final key =
                          '${m.year}-${m.month.toString().padLeft(2, '0')}';
                      manualMap[key] =
                          _tryParseMoney(manualControllers[key]?.text ?? '') ?? 0.0;
                      leaseMap[key] =
                          _tryParseMoney(leaseControllers[key]?.text ?? '') ??
                              config.leaseCost;
                      staffMap[key] =
                          _tryParseMoney(staffControllers[key]?.text ?? '') ??
                              config.staffDailyCost;
                    }
                    Navigator.pop(ctx, {
                      'manual': manualMap,
                      'lease': leaseMap,
                      'staff': staffMap,
                    });
                  },
                  child: const Text('შენახვა'),
                ),
              ],
            );
          },
        );
      },
    );
    for (final c in manualControllers.values) {
      c.dispose();
    }
    for (final c in leaseControllers.values) {
      c.dispose();
    }
    for (final c in staffControllers.values) {
      c.dispose();
    }
    return result;
  }

  Future<void> _generateFullReportXlsx() async {
    if (_isGeneratingFullReport) return;
    final config = _tryBuildMonthlyReportConfig();
    if (config == null) {
      unawaited(showPosToast(
        context: context,
        message: 'ჯერ შეავსეთ თვიური ანგარიშის კონფიგურაცია სწორად.',
        style: PosToastStyle.error,
      ));
      return;
    }
    final rangeMonths = _monthsBetween(_fullReportStartMonth, _fullReportEndMonth);
    if (mounted) {
      setState(() => _isGeneratingFullReport = true);
    }
    try {
      final payload = await _promptManualSalesForMonths(rangeMonths, config);
      if (payload == null) return;
      final manualMap = payload['manual'] ?? <String, double>{};
      final leaseMap = payload['lease'] ?? <String, double>{};
      final staffMap = payload['staff'] ?? <String, double>{};

      // Persist manual per month.
      for (final m in rangeMonths) {
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        await DatabaseService.setMonthlyReportManualSalesForMonth(
          m.year,
          m.month,
          manualMap[key] ?? 0.0,
        );
        await DatabaseService.setMonthlyReportLeaseCostOverrideForMonth(
          m.year,
          m.month,
          leaseMap[key],
        );
        await DatabaseService.setMonthlyReportStaffDailyCostOverrideForMonth(
          m.year,
          m.month,
          staffMap[key],
        );
      }

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'შეინახეთ სრული ანგარიში (XLSX)',
        fileName: 'full_report_${_fullReportStartMonth.year}_${_fullReportStartMonth.month.toString().padLeft(2, '0')}_to_${_fullReportEndMonth.year}_${_fullReportEndMonth.month.toString().padLeft(2, '0')}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (outputPath == null) return;

      final manualByMonth = <String, double>{};
      final leaseByMonth = <String, double>{};
      final staffByMonth = <String, double>{};
      final periodEndByMonth = <String, DateTime>{};
      for (final m in rangeMonths) {
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        manualByMonth[key] = DatabaseService.getMonthlyReportManualSalesForMonth(
          m.year,
          m.month,
        );
        leaseByMonth[key] =
            DatabaseService.getMonthlyReportLeaseCostOverrideForMonth(
              m.year,
              m.month,
            ) ??
            config.leaseCost;
        staffByMonth[key] =
            DatabaseService.getMonthlyReportStaffDailyCostOverrideForMonth(
              m.year,
              m.month,
            ) ??
            config.staffDailyCost;
        periodEndByMonth[key] = _monthPeriodEnd(m);
      }
      final bytes = MonthlyReportService.buildFullReportXlsxBytes(
        months: rangeMonths,
        config: config,
        manualSalesByMonth: manualByMonth,
        leaseByMonth: leaseByMonth,
        staffDailyByMonth: staffByMonth,
        periodEndByMonth: periodEndByMonth,
      );
      await File(outputPath).writeAsBytes(bytes, flush: true);
      _refreshFullReportPreview();
      if (!mounted) return;
      unawaited(showPosToast(
        context: context,
        message: 'ფაილი წარმატებით შეინახა: $outputPath',
        style: PosToastStyle.success,
      ));
    } finally {
      if (mounted) {
        setState(() => _isGeneratingFullReport = false);
      }
    }
  }

  Future<void> _generateFullReportPdf() async {
    if (_isGeneratingFullReport) return;
    final config = _tryBuildMonthlyReportConfig();
    if (config == null) {
      unawaited(showPosToast(
        context: context,
        message: 'ჯერ შეავსეთ თვიური ანგარიშის კონფიგურაცია სწორად.',
        style: PosToastStyle.error,
      ));
      return;
    }
    final rangeMonths = _monthsBetween(_fullReportStartMonth, _fullReportEndMonth);
    if (mounted) {
      setState(() => _isGeneratingFullReport = true);
    }
    try {
      final payload = await _promptManualSalesForMonths(rangeMonths, config);
      if (payload == null) return;
      final manualMap = payload['manual'] ?? <String, double>{};
      final leaseMap = payload['lease'] ?? <String, double>{};
      final staffMap = payload['staff'] ?? <String, double>{};

      for (final m in rangeMonths) {
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        await DatabaseService.setMonthlyReportManualSalesForMonth(
          m.year,
          m.month,
          manualMap[key] ?? 0.0,
        );
        await DatabaseService.setMonthlyReportLeaseCostOverrideForMonth(
          m.year,
          m.month,
          leaseMap[key],
        );
        await DatabaseService.setMonthlyReportStaffDailyCostOverrideForMonth(
          m.year,
          m.month,
          staffMap[key],
        );
      }

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'შეინახეთ სრული ანგარიში (PDF)',
        fileName:
            'full_report_${_fullReportStartMonth.year}_${_fullReportStartMonth.month.toString().padLeft(2, '0')}_to_${_fullReportEndMonth.year}_${_fullReportEndMonth.month.toString().padLeft(2, '0')}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (outputPath == null) return;

      final manualByMonth = <String, double>{};
      final leaseByMonth = <String, double>{};
      final staffByMonth = <String, double>{};
      final periodEndByMonth = <String, DateTime>{};
      for (final m in rangeMonths) {
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        manualByMonth[key] = DatabaseService.getMonthlyReportManualSalesForMonth(
          m.year,
          m.month,
        );
        leaseByMonth[key] =
            DatabaseService.getMonthlyReportLeaseCostOverrideForMonth(
              m.year,
              m.month,
            ) ??
            config.leaseCost;
        staffByMonth[key] =
            DatabaseService.getMonthlyReportStaffDailyCostOverrideForMonth(
              m.year,
              m.month,
            ) ??
            config.staffDailyCost;
        periodEndByMonth[key] = _monthPeriodEnd(m);
      }

      final bytes = await MonthlyReportService.buildFullReportPdfBytes(
        months: rangeMonths,
        config: config,
        manualSalesByMonth: manualByMonth,
        leaseByMonth: leaseByMonth,
        staffDailyByMonth: staffByMonth,
        periodEndByMonth: periodEndByMonth,
      );
      await File(outputPath).writeAsBytes(bytes, flush: true);
      _refreshFullReportPreview();
      if (!mounted) return;
      unawaited(showPosToast(
        context: context,
        message: 'PDF ფაილი წარმატებით შეინახა: $outputPath',
        style: PosToastStyle.success,
      ));
    } finally {
      if (mounted) {
        setState(() => _isGeneratingFullReport = false);
      }
    }
  }

  void _syncMonthlyManualSalesField() {
    final month = _selectedMonthlyReportMonth;
    final amount = DatabaseService.getMonthlyReportManualSalesForMonth(
      month.year,
      month.month,
    );
    _monthlyReportManualSalesController.text = _formatMoneyField(amount);
  }

  String _formatRelativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inMinutes < 1) {
      return 'moments ago';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    }
    return '${difference.inDays} d ago';
  }

  String _formatServiceFeeField(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value < 1 ? value.toStringAsFixed(2) : value.toStringAsFixed(1);
  }

  String _formatMoneyField(double value) {
    return value.toStringAsFixed(2);
  }

  double? _tryParseMoney(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      return null;
    }
    return parsed;
  }

  int _getDaysInMonth(DateTime date) {
    final firstOfNextMonth = DateTime(date.year, date.month + 1, 1);
    return firstOfNextMonth.subtract(const Duration(days: 1)).day;
  }

  int _maxReportEndDayForMonth(DateTime month, int fallbackDaysInMonth) {
    final now = DateTime.now();
    final daysInMonth = _getDaysInMonth(month);
    if (month.year == now.year && month.month == now.month) {
      return now.day.clamp(1, daysInMonth).toInt();
    }
    return fallbackDaysInMonth.clamp(1, daysInMonth).toInt();
  }

  List<DateTime> _buildRecentMonths(DateTime anchor, int count) {
    final firstOfMonth = DateTime(anchor.year, anchor.month);
    return List<DateTime>.generate(
      count,
      (index) => DateTime(firstOfMonth.year, firstOfMonth.month - index),
    );
  }

  MonthlyReportConfig? _tryBuildMonthlyReportConfig() {
    final lease = _tryParseMoney(_monthlyReportLeaseController.text);
    final staff = _tryParseMoney(_monthlyReportStaffDailyController.text);
    if (lease == null || staff == null) {
      return null;
    }
    final ratio = _monthlyReportProfitRatio.clamp(0.0, 1.0);
    return MonthlyReportConfig(
      leaseCost: lease,
      staffDailyCost: staff,
      foodProfitRatio: ratio,
    );
  }

  void _refreshMonthlyReportPreview() {
    final config = _tryBuildMonthlyReportConfig();
    MonthlyReportSummary? summary;
    String? error;
    final selectedMonth = _selectedMonthlyReportMonth;
    final manualSales = _tryParseMoney(_monthlyReportManualSalesController.text);
    final daysInMonth = _getDaysInMonth(selectedMonth);
    final maxEndDay = _maxReportEndDayForMonth(selectedMonth, daysInMonth);
    final int startDay = _monthlyReportStartDay.clamp(1, daysInMonth).toInt();
    final int endDay = _monthlyReportEndDay
        .clamp(startDay, maxEndDay)
        .toInt();
    final periodStart = DateTime(
      selectedMonth.year,
      selectedMonth.month,
      startDay,
    );
    final periodEnd = DateTime(selectedMonth.year, selectedMonth.month, endDay);

    if (config == null) {
      error = 'გთხოვთ შეიყვანოთ მხოლოდ დადებითი რიცხვები ორივე ველში.';
    } else if (manualSales == null) {
      error = 'ხელით დამატებული გაყიდვების ველში მიუთითეთ სწორი რიცხვი.';
    } else {
      try {
        summary = MonthlyReportService.calculateSummary(
          year: selectedMonth.year,
          month: selectedMonth.month,
          overrideConfig: config,
          periodStart: periodStart,
          periodEnd: periodEnd,
          manualSalesAdjustment: manualSales,
        );
      } catch (_) {
        error = 'ანგარიშის გამოთვლა ვერ მოხერხდა. სცადეთ კვლავ.';
      }
    }

    if (!mounted) {
      _monthlyReportStartDay = startDay;
      _monthlyReportEndDay = endDay;
      _monthlyReportPreview = summary;
      _monthlyReportInputError = error;
      return;
    }

    setState(() {
      _monthlyReportStartDay = startDay;
      _monthlyReportEndDay = endDay;
      _monthlyReportPreview = summary;
      _monthlyReportInputError = error;
    });
  }

  Future<void> _saveMonthlyReportConfig() async {
    final config = _tryBuildMonthlyReportConfig();
    if (config == null) {
      _refreshMonthlyReportPreview();
      unawaited(
        showPosToast(
          context: context,
          message: 'გთხოვთ შეავსოთ ყველა ველი სწორი რიცხვებით.',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isSavingMonthlyReportConfig = true;
      });
    }

    try {
      await MonthlyReportService.updateConfig(
        leaseCost: config.leaseCost,
        staffDailyCost: config.staffDailyCost,
        foodProfitRatio: config.foodProfitRatio,
      );
      final selectedMonth = _selectedMonthlyReportMonth;
      final manualSales = _tryParseMoney(_monthlyReportManualSalesController.text) ?? 0.0;
      await DatabaseService.setMonthlyReportManualSalesForMonth(
        selectedMonth.year,
        selectedMonth.month,
        manualSales,
      );
      _monthlyReportLeaseController.text = _formatMoneyField(config.leaseCost);
      _monthlyReportStaffDailyController.text = _formatMoneyField(
        config.staffDailyCost,
      );
      _syncMonthlyManualSalesField();
      _refreshMonthlyReportPreview();

      if (!mounted) {
        return;
      }

      unawaited(
        showPosToast(
          context: context,
          message: 'კონფიგურაცია შენახულია.',
          style: PosToastStyle.success,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      unawaited(
        showPosToast(
          context: context,
          message: 'შენახვა ვერ მოხერხდა: $error',
          style: PosToastStyle.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingMonthlyReportConfig = false;
        });
      }
    }
  }

  Future<void> _generateMonthlyReportExcel() async {
    final config = _tryBuildMonthlyReportConfig();
    if (config == null) {
      _refreshMonthlyReportPreview();
      unawaited(
        showPosToast(
          context: context,
          message: 'გთხოვთ შეავსოთ ყველა ველი სწორი რიცხვებით.',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    final selectedMonth = _selectedMonthlyReportMonth;
    final manualSales = _tryParseMoney(_monthlyReportManualSalesController.text);
    if (manualSales == null) {
      unawaited(
        showPosToast(
          context: context,
          message: 'ხელით დამატებული გაყიდვების ველში მიუთითეთ სწორი რიცხვი.',
          style: PosToastStyle.error,
        ),
      );
      return;
    }
    final daysInMonth = _getDaysInMonth(selectedMonth);
    final maxEndDay = _maxReportEndDayForMonth(selectedMonth, daysInMonth);
    final int startDay = _monthlyReportStartDay.clamp(1, daysInMonth).toInt();
    final int endDay = _monthlyReportEndDay
        .clamp(startDay, maxEndDay)
        .toInt();
    final periodStart = DateTime(
      selectedMonth.year,
      selectedMonth.month,
      startDay,
    );
    final periodEnd = DateTime(selectedMonth.year, selectedMonth.month, endDay);

    if (mounted) {
      setState(() {
        _isGeneratingMonthlyReport = true;
      });
    }

    try {
      final defaultFileName =
          'monthly_full_report_${selectedMonth.year}_${selectedMonth.month.toString().padLeft(2, '0')}.xlsx';

      // Let the user pick where to save the CSV.
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'შეინახეთ თვიური ანგარიში (XLSX)',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputPath == null) return;

      final excelBytes = MonthlyReportService.buildExcelXlsxBytes(
        year: selectedMonth.year,
        month: selectedMonth.month,
        overrideConfig: config,
        periodStart: periodStart,
        periodEnd: periodEnd,
        manualSalesAdjustment: manualSales,
      );

      final outFile = File(outputPath);
      await outFile.writeAsBytes(excelBytes, flush: true);

      if (!mounted) {
        return;
      }

      unawaited(
        showPosToast(
          context: context,
          message: 'ფაილი წარმატებით შეინახა: ${outFile.path}',
          style: PosToastStyle.success,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      unawaited(
        showPosToast(
          context: context,
          message: 'Excel (XLSX) ფაილის შექმნა ვერ მოხერხდა: $error',
          style: PosToastStyle.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingMonthlyReport = false;
        });
      }
    }
  }

  Future<void> _generateMonthlyReportPdf() async {
    final config = _tryBuildMonthlyReportConfig();
    if (config == null) {
      _refreshMonthlyReportPreview();
      unawaited(
        showPosToast(
          context: context,
          message: 'გთხოვთ შეავსოთ ყველა ველი სწორი რიცხვებით.',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    final selectedMonth = _selectedMonthlyReportMonth;
    final manualSales = _tryParseMoney(_monthlyReportManualSalesController.text);
    if (manualSales == null) {
      unawaited(
        showPosToast(
          context: context,
          message: 'ხელით დამატებული გაყიდვების ველში მიუთითეთ სწორი რიცხვი.',
          style: PosToastStyle.error,
        ),
      );
      return;
    }
    final daysInMonth = _getDaysInMonth(selectedMonth);
    final maxEndDay = _maxReportEndDayForMonth(selectedMonth, daysInMonth);
    final int startDay = _monthlyReportStartDay.clamp(1, daysInMonth).toInt();
    final int endDay = _monthlyReportEndDay.clamp(startDay, maxEndDay).toInt();
    final periodStart = DateTime(selectedMonth.year, selectedMonth.month, startDay);
    final periodEnd = DateTime(selectedMonth.year, selectedMonth.month, endDay);

    if (mounted) {
      setState(() {
        _isGeneratingMonthlyReport = true;
      });
    }

    try {
      final defaultFileName =
          'monthly_full_report_${selectedMonth.year}_${selectedMonth.month.toString().padLeft(2, '0')}.pdf';
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'შეინახეთ თვიური ანგარიში (PDF)',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputPath == null) return;

      final pdfBytes = await MonthlyReportService.buildMonthlyPdfBytes(
        year: selectedMonth.year,
        month: selectedMonth.month,
        overrideConfig: config,
        periodStart: periodStart,
        periodEnd: periodEnd,
        manualSalesAdjustment: manualSales,
      );

      await File(outputPath).writeAsBytes(pdfBytes, flush: true);

      if (!mounted) {
        return;
      }

      unawaited(
        showPosToast(
          context: context,
          message: 'PDF ფაილი წარმატებით შეინახა: $outputPath',
          style: PosToastStyle.success,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      unawaited(
        showPosToast(
          context: context,
          message: 'PDF ფაილის შექმნა ვერ მოხერხდა: $error',
          style: PosToastStyle.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingMonthlyReport = false;
        });
      }
    }
  }

  String _formatDateNumeric(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  String _formatDateTimeDisplay(DateTime date) {
    final datePart = _formatDateNumeric(date);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$datePart $hour:$minute';
  }

  String _getGeorgianMonthName(int month) {
    const months = [
      'იანვარი',
      'თებერვალი',
      'მარტი',
      'აპრილი',
      'მაისი',
      'ივნისი',
      'ივლისი',
      'აგვისტო',
      'სექტემბერი',
      'ოქტომბერი',
      'ნოემბერი',
      'დეკემბერი',
    ];
    if (month < 1 || month > 12) {
      return 'უცნობი';
    }
    return months[month - 1];
  }

  void _changeSalesMonth(int delta) {
    final selected = DateTime(_selectedSalesYear, _selectedSalesMonth, 1);
    final updated = DateTime(selected.year, selected.month + delta, 1);
    final currentDate = DatabaseService.getCurrentDate();
    final currentMonth = DateTime(currentDate.year, currentDate.month, 1);
    if (delta > 0 && updated.isAfter(currentMonth)) {
      return;
    }

    setState(() {
      _selectedSalesYear = updated.year;
      _selectedSalesMonth = updated.month;
    });
  }

  void _setSelectedSalesMonth(DateTime month) {
    final sanitized = DateTime(month.year, month.month, 1);
    final currentDate = DatabaseService.getCurrentDate();
    final currentMonth = DateTime(currentDate.year, currentDate.month, 1);
    if (sanitized.isAfter(currentMonth)) {
      return;
    }

    setState(() {
      _selectedSalesYear = sanitized.year;
      _selectedSalesMonth = sanitized.month;
    });
  }

  void _changeAuditMonth(int delta) {
    final selected = DateTime(_selectedAuditYear, _selectedAuditMonth, 1);
    final updated = DateTime(selected.year, selected.month + delta, 1);
    final currentDate = DatabaseService.getCurrentDate();
    final currentMonth = DateTime(currentDate.year, currentDate.month, 1);
    if (delta > 0 && updated.isAfter(currentMonth)) {
      return;
    }

    setState(() {
      _selectedAuditYear = updated.year;
      _selectedAuditMonth = updated.month;
    });
  }

  void _setSelectedAuditMonth(DateTime month) {
    final sanitized = DateTime(month.year, month.month, 1);
    final currentDate = DatabaseService.getCurrentDate();
    final currentMonth = DateTime(currentDate.year, currentDate.month, 1);
    if (sanitized.isAfter(currentMonth)) {
      return;
    }

    setState(() {
      _selectedAuditYear = sanitized.year;
      _selectedAuditMonth = sanitized.month;
    });
  }

  String _getSectionTitle(String section) {
    switch (section) {
      case 'staff':
      case 'waiters':
      case 'users':
        return 'პერსონალი';
      case 'menu':
        return 'მენიუ';
      case 'packages':
        return 'პაკეტები';
      case 'reservations':
        return 'რეზერვაციები';
      case 'closeday':
        return 'დღის დახურვა';
      case 'sales':
        return 'გაყიდვები';
      case 'salesReport':
        return 'გაყიდვების რეპორტი';
      case 'audit':
        return 'აუდიტი';
      case 'errors':
        return 'შეცდომები';
      case 'settings':
        return 'პარამეტრები';
      default:
        return 'ადმინ პანელი';
    }
  }

  Widget _buildSidebar() {
    final mobileWidth = MediaQuery.of(context).size.width * 0.85;
    final width = _isMobile
        ? (_isSidebarExpanded ? mobileWidth : 0.0)
        : (_isSidebarExpanded ? 220.0 : 220.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: width,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: _isMobile ? mobileWidth : 220.0,
          child: Column(
            children: [
              _buildSidebarHeader(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(bottom: _isMobile ? 32 : 0),
                  children: _buildSidebarMenuItems(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSidebarMenuItems() {
    if (_isLimitedAdmin) {
      return [
        _buildMenuItem(
          icon: Icons.groups_rounded,
          title: 'პერსონალი',
          section: 'staff',
        ),
        _buildMenuItem(
          icon: Icons.event_available,
          title: 'რეზერვაციები',
          section: 'reservations',
        ),
        _buildMenuItem(
          icon: Icons.calendar_today,
          title: 'დღის დახურვა',
          section: 'closeday',
        ),
      ];
    }

    return [
      _buildMenuItem(
        icon: Icons.groups_rounded,
        title: 'პერსონალი',
        section: 'staff',
      ),
      _buildMenuItem(
        icon: Icons.restaurant_menu,
        title: 'მენიუ',
        section: 'menu',
      ),
      _buildMenuItem(
        icon: Icons.inventory_2,
        title: 'პაკეტები',
        section: 'packages',
      ),
      _buildMenuItem(
        icon: Icons.event_available,
        title: 'რეზერვაციები',
        section: 'reservations',
      ),
      if (!_isMobile)
        _buildMenuItem(
          icon: Icons.calendar_today,
          title: 'დღის დახურვა',
          section: 'closeday',
        ),
      _buildMenuItem(
        icon: Icons.history,
        title: 'გაყიდვები',
        section: 'sales',
      ),
      _buildMenuItem(
        icon: Icons.insights,
        title: 'გაყიდვების რეპორტი',
        section: 'salesReport',
      ),
      _buildMenuItem(
        icon: Icons.report_problem,
        title: 'აუდიტი',
        section: 'audit',
      ),
      if (!_isMobile)
        _buildMenuItem(
          icon: Icons.bug_report,
          title: 'შეცდომები',
          section: 'errors',
        ),
      _buildMenuItem(
        icon: Icons.settings,
        title: 'პარამეტრები',
        section: 'settings',
      ),
    ];
  }

  Widget _buildSidebarHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'მართვის ცენტრი',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String section,
  }) {
    final isSelected = _selectedSection == section;
    final iconColor = isSelected ? Colors.white : const Color(0xFFE2E8F0);
    final textStyle = TextStyle(
      color: iconColor,
      fontSize: 12,
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
    );

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: textStyle)),
        ],
      ),
    );

    content = Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 350),
      child: content,
    );

    return Semantics(
      button: true,
      label: title,
      selected: isSelected,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            _selectedSection = section;
            if (_isMobile) {
              _isSidebarExpanded = false;
            }
          });
        },
        child: content,
      ),
    );
  }

  Widget _buildSettingsSection() {
    return AdminSettingsSection(
      formatDateTimeDisplay: _formatDateTimeDisplay,
      formatRelativeTime: _formatRelativeTime,
      getGeorgianMonthName: _getGeorgianMonthName,
      getDaysInMonth: _getDaysInMonth,
      getPrintersList: () => _printersList,
      printerNameControllers: _printerNameControllers,
      printerIpControllers: _printerIpControllers,
      printerPortControllers: _printerPortControllers,
      onAddPrinter: _addPrinter,
      onRemovePrinter: _removePrinter,
      getPrinterRole: _getPrinterRoleAt,
      onPrinterRoleChanged: _setPrinterRoleAt,
      kitchenPrinterController: _kitchenPrinterController,
      receiptPrinterController: _receiptPrinterController,
      printerPortController: _printerPortController,
      serviceFeeController: _serviceFeeController,
      currentCancellationPasswordController:
          _currentCancellationPasswordController,
      newCancellationPasswordController: _newCancellationPasswordController,
      confirmCancellationPasswordController:
          _confirmCancellationPasswordController,
      cancellationPasswordHintController: _cancellationPasswordHintController,
      monthlyReportLeaseController: _monthlyReportLeaseController,
      monthlyReportStaffDailyController: _monthlyReportStaffDailyController,
      monthlyReportManualSalesController: _monthlyReportManualSalesController,
      serviceFeeEnabledByDefault: _serviceFeeEnabledByDefault,
      onServiceFeeEnabledByDefaultChanged: (value) {
        setState(() {
          _serviceFeeEnabledByDefault = value;
        });
      },
      serviceFeePercentDisplay:
          DatabaseService.getFormattedServiceFeePercentage(),
      isSavingPrinterSettings: _isSavingPrinterSettings,
      isTestingPrinters: _isTestingPrinters,
      isSavingServiceFee: _isSavingServiceFee,
      defaultLanguageSetting: _defaultLanguageSetting,
      onDefaultLanguageSettingChanged: (value) {
        setState(() {
          _defaultLanguageSetting = value;
        });
      },
      isSavingLocalization: _isSavingLocalization,
      lastBackupPath: _lastBackupPath,
      lastRestorePath: _lastRestorePath,
      isCreatingBackup: _isCreatingBackup,
      isRestoringBackup: _isRestoringBackup,
      isCancellationPasswordSet: _isCancellationPasswordSet,
      isSavingCancellationPassword: _isSavingCancellationPassword,
      cancellationPasswordUpdatedAt: _cancellationPasswordUpdatedAt,
      restrictTableCloseToOwner: _restrictTableCloseToOwner,
      onRestrictTableCloseToOwnerChanged: (value) {
        setState(() {
          _restrictTableCloseToOwner = value;
        });
      },
      isSavingTableOwnershipSettings: _isSavingTableOwnershipSettings,
      monthlyReportProfitRatio: _monthlyReportProfitRatio,
      onMonthlyReportProfitRatioChanged: (value) {
        setState(() {
          final normalized = value.clamp(0.0, 1.0);
          _monthlyReportProfitRatio = double.parse(
            normalized.toStringAsFixed(2),
          );
        });
        _refreshMonthlyReportPreview();
      },
      isSavingMonthlyReportConfig: _isSavingMonthlyReportConfig,
      isGeneratingMonthlyReport: _isGeneratingMonthlyReport,
      selectedMonthlyReportMonth: _selectedMonthlyReportMonth,
      onSelectedMonthlyReportMonthChanged: (value) {
        setState(() {
          final normalized = DateTime(value.year, value.month);
          final newDaysInMonth = _getDaysInMonth(normalized);
          final maxEndDay = _maxReportEndDayForMonth(normalized, newDaysInMonth);
          final int newStart = _monthlyReportStartDay
              .clamp(1, newDaysInMonth)
              .toInt();
          final int newEnd = _monthlyReportEndDay
              .clamp(newStart, maxEndDay)
              .toInt();
          _selectedMonthlyReportMonth = normalized;
          _monthlyReportStartDay = newStart;
          _monthlyReportEndDay = newEnd;
        });
        _syncMonthlyManualSalesField();
        _refreshMonthlyReportPreview();
      },
      monthlyReportStartDay: _monthlyReportStartDay,
      onMonthlyReportStartDayChanged: (value) {
        setState(() {
          _monthlyReportStartDay = value;
          if (_monthlyReportEndDay < value) {
            _monthlyReportEndDay = value;
          }
        });
        _refreshMonthlyReportPreview();
      },
      monthlyReportEndDay: _monthlyReportEndDay,
      onMonthlyReportEndDayChanged: (value) {
        setState(() {
          _monthlyReportEndDay = value;
          if (_monthlyReportStartDay > value) {
            _monthlyReportStartDay = value;
          }
        });
        _refreshMonthlyReportPreview();
      },
      monthlyReportMonthOptions: _monthlyReportMonthOptions,
      monthlyReportPreview: _monthlyReportPreview,
      monthlyReportInputError: _monthlyReportInputError,
      currencyFormatter: _currencyFormatter,
      fullReportStartMonth: _fullReportStartMonth,
      fullReportEndMonth: _fullReportEndMonth,
      fullReportMonthOptions: _fullReportMonthOptions,
      fullReportPreviewMonths: _fullReportPreviewMonths,
      fullReportTotalSalesAllTime: _fullReportTotalSalesAllTime,
      isGeneratingFullReport: _isGeneratingFullReport,
      onFullReportStartMonthChanged: (value) {
        setState(() {
          _fullReportStartMonth = DateTime(value.year, value.month);
          if (_fullReportStartMonth.isAfter(_fullReportEndMonth)) {
            _fullReportEndMonth = _fullReportStartMonth;
          }
        });
        _refreshFullReportPreview();
      },
      onFullReportEndMonthChanged: (value) {
        setState(() {
          _fullReportEndMonth = DateTime(value.year, value.month);
          if (_fullReportEndMonth.isBefore(_fullReportStartMonth)) {
            _fullReportStartMonth = _fullReportEndMonth;
          }
        });
        _refreshFullReportPreview();
      },
      onGenerateFullReportXlsx: _generateFullReportXlsx,
      onGenerateFullReportPdf: _generateFullReportPdf,
      onRefreshFullReportPreview: _refreshFullReportPreview,
      onRefreshMonthlyReportPreview: _refreshMonthlyReportPreview,
      onSaveMonthlyReportConfig: _saveMonthlyReportConfig,
      onGenerateMonthlyReportExcel: _generateMonthlyReportExcel,
      onGenerateMonthlyReportPdf: _generateMonthlyReportPdf,
      onSavePrinterSettings: _savePrinterSettings,
      onTestPrinterConnections: _testPrinterConnections,
      onScanPrinters: _scanPrintersOnLan,
      onSaveServiceFeeSettings: _saveServiceFeeSettings,
      onSaveCancellationPassword: _saveCancellationPassword,
      onSaveTableOwnershipSettings: _saveTableOwnershipSettings,
      onSaveLocalizationSettings: _saveLocalizationSettings,
      onCreateBackupFile: _createBackupFile,
      onRestoreBackupFromFile: _restoreBackupFromFile,
    );
  }

  VoidCallback? _buildSetBusinessDateToLastClosedAction() {
    final dates = DatabaseService.getOperatedBusinessDates();
    if (dates.isEmpty) {
      return null;
    }

    final current = DatabaseService.getCurrentDate();
    final currentOnly = DateTime(current.year, current.month, current.day);
    final lastClosed = dates.last;
    final lastClosedOnly = DateTime(
      lastClosed.year,
      lastClosed.month,
      lastClosed.day,
    );

    if (lastClosedOnly == currentOnly) {
      return null;
    }

    return () {
      unawaited(_confirmBusinessDateChange(lastClosed));
    };
  }

  Future<void> _savePrinterSettings() async {
    final kitchenIp = _kitchenPrinterController.text.trim();
    final receiptIp = _receiptPrinterController.text.trim();
    const port = 9100;

    if (kitchenIp.isNotEmpty && !_isValidIpv4(kitchenIp)) {
      unawaited(showErrorToast(context, 'Kitchen printer IP is invalid.'));
      return;
    }
    if (receiptIp.isNotEmpty && !_isValidIpv4(receiptIp)) {
      unawaited(showErrorToast(context, 'Receipt printer IP is invalid.'));
      return;
    }

    setState(() {
      _isSavingPrinterSettings = true;
    });

    try {
      await DatabaseService.savePrintersList(const <Map<String, dynamic>>[]);
      await DatabaseService.savePrinterConfiguration(
        kitchenIp: kitchenIp,
        receiptIp: receiptIp,
        port: port,
      );
      _printerPortController.text = '9100';
      await PrinterService.initialize(forceReconnect: true);

      if (!mounted) return;
      unawaited(
        showSuccessToast(context, 'Printer settings saved successfully.'),
      );
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Could not save printer settings: $e'));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPrinterSettings = false;
        });
      }
    }
  }

  Future<void> _testPrinterConnections() async {
    final kitchenIp = _kitchenPrinterController.text.trim();
    final receiptIp = _receiptPrinterController.text.trim();
    const port = 9100;

    if (kitchenIp.isNotEmpty && !_isValidIpv4(kitchenIp)) {
      unawaited(showErrorToast(context, 'Kitchen printer IP is invalid.'));
      return;
    }
    if (receiptIp.isNotEmpty && !_isValidIpv4(receiptIp)) {
      unawaited(showErrorToast(context, 'Receipt printer IP is invalid.'));
      return;
    }

    if (kitchenIp.isEmpty && receiptIp.isEmpty) {
      unawaited(
        showErrorToast(context, 'Configure at least one printer IP to test.'),
      );
      return;
    }

    setState(() {
      _isTestingPrinters = true;
    });

    try {
      final results = await PrinterService.testConnections(
        kitchenIp: kitchenIp,
        receiptIp: receiptIp,
        port: port,
      );

      if (!mounted) return;

      final kitchenConfigured = kitchenIp.isNotEmpty;
      final receiptConfigured = receiptIp.isNotEmpty;
      final kitchenOk = !kitchenConfigured || results['kitchen'] == true;
      final receiptOk = !receiptConfigured || results['receipt'] == true;

      final message = StringBuffer();
      message.write(
        kitchenConfigured
            ? (kitchenOk
                  ? 'Kitchen printer reachable ($kitchenIp:$port).'
                  : 'Kitchen printer unreachable ($kitchenIp:$port).')
            : 'Kitchen printer not configured.',
      );
      message.write(' ');
      message.write(
        receiptConfigured
            ? (receiptOk
                  ? 'Receipt printer reachable ($receiptIp:$port).'
                  : 'Receipt printer unreachable ($receiptIp:$port).')
            : 'Receipt printer not configured.',
      );

      final style = (kitchenOk && receiptOk)
          ? PosToastStyle.success
          : (kitchenConfigured || receiptConfigured)
          ? PosToastStyle.info
          : PosToastStyle.info;

      unawaited(
        showPosToast(
          context: context,
          message: message.toString(),
          style: style,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Connection test failed: $e'));
    } finally {
      if (mounted) {
        setState(() {
          _isTestingPrinters = false;
        });
      }
    }
  }

  Future<void> _scanPrintersOnLan() async {
    if (!mounted) {
      return;
    }
    unawaited(
      showPosToast(
        context: context,
        message: 'პრინტერების სკანირება გამორთულია. შეიყვანეთ IP ხელით.',
        style: PosToastStyle.info,
      ),
    );
  }

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      if (part.isEmpty) {
        return false;
      }
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return false;
      }
    }
    return true;
  }

  Future<void> _saveServiceFeeSettings() async {
    final rawValue = _serviceFeeController.text.trim().replaceAll(',', '.');
    final parsedPercent = double.tryParse(rawValue);

    if (parsedPercent == null || parsedPercent < 0 || parsedPercent > 100) {
      unawaited(
        showErrorToast(
          context,
          'Enter a valid service fee percentage between 0 and 100.',
        ),
      );
      return;
    }

    setState(() {
      _isSavingServiceFee = true;
    });

    try {
      await DatabaseService.updateServiceFeeSettings(
        percentage: parsedPercent,
        enabledByDefault: _serviceFeeEnabledByDefault,
      );
      _serviceFeePercent = parsedPercent;
      _serviceFeeController.text = _formatServiceFeeField(parsedPercent);

      if (!mounted) return;
      unawaited(
        showSuccessToast(
          context,
          'Service fee updated to ${_formatServiceFeeField(parsedPercent)}%.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Failed to update service fee: $e'));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingServiceFee = false;
        });
      }
    }
  }

  Future<void> _saveCancellationPassword() async {
    final newCode = _newCancellationPasswordController.text.trim();
    final confirmCode = _confirmCancellationPasswordController.text.trim();
    final currentCode = _currentCancellationPasswordController.text.trim();
    final hintText = _cancellationPasswordHintController.text.trim();
    final hintChanged = hintText != _lastSavedCancellationHint;
    final codePattern = RegExp(r'^\d{6}$');

    final wantsPasswordChange = newCode.isNotEmpty || confirmCode.isNotEmpty;

    if (!wantsPasswordChange && !hintChanged) {
      unawaited(
        showPosToast(
          context: context,
          message: 'Nothing to update yet. Adjust the password or hint.',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    if (wantsPasswordChange) {
      if (!codePattern.hasMatch(newCode) ||
          !codePattern.hasMatch(confirmCode)) {
        unawaited(
          showErrorToast(
            context,
            'Enter a 6-digit numeric code for the new password.',
          ),
        );
        return;
      }

      if (newCode != confirmCode) {
        unawaited(
          showErrorToast(
            context,
            'New password and confirmation do not match.',
          ),
        );
        return;
      }

      if (_isCancellationPasswordSet &&
          !DatabaseService.verifyDestructiveActionPassword(currentCode)) {
        unawaited(
          showErrorToast(
            context,
            'Current cancellation password is incorrect.',
          ),
        );
        return;
      }
    } else {
      // Hint-only update still requires verifying the current code
      if (!_isCancellationPasswordSet) {
        unawaited(
          showErrorToast(
            context,
            'Set a cancellation password before adding a hint.',
          ),
        );
        return;
      }

      if (currentCode.isEmpty ||
          !DatabaseService.verifyDestructiveActionPassword(currentCode)) {
        unawaited(
          showErrorToast(
            context,
            'Enter the current cancellation password to update the hint.',
          ),
        );
        return;
      }
    }

    final wasSet = _isCancellationPasswordSet;

    setState(() {
      _isSavingCancellationPassword = true;
    });

    try {
      if (wantsPasswordChange) {
        await DatabaseService.setDestructiveActionPassword(
          newCode,
          hint: hintText,
        );
        if (!mounted) {
          return;
        }

        setState(() {
          _isCancellationPasswordSet = true;
          _cancellationPasswordUpdatedAt =
              DatabaseService.getDestructiveActionPasswordUpdatedAt();
          _lastSavedCancellationHint = hintText;
          _currentCancellationPasswordController.clear();
          _newCancellationPasswordController.clear();
          _confirmCancellationPasswordController.clear();
        });

        unawaited(
          showSuccessToast(
            context,
            wasSet
                ? 'Cancellation password updated successfully.'
                : 'Cancellation password saved successfully.',
          ),
        );
      } else {
        await DatabaseService.setDestructiveActionPasswordHint(hintText);
        if (!mounted) {
          return;
        }

        setState(() {
          _cancellationPasswordUpdatedAt =
              DatabaseService.getDestructiveActionPasswordUpdatedAt();
          _lastSavedCancellationHint = hintText;
          _currentCancellationPasswordController.clear();
        });

        unawaited(
          showSuccessToast(context, 'Cancellation password hint updated.'),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      unawaited(
        showErrorToast(context, 'Unable to save cancellation password: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCancellationPassword = false;
        });
      }
    }
  }

  Future<void> _saveTableOwnershipSettings() async {
    setState(() {
      _isSavingTableOwnershipSettings = true;
    });

    try {
      await DatabaseService.setTableCloseRestrictedToOwner(
        _restrictTableCloseToOwner,
      );

      if (mounted) {
        await showSuccessToast(
          context,
          'მაგიდის დახურვის პარამეტრები შენახულია',
        );
      }
    } catch (error) {
      if (mounted) {
        await showErrorToast(context, 'შენახვა ვერ მოხერხდა: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingTableOwnershipSettings = false;
        });
      }
    }
  }

  Future<void> _saveLocalizationSettings() async {
    setState(() {
      _isSavingLocalization = true;
    });

    try {
      await DatabaseService.setDefaultLanguage(_defaultLanguageSetting);
      if (!mounted) return;
      unawaited(
        showSuccessToast(
          context,
          _defaultLanguageSetting == 'ka'
              ? 'Default language set to Georgian.'
              : 'Default language set to English.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      unawaited(
        showErrorToast(context, 'Unable to save language preference: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLocalization = false;
        });
      }
    }
  }

  Future<void> _restoreBackupFromFile() async {
    if (kIsWeb) {
      unawaited(
        showPosToast(
          context: context,
          message: 'Backup restore is not available on web builds.',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    if (_isRestoringBackup) {
      return;
    }

    FilePickerResult? pickerResult;
    try {
      pickerResult = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select VPOS backup JSON file',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
    } catch (e) {
      unawaited(showErrorToast(context, 'Could not open file picker: $e'));
      return;
    }

    if (pickerResult == null || pickerResult.files.isEmpty) {
      return;
    }

    final selected = pickerResult.files.single;
    String? resolvedPath = selected.path;
    File? tempFile;

    try {
      if ((resolvedPath == null || resolvedPath.isEmpty) &&
          selected.bytes == null) {
        unawaited(
          showErrorToast(
            context,
            'Backup file path missing. Please try again.',
          ),
        );
        return;
      }

      if (resolvedPath == null || resolvedPath.isEmpty) {
        final tempDir = await Directory.systemTemp.createTemp('vpos_restore_');
        final safeName = selected.name.isNotEmpty
            ? selected.name
            : 'pos_backup_${DateTime.now().millisecondsSinceEpoch}.json';
        tempFile = File('${tempDir.path}/$safeName');
        await tempFile.writeAsBytes(selected.bytes!);
        resolvedPath = tempFile.path;
      }

      final backupFile = File(resolvedPath);
      if (!await backupFile.exists()) {
        unawaited(
          showErrorToast(context, 'Backup file not found at $resolvedPath'),
        );
        return;
      }

      setState(() {
        _isRestoringBackup = true;
      });

      await DatabaseService.restoreDataBackupFromFile(backupFile);

      if (!mounted) {
        return;
      }

      setState(() {
        _lastRestorePath = resolvedPath!;
        _initializeSettingsState();
        final currentDate = DatabaseService.getCurrentDate();
        _selectedSalesYear = currentDate.year;
        _selectedSalesMonth = currentDate.month;
        _selectedAuditYear = currentDate.year;
        _selectedAuditMonth = currentDate.month;
      });

      // Push restored business date + state immediately so mobile reflects
      // close-day/current-date correctly right after backup import.
      unawaited(ManagerSyncService.syncToManagerApp());

      final acknowledged = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E3A8A,
                            ).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.cloud_done_outlined,
                            color: Color(0xFF1E3A8A),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'აღდგენა დასრულდა',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        'სარეზერვო ასლი აღდგენილია (DB v${DatabaseService.dbVersion}). მონაცემების სრულად განახლებისთვის აპი გადაიყვანება ავტორიზაციაზე.',
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('გაგრძელება'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (acknowledged == true && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        unawaited(showErrorToast(context, 'Restore failed: $e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringBackup = false;
        });
      }
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          final tempDir = tempFile.parent;
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _createBackupFile() async {
    // Show file picker to choose where to save the backup
    final String? selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Backup File',
      fileName:
          'pos_backup_${DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-')}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (selectedPath == null) {
      // User cancelled the file picker
      return;
    }

    if (!mounted) return;

    setState(() {
      _isCreatingBackup = true;
    });

    try {
      final backupFile = await DatabaseService.createDataBackup(
        targetFilePath: selectedPath,
      );
      if (!mounted) return;
      setState(() {
        _lastBackupPath = backupFile.path;
      });
      unawaited(
        showSuccessToast(context, 'Backup saved to ${backupFile.path}'),
      );
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Backup failed: $e'));
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingBackup = false;
        });
      }
    }
  }

  Future<void> _showBusinessDateSelector() async {
    final currentBusinessDate = DatabaseService.getCurrentDate();
    final currentDateOnly = DateTime(
      currentBusinessDate.year,
      currentBusinessDate.month,
      currentBusinessDate.day,
    );
    final dates = DatabaseService.getOperatedBusinessDates();
    if (dates.isEmpty) {
      if (mounted) {
        unawaited(showErrorToast(context, 'No historical dates available'));
      }
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: const Color(0xFFF8FAFC),
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        color: Color(0xFF1E3A8A),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'აირჩიე ბიზნეს თარიღი',
                          style: TextStyle(
                            color: Color(0xFF1F2937),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    itemCount: dates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final date = dates[dates.length - 1 - index];
                      final georgianLabel =
                          DatabaseService.getGeorgianFormattedDate(date);
                      final technicalLabel =
                          '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
                      final isCurrentDate =
                          DateTime(date.year, date.month, date.day) ==
                          currentDateOnly;

                      return Material(
                        color: isCurrentDate
                            ? const Color(0xFFEFF6FF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: isCurrentDate
                              ? null
                              : () async {
                                  final curDate =
                                      DatabaseService.getCurrentDate();
                                  final georgianCur =
                                      DatabaseService.getGeorgianFormattedDate(
                                        curDate,
                                      );
                                  final georgianTgt =
                                      DatabaseService.getGeorgianFormattedDate(
                                        date,
                                      );
                                  final confirmed = await showDialog<bool>(
                                    context: dialogContext,
                                    barrierColor: Colors.black26,
                                    builder: (confirmCtx) {
                                      return Dialog(
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        elevation: 8,
                                        insetPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 32,
                                              vertical: 24,
                                            ),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 420,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            const Color(
                                                              0xFF1E3A8A,
                                                            ).withValues(
                                                              alpha: 0.1,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: const Icon(
                                                        Icons
                                                            .event_repeat_rounded,
                                                        color: Color(
                                                          0xFF1E3A8A,
                                                        ),
                                                        size: 20,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    const Expanded(
                                                      child: Text(
                                                        'თარიღის დადასტურება',
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF0F172A,
                                                          ),
                                                          fontSize: 17,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            confirmCtx,
                                                          ).pop(false),
                                                      icon: const Icon(
                                                        Icons.close_rounded,
                                                      ),
                                                      color: const Color(
                                                        0xFF94A3B8,
                                                      ),
                                                      iconSize: 20,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 20),
                                                Container(
                                                  width: double.infinity,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 14,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFF8FAFC,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFE2E8F0,
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
                                                              'მიმდინარე',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .blueGrey
                                                                    .shade600,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              georgianCur,
                                                              style: const TextStyle(
                                                                color: Color(
                                                                  0xFF374151,
                                                                ),
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const Icon(
                                                        Icons
                                                            .arrow_forward_rounded,
                                                        color: Color(
                                                          0xFF94A3B8,
                                                        ),
                                                        size: 18,
                                                      ),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .end,
                                                          children: [
                                                            Text(
                                                              'გადასვლა',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .blueGrey
                                                                    .shade600,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              georgianTgt,
                                                              style: const TextStyle(
                                                                color: Color(
                                                                  0xFF1E3A8A,
                                                                ),
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  'ეს ქმედება გახსნის არჩეულ ბიზნეს დღეს, რათა შეძლო შეკვეთების და ჯავშნების კორექტირება.',
                                                  style: TextStyle(
                                                    color: Color(0xFF64748B),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w400,
                                                    height: 1.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 24),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: OutlinedButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              confirmCtx,
                                                            ).pop(false),
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor:
                                                              const Color(
                                                                0xFF334155,
                                                              ),
                                                          side:
                                                              const BorderSide(
                                                                color: Color(
                                                                  0xFFCBD5E1,
                                                                ),
                                                              ),
                                                          minimumSize:
                                                              const Size.fromHeight(
                                                                44,
                                                              ),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                          ),
                                                        ),
                                                        child: const Text(
                                                          'გაუქმება',
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              confirmCtx,
                                                            ).pop(true),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              const Color(
                                                                0xFF1E3A8A,
                                                              ),
                                                          foregroundColor:
                                                              Colors.white,
                                                          minimumSize:
                                                              const Size.fromHeight(
                                                                44,
                                                              ),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                          ),
                                                          elevation: 0,
                                                        ),
                                                        child: const Text(
                                                          'დადასტურება',
                                                        ),
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
                                  if (confirmed == true) {
                                    if (dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                    try {
                                      await DatabaseService.setCurrentDate(
                                        date,
                                      );
                                      await DatabaseService.activateTodaysReservations();
                                      if (!mounted) return;
                                      setState(() {});
                                      unawaited(
                                        showSuccessToast(
                                          context,
                                          'Business date switched to $georgianTgt',
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      unawaited(
                                        showErrorToast(
                                          context,
                                          'Error changing date: $e',
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isCurrentDate
                                        ? const Color(
                                            0xFF1E3A8A,
                                          ).withValues(alpha: 0.2)
                                        : const Color(
                                            0xFF1E3A8A,
                                          ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isCurrentDate
                                        ? Icons.event_available
                                        : Icons.event,
                                    color: const Color(0xFF1E3A8A),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        georgianLabel,
                                        style: TextStyle(
                                          color: isCurrentDate
                                              ? const Color(0xFF1E3A8A)
                                              : const Color(0xFF0F172A),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        technicalLabel,
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCurrentDate)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E3A8A),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'მიმდინარე',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF94A3B8),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('გაუქმება'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmBusinessDateChange(DateTime targetDate) async {
    final currentDate = DatabaseService.getCurrentDate();
    if (currentDate == targetDate) {
      return;
    }

    final georgianCurrent = DatabaseService.getGeorgianFormattedDate(
      currentDate,
    );
    final georgianTarget = DatabaseService.getGeorgianFormattedDate(targetDate);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 8,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.event_repeat_rounded,
                          color: Color(0xFF1E3A8A),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'თარიღის დადასტურება',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF94A3B8),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'მიმდინარე',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade600,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                georgianCurrent,
                                style: const TextStyle(
                                  color: Color(0xFF374151),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF94A3B8),
                          size: 18,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'გადასვლა',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade600,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                georgianTarget,
                                style: const TextStyle(
                                  color: Color(0xFF1E3A8A),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ეს ქმედება გახსნის არჩეულ ბიზნეს დღეს, რათა შეძლო შეკვეთების და ჯავშნების კორექტირება.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('გაუქმება'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('დადასტურება'),
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

    if (confirmed == true) {
      try {
        await DatabaseService.setCurrentDate(targetDate);
        await DatabaseService.activateTodaysReservations();
        if (!mounted) return;
        setState(() {});
        unawaited(
          showSuccessToast(
            context,
            'Business date switched to ${DatabaseService.getGeorgianFormattedDate(targetDate)}',
          ),
        );
      } catch (e) {
        if (!mounted) return;
        unawaited(showErrorToast(context, 'Error changing date: $e'));
      }
    }
  }

  Future<void> _reprintSaleReceipt(Map<String, dynamic> sale) async {
    final itemMaps = _resolveSaleItemsForPrint(sale);
    final items = itemMaps.map((item) {
      final qty = item['quantity'] ?? 0;
      final name = item['itemName'] ?? '';
      final total = (item['total'] as num?)?.toDouble() ?? 0.0;
      return '${qty}x $name - ₾${total.toStringAsFixed(2)}';
    }).toList();

    final subtotal = itemMaps.fold<double>(
      0,
      (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0.0),
    );
    final includeServiceFee = sale['includeServiceFee'] == true;
    final serviceFee = includeServiceFee ? subtotal * 0.10 : 0.0;
    final totalAmount =
        (sale['totalAmount'] as num?)?.toDouble() ?? subtotal + serviceFee;
    final tableNumbers = ((sale['tableNumbers'] as List?)?.cast<String>() ?? [])
        .join(', ');
    final paymentLabel = PaymentUtils.formatPaymentDisplay(sale);

    PrinterService.printReceiptInBackground(
      items: items,
      subtotal: subtotal,
      serviceFee: includeServiceFee ? serviceFee : null,
      includeServiceFee: includeServiceFee,
      total: totalAmount,
      tableNumber: tableNumbers.isEmpty ? null : tableNumbers,
      orderNumber: sale['orderId'].toString(),
      paymentMethod: paymentLabel,
      onComplete: (success) {
        if (!mounted) return;
        unawaited(
          showPosToast(
            context: context,
            message: success
                ? 'Receipt sent to printer'
                : 'Printer unavailable. Please check connection.',
            style: success ? PosToastStyle.success : PosToastStyle.error,
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _resolveSaleItemsForPrint(
    Map<String, dynamic> sale,
  ) {
    List<Map<String, dynamic>> parseItems(dynamic rawItems) {
      if (rawItems is! List) {
        return const [];
      }

      return rawItems.whereType<Map>().map((raw) {
        return {
          'itemName': raw['itemName'] ?? raw['name'] ?? 'უცნობი პოზიცია',
          'quantity': (raw['quantity'] as num?)?.toInt() ?? 0,
          'total': (raw['total'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();
    }

    final directItems = parseItems(sale['items']);
    if (directItems.isNotEmpty) {
      return directItems;
    }

    final finalTransaction = sale['finalTransaction'];
    if (finalTransaction is Map) {
      return parseItems(finalTransaction['items']);
    }

    return const [];
  }

  double _resolveLinkedAdvanceForSale(Map<String, dynamic> sale) {
    final saleAdvance =
        (sale['advanceAmount'] as num?)?.toDouble() ??
        (sale['discountAmount'] as num?)?.toDouble() ??
        0.0;
    if (saleAdvance > 0) {
      return saleAdvance;
    }

    final orderId = sale['orderId'];
    final saleDate = sale['date']?.toString();
    final allSales = DatabaseService.getAllSales();
    final linkedAdvance = allSales
        .where((record) {
          if (record['orderId'] != orderId) {
            return false;
          }
          if (saleDate != null &&
              saleDate.isNotEmpty &&
              record['date'] != saleDate) {
            return false;
          }
          if (record['isCancelled'] == true ||
              record['restoredToOrder'] == true) {
            return false;
          }
          final paymentMethod = (record['paymentMethod'] as String? ?? '')
              .trim()
              .toLowerCase();
          return paymentMethod == PaymentUtils.methodAdvance;
        })
        .fold<double>(0.0, (sum, record) {
          return sum + ((record['totalAmount'] as num?)?.toDouble() ?? 0.0);
        });

    return linkedAdvance;
  }

  Future<void> _reprintSaleFullReceipt(Map<String, dynamic> sale) async {
    final itemMaps = _resolveSaleItemsForPrint(sale);
    final items = itemMaps.map((item) {
      final qty = item['quantity'] ?? 0;
      final name = item['itemName'] ?? '';
      final total = (item['total'] as num?)?.toDouble() ?? 0.0;
      return '${qty}x $name - ₾${total.toStringAsFixed(2)}';
    }).toList();

    final subtotalFromSale = (sale['subtotalAmount'] as num?)?.toDouble();
    final subtotalFromItems = itemMaps.fold<double>(
      0,
      (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0.0),
    );
    final subtotal = subtotalFromSale ?? subtotalFromItems;

    final finalTransaction = sale['finalTransaction'];
    final includeServiceFee = sale['includeServiceFee'] == true;
    final serviceFeeFromFinal = finalTransaction is Map
        ? (finalTransaction['serviceFee'] as num?)?.toDouble()
        : null;
    final serviceFee =
        serviceFeeFromFinal ?? (includeServiceFee ? subtotal * 0.10 : 0.0);
    final manualAdjustment =
        (sale['manualAdjustmentAmount'] as num?)?.toDouble() ??
        (finalTransaction is Map
            ? (finalTransaction['manualAdjustment'] as num?)?.toDouble() ?? 0.0
            : 0.0);
    final linkedAdvance = _resolveLinkedAdvanceForSale(sale);

    final totalAmount =
        (sale['totalAmount'] as num?)?.toDouble() ?? subtotal + serviceFee;
    final tableNumbers = ((sale['tableNumbers'] as List?)?.cast<String>() ?? [])
        .join(', ');
    final paymentLabel = PaymentUtils.formatPaymentDisplay(sale);

    PrinterService.printReceiptInBackground(
      items: items,
      subtotal: subtotal,
      serviceFee: includeServiceFee ? serviceFee : null,
      includeServiceFee: includeServiceFee,
      total: totalAmount,
      tableNumber: tableNumbers.isEmpty ? null : tableNumbers,
      orderNumber: sale['orderId'].toString(),
      paymentMethod: paymentLabel,
      discountAmount: linkedAdvance > 0 ? linkedAdvance : null,
      manualAdjustment: manualAdjustment != 0 ? manualAdjustment : null,
      receiptType: 'client',
      onComplete: (success) {
        if (!mounted) return;
        unawaited(
          showPosToast(
            context: context,
            message: success
                ? 'Full receipt sent to printer'
                : 'Printer unavailable. Please check connection.',
            style: success ? PosToastStyle.success : PosToastStyle.error,
          ),
        );
      },
    );
  }

  Future<void> _confirmCancelSale(Map<String, dynamic> sale) async {
    final isCancelled = sale['isCancelled'] == true;
    if (isCancelled) {
      return;
    }

    final orderId = sale['orderId'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Sale Record',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to cancel Order #$orderId in sales history?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('გაუქმება / Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await DatabaseService.cancelSaleRecord(sale['recordKey']);
      if (success) {
        final reservationCancelled =
            await DatabaseService.cancelReservationByOrderId(orderId as int);
        if (!mounted) return;
        setState(() {});
        final message = reservationCancelled
            ? 'Order #$orderId cancelled. Linked reservation updated.'
            : 'Order #$orderId cancelled.';
        unawaited(
          showPosToast(
            context: context,
            message: message,
            style: PosToastStyle.info,
          ),
        );
      } else if (mounted) {
        unawaited(showErrorToast(context, 'Could not cancel sale record.'));
      }
    }
  }

  Future<void> _restoreClosedSale(Map<String, dynamic> sale) async {
    final isRestored = sale['restoredToOrder'] == true;
    if (isRestored) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'ეს გაყიდვა უკვე დაბრუნებულია.'));
      return;
    }

    final saleDate = (sale['date'] as String?) ?? '';
    final todayDate = DatabaseService.getCurrentDate().toIso8601String().split(
      'T',
    )[0];
    if (saleDate != todayDate) {
      if (!mounted) return;
      unawaited(
        showErrorToast(
          context,
          'დაბრუნება შესაძლებელია მხოლოდ მიმდინარე ბიზნეს თარიღისთვის.',
        ),
      );
      return;
    }

    final orderId = sale['orderId'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'მაგიდაზე დაბრუნება',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ შეკვეთის (#$orderId) დაბრუნება აქტიურ მაგიდაზე?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('გაუქმება', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
            ),
            child: const Text('დაბრუნება'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final success = await DatabaseService.restoreClosedOrderFromSale(
      recordKey: sale['recordKey'],
      restoredBy: widget.user.username,
    );
    if (!mounted) return;

    if (success) {
      setState(() {});
      unawaited(showSuccessToast(context, 'შეკვეთა დაბრუნდა აქტიურ მაგიდაზე.'));
    } else {
      unawaited(
        showErrorToast(
          context,
          'დაბრუნება ვერ შესრულდა. შესაძლოა თარიღი არასწორია ან მაგიდა დაკავებულია.',
        ),
      );
    }
  }

  Widget _buildContent() {
    if (_isLimitedAdmin && !_limitedAdminSections.contains(_selectedSection)) {
      return AdminStaffSection(user: widget.user);
    }

    switch (_selectedSection) {
      case 'staff':
      case 'waiters':
      case 'users':
        return AdminStaffSection(user: widget.user);
      case 'menu':
        return AdminMenuSection(user: widget.user);
      case 'packages':
        return AdminPackagesSection(user: widget.user);
      case 'reservations':
        return AdminReservationsSection(user: widget.user);
      case 'closeday':
        return AdminCloseDaySection(
          user: widget.user,
          onShowBusinessDateSelector: _showBusinessDateSelector,
          onSetBusinessDateToToday: _buildSetBusinessDateToLastClosedAction(),
          formatDateTimeDisplay: _formatDateTimeDisplay,
        );
      case 'sales':
        return AdminSalesSection(
          onReprintSaleReceipt: _reprintSaleReceipt,
          onReprintFullSaleReceipt: _reprintSaleFullReceipt,
          onConfirmCancelSale: _confirmCancelSale,
          onRestoreClosedSale: _restoreClosedSale,
        );
      case 'salesReport':
        return AdminSalesReportSection(
          selectedSalesYear: _selectedSalesYear,
          selectedSalesMonth: _selectedSalesMonth,
          onChangeSalesMonth: _changeSalesMonth,
          onSetSelectedSalesMonth: _setSelectedSalesMonth,
        );
      case 'audit':
        return AdminAuditLogSection(
          selectedAuditYear: _selectedAuditYear,
          selectedAuditMonth: _selectedAuditMonth,
          onChangeAuditMonth: _changeAuditMonth,
          onSetSelectedAuditMonth: _setSelectedAuditMonth,
        );
      case 'errors':
        return const AdminErrorLogSection();
      case 'settings':
        return _buildSettingsSection();
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainContent = Expanded(child: ClipRect(child: _buildContent()));

    return Scaffold(
      backgroundColor: _surfaceColor,
      appBar: _isMobile
          ? AppBar(
              backgroundColor: const Color(0xFF1E3A8A),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                _getSectionTitle(_selectedSection),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(_isSidebarExpanded ? Icons.close : Icons.menu),
                  onPressed: () {
                    setState(() {
                      _isSidebarExpanded = !_isSidebarExpanded;
                    });
                  },
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          // Main content and sidebar
          _isMobile
              ? Stack(
                  children: [
                    Column(children: [mainContent]),
                    if (_isSidebarExpanded)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSidebarExpanded = false;
                            });
                          },
                          child: Container(
                            color: Colors.black.withOpacity(0.4),
                          ),
                        ),
                      ),
                    _buildSidebar(),
                  ],
                )
              : Row(
                  children: [
                    // Sidebar
                    _buildSidebar(),

                    // Main content
                    mainContent,
                  ],
                ),
        ],
      ),
    );
  }
}
