import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/station_print_plan.dart';

String uid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
String hash(String value) => sha256.convert(utf8.encode(value)).toString();

Map<String, dynamic> fixture() => {
  'version': 1,
  'venueId': uid(1),
  'sourceDeviceId': uid(30),
  'revision': 1,
  'catalogDigest': hash('full'),
  'stations': [
    for (var i = 0; i < 4; i++)
      {
        'id': uid(50 + i),
        'name': ['Kitchen', 'Bar', 'Receipt', 'Other receipt'][i],
        'scope': i < 2 ? 'VENUE_SHARED' : 'LOCAL',
        'ownerDeviceId': i < 2 ? '' : uid(i == 2 ? 30 : 31),
        'enabled': true,
        'queueDigest': hash(i < 2 ? 'shared' : 'local$i'),
        'profile': {
          'protocol': 1,
          'paperWidthMm': 80,
          'rasterWidthDots': 576,
          'language': 'escposRaster',
          'cutter': 'partial',
          'encoding': 'georgianViaRaster',
        },
      },
  ],
  'rules': [
    {
      'kind': 'item',
      'matchId': 'khinkali',
      'stations': [uid(50)],
    },
    {
      'kind': 'category',
      'matchId': 'drinks',
      'stations': [uid(51)],
    },
  ],
};

StationRoutingCatalog decode(
  Map<String, dynamic> body, {
  String? venue,
  String? device,
}) {
  final raw = utf8.encode(jsonEncode(body));
  return StationRoutingCatalog.decode(
    raw: raw,
    expectedDigest: sha256.convert(raw).toString(),
    venueId: venue ?? uid(1),
    sourceDeviceId: device ?? uid(30),
  );
}

StationPrintPlan plan(
  StationRoutingCatalog catalog, {
  List<StationPrintLine>? lines,
  String effect = 'confirm-1',
  String orderType = 'dineIn',
}) => catalog.plan(
  effectId: effect,
  orderType: orderType,
  outputKind: 'production',
  businessRef: 'Order 1',
  createdAt: 1791800000000,
  lines:
      lines ??
      [
        StationPrintLine(id: 'line1', itemId: 'khinkali'),
        StationPrintLine(id: 'line2', itemId: 'beer', categoryId: 'drinks'),
      ],
);

Matcher failure(StationPlanningFailure reason) => throwsA(
  isA<StationPlanningException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  test('all ten source Devices have the same shared output identities', () {
    final expected = plan(
      decode(fixture()),
    ).tickets.map((t) => t.jobId).toList();
    for (var i = 0; i < 10; i++) {
      final body = fixture()..['sourceDeviceId'] = uid(100 + i);
      final result = plan(decode(body, device: uid(100 + i)));
      expect(result.tickets.map((t) => t.jobId), expected);
      expect(result.tickets.map((t) => t.station.id), [uid(50), uid(51)]);
      expect(result.tickets[0].lines.single.id, 'line1');
      expect(result.tickets[1].lines.single.id, 'line2');
    }
  });

  test('explicit fan-out sorts stations and preserves line order', () {
    final result = plan(
      decode(fixture()),
      lines: [
        StationPrintLine(id: 'a', stationIds: [uid(51), uid(50)]),
        StationPrintLine(id: 'b', stationIds: [uid(50)]),
      ],
    );
    expect(result.tickets.map((t) => t.station.id), [uid(50), uid(51)]);
    expect(result.tickets.first.lines.map((l) => l.id), ['a', 'b']);
    expect(result.tickets.last.lines.map((l) => l.id), ['a']);
  });

  test(
    'item, subcategory, category, default and order-specific precedence',
    () {
      final body = fixture();
      body['rules'] = [
        {
          'kind': 'default',
          'matchId': '',
          'stations': [uid(50)],
        },
        {
          'kind': 'category',
          'matchId': 'food',
          'stations': [uid(51)],
        },
        {
          'kind': 'subcategory',
          'matchId': 'hot',
          'stations': [uid(50)],
        },
        {
          'kind': 'item',
          'matchId': 'x',
          'stations': [uid(51)],
        },
        {
          'kind': 'item',
          'matchId': 'x',
          'orderType': 'takeaway',
          'stations': [uid(50)],
        },
      ];
      final catalog = decode(body);
      String target(
        String item,
        String sub,
        String cat, [
        String order = 'dineIn',
      ]) => plan(
        catalog,
        orderType: order,
        lines: [
          StationPrintLine(
            id: 'a',
            itemId: item,
            subcategoryId: sub,
            categoryId: cat,
          ),
        ],
      ).tickets.single.station.id;
      expect(target('x', 'hot', 'food'), uid(51));
      expect(target('x', 'hot', 'food', 'takeaway'), uid(50));
      expect(target('other', 'hot', 'food'), uid(50));
      expect(target('other', 'other', 'food'), uid(51));
      expect(target('other', 'other', 'other'), uid(50));
    },
  );

  test('own LOCAL and shared outputs retain different queue digests', () async {
    final result = plan(
      decode(fixture()),
      lines: [
        StationPrintLine(id: 'a', stationIds: [uid(50), uid(52)]),
      ],
    );
    final jobs = await result.freeze(render: (_) async => [1, 2, 3]);
    expect(jobs.map((j) => jsonDecode(utf8.decode(j.bytes))['configDigest']), [
      hash('shared'),
      hash('local2'),
    ]);
  });

  test('foreign LOCAL selection refuses the whole plan', () {
    expect(
      () => plan(
        decode(fixture()),
        lines: [
          StationPrintLine(id: 'a', stationIds: [uid(50), uid(53)]),
        ],
      ),
      failure(StationPlanningFailure.foreignLocalStation),
    );
  });

  test('disabled specific target does not fall back to default', () {
    final body = fixture();
    body['stations'][0]['enabled'] = false;
    (body['rules'] as List).add({
      'kind': 'default',
      'matchId': '',
      'stations': [uid(51)],
    });
    expect(
      () => plan(decode(body)),
      failure(StationPlanningFailure.stationUnavailable),
    );
  });

  test('unmapped and unknown explicit destinations fail closed', () {
    final catalog = decode(fixture());
    expect(
      () => plan(
        catalog,
        lines: [StationPrintLine(id: 'a', itemId: 'unknown')],
      ),
      failure(StationPlanningFailure.unmappedLine),
    );
    expect(
      () => plan(
        catalog,
        lines: [
          StationPrintLine(id: 'a', stationIds: [uid(99)]),
        ],
      ),
      failure(StationPlanningFailure.stationUnavailable),
    );
  });

  test('duplicate lines and explicit destinations are rejected', () {
    expect(
      () => StationPrintLine(id: 'a', stationIds: [uid(50), uid(50)]),
      failure(StationPlanningFailure.invalidInput),
    );
    expect(
      () => plan(
        decode(fixture()),
        lines: [
          StationPrintLine(id: 'a', itemId: 'khinkali'),
          StationPrintLine(id: 'a', itemId: 'khinkali'),
        ],
      ),
      failure(StationPlanningFailure.invalidInput),
    );
  });

  test('identity and content digest are checked independently', () {
    expect(
      () => decode(fixture(), venue: uid(2)),
      failure(StationPlanningFailure.identityMismatch),
    );
    expect(
      () => decode(fixture(), device: uid(31)),
      failure(StationPlanningFailure.identityMismatch),
    );
    expect(
      () => StationRoutingCatalog.decode(
        raw: utf8.encode(jsonEncode(fixture())),
        expectedDigest: hash('wrong'),
        venueId: uid(1),
        sourceDeviceId: uid(30),
      ),
      failure(StationPlanningFailure.invalidCatalog),
    );
  });

  for (final entry in <String, void Function(Map<String, dynamic>)>{
    'unknown field': (b) => b['activate'] = true,
    'future version': (b) => b['version'] = 2,
    'fraction revision': (b) => b['revision'] = 1.5,
    'duplicate station': (b) => (b['stations'] as List).add(b['stations'][0]),
    'duplicate rule': (b) => (b['rules'] as List).add(b['rules'][0]),
    'missing rule station': (b) => b['rules'][0]['stations'] = [uid(90)],
    'duplicate rule station': (b) =>
        b['rules'][0]['stations'] = [uid(50), uid(50)],
    'different shared digests': (b) =>
        b['stations'][1]['queueDigest'] = hash('other'),
    'shared owner': (b) => b['stations'][0]['ownerDeviceId'] = uid(30),
    'missing local owner': (b) => b['stations'][2]['ownerDeviceId'] = '',
    'unknown scope': (b) => b['stations'][0]['scope'] = 'AUTO',
    'unsupported renderer': (b) =>
        b['stations'][0]['profile']['language'] = 'windowsDriverRendered',
    'null order filter': (b) => b['rules'] = [
      <String, dynamic>{
        ...b['rules'][0] as Map<String, dynamic>,
        'orderType': null,
      },
    ],
    'unknown profile field': (b) =>
        b['stations'][0]['profile']['commands'] = 'raw',
  }.entries) {
    test('rejects ${entry.key}', () {
      final body = fixture();
      entry.value(body);
      expect(
        () => decode(body),
        failure(StationPlanningFailure.invalidCatalog),
      );
    });
  }

  test(
    'catalog, lines, plans and frozen bytes cannot be externally mutated',
    () async {
      final body = fixture();
      final catalog = decode(body);
      body['stations'][0]['enabled'] = false;
      final ids = [uid(50)];
      final line = StationPrintLine(id: 'a', stationIds: ids);
      ids.add(uid(51));
      final result = plan(catalog, lines: [line]);
      final payload = [1, 2, 3];
      var calls = 0;
      final first = result.freeze(
        render: (_) async {
          calls++;
          return payload;
        },
      );
      final second = result.freeze(
        render: (_) async => throw StateError('rendered twice'),
      );
      expect(identical(first, second), isTrue);
      final jobs = await first;
      payload[0] = 99;
      expect(calls, 1);
      expect(jsonDecode(utf8.decode(jobs.single.bytes))['payload'], 'AQID');
      expect(() => jobs.single.bytes[0] = 1, throwsUnsupportedError);
      expect(() => result.tickets.clear(), throwsUnsupportedError);
      expect(() => catalog.stations.clear(), throwsUnsupportedError);
      expect(() => line.stationIds.clear(), throwsUnsupportedError);
    },
  );

  for (final payload in <List<int>>[
    [],
    [-1],
    [256],
    List.filled(8 * 1024 * 1024 + 1025, 1),
  ]) {
    test(
      'invalid payload ${payload.length} never yields a partial job set',
      () async {
        final result = plan(decode(fixture()));
        var calls = 0;
        await expectLater(
          result.freeze(render: (_) async => ++calls == 1 ? [1] : payload),
          failure(StationPlanningFailure.invalidPayload),
        );
        expect(calls, 2);
      },
    );
  }

  test(
    'render failure remains an error and cannot regenerate this plan',
    () async {
      final result = plan(decode(fixture()));
      var calls = 0;
      final attempt = result.freeze(
        render: (_) async {
          calls++;
          throw StateError('render');
        },
      );
      await expectLater(attempt, throwsStateError);
      await expectLater(
        result.freeze(render: (_) async => [1]),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test('labels use UTF-8 byte limits and reject invalid Unicode', () {
    expect(
      () => plan(decode(fixture()), effect: List.filled(54, 'ა').join()),
      failure(StationPlanningFailure.invalidInput),
    );
    expect(
      () => StationPrintLine(id: '\ud800'),
      failure(StationPlanningFailure.invalidInput),
    );
  });
}
