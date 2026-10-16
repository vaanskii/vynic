import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/quick_order_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/pos/quick_checkout_service.dart';
import 'package:vynic/core/services/pos/table_payment_service.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_checkout_estimates_');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-15T00:00:00.000',
      'lastOrderId': 0,
      'serviceFeeEnabled': false,
      'serviceFeePercent': 0.0,
    });
  });
  tearDown(() async {
    PosSession.clear();
    await fixture.close();
    await dir.delete(recursive: true);
  });
  OrderItem line() => OrderItem(
    itemKey: 'synthetic',
    itemName: 'Synthetic item',
    unitPrice: 10,
    quantity: 1,
    total: 10,
    menuItemId: 'synthetic-menu',
  );
  const cash = TablePaymentSelection(
    method: TablePaymentMethod.cash,
    cashAmount: 10,
    bankAmount: 0,
  );
  Future<void> session(String role) async {
    final user = User(username: 'synthetic', pinCode: '0000', role: role);
    await DatabaseCore.userBox!.put('synthetic', user);
    PosSession.start(user);
  }

  Future<dynamic> estimate() => QuickOrderRepository.saveQuickOrderDraft(
    createdBy: 'synthetic',
    items: [line()],
    subtotal: 10,
    includeServiceFee: false,
    serviceFeeRate: 0,
    customerName: '  თამარ მელაძე  ',
    customerPhone: '555 123 456',
  );

  test(
    'quick checkout creates no physical table and retry/concurrent taps produce one sale',
    () async {
      Future<dynamic> settle() => QuickCheckoutService.settle(
        requestId: 'synthetic-checkout',
        actor: 'synthetic',
        items: [line()],
        payment: cash,
      );
      final results = await Future.wait([settle(), settle()]);
      expect(results.every((r) => r.isSuccess as bool), isTrue);
      expect(DatabaseCore.tableBox!.values, isEmpty);
      expect(DatabaseCore.reservationBox!.values, isEmpty);
      expect(DatabaseCore.orderBox!.values, hasLength(1));
      expect(DatabaseCore.orderBox!.values.single.status, 'closed');
      expect(
        DatabaseCore.salesBox!.values.where(
          (s) => SalesRepository.countsAsRevenue(s as Map),
        ),
        hasLength(1),
      );
      expect((DatabaseCore.salesBox!.values.single as Map)['totalAmount'], 10);
    },
  );
  test('invalid quick tender cannot create an order or sale', () async {
    await expectLater(
      QuickCheckoutService.settle(
        requestId: 'bad',
        actor: 'synthetic',
        items: [line()],
        payment: const TablePaymentSelection(
          method: TablePaymentMethod.cash,
          cashAmount: 9,
          bankAmount: 0,
        ),
      ),
      throwsArgumentError,
    );
    expect(DatabaseCore.orderBox!.values, isEmpty);
    expect(DatabaseCore.salesBox!.values, isEmpty);
  });
  test(
    'interruption after creation can resume the same quick checkout without another order',
    () async {
      await OrderRepository.createTakeAwayOrder(
        customerName: 'სწრაფი გაყიდვა',
        customerPhone: '',
        pickupTime: '',
        items: [line()],
        createdBy: 'synthetic',
        requestId: 'resume',
      );
      final result = await QuickCheckoutService.settle(
        requestId: 'resume',
        actor: 'synthetic',
        items: [line()],
        payment: cash,
      );
      expect(result.isSuccess, isTrue);
      expect(DatabaseCore.orderBox!.values, hasLength(1));
      expect(DatabaseCore.salesBox!.values, hasLength(1));
    },
  );
  test(
    'estimate contacts survive ordinary item updates and Hive reopen; search is real',
    () async {
      final saved = await estimate();
      await QuickOrderRepository.updateQuickOrderDraft(
        id: saved.id as String,
        createdBy: 'synthetic',
        items: [line()],
        subtotal: 10,
        includeServiceFee: false,
        serviceFeeRate: 0,
      );
      await fixture.close();
      await fixture.open(dir.path);
      final draft = QuickOrderRepository.getQuickOrderDraft(
        saved.id as String,
      )!;
      expect(draft.customerName, 'თამარ მელაძე');
      expect(draft.customerPhone, '555 123 456');
      for (final query in [
        'მელაძე',
        '555123456',
        '555-123-456',
        '10',
        '10,00',
      ]) {
        expect(draft.matchesSearch(query), isTrue, reason: query);
      }
      expect(draft.matchesSearch('11.00'), isFalse);
      expect(draft.matchesSearch('სხვა ადამიანი'), isFalse);
    },
  );
  test(
    'supervisor, waiter and signed-out calls cannot delete or clear estimates',
    () async {
      final draft = await estimate();
      for (final role in ['supervisor', 'waiter']) {
        await session(role);
        await expectLater(
          QuickOrderRepository.deleteQuickOrderDraft(draft.id as String),
          throwsStateError,
        );
        await expectLater(
          QuickOrderRepository.clearQuickOrderDrafts(),
          throwsStateError,
        );
      }
      PosSession.clear();
      await expectLater(
        QuickOrderRepository.deleteQuickOrderDraft(draft.id as String),
        throwsStateError,
      );
      expect(QuickOrderRepository.getQuickOrderDrafts(), hasLength(1));
    },
  );
  test(
    'manager authority is re-read from storage; stale manager session cannot delete',
    () async {
      final draft = await estimate();
      await session('manager');
      await DatabaseCore.userBox!.put(
        'synthetic',
        User(username: 'synthetic', pinCode: '0000', role: 'supervisor'),
      );
      await expectLater(
        QuickOrderRepository.deleteQuickOrderDraft(draft.id as String),
        throwsStateError,
      );
      await session('manager');
      await QuickOrderRepository.deleteQuickOrderDraft(draft.id as String);
      expect(QuickOrderRepository.getQuickOrderDrafts(), isEmpty);
    },
  );
}
