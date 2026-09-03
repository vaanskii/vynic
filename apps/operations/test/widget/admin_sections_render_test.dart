import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/admin_audit_log_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_data_backup_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_developer_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_menu_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_packages_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_sales_report_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_settings_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_display_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_error_log_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_reservations_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_sales_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_staff_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/security/developer_access.dart';

/// Builds every admin section under the panel's real theme and asserts none of
/// them throws. The restyle touched all fourteen, and a section that fails to
/// build is the one failure mode a colour change can actually cause — a token
/// used where it is not a constant, a palette entry that no longer exists.
///
/// Set `VYNIC_DUMP_DIR` and each section is also written out as a PNG, which is
/// how the restyle was checked in the first place: looking at the sections
/// beats reasoning about them. Without it the renders happen but nothing is
/// saved, so the suite stays fast and leaves no files behind.

late Directory _tempDir;
String? _outDir;

final _user = User(username: 'giorgi', pinCode: '0000', role: 'manager');

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
  if (!Hive.isAdapterRegistered(5)) {
    Hive.registerAdapter(MenuCategoryDBAdapter());
    Hive.registerAdapter(MenuSubcategoryDBAdapter());
    Hive.registerAdapter(MenuItemDBAdapter());
    Hive.registerAdapter(MenuVariantDBAdapter());
  }
  if (!Hive.isAdapterRegistered(11)) {
    Hive.registerAdapter(PackageAdapter());
    Hive.registerAdapter(PackageItemAdapter());
  }
}

Future<void> _seed() async {
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('rd_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('rd_orders');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('rd_res');
  DatabaseCore.settingsBox = await Hive.openBox('rd_settings');
  DatabaseCore.userBox = await Hive.openBox<User>('rd_users');
  DatabaseCore.salesBox = await Hive.openBox('rd_sales');
  DatabaseCore.errorLogBox = await Hive.openBox('rd_errors');
  DatabaseCore.auditLogBox = await Hive.openBox('rd_audit');
  DatabaseCore.expenseBox = await Hive.openBox('rd_expenses');
  DatabaseCore.metaBox = await Hive.openBox('rd_meta');
  DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('rd_menu');
  DatabaseCore.packageBox = await Hive.openBox<Package>('rd_packages');

  await DatabaseCore.settingsBox!.put(
    'currentDate',
    DateTime.now().toIso8601String(),
  );

  for (final entry in const [
    ('giorgi', 'manager'),
    ('nino', 'waiter'),
    ('levani', 'waiter'),
    ('mariami', 'supervisor'),
  ]) {
    await DatabaseCore.userBox!.add(
      User(username: entry.$1, pinCode: '0000', role: entry.$2),
    );
  }
}

/// The management centre's shell, including the theme the real screen wraps
/// its content in.
Widget _shell(Size size, Widget section) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Theme(
          data: AdminTheme.of(context),
          child: Scaffold(
            backgroundColor: const Color(0xFFF7F6F4),
            body: RepaintBoundary(
              key: const ValueKey('shot'),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: 236),
                    Expanded(child: ClipRect(child: section)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
}

Future<void> _render(
  WidgetTester tester,
  String name,
  Widget section, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_shell(size, section));
  await tester.pump(const Duration(milliseconds: 300));

  expect(tester.takeException(), isNull, reason: '$name failed to build');

  if (_outDir != null) {
    await tester.runAsync(() => _shoot(tester, name));
  }
}

void main() {
  setUpAll(() async {
    _outDir = Platform.environment['VYNIC_DUMP_DIR'];
    if (_outDir != null) Directory(_outDir!).createSync(recursive: true);
    _tempDir = await Directory.systemTemp.createTemp('vynic_render_dump');
    Hive.init(_tempDir.path);
    _registerAdapters();
    await _seed();
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.tableBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.reservationBox = null;
    DatabaseCore.settingsBox = null;
    DatabaseCore.userBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.errorLogBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.expenseBox = null;
    DatabaseCore.metaBox = null;
    DatabaseCore.menuBox = null;
    DatabaseCore.packageBox = null;
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  testWidgets('staff', (tester) async {
    await _render(tester, 'staff', AdminStaffSection(user: _user));
  });

  testWidgets('reservations', (tester) async {
    await _render(
      tester,
      'reservations',
      AdminReservationsSection(user: _user),
    );
  });

  testWidgets('sales', (tester) async {
    await _render(
      tester,
      'sales',
      AdminSalesSection(
        onReprintSaleReceipt: (_) async {},
        onReprintFullSaleReceipt: (_) async {},
        onConfirmCancelSale: (_) async {},
        onRestoreClosedSale: (_) async {},
      ),
    );
  });

  testWidgets('display', (tester) async {
    await _render(
      tester,
      'display',
      AdminDisplaySection(
        displaySettings: const PosDisplaySettings(),
        onDisplaySettingsChanged: (_) {},
        isSaving: false,
        onSave: () {},
      ),
    );
  });

  testWidgets('errors', (tester) async {
    await _render(tester, 'errors', const AdminErrorLogSection());
  });

  testWidgets('backup', (tester) async {
    await _render(
      tester,
      'backup',
      SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: AdminDataBackupPanel(
          lastBackupPath: '/Users/giorgi/vynic-backup-2026-08-22.json',
          lastRestorePath: null,
          isCreatingBackup: false,
          isRestoringBackup: false,
          onCreateBackupFile: () async {},
          onRestoreBackupFromFile: () async {},
        ),
      ),
    );
  });

  testWidgets('backup, as Settings renders it — create only', (tester) async {
    // Restore clears every box before it writes, so a manager reaching for
    // last week's file to „check something" destroys the week. Settings gets
    // the create button and nothing else.
    await _render(
      tester,
      'backup_create_only',
      SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: AdminDataBackupPanel(
          lastBackupPath: '/Users/giorgi/vynic-backup-2026-08-22.json',
          lastRestorePath: '/Users/giorgi/vynic-backup-2026-08-01.json',
          isCreatingBackup: false,
          isRestoringBackup: false,
          onCreateBackupFile: () async {},
          onRestoreBackupFromFile: () async {},
          allowRestore: false,
        ),
      ),
    );

    expect(find.text('სარეზერვო ასლიდან აღდგენა'), findsNothing);
    expect(find.text('სარეზერვო ფაილის შექმნა'), findsOneWidget);
  });

  testWidgets('developer', (tester) async {
    DeveloperAccess.resetForTest();
    addTearDown(DeveloperAccess.resetForTest);

    await _render(
      tester,
      'developer',
      const AdminDeveloperSection(
        onCreateBackupFile: _noop,
        onRestoreBackupFromFile: _noop,
        isCreatingBackup: false,
        isRestoringBackup: false,
        lastBackupPath: null,
        lastRestorePath: null,
      ),
    );

    // Locked, so every tool renders as denied rather than throwing — the state
    // a manager would land in if the routing guard ever let them through.
    expect(find.textContaining('not granted by this token'), findsWidgets);
  });

  testWidgets('audit', (tester) async {
    await _render(
      tester,
      'audit',
      AdminAuditLogSection(
        selectedAuditYear: 2026,
        selectedAuditMonth: 8,
        onChangeAuditMonth: (_) {},
        onSetSelectedAuditMonth: (_) {},
      ),
    );
  });

  testWidgets('salesReport', (tester) async {
    await _render(
      tester,
      'sales_report',
      AdminSalesReportSection(
        selectedSalesYear: 2026,
        selectedSalesMonth: 8,
        onChangeSalesMonth: (_) {},
        onSetSelectedSalesMonth: (_) {},
      ),
    );
  });

  testWidgets('menu', (tester) async {
    await _render(tester, 'menu', AdminMenuSection(user: _user));
  });

  testWidgets('packages', (tester) async {
    await _render(tester, 'packages', AdminPackagesSection(user: _user));
  });

  testWidgets('settings', (tester) async {
    final controllers = List.generate(5, (_) => TextEditingController());
    addTearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
    });
    controllers[0].text = '10';

    await _render(
      tester,
      'settings',
      AdminSettingsSection(
        dataBackup: AdminDataBackupPanel(
          lastBackupPath: null,
          lastRestorePath: null,
          isCreatingBackup: false,
          isRestoringBackup: false,
          onCreateBackupFile: () async {},
          onRestoreBackupFromFile: () async {},
        ),
        formatDateTimeDisplay: (d) => d.toIso8601String(),
        formatRelativeTime: (d) => 'a moment ago',
        serviceFeeController: controllers[0],
        currentCancellationPasswordController: controllers[1],
        newCancellationPasswordController: controllers[2],
        confirmCancellationPasswordController: controllers[3],
        cancellationPasswordHintController: controllers[4],
        serviceFeeEnabledByDefault: true,
        onServiceFeeEnabledByDefaultChanged: (_) {},
        receiptServiceFeeLineVisible: true,
        onReceiptServiceFeeLineVisibleChanged: (_) {},
        closeReceiptServiceFeeLineVisible: false,
        onCloseReceiptServiceFeeLineVisibleChanged: (_) {},
        serviceFeePercentDisplay: '10%',
        isSavingServiceFee: false,
        defaultLanguageSetting: 'ka',
        onDefaultLanguageSettingChanged: (_) {},
        isSavingLocalization: false,
        isCancellationPasswordSet: true,
        isSavingCancellationPassword: false,
        cancellationPasswordUpdatedAt: null,
        restrictTableCloseToOwner: true,
        onRestrictTableCloseToOwnerChanged: (_) {},
        isSavingTableOwnershipSettings: false,
        onSaveServiceFeeSettings: () async {},
        onSaveCancellationPassword: () async {},
        onSaveTableOwnershipSettings: () async {},
        onSaveLocalizationSettings: () async {},
      ),
    );
  });
}

Future<void> _noop() async {}
