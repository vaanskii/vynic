import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/non_fiscal_close_grant.dart';

void main() {
  const credential = 'synthetic-current-credential';
  final grant = NonFiscalCloseGrant(
    deviceId: 'device-a',
    venueId: 'venue-a',
    installationId: 'installation-a',
    credentialFingerprint: NonFiscalCloseGrant.fingerprint(credential),
    enabled: true,
  );
  bool allows(
    NonFiscalCloseGrant? value, {
    String? device = 'device-a',
    String? venue = 'venue-a',
    String? installation = 'installation-a',
    String? key = credential,
  }) =>
      value?.allows(
        device: device,
        venue: venue,
        installation: installation,
        credential: key,
      ) ==
      true;
  test(
    'durable explicit grant is bound to Device, Venue, installation and credential',
    () {
      expect(allows(NonFiscalCloseGrant.fromMap(grant.toMap())), true);
      expect(allows(grant, device: 'device-b'), false);
      expect(allows(grant, venue: 'venue-b'), false);
      expect(allows(grant, installation: 'installation-b'), false);
      expect(allows(grant, key: 'rotated-credential'), false);
      expect(allows(grant, device: null), false);
      expect(allows(grant, key: null), false);
    },
  );
  test(
    'missing, malformed, legacy or disabled authority cannot grant access',
    () {
      for (final raw in [
        null,
        ['NON_FISCAL_CLOSE'],
        {},
        {...grant.toMap(), 'version': 0},
        {...grant.toMap(), 'enabled': 'true'},
        {...grant.toMap(), 'venueId': ''},
        {...grant.toMap(), 'enabled': false},
      ]) {
        expect(allows(NonFiscalCloseGrant.fromMap(raw)), false);
      }
    },
  );
  test('wall clock metadata cannot enable or extend a disabled decision', () {
    for (final timestamp in ['1900-01-01T00:00:00Z', '2999-01-01T00:00:00Z']) {
      final raw = {
        ...grant.toMap(),
        'enabled': false,
        'observedAt': timestamp,
        'expiresAt': timestamp,
      };
      expect(allows(NonFiscalCloseGrant.fromMap(raw)), false);
    }
  });
}
