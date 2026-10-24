import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/non_fiscal_close_grant.dart';

class _Age implements Stopwatch {
  Duration value = Duration.zero;
  @override
  Duration get elapsed => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'grant is identity bound and expires on monotonic age, including offline',
    () {
      final age = _Age();
      final grant = NonFiscalCloseGrant(
        deviceId: 'device-a',
        venueId: 'venue-a',
        age: age,
      );
      expect(grant.allows('device-a', 'venue-a'), true);
      expect(grant.allows('device-b', 'venue-a'), false);
      expect(grant.allows('device-a', 'venue-b'), false);
      expect(grant.allows(null, null), false);
      age.value =
          NonFiscalCloseGrant.lifetime - const Duration(microseconds: 1);
      expect(grant.allows('device-a', 'venue-a'), true);
      age.value = NonFiscalCloseGrant.lifetime;
      expect(grant.allows('device-a', 'venue-a'), false);
      age.value = const Duration(days: 1);
      expect(grant.allows('device-a', 'venue-a'), false);
    },
  );
}
