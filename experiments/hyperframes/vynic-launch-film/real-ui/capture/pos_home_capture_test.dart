import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/windows_pos/screens/home_screen.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/session_lock.dart';

import 'fonts.dart';

late Directory tempDir;
const out = '/private/tmp/claude-501/-Users-vaanskii-Developer-vynic/45c00cc0-bb0b-4c1e-9daf-b54e3b6de383/scratchpad/captures';

Future<void> shot(WidgetTester t, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('$out/$name.png'));
}

void main() {
  setUpAll(() async {
    await loadCaptureFonts();
    tempDir = Directory.systemTemp.createTempSync('vynic_capture');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(QuickOrderDraftAdapter());
  });

  testWidgets('pos home', (tester) async {
    await tester.runAsync(() async {
      DatabaseCore.settingsBox = await Hive.openBox('c_settings');
      DatabaseCore.salesBox = await Hive.openBox('c_sales');
      DatabaseCore.auditLogBox = await Hive.openBox('c_audit');
      DatabaseCore.orderBox = await Hive.openBox<Order>('c_orders');
      DatabaseCore.tableBox = await Hive.openBox<TableModel>('c_tables');
      DatabaseCore.reservationBox = await Hive.openBox<Reservation>('c_res');
      DatabaseCore.closureJournalBox = await Hive.openBox('c_journal');
      await DatabaseCore.settingsBox!.put('currentDate', '2026-09-30T00:00:00.000');
      for (var i = 1; i <= 8; i++) {
        await DatabaseCore.tableBox!.put('first-$i', TableModel(tableNumber: '$i', floor: 'first'));
      }
    });
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(2880, 1800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ka'),
      supportedLocales: const [Locale('ka'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(fontFamily: 'NotoSansGeorgian', fontFamilyFallback: const ['Roboto']),
      home: HomeScreen(user: User(username: 'ნინო', pinCode: '0000', role: 'manager')),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, 'pos_floor_v0');
    SessionLock.disarm();
  });
}
