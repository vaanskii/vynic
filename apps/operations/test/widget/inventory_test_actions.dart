import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> reviewReceiving(WidgetTester tester) async {
  final next = find.byKey(const Key('receiving-next'));
  if (next.evaluate().isEmpty) return;
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

Future<void> openInventorySection(WidgetTester tester, String section) async {
  final target = find.byKey(Key('inventory-tab-$section'));
  if (target.evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('inventory-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}
