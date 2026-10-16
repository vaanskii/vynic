import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/apps/mobile_app/manager_app_shell.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'fonts.dart';
import 'harness.dart';
import 'manager_api.dart';
import 'dart:convert';
import 'dart:io';

Future<void> anim(WidgetTester t) async {
  await settle(t, 900);
  for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 250)); }
}

Future<void> tapIcon(WidgetTester t, IconData icon) async {
  final f = find.byIcon(icon);
  if (f.evaluate().isEmpty) { print('MISSING icon $icon'); return; }
  await t.tap(f.last, warnIfMissed: false);
  await anim(t);
}

void main() {
  setUpAll(loadCaptureFonts);
  testWidgets('manager', (t) async {
    t.view..devicePixelRatio = 3..physicalSize = const Size(396 * 3, 856 * 3);
    addTearDown(t.view.reset);
    await http.runWithClient(() async {
      await t.pumpWidget(app(ManagerAppShell(user: User(username: 'ნინო', pinCode: '0000', role: 'manager'))));
      await anim(t);
      // scroll the static placeholder insight card out of view: start at the business-day card
      await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await anim(t);
      await shot(t, 'mgr_01_dash_before');
      rectOf(t, 'm_rev', find.text('აქტიური ცვლის შემოსავალი'));
      rectOf(t, 'm_revval', find.text('₾2,868.65'));
      rectOf(t, 'm_closed', find.text('დახურული'));
      rectOf(t, 'm_open', find.textContaining('ღია ('));
      rectOf(t, 'm_cash', find.text('₾340.85'));
      afterRefresh = true;
      await t.fling(find.byType(Scrollable).first, const Offset(0, 700), 1500);
      await t.pump(const Duration(milliseconds: 60));
      await t.pump(const Duration(milliseconds: 120));
      await shot(t, 'mgr_02_pull');
      for (var i = 0; i < 6; i++) { await anim(t); }
      for (var i = 0; i < 20 && find.text('₾2,914.85').evaluate().isEmpty; i++) { await anim(t); }
      await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await anim(t);
      await shot(t, 'mgr_03_dash_after');
      rectOf(t, 'm_revval2', find.text('₾2,914.85'));
      await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await anim(t);
      await shot(t, 'mgr_04_dash_scrolled');
      dumpTexts(t, 'dash');
      await tapIcon(t, Icons.table_bar_rounded);
      await shot(t, 'mgr_05_tables');
      dumpTexts(t, 'tables');
      await tapIcon(t, Icons.inventory_2_outlined);
      await shot(t, 'mgr_06_inventory');
      rectOf(t, 'mgr_06_inventory', find.text('ახალი მიღება'), last: true);
      dumpTexts(t, 'inv');
      await tapText(t, 'ახალი მიღება');
      await anim(t);
      await shot(t, 'mgr_08_recv_editor');
      Future<void> key(String k) async {
        final f = find.byKey(Key(k));
        if (f.evaluate().isEmpty) { print('MISSING key $k'); return; }
        await t.ensureVisible(f); await t.pump(const Duration(milliseconds: 200));
        await t.tap(f, warnIfMissed: false); await anim(t);
      }
      await key('receiving-line-item-0-null');
      final opts = find.descendant(of: find.byType(InventoryIngredientPicker), matching: find.byType(ListTile));
      if (opts.evaluate().isNotEmpty) { await t.tap(opts.first); await anim(t); }
      await t.enterText(find.byKey(const Key('receiving-line-quantity-0')), '20');
      await t.enterText(find.byKey(const Key('receiving-line-cost-0')), '3');
      await anim(t);
      await shot(t, 'mgr_09_recv_lines');
      rectOf(t, 'm_qty', find.byKey(const Key('receiving-line-quantity-0')));
      rectOf(t, 'm_next', find.byKey(const Key('receiving-next')));
      await key('receiving-next');
      await shot(t, 'mgr_09b_recv_payment');
      dumpTexts(t, 'pay');
      await tapText(t, 'ნაწილობრივ გადავიხადე', last: true);
      await anim(t);
      final paid = find.byKey(const Key('receiving-paid-now'));
      if (paid.evaluate().isNotEmpty) { await t.enterText(paid, '30'); await anim(t); }
      await t.testTextInput.receiveAction(TextInputAction.done);
      await anim(t);
      await shot(t, 'mgr_09c_recv_review');
      rectOf(t, 'm_partial', find.text('ნაწილობრივ გადავიხადე'));
      rectOf(t, 'm_remaining', find.textContaining('დარჩა'));
      rectOf(t, 'mgr_09c_recv_review', find.text('მიღების დადასტურება'), last: true);
      dumpTexts(t, 'review');
      await key('receiving-save');
      await anim(t); await anim(t);
      await shot(t, 'mgr_09d_after_save');
      rectOf(t, 'mgr_09d_after_save', find.text('ქალაქის წისქვილი'), last: true);
      dumpTexts(t, 'saved');
      await tapText(t, 'ნაშთები');
      await anim(t);
      await shot(t, 'mgr_09e_stock');
      rectOf(t, 'mgr_09e_stock', find.text('ფქვილი'), last: true);
      final back = find.byTooltip("Back"); if (back.evaluate().isNotEmpty) { await t.tap(back.first); } else { t.state<NavigatorState>(find.byType(Navigator).last).maybePop(); } await anim(t);
      await tapIcon(t, Icons.book_online_rounded);
      await shot(t, 'mgr_07_reservations');
      rectOf(t, 'mgr_07_reservations', find.text('ლევან კაპანაძე'), last: true);
      await tapText(t, 'ლევან კაპანაძე');
      await anim(t);
      await shot(t, 'mgr_10_res_detail');
      rectOf(t, 'mgr_10_res_detail', find.text('დადასტურება'), last: true);
      dumpTexts(t, 'resdetail');
      await tapText(t, 'დადასტურება', last: true);
      await anim(t);
      await shot(t, 'mgr_11_res_confirmed');
      dumpTexts(t, 'resconf');
    }, managerMock);
    rectOf(t, 'nav_tables', find.byIcon(Icons.table_bar_rounded), last: true);
    rectOf(t, 'nav_inv', find.byIcon(Icons.inventory_2_outlined), last: true);
    rectOf(t, 'nav_res', find.byIcon(Icons.book_online_rounded), last: true);
    await t.runAsync(() => File('$capOut/mgr_rects.json').writeAsString(jsonEncode(rects)));
    print('REQ: ${requested.toSet().join(' | ')}');
    await t.pump(const Duration(seconds: 10));
  });
}
