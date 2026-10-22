import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/windows_pos/screens/pos_manager_registration_screen.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/auth/manager_activation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final credential =
      'vynic-device-v1.11111111-1111-4111-8111-111111111111.${'a' * 43}';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos-registration-test-');
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await EdgeDeviceCredentialStore.save(credential);
  });
  tearDown(() async {
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = null;
    await directory.delete(recursive: true);
  });
  test(
    'registration refuses missing Device identity before sending credentials',
    () async {
      EdgeDeviceCredentialStore.resetForTest();
      var requested = false;
      await expectLater(
        PosManagerRegistrationService.complete(
          code: 'synthetic-code',
          name: 'Synthetic manager',
          pin: '481259',
          requestId: 'synthetic-request',
          client: MockClient((_) async {
            requested = true;
            return http.Response('{}', 200);
          }),
        ),
        throwsA(isA<ActivationFailure>()),
      );
      expect(requested, isFalse);
    },
  );

  testWidgets('POS supplies a masked on-screen PIN pad', (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: PosManagerRegistrationScreen()),
    );
    await tester.tap(find.byTooltip('ახალი PIN — ეკრანის კლავიატურა'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.pump();
    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'ახალი PIN'),
    );
    expect(field.controller!.text, '4');
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'ახალი PIN'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.obscureText, isTrue);
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == '4'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'closing while activation is pending does not touch disposed controllers',
    (tester) async {
      final response = Completer<http.Response>();
      await tester.pumpWidget(
        MaterialApp(
          home: PosManagerRegistrationScreen(
            client: MockClient((_) => response.future),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'აქტივაციის კოდი'),
        'synthetic-code',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'თქვენი სახელი'),
        'Test manager',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'ახალი PIN'),
        '481259',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'გაიმეორეთ PIN'),
        '481259',
      );
      await tester.ensureVisible(find.text('აქტივაცია'));
      await tester.tap(find.text('აქტივაცია'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [375.0, 1024.0]) {
    testWidgets(
      'activation validates confirmation and retries with stable identity at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <Map<String, dynamic>>[];
        final client = MockClient((r) async {
          expect(r.url.path, '/edge/manager-activation');
          expect(r.headers['X-POS-Sync-Key'], credential);
          requests.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', requests.length == 1 ? 503 : 200);
        });
        await tester.pumpWidget(
          MaterialApp(home: PosManagerRegistrationScreen(client: client)),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'აქტივაციის კოდი'),
          'synthetic-code',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'თქვენი სახელი'),
          'Test manager',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'ახალი PIN'),
          '481259',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'გაიმეორეთ PIN'),
          '999999',
        );
        await tester.ensureVisible(find.text('აქტივაცია'));
        await tester.tap(find.text('აქტივაცია'));
        await tester.pumpAndSettle();
        expect(requests, isEmpty);
        expect(find.text('PIN არ ემთხვევა'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'გაიმეორეთ PIN'),
          '481259',
        );
        await tester.ensureVisible(find.text('აქტივაცია'));
        await tester.tap(find.text('აქტივაცია'));
        await tester.pumpAndSettle();
        expect(
          find.text('აქტივაცია ვერ დასრულდა. სცადეთ ხელახლა.'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('აქტივაცია'));
        await tester.tap(find.text('აქტივაცია'));
        await tester.pumpAndSettle();
        expect(requests, hasLength(2));
        expect(requests[0], requests[1]);
        expect(requests[0].containsKey('venueCode'), isFalse);
        expect(requests[0].containsKey('venueId'), isFalse);
        expect(find.text('აქტივაცია დასრულდა'), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'enrollment setup asks no extra code and retries with stable grant/request identity',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((r) async {
        expect(r.url.path, '/edge/manager-setup');
        requests.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response('{}', requests.length == 1 ? 503 : 200);
      });
      const id = '00000000-0000-4000-8000-000000000099';
      await tester.pumpWidget(
        MaterialApp(
          home: PosManagerRegistrationScreen(client: client, setupId: id),
        ),
      );
      expect(
        find.widgetWithText(TextFormField, 'აქტივაციის კოდი'),
        findsNothing,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'თქვენი სახელი'),
        'Synthetic manager',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'ახალი PIN'),
        '481259',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'გაიმეორეთ PIN'),
        '481259',
      );
      await tester.ensureVisible(find.text('აქტივაცია'));
      await tester.tap(find.text('აქტივაცია'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('აქტივაცია'));
      await tester.tap(find.text('აქტივაცია'));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(jsonEncode(requests[0]) == jsonEncode(requests[1]), isTrue);
      expect(requests[0].containsKey('code'), isFalse);
      expect(requests[0].containsKey('venueId'), isFalse);
      expect(requests[0]['setupId'], id);
      expect(requests[0]['requestId'], id);
      expect(find.text('აქტივაცია დასრულდა'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
