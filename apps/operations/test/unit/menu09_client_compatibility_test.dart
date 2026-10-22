import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/menu/menu_client_compatibility.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';
import 'package:vynic/core/services/edge/edge_enrollment_client.dart';

void main() {
  tearDown(() => MenuClientCompatibility.updateRequired.value = null);
  test(
    'current binary reports capability independently of installation state',
    () {
      expect(MenuClientCompatibility.report['capabilities'], [
        'CANONICAL_MENU_V2',
      ]);
      expect(MenuClientCompatibility.report.containsKey('deviceId'), false);
      expect(MenuClientCompatibility.report.containsKey('venueId'), false);
    },
  );
  test(
    'enrollment update-required is actionable and never returns a credential',
    () async {
      final c = EdgeEnrollmentClient(
        httpClient: MockClient((r) async {
          expect(
            (jsonDecode(r.body) as Map)['menuClient'],
            MenuClientCompatibility.report,
          );
          return http.Response('{"code":"MENU_UPDATE_REQUIRED"}', 426);
        }),
      );
      final result = await c.enroll(
        baseUrl: 'http://synthetic',
        code: 'synthetic',
        installationId: 'synthetic',
        platform: 'WINDOWS',
      );
      expect(result.outcome, EdgeEnrollmentOutcome.updateRequired);
      expect(result.isEnrolled, false);
      expect(result.credential, isNull);
      expect(result.message, MenuClientCompatibility.updateMessage);
      c.close();
    },
  );
  test(
    'Menu transport always reports current process and exposes typed refusal',
    () async {
      final t = HttpMenuSyncTransport(
        baseUrl: () => 'http://synthetic',
        credential: () => 'synthetic',
        client: MockClient((r) async {
          expect(
            jsonDecode(r.headers['X-Vynic-Menu-Client']!),
            MenuClientCompatibility.report,
          );
          return http.Response('{"code":"MENU_UPDATE_REQUIRED"}', 426);
        }),
      );
      final r = await t.catalog();
      expect(r.ok, false);
      expect(r.code, 'MENU_UPDATE_REQUIRED');
      expect(MenuClientCompatibility.updateRequired.value, isNotNull);
      t.close();
    },
  );
  test(
    'connectivity failure does not invent update requirement or clear a known refusal',
    () {
      MenuClientCompatibility.observe(0, null);
      expect(MenuClientCompatibility.updateRequired.value, isNull);
      MenuClientCompatibility.observe(426, {'code': 'MENU_UPDATE_REQUIRED'});
      MenuClientCompatibility.observe(0, null);
      expect(MenuClientCompatibility.updateRequired.value, isNotNull);
      MenuClientCompatibility.observe(200, {});
      expect(MenuClientCompatibility.updateRequired.value, isNull);
    },
  );
}
