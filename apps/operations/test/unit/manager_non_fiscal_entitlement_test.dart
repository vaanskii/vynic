import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';

void main() {
  tearDown(ManagerEntitlements.clear);
  test('missing, malformed and disabled Manager snapshots fail closed', () {
    ManagerEntitlements.clear();
    expect(ManagerEntitlements.has(FeatureKeys.nonFiscalClose), false);
    for (final snapshot in <Map<String, dynamic>>[
      {},
      {'features': 'NON_FISCAL_CLOSE'},
      {
        'features': [FeatureKeys.nonFiscalClose, 1],
      },
      {
        'features': [FeatureKeys.nonFiscalClose],
        'commercialAccess': false,
      },
    ]) {
      ManagerEntitlements.apply({
        'features': [FeatureKeys.nonFiscalClose],
      });
      ManagerEntitlements.apply(snapshot);
      expect(ManagerEntitlements.has(FeatureKeys.nonFiscalClose), false);
    }
  });
  testWidgets(
    'explicit session access survives an outage until a server revocation or logout',
    (tester) async {
      ManagerEntitlements.apply({
        'features': [FeatureKeys.pos, FeatureKeys.nonFiscalClose],
      });
      expect(ManagerEntitlements.has(FeatureKeys.nonFiscalClose), true);
      await tester.pump(const Duration(days: 1));
      expect(ManagerEntitlements.has(FeatureKeys.nonFiscalClose), true);
      ManagerEntitlements.apply({
        'features': [FeatureKeys.pos],
      });
      expect(ManagerEntitlements.has(FeatureKeys.nonFiscalClose), false);
      expect(ManagerEntitlements.has(FeatureKeys.pos), true);
      ManagerEntitlements.clear();
    },
  );
}
