import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/windows_pos/screens/home_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'fonts.dart';
import 'harness.dart';
import 'seed.dart';
import 'dart:convert';

void main() {
  setUpAll(() async {
    await loadCaptureFonts();
    Hive.init(Directory.systemTemp.createTempSync('vcap').path);
    registerAll();
  });
  testWidgets('pos flow', (t) async {
    await t.runAsync(() => seedRestaurant('p1', DateTime.now()));
    t.view..devicePixelRatio = 2..physicalSize = const Size(2880, 1800);
    addTearDown(t.view.reset);
    await t.pumpWidget(app(HomeScreen(user: User(username: 'ნინო', pinCode: '0000', role: 'manager'))));
    await t.pump(const Duration(milliseconds: 500));
    await settle(t, 900);
    await shot(t, 'pos_01_floor');
    rectOf(t, 'floor_t4', find.text('მაგიდა 4'));
    for (final tab in ['დათვლა', 'გატანები', 'რეზერვაცია', 'X', 'მართვის ცენტრი']) { rectOf(t, 'tab_$tab', find.text(tab)); }
    await tapText(t, 'მაგიდა 4');
    await shot(t, 'pos_02_editor_empty');
    rectOf(t, 'plus0', find.byIcon(Icons.add));
    rectOf(t, 'cat_salads', find.text('სალათები'));
    rectOf(t, 'cat_drinks', find.text('სასმელები'));
    rectOf(t, 'tile0', find.text('ხაჭაპური აჭარული'));
    rectOf(t, 'add_order', find.text('შეკვეთის დამატება'));
    rectOf(t, 'total', find.text('0.00 ₾'), last: true);
    await addItem(t, 0, padShot: 'pos_03a_pad');
    await shot(t, 'pos_03_item1');
    await tapText(t, 'სალათები');
    await addItem(t, 0);
    await shot(t, 'pos_04_item2');
    await tapText(t, 'სასმელები');
    await addItem(t, 0);
    await shot(t, 'pos_05_item3');
    rectOf(t, 'total3', find.text('46.20 ₾'), last: true);
    for (final n in ['ლიმონათი', 'ქართული სალათი', 'ხაჭაპური აჭარული']) { rectOf(t, 'line_$n', find.text(n), last: true); }
    dumpTexts(t, 'editor3');
    await tapText(t, 'შეკვეთის დამატება', last: true);
    for (var i = 0; i < 10 && find.text('შეკვეთის დადასტურება').evaluate().isEmpty; i++) { await settle(t, 400); }
    await shot(t, 'pos_06_detail_pending');
    await tapText(t, 'შეკვეთის დადასტურება', last: true);
    await settle(t, 1200);
    await shot(t, 'pos_07_detail_confirmed');
    rectOf(t, 'detail_status', find.text('დაკავებული'));
    rectOf(t, 'detail_total', find.text('46.20 ₾'), last: true);
    rectOf(t, 'detail_back', find.text('მაგიდები'));
    dumpTexts(t, 'confirmed');
    await tapText(t, 'მაგიდები');
    await settle(t, 1200);
    await shot(t, 'pos_08_floor_after');
    rectOf(t, 'floor2_t4', find.text('მაგიდა 4'));
    dumpTexts(t, 'floor2');
    for (final tab in [('დათვლა', 'pos_10_calc'), ('გატანები', 'pos_11_takeaway'), ('რეზერვაცია', 'pos_12_reservations'), ('X', 'pos_14_xreport')]) {
      await tapText(t, tab.$1);
      await settle(t);
      await shot(t, tab.$2);
      dumpTexts(t, tab.$1);
    }
    await tapText(t, 'მართვის ცენტრი');
    await settle(t, 1500);
    dumpTexts(t, 'adminopen');
    await shot(t, 'pos_20_admin');
    for (final sec in [('მენიუ', 'pos_21_admin_menu'), ('მაგიდები', 'pos_22_admin_tables'), ('დღის დახურვა', 'pos_23_admin_close'), ('რეზერვაციები', 'pos_24_admin_res'), ('მარაგები', 'pos_25_admin_inventory')]) {
      await tapText(t, sec.$1, last: false);
      await settle(t, 900);
      await shot(t, sec.$2);
      dumpTexts(t, sec.$1);
      dumpFamilies(t);
    }
    await t.runAsync(() => File('$capOut/pos_rects.json').writeAsString(jsonEncode(rects)));
    await t.pump(const Duration(seconds: 5));
    SessionLock.disarm();
  });
}
