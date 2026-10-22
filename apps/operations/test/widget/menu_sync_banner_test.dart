import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/menu_sync_banner.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';
import 'package:vynic/core/services/menu/pos_menu_sync_service.dart';

MenuMutationEntry _entry({
  MenuMutationStatus status = MenuMutationStatus.conflict,
  Map<String, dynamic>? conflict,
  String? lastError,
}) => MenuMutationEntry(
  seq: 1,
  mutationId: 'm-1',
  venueId: 'venue-a',
  entityType: 'ITEM',
  operation: 'UPSERT',
  entityId: 'item-1',
  expectedRevision: 42,
  patch: {'price': 21.0},
  status: status,
  createdAt: DateTime.utc(2026, 9, 28),
  conflict: conflict,
  lastError: lastError,
);

void main() {
  final status = PosMenuSyncService.instance.status;
  tearDown(() => status.value = const MenuSyncStatus());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: MenuSyncBanner())),
  );

  testWidgets('routine sync (pending while offline) stays silent', (
    tester,
  ) async {
    status.value = const MenuSyncStatus(
      mode: MenuSyncMode.canonical,
      pending: 3,
      reachable: false,
    );
    await pump(tester);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('a conflict explains itself with current vs pending values', (
    tester,
  ) async {
    status.value = MenuSyncStatus(
      mode: MenuSyncMode.canonical,
      attention: [
        _entry(
          conflict: {
            'currentRevision': 43,
            'deleted': false,
            'current': {'nameKa': 'ხინკალი', 'price': 22.0},
          },
        ),
      ],
    );
    await pump(tester);
    expect(
      find.text('ეს პროდუქტი სხვა მოწყობილობაზე შეიცვალა.'),
      findsOneWidget,
    );
    expect(find.text('ხინკალი'), findsOneWidget);
    expect(find.text('22.00 ₾'), findsOneWidget);
    expect(find.text('21.00 ₾'), findsOneWidget);
    expect(find.text('მიმდინარეს გამოყენება'), findsOneWidget);
    expect(find.text('ჩემი ცვლილების ხელახლა გამოყენება'), findsOneWidget);
    expect(find.textContaining('409'), findsNothing);
  });

  testWidgets('a deletion elsewhere offers only keeping the current state', (
    tester,
  ) async {
    status.value = MenuSyncStatus(
      mode: MenuSyncMode.canonical,
      attention: [
        _entry(
          conflict: {'currentRevision': 43, 'deleted': true, 'current': null},
        ),
      ],
    );
    await pump(tester);
    expect(
      find.text('ეს პროდუქტი სხვა მოწყობილობაზე წაიშალა.'),
      findsOneWidget,
    );
    expect(find.text('ჩემი ცვლილების ხელახლა გამოყენება'), findsNothing);
  });

  testWidgets('a different local menu is never replaced without confirmation', (
    tester,
  ) async {
    status.value = const MenuSyncStatus(mode: MenuSyncMode.adoptionBlocked);
    await pump(tester);
    await tester.tap(find.text('Cloud მენიუს გამოყენება'));
    await tester.pumpAndSettle();
    expect(find.text('ჩანაცვლება'), findsOneWidget);
    await tester.tap(find.text('გაუქმება'));
    await tester.pumpAndSettle();
    expect(status.value.mode, MenuSyncMode.adoptionBlocked);
  });
}
