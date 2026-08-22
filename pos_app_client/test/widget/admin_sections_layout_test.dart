import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/admin_data_backup_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_staff_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

/// Admin sections sit in the management centre's content column, which is a
/// stretched `Expanded`. Two things have to hold there: nothing overflows as
/// the column narrows, and a section shorter than the window starts at the
/// top rather than floating in the middle of the page.

late Directory _tempDir;

final _user = User(username: 'giorgi', pinCode: '0000', role: 'manager');

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
}

Future<void> _seed() async {
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('as_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('as_orders');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('as_res');
  DatabaseCore.settingsBox = await Hive.openBox('as_settings');
  DatabaseCore.userBox = await Hive.openBox<User>('as_users');

  await DatabaseCore.settingsBox!.put(
    'currentDate',
    DateTime.now().toIso8601String(),
  );

  for (final entry in const [
    ('giorgi', 'manager'),
    ('nino', 'waiter'),
    ('levani', 'waiter'),
  ]) {
    await DatabaseCore.userBox!.add(
      User(username: entry.$1, pinCode: '0000', role: entry.$2),
    );
  }
}

/// The management centre's shell: a fixed sidebar and a stretched content
/// column. Reproduced rather than pumping AdminScreen so the alignment can be
/// asserted without dragging in the whole screen's initialisation.
Widget _shell(Size size, Widget section) {
  const sidebar = 236.0;
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: sidebar),
              Expanded(
                child: ClipRect(
                  child: KeyedSubtree(
                    key: const ValueKey('section'),
                    child: section,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _backup() => SingleChildScrollView(
  padding: const EdgeInsets.all(18),
  child: AdminDataBackupPanel(
    lastBackupPath: null,
    lastRestorePath: null,
    isCreatingBackup: false,
    isRestoringBackup: false,
    onCreateBackupFile: () async {},
    onRestoreBackupFromFile: () async {},
  ),
);

const _widths = <double>[1024, 1280, 1440, 1920];

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_admin_sections');
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
    if (_tempDir.existsSync()) {
      _tempDir.deleteSync(recursive: true);
    }
  });

  group('პერსონალი', () {
    for (final width in _widths) {
      testWidgets('the search row fits at ${width.round()} wide', (
        tester,
      ) async {
        final size = Size(width, 800);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_shell(size, AdminStaffSection(user: _user)));
        await tester.pump();

        // The search field used to be a hard 270pt box, so once the title and
        // the filter button had taken their share the row overflowed.
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the search row never outgrows the column it sits in', (
      tester,
    ) async {
      // The field was a hard 270pt SizedBox, so once the title and the filter
      // button had taken their share there was nothing left to give. It is a
      // cap now, and the row is measured against its parent at each width.
      for (final width in _widths) {
        final size = Size(width, 800);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_shell(size, AdminStaffSection(user: _user)));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: '$width');

        final field = tester.getRect(find.byType(PosOnScreenTextField).first);
        final section = tester.getRect(find.byKey(const ValueKey('section')));
        expect(
          field.right,
          lessThanOrEqualTo(section.right + 0.5),
          reason: 'search runs past the column at $width',
        );
        expect(field.width, greaterThan(0), reason: '$width');
      }
    });
  });

  group('content starts at the top', () {
    testWidgets('a short section fills the column rather than centring', (
      tester,
    ) async {
      const size = Size(1440, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(size, _backup()));
      await tester.pump();

      // The backup panel is far shorter than 900pt. Under the old
      // centre-aligned Row it was handed a loose height and floated in the
      // middle of the page; stretched, it starts at the top.
      final section = tester.getRect(find.byKey(const ValueKey('section')));
      expect(section.top, closeTo(0, 0.5));
      expect(section.height, closeTo(900, 0.5));
    });

    testWidgets('its content is anchored to the top of the column', (
      tester,
    ) async {
      const size = Size(1440, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(size, _backup()));
      await tester.pump();

      final panel = tester.getRect(find.byType(AdminDataBackupPanel));
      // Sitting just below the section's own 18pt padding, not halfway down.
      expect(panel.top, closeTo(18, 1));
    });
  });
}
