import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/package.dart';

void main() {
  test('OrderItem JSON round trip preserves identity and frozen values', () {
    final line = OrderItem(
      itemKey: 'khinkali',
      itemName: 'Khinkali',
      unitPrice: 2.5,
      quantity: 4,
      total: 10,
      comment: 'No pepper',
      menuItemId: 'menu-khinkali',
      variantId: 'variant-ten',
    );

    final restored = OrderItem.fromJson(line.toJson());
    expect(restored.menuItemId, 'menu-khinkali');
    expect(restored.variantId, 'variant-ten');
    expect(restored.itemName, 'Khinkali');
    expect(restored.unitPrice, 2.5);
    expect(restored.comment, 'No pepper');
  });

  test('legacy and manual Order lines remain valid without identity', () {
    final legacy = OrderItem.fromJson({
      'name': 'Manual corkage',
      'price': 5,
      'quantity': 1,
    });

    expect(legacy.menuItemId, isNull);
    expect(legacy.variantId, isNull);
    expect(legacy.itemName, 'Manual corkage');
    expect(legacy.total, 5);
  });

  test('live Menu changes cannot rewrite an Order or Package snapshot', () {
    final menu = MenuItemDB.create(
      translationsEn: {'name': 'Khinkali'},
      translationsKa: {'name': 'ხინკალი'},
      price: 2.5,
    );
    final orderLine = OrderItem(
      itemKey: 'khinkali',
      itemName: menu.translationsEn['name']!,
      unitPrice: menu.price!,
      quantity: 1,
      total: menu.price!,
      menuItemId: menu.id,
    );
    final packageLine = PackageItem(
      itemKey: 'khinkali',
      itemName: menu.translationsEn['name']!,
      unitPrice: menu.price!,
      quantity: 10,
      menuItemId: menu.id,
    );

    menu.translationsEn = {'name': 'Royal Khinkali'};
    menu.price = 3;

    expect(orderLine.menuItemId, menu.id);
    expect(orderLine.itemName, 'Khinkali');
    expect(orderLine.unitPrice, 2.5);
    expect(packageLine.menuItemId, menu.id);
    expect(packageLine.itemName, 'Khinkali');
    expect(packageLine.unitPrice, 2.5);
  });
}
