import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/printer_agent_profile.dart';
import 'package:vynic/core/services/printing/printer_agent_runtime_profile.dart';
import 'package:vynic/core/services/security/developer_access.dart';

import '../support/pos02_developer_fixture.dart';
import '../support/pos02_fixture.dart';
import '../support/printer_agent_status_fixture.dart';

String _fixturePath(Directory directory, String child) =>
    File.fromUri(directory.uri.resolve(child)).path;

class _Connection implements PrinterAgentRuntimeConnection {
  _Connection(this.result);
  final Future<PrinterAgentHealth> Function() result;
  int calls = 0, closes = 0;
  @override
  Future<PrinterAgentHealth> health() {
    calls++;
    return result();
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  late Directory root;
  late Pos02Fixture fixture;
  late Map<String, dynamic> json;
  late File profile;
  late _Connection connection;
  late PrinterAgentRuntimeBinding binding;
  late int connects;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_agent_profile_unit_');
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed();
    await unlockSyntheticPrinterDeveloper();
    binding = agentBinding;
    connects = 0;
    connection = _Connection(() async => agentHealth());
    // Digest/IO seam only: these short synthetic PEM bytes are not valid X509
    // credentials. The separate real mTLS fixture uses real certificates.
    const der = [1, 2, 3, 4, 5];
    final pem =
        '-----BEGIN CERTIFICATE-----\n${base64.encode(der)}\n-----END CERTIFICATE-----\n';
    await File(_fixturePath(root, 'server.pem')).writeAsString(pem);
    await File(_fixturePath(root, 'client.pem')).writeAsString(pem);
    await File(
      _fixturePath(root, 'client-key.pem'),
    ).writeAsString('SYNTHETIC_UNIT_KEY_NO_CERTIFICATE_AUTHORITY');
    json = {
      'version': 1,
      'provisionStatus': 'HELD_PROVISIONING',
      'listenAddress': '127.0.0.1:43123',
      'clientId': agentClient,
      'currentDeviceInstallationId': agentDeviceInstallation,
      'pins': agentPins().toJson(),
      'serverCertificatePath': _fixturePath(root, 'server.pem'),
      'serverCertificateSha256': sha256.convert(der).toString(),
      'clientCertificatePath': _fixturePath(root, 'client.pem'),
      'clientPrivateKeyPath': _fixturePath(root, 'client-key.pem'),
      'clientCertificateSha256': sha256.convert(der).toString(),
    };
    profile = File(_fixturePath(root, 'profile.json'));
    await profile.writeAsString(jsonEncode(json));
  });
  tearDown(() async {
    DeveloperAccess.resetForTest();
    DeveloperAccess.publicKeyOverride = null;
    await fixture.close();
    await root.delete(recursive: true);
  });

  PrinterAgentRuntimeProfile source({String? name}) =>
      PrinterAgentRuntimeProfile(
        profilePath: name ?? profile.path,
        bindingReader: () => binding,
        connector: (configured, certificate, key) {
          connects++;
          expect(configured.pins.matches(agentPins()), isTrue);
          expect(configured.port, 43123);
          expect(configured.clientId, agentClient);
          expect(configured.expectedInstallationId, agentDeviceInstallation);
          expect(configured.expectedAgentInstallationId, agentInstallation);
          expect(certificate, isNotEmpty);
          expect(key, isNotEmpty);
          return connection;
        },
      );
  Matcher runtimeFailure(PrinterAgentRuntimeFailure reason) =>
      isA<PrinterAgentRuntimeException>().having(
        (e) => e.reason,
        'reason',
        reason,
      );
  Matcher invalidProfile() => anyOf(
    runtimeFailure(PrinterAgentRuntimeFailure.invalidProfile),
    isA<PrinterAgentException>().having(
      (e) => e.reason,
      'reason',
      PrinterAgentFailure.invalidProfile,
    ),
  );

  test(
    'empty explicit flag is neutral and performs no IO or connection',
    () async {
      final reader = source(name: '');
      expect(reader.isConfigured, isFalse);
      await expectLater(
        reader.health(),
        throwsA(runtimeFailure(PrinterAgentRuntimeFailure.notConfigured)),
      );
      expect(connects, 0);
    },
  );

  test(
    'strict profile passes explicit pins and closes the read-only connection',
    () async {
      final health = await source().health();
      expect(health.pins.matches(agentPins()), isTrue);
      expect(health.physicalHeld, isTrue);
      expect(health.admissionHeld, isTrue);
      expect(connects, 1);
      expect(connection.calls, 1);
      expect(connection.closes, 1);
      expect(fixture.connections, 0);
    },
  );

  for (final field in ['device', 'venue', 'installation']) {
    test(
      'foreign $field is held before credential files or connection',
      () async {
        json['pins'] = agentPins(
          device: field == 'device' ? agentOther : agentDevice,
          venue: field == 'venue' ? agentOther : agentVenue,
          installation: agentInstallation,
        ).toJson();
        if (field == 'installation')
          json['currentDeviceInstallationId'] = agentOther;
        json['clientPrivateKeyPath'] = _fixturePath(
          root,
          'not-present-key.pem',
        );
        await profile.writeAsString(jsonEncode(json));
        await expectLater(
          source().health(),
          throwsA(runtimeFailure(PrinterAgentRuntimeFailure.bindingMismatch)),
        );
        expect(connects, 0);
      },
    );
  }

  for (final field in ['device', 'venue', 'installation']) {
    test('missing active $field never invents a binding', () async {
      binding = PrinterAgentRuntimeBinding(
        deviceId: field == 'device' ? null : agentDevice,
        venueId: field == 'venue' ? null : agentVenue,
        deviceInstallationId: field == 'installation'
            ? null
            : agentDeviceInstallation,
        loaded: true,
        enrolled: true,
      );
      final reason = switch (field) {
        'device' => PrinterAgentRuntimeFailure.missingDevice,
        'venue' => PrinterAgentRuntimeFailure.missingVenue,
        _ => PrinterAgentRuntimeFailure.missingInstallation,
      };
      await expectLater(source().health(), throwsA(runtimeFailure(reason)));
      expect(connects, 0);
    });
  }

  test(
    'revoked developer scope refuses even a missing profile before IO',
    () async {
      DeveloperAccess.lock();
      await expectLater(
        source(name: _fixturePath(root, 'missing.json')).health(),
        throwsA(runtimeFailure(PrinterAgentRuntimeFailure.scopeDenied)),
      );
      expect(connects, 0);
    },
  );

  for (final address in [
    'localhost:43123',
    '0.0.0.0:43123',
    '192.0.2.1:43123',
    '127.0.0.1:0',
    '127.0.0.1:65536',
    '127.0.0.1:043123',
  ]) {
    test('noncanonical/nonloopback address $address refuses', () async {
      json['listenAddress'] = address;
      await profile.writeAsString(jsonEncode(json));
      await expectLater(source().health(), throwsA(invalidProfile()));
      expect(connects, 0);
    });
  }

  test(
    'unknown or activated provision state refuses rather than enabling',
    () async {
      json['provisionStatus'] = 'ACTIVE';
      await profile.writeAsString(jsonEncode(json));
      await expectLater(source().health(), throwsA(invalidProfile()));
      expect(connects, 0);
    },
  );

  test('extra CA fallback and authority fields refuse', () async {
    for (final key in ['serverCAPath', 'tenantId', 'activate']) {
      final candidate = {...json, key: 'unexpected'};
      await profile.writeAsString(jsonEncode(candidate));
      await expectLater(source().health(), throwsA(invalidProfile()));
    }
    expect(connects, 0);
  });

  test('duplicate keys including escaped spellings refuse', () async {
    for (final duplicate in [
      '"version":1,"version":1',
      r'"version":1,"v\u0065rsion":1',
    ]) {
      await profile.writeAsString(
        jsonEncode(json).replaceFirst('"version":1', duplicate),
      );
      await expectLater(source().health(), throwsA(invalidProfile()));
    }
    expect(connects, 0);
  });

  test('invalid UTF8 and oversize/deep JSON are bounded and refused', () async {
    await profile.writeAsBytes([0xff]);
    await expectLater(source().health(), throwsA(invalidProfile()));
    await profile.writeAsString('${' ' * (64 * 1024 + 1)}${jsonEncode(json)}');
    await expectLater(source().health(), throwsA(invalidProfile()));
    await profile.writeAsString('${'{"nested":' * 16}1${'}' * 16}');
    await expectLater(source().health(), throwsA(invalidProfile()));
    expect(connects, 0);
  });

  test('float version, arrays and unknown nested pin keys refuse', () async {
    for (final change in [
      {...json, 'version': 1.0},
      {...json, 'pins': []},
      {
        ...json,
        'pins': {...agentPins().toJson(), 'tenantId': agentVenue},
      },
    ]) {
      await profile.writeAsString(jsonEncode(change));
      await expectLater(source().health(), throwsA(invalidProfile()));
    }
    expect(connects, 0);
  });

  test('relative profile/credential paths are held without fallback', () async {
    await expectLater(
      source(name: 'profile.json').health(),
      throwsA(invalidProfile()),
    );
    json['clientPrivateKeyPath'] = 'client-key.pem';
    await profile.writeAsString(jsonEncode(json));
    await expectLater(source().health(), throwsA(invalidProfile()));
    expect(connects, 0);
  });

  test('explicit certificate hashes must match exact leaf DER', () async {
    json['serverCertificateSha256'] = 'f' * 64;
    await profile.writeAsString(jsonEncode(json));
    await expectLater(source().health(), throwsA(invalidProfile()));
    expect(connects, 0);
  });

  test('symlinked key or directory escape is refused', () async {
    final outside = await Directory.systemTemp.createTemp(
      'vynic_agent_profile_outside_',
    );
    addTearDown(() => outside.delete(recursive: true));
    await File(
      _fixturePath(outside, 'key.pem'),
    ).writeAsString('OUTSIDE_SYNTHETIC');
    await Link(
      _fixturePath(root, 'linked-key.pem'),
    ).create(_fixturePath(outside, 'key.pem'));
    json['clientPrivateKeyPath'] = _fixturePath(root, 'linked-key.pem');
    await profile.writeAsString(jsonEncode(json));
    await expectLater(
      source().health(),
      throwsA(isA<PrinterAgentRuntimeException>()),
    );
    await Link(_fixturePath(root, 'escape')).create(outside.path);
    json['clientPrivateKeyPath'] = _fixturePath(root, 'escape/key.pem');
    await profile.writeAsString(jsonEncode(json));
    await expectLater(source().health(), throwsA(invalidProfile()));
    expect(connects, 0);
  });

  test('identity and scope are rechecked after actual async seam', () async {
    connection = _Connection(() async {
      binding = const PrinterAgentRuntimeBinding(
        deviceId: agentOther,
        venueId: agentVenue,
        deviceInstallationId: agentDeviceInstallation,
        loaded: true,
        enrolled: true,
      );
      return agentHealth();
    });
    await expectLater(
      source().health(),
      throwsA(runtimeFailure(PrinterAgentRuntimeFailure.bindingMismatch)),
    );
    expect(connection.closes, 1);
    binding = agentBinding;
    connection = _Connection(() async {
      DeveloperAccess.lock();
      return agentHealth();
    });
    await expectLater(
      source().health(),
      throwsA(runtimeFailure(PrinterAgentRuntimeFailure.scopeDenied)),
    );
    expect(connection.closes, 1);
  });

  test(
    'profile revision changed during health invalidates old response',
    () async {
      connection = _Connection(() async {
        json['pins'] = agentPins(configRevision: 2).toJson();
        await profile.writeAsString(jsonEncode(json));
        return agentHealth();
      });
      await expectLater(
        source().health(),
        throwsA(runtimeFailure(PrinterAgentRuntimeFailure.profileChanged)),
      );
      expect(connection.closes, 1);
    },
  );

  test(
    'credential file changed during health invalidates old response',
    () async {
      connection = _Connection(() async {
        await File(
          _fixturePath(root, 'client-key.pem'),
        ).writeAsString('CHANGED_SYNTHETIC_KEY');
        return agentHealth();
      });
      await expectLater(
        source().health(),
        throwsA(runtimeFailure(PrinterAgentRuntimeFailure.profileChanged)),
      );
      expect(connection.closes, 1);
    },
  );

  test(
    'changed returned configuration pin and typed auth failure both close',
    () async {
      connection = _Connection(
        () async => agentHealth(pins: agentPins(configRevision: 2)),
      );
      await expectLater(
        source().health(),
        throwsA(
          isA<PrinterAgentException>().having(
            (e) => e.reason,
            'reason',
            PrinterAgentFailure.profileMismatch,
          ),
        ),
      );
      expect(connection.closes, 1);
      connection = _Connection(
        () async => throw const PrinterAgentException(
          PrinterAgentFailure.authentication,
        ),
      );
      await expectLater(
        source().health(),
        throwsA(
          isA<PrinterAgentException>().having(
            (e) => e.reason,
            'reason',
            PrinterAgentFailure.authentication,
          ),
        ),
      );
      expect(connection.closes, 1);
      expect(fixture.connections, 0);
    },
  );
  test(
    'distinct POS and Go installation IDs are explicit, never inferred',
    () async {
      expect(agentDeviceInstallation, isNot(agentInstallation));
      final health = await source().health();
      expect(health.pins.installationId, agentInstallation);
      expect(binding.deviceInstallationId, agentDeviceInstallation);
      expect(connects, 1);
    },
  );

  test(
    'missing or malformed explicit POS installation field refuses',
    () async {
      for (final value in [null, agentInstallation, 42, 'not-a-uuid']) {
        final candidate = {...json};
        if (value == null) {
          candidate.remove('currentDeviceInstallationId');
        } else {
          candidate['currentDeviceInstallationId'] = value;
        }
        await profile.writeAsString(jsonEncode(candidate));
        await expectLater(
          source().health(),
          throwsA(isA<PrinterAgentRuntimeException>()),
        );
      }
      expect(connects, 0);
    },
  );

  test(
    'restoration and transition guards refuse before any connection',
    () async {
      for (final restore in [false, true]) {
        binding = PrinterAgentRuntimeBinding(
          deviceId: agentDevice,
          venueId: agentVenue,
          deviceInstallationId: agentDeviceInstallation,
          loaded: true,
          enrolled: true,
          changing: !restore,
          restorationHeld: restore,
        );
        await expectLater(
          source().health(),
          throwsA(
            runtimeFailure(
              restore
                  ? PrinterAgentRuntimeFailure.restorationHeld
                  : PrinterAgentRuntimeFailure.identityChanging,
            ),
          ),
        );
      }
      expect(connects, 0);
    },
  );

  test(
    'POS installation changes during health while Go identity stays fixed',
    () async {
      connection = _Connection(() async {
        binding = const PrinterAgentRuntimeBinding(
          deviceId: agentDevice,
          venueId: agentVenue,
          deviceInstallationId: agentOther,
          loaded: true,
          enrolled: true,
        );
        return agentHealth();
      });
      await expectLater(
        source().health(),
        throwsA(runtimeFailure(PrinterAgentRuntimeFailure.bindingMismatch)),
      );
      expect(connection.closes, 1);
    },
  );

  test(
    'restore starts during health and suppresses the previous response',
    () async {
      connection = _Connection(() async {
        binding = const PrinterAgentRuntimeBinding(
          deviceId: agentDevice,
          venueId: agentVenue,
          deviceInstallationId: agentDeviceInstallation,
          loaded: true,
          enrolled: true,
          restorationHeld: true,
        );
        return agentHealth();
      });
      await expectLater(
        source().health(),
        throwsA(runtimeFailure(PrinterAgentRuntimeFailure.restorationHeld)),
      );
      expect(connection.closes, 1);
    },
  );
}
