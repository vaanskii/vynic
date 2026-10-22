import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_transport.dart';
import '../../tool/pos02_acceptance_ledger.dart';
import '../support/pos02_acceptance_runner.dart';
import '../../tool/pos02_acceptance_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  late DateTime now;
  DateTime Function()? boundaryClock;
  Pos02AcceptanceSession? session;
  AcceptanceLedger? standalone;
  int nextId = 0;
  AcceptanceWindow window({
    String? id,
    String? actionId,
    String? jobId,
    bool copy = false,
    int allowance = 0,
    String target = 'kitchen',
    String host = '10.10.10.5',
  }) {
    final identity = id ?? 'pos02-window-${nextId++}';
    final action = actionId ?? '$identity-action';
    return AcceptanceWindow({
      'protocol': 1,
      'baseCandidate': pos02BaseCandidate,
      'candidateSha256': 'a' * 64,
      'windowId': identity,
      'approval': 'SYNTHETIC TEST ONLY; no physical authorization',
      'startsAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(minutes: 1)).toIso8601String(),
      'allowance': allowance,
      'host': host,
      'port': 9100,
      'target': target,
      'model': 'SYNTHETIC; not qualified',
      'firmware': 'SYNTHETIC',
      'paperMm': 80,
      'action': copy ? 'copy' : 'original',
      'actionId': action,
      'jobId': jobId ?? action,
    });
  }

  Directory getRoot() => Directory('${temp.path}/owned');
  Future<Pos02AcceptanceSession> open(
    AcceptanceWindow spec, {
    bool physical = false,
    Future<PrinterWriteSocket> Function(String, int)? connector,
    Future<List<int>> Function(PrintQueueTarget)? render,
    bool actualRender = false,
  }) async => session = await Pos02AcceptanceSession.open(
    root: getRoot(),
    window: spec,
    executePhysical: physical,
    clock: () => boundaryClock?.call() ?? now,
    connectorForTest: connector,
    renderForTest: actualRender || physical
        ? null
        : render ?? (_) async => ascii.encode('SYNTHETIC RASTER'),
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp(
      'vynic_pos02_acceptance_test_',
    );
    now = DateTime.utc(2026, 10, 2, 12);
    boundaryClock = null;
    messenger.setMockMethodCallHandler(
      paths,
      (_) async =>
          throw StateError('Runner must not resolve ordinary app data'),
    );
  });
  tearDown(() async {
    await session?.close();
    session = null;
    standalone?.close();
    standalone = null;
    messenger.setMockMethodCallHandler(paths, null);
    await temp.delete(recursive: true);
  });

  test(
    'default zero-budget run is synthetic and uses durable candidate service',
    () async {
      final s = await open(window());
      expect(s.simulated, true);
      expect(s.ledger.window.allowance, 0);
      expect(() => HttpClient(), throwsStateError);
      expect(DatabaseCore.orderBox!.isEmpty, true);
      expect(DatabaseCore.salesBox!.isEmpty, true);
      expect(PrintJobRepository.all(), isEmpty);
      final job = (await s.submit(go: true))!;
      expect(job.state, PrintJobState.sent);
      expect(job.label, 'Kitchen / POS02 TEST');
      expect(s.fakeSocket.writes.single, job.transmissionBytes);
      expect(s.ledger.events.map((e) => e['event']), [
        'reserved',
        'admitted',
        'connect',
        'write',
        'completed',
      ]);
      expect((s.ledger.events.first['detail'] as Map)['simulated'], true);
      expect(
        PrintReconciliation.policy,
        PrintReconciliationPolicy.unconfigured,
      );
    },
  );

  test(
    'physical flag with zero allowance fails before rendering or connector',
    () async {
      var connects = 0;
      final s = await open(
        window(),
        physical: true,
        connector: (_, _) async {
          connects++;
          return AcceptanceFakeSocket();
        },
      );
      await expectLater(s.submit(go: true), throwsStateError);
      expect(connects, 0);
      expect(s.ledger.events, isEmpty);
      expect(PrintJobRepository.all(), isEmpty);
    },
  );

  test('Cancel and its repeated Go cannot admit or connect', () async {
    final s = await open(window());
    expect(await s.submit(go: false), isNull);
    expect(await s.submit(go: true), isNull);
    expect(s.ledger.events.single['event'], 'cancelled');
    expect(s.transport.connectionCalls, 0);
    expect(PrintJobRepository.all(), isEmpty);
  });

  test('double submission admits one stable original', () async {
    final render = Completer<List<int>>();
    final s = await open(window(), render: (_) => render.future);
    final first = s.submit(go: true);
    await expectLater(s.submit(go: true), throwsStateError);
    render.complete(ascii.encode('SYNTHETIC'));
    final job = (await first)!;
    expect((await s.submit(go: true))!.id, job.id);
    expect(s.fakeSocket.writes, hasLength(1));
    expect(PrintJobRepository.all(), hasLength(1));
  });

  test(
    'successful relaunch keeps reservation spent and sends nothing',
    () async {
      final spec = window();
      final first = await open(spec);
      final job = (await first.submit(go: true))!;
      await first.close();
      session = null;
      final second = await open(spec);
      expect((await second.submit(go: true))!.id, job.id);
      expect(second.fakeSocket.writes, isEmpty);
      expect(second.transport.connectionCalls, 0);
      expect(second.ledger.events, hasLength(5));
    },
  );

  for (final failure in ['add', 'flush', 'connect']) {
    test(
      '$failure failure never refunds, reconnects, or retries after restart',
      () async {
        final spec = window();
        final socket = AcceptanceFakeSocket()
          ..failAdd = failure == 'add'
          ..failFlush = failure == 'flush';
        var connects = 0;
        final first = await open(
          spec,
          connector: (_, _) async {
            connects++;
            if (failure == 'connect')
              throw const SocketException('No-byte failure');
            return socket;
          },
        );
        final job = (await first.submit(go: true))!;
        expect(
          job.state,
          failure == 'connect' ? PrintJobState.failed : PrintJobState.uncertain,
        );
        expect(connects, 1);
        expect(socket.writes, hasLength(failure == 'connect' ? 0 : 1));
        await first.close();
        session = null;
        final second = await open(spec);
        expect((await second.submit(go: true))!.state, job.state);
        PrintQueue.start();
        await PrintQueue.idle;
        PrintQueue.stop();
        expect(second.fakeSocket.writes, isEmpty);
        expect(second.transport.connectionCalls, 0);
        await expectLater(
          PrintReconciliation.retryNotSent(job, 'TEST retry', 'pos02-retry'),
          throwsStateError,
        );
      },
    );
  }

  test('render failure consumes reservation across restart', () async {
    final spec = window();
    final first = await open(
      spec,
      render: (_) async => throw StateError('Bad render'),
    );
    await expectLater(first.submit(go: true), throwsStateError);
    expect(first.ledger.has('reserved'), true);
    expect(first.transport.connectionCalls, 0);
    await first.close();
    session = null;
    final second = await open(spec);
    expect(await second.submit(go: true), isNull);
    expect(second.fakeSocket.writes, isEmpty);
  });

  test(
    'expiry after render prevents admission; reservation stays spent',
    () async {
      final s = await open(
        window(),
        render: (_) async {
          now = now.add(const Duration(minutes: 2));
          return ascii.encode('SYNTHETIC');
        },
      );
      await expectLater(s.submit(go: true), throwsStateError);
      expect(s.ledger.has('reserved'), true);
      expect(PrintJobRepository.all(), isEmpty);
      expect(s.transport.connectionCalls, 0);
    },
  );

  test('expiry during connection destroys socket before add', () async {
    final socket = AcceptanceFakeSocket();
    final s = await open(
      window(),
      connector: (_, _) async {
        now = now.add(const Duration(minutes: 2));
        return socket;
      },
    );
    final job = (await s.submit(go: true))!;
    expect(job.state, PrintJobState.failed);
    expect(s.transport.connectionCalls, 1);
    expect(socket.destroyed, true);
    expect(socket.writes, isEmpty);
    expect(s.ledger.has('write'), false);
  });

  test(
    'real Georgian kitchen and receipt renderers use actual service admission',
    () async {
      for (final target in ['kitchen', 'receipt']) {
        final s = await open(window(target: target), actualRender: true);
        final job = (await s.submit(go: true))!;
        expect(
          job.label,
          '${target == 'kitchen' ? 'Kitchen' : 'Receipt'} / POS02 TEST',
        );
        expect(job.transmissionBytes.length, greaterThan(1000));
        expect(
          latin1.decode(job.transmissionBytes),
          contains('TEST / DO NOT PREPARE'),
        );
        expect(s.fakeSocket.writes.single, job.transmissionBytes);
        await s.close();
        session = null;
      }
    },
  );

  test(
    'copy requires a separate window, freezes payload and records fresh Staff',
    () async {
      final first = await open(window());
      final original = (await first.submit(go: true))!;
      final frozen = original.toMap()['payloadSha256'];
      await first.close();
      session = null;
      final s = await open(window(copy: true, jobId: original.id));
      final copy = (await s.submit(go: true))!;
      expect(copy.attempts, hasLength(2));
      expect(copy.toMap()['payloadSha256'], frozen);
      expect(copy.latest['actorId'], 'pos02-synthetic-operator');
      expect(copy.latest['reason'], PrintReconciliation.kitchenCopyReason);
      expect(
        latin1.decode(s.fakeSocket.writes.single),
        contains('REPRINT COPY 1'),
      );
      await s.submit(go: true);
      expect(s.fakeSocket.writes, hasLength(1));
      s.recordObservation(
        slips: 1,
        operator: 'synthetic reviewer',
        evidence: 'fake fixture',
        note: 'synthetic only',
      );
      expect(PrintJobRepository.read(copy.id)!.state, PrintJobState.sent);
      await expectLater(
        PrintReconciliation.confirm(copy, 'Checked paper', 'pos02-confirm'),
        throwsStateError,
      );
    },
  );

  test(
    'receipt copy policy remains unconfigured and consumes failed reservation',
    () async {
      final first = await open(window(target: 'receipt'));
      final receipt = (await first.submit(go: true))!;
      await first.close();
      session = null;
      final s = await open(
        window(target: 'receipt', copy: true, jobId: receipt.id),
      );
      await expectLater(s.submit(go: true), throwsStateError);
      expect(s.ledger.has('reserved'), true);
      expect(s.transport.connectionCalls, 0);
      expect(PrintJobRepository.read(receipt.id)!.attempts, hasLength(1));
      await expectLater(
        PrintReconciliation.reprint(receipt, 'TEST copy', 'pos02-receipt-copy'),
        throwsStateError,
      );
    },
  );

  test(
    'interrupted admission is held on startup without automatic delivery',
    () async {
      final first = await open(window());
      final job = (await first.submit(go: true))!;
      final body = job.toMap();
      body['attempts'][0].remove('sentAt');
      body['attempts'][0]['state'] = 'queued';
      body['audit'] = [body['audit'][0]];
      // A legitimate queued fixture models a crash between Hive admission and arm.
      await DatabaseCore.metaBox!.put('print_job:v1:${job.id}', body);
      await DatabaseCore.metaBox!.flush();
      await first.close();
      session = null;
      final second = await open(first.ledger.window);
      expect(PrintJobRepository.read(job.id)!.state, PrintJobState.uncertain);
      await second.submit(go: true);
      expect(second.fakeSocket.writes, isEmpty);
    },
  );

  test('ledger cannot be held by two sessions in the same process', () {
    final spec = window();
    standalone = AcceptanceLedger.open(getRoot(), spec);
    expect(() => AcceptanceLedger.open(getRoot(), spec), throwsStateError);
  });
  test('physical reservation is spent persistently before rendering', () {
    final spec = window(allowance: 1);
    final first = AcceptanceLedger.open(getRoot(), spec);
    first.reserve(now, simulated: false);
    first.close();
    standalone = AcceptanceLedger.open(getRoot(), spec);
    expect(() => standalone!.reserve(now, simulated: false), throwsStateError);
    expect(standalone!.events.single['event'], 'reserved');
  });
  for (final corrupt in [
    'partial',
    'invalidJson',
    'changedHash',
    'missingSpec',
    'missingJournal',
    'changedSpec',
  ]) {
    test('$corrupt ledger fails closed without a new budget', () {
      final spec = window(allowance: 1);
      final first = AcceptanceLedger.open(getRoot(), spec);
      first.reserve(now, simulated: false);
      first.close();
      final dir = '${getRoot().path}/windows/${spec.id}';
      final journal = File('$dir/journal.jsonl');
      switch (corrupt) {
        case 'partial':
          journal.writeAsStringSync(journal.readAsStringSync().trimRight());
        case 'invalidJson':
          journal.writeAsStringSync('broken\n');
        case 'changedHash':
          journal.writeAsStringSync(
            journal.readAsStringSync().replaceFirst('reserved', 'cancelled'),
          );
        case 'missingSpec':
          File('$dir/spec.json').deleteSync();
        case 'missingJournal':
          journal.deleteSync();
        case 'changedSpec':
          File('$dir/spec.json').writeAsStringSync('{}');
      }
      expect(() => AcceptanceLedger.open(getRoot(), spec), throwsA(anything));
    });
  }
  test('same window binds source, role, endpoint, action and budget', () {
    final spec = window();
    AcceptanceLedger.open(getRoot(), spec).close();
    for (final change in [
      {'candidateSha256': 'b' * 64},
      {'target': 'receipt'},
      {'host': '10.10.10.6'},
      {'actionId': 'pos02-other', 'jobId': 'pos02-other'},
      {'allowance': 1},
    ]) {
      expect(
        () => AcceptanceLedger.open(
          getRoot(),
          AcceptanceWindow({...spec.body, ...change}),
        ),
        throwsStateError,
      );
    }
  });
  test('unowned and linked roots are refused', () {
    getRoot().createSync();
    expect(() => AcceptanceLedger.open(getRoot(), window()), throwsStateError);
    getRoot().deleteSync();
    Link(getRoot().path).createSync(temp.path);
    expect(() => AcceptanceLedger.open(getRoot(), window()), throwsStateError);
  });

  Future<(Pos02AcceptanceSession, PrintJob)> armDirect() async {
    final s = await open(window());
    s.ledger.reserve(now, simulated: true);
    final job = PrintJob.create(
      id: s.ledger.window.jobId,
      target: PrintQueueTarget.kitchen,
      host: s.ledger.window.host,
      port: 9100,
      label: 'SYNTHETIC TEST',
      bytes: ascii.encode('TEST / DO NOT PREPARE'),
    );
    await PrintQueue.enqueue(job);
    s.transport.arm(job);
    await PrintJobRepository.transition(
      job.id,
      job.attemptId,
      PrintJobState.queued,
      PrintJobState.sending,
    );
    return (s, job);
  }

  test('same socket cannot resend even when first add throws', () async {
    final (s, job) = await armDirect();
    final socket = await s.transport.connect(job.host, job.port);
    s.fakeSocket.failAdd = true;
    expect(
      () => socket.add(job.transmissionBytes),
      throwsA(isA<SocketException>()),
    );
    expect(() => socket.add(job.transmissionBytes), throwsStateError);
    expect(s.fakeSocket.writes, hasLength(1));
    expect(s.ledger.events.where((e) => e['event'] == 'write'), hasLength(1));
  });
  test(
    'exact endpoint and bytes are checked immediately before connect and add',
    () async {
      final (s, job) = await armDirect();
      await expectLater(
        s.transport.connect('10.10.10.6', 9100),
        throwsStateError,
      );
      await expectLater(s.transport.connect(job.host, 9101), throwsStateError);
      expect(s.transport.connectionCalls, 0);
      final socket = await s.transport.connect(job.host, 9100);
      expect(() => socket.add([...job.transmissionBytes, 0]), throwsStateError);
      expect(s.ledger.has('write'), false);
      socket.add(job.transmissionBytes);
      expect(s.fakeSocket.writes.single, job.transmissionBytes);
      await expectLater(s.transport.connect(job.host, 9100), throwsStateError);
    },
  );
  test('expiry immediately before add denies the frozen bytes', () async {
    final (s, job) = await armDirect();
    final socket = await s.transport.connect(job.host, 9100);
    now = now.add(const Duration(minutes: 2));
    expect(() => socket.add(job.transmissionBytes), throwsStateError);
    expect(s.fakeSocket.writes, isEmpty);
    expect(s.ledger.has('connect'), true);
    expect(s.ledger.has('write'), false);
  });
  test(
    'expiry immediately before connect denies all connector calls',
    () async {
      final (s, job) = await armDirect();
      now = now.add(const Duration(minutes: 2));
      await expectLater(s.transport.connect(job.host, 9100), throwsStateError);
      expect(s.transport.connectionCalls, 0);
    },
  );
  test(
    'simulated reservation cannot authorize a zero-budget physical transport',
    () async {
      var calls = 0;
      final s = await open(
        window(),
        physical: true,
        connector: (_, _) async {
          calls++;
          return AcceptanceFakeSocket();
        },
      );
      s.ledger.reserve(now, simulated: true);
      final job = PrintJob.create(
        id: s.ledger.window.jobId,
        target: PrintQueueTarget.kitchen,
        host: s.ledger.window.host,
        port: 9100,
        label: 'SYNTHETIC',
        bytes: ascii.encode('TEST / DO NOT PREPARE'),
      );
      await PrintQueue.enqueue(job);
      expect(() => s.transport.arm(job), throwsStateError);
      await expectLater(
        s.transport.connect(job.host, job.port),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );
  test(
    'one-budget physical mode uses actual render and one fake connector only',
    () async {
      final fake = AcceptanceFakeSocket();
      var calls = 0;
      final s = await open(
        window(allowance: 1),
        physical: true,
        connector: (_, _) async {
          calls++;
          return fake;
        },
      );
      final job = (await s.submit(go: true))!;
      expect(calls, 1);
      expect(fake.writes.single, job.transmissionBytes);
      expect((s.ledger.events.first['detail'] as Map)['simulated'], false);
      await s.submit(go: true);
      expect(calls, 1);
    },
  );
  test(
    'admission/ledger failure before arm retains reservation and makes no write',
    () async {
      final s = await open(
        window(),
        render: (_) async {
          final journal = File(
            '${getRoot().path}/windows/${session!.ledger.window.id}/journal.jsonl',
          );
          // Corruption on disk cannot mint another budget on the next open.
          journal.writeAsStringSync(
            'partial',
            mode: FileMode.append,
            flush: true,
          );
          return [];
        },
      );
      await expectLater(s.submit(go: true), throwsStateError);
      expect(s.transport.connectionCalls, 0);
      final spec = s.ledger.window;
      await s.close();
      session = null;
      await expectLater(open(spec), throwsA(anything));
    },
  );
  test(
    'expiry during durable connect flush denies connector and stays spent',
    () async {
      final (s, job) = await armDirect();
      boundaryClock = () =>
          s.ledger.has('connect') ? now.add(const Duration(minutes: 2)) : now;
      await expectLater(s.transport.connect(job.host, 9100), throwsStateError);
      expect(s.transport.connectionCalls, 0);
      expect(s.ledger.has('connect'), true);
      boundaryClock = null;
      await expectLater(s.transport.connect(job.host, 9100), throwsStateError);
    },
  );
  test(
    'expiry during durable write flush denies add and keeps write spent',
    () async {
      final (s, job) = await armDirect();
      final socket = await s.transport.connect(job.host, 9100);
      boundaryClock = () =>
          s.ledger.has('write') ? now.add(const Duration(minutes: 2)) : now;
      expect(() => socket.add(job.transmissionBytes), throwsStateError);
      expect(s.fakeSocket.writes, isEmpty);
      expect(s.ledger.has('write'), true);
      boundaryClock = null;
      expect(() => socket.add(job.transmissionBytes), throwsStateError);
    },
  );
  for (final name in ['settings', 'users', 'audit_sync_state']) {
    test(
      'partially open normal $name storage is refused and preserved',
      () async {
        final elsewhere = Directory('${temp.path}/other')..createSync();
        Hive.init(elsewhere.path);
        if (!Hive.isAdapterRegistered(UserAdapter().typeId))
          Hive.registerAdapter(UserAdapter());
        final box = name == 'users'
            ? await Hive.openBox<User>(name)
            : await Hive.openBox(name);
        try {
          await box.put(
            'preserve',
            name == 'users'
                ? User(username: 'preserve', pinCode: '1234', role: 'waiter')
                : 'USER-OWNED',
          );
          await box.flush();
          final bytes = File(box.path!).readAsBytesSync();
          await expectLater(open(window()), throwsStateError);
          expect(box.isOpen, true);
          expect(File(box.path!).readAsBytesSync(), bytes);
          expect(getRoot().existsSync(), false);
        } finally {
          await box.close();
        }
      },
    );
  }
  test('audit details detach from caller maps and returned snapshots', () {
    standalone = AcceptanceLedger.open(getRoot(), window());
    standalone!.reserve(now, simulated: true);
    final original = {'state': 'failed'};
    standalone!.append('completed', now, original);
    original['state'] = 'sent';
    (standalone!.events.last['detail'] as Map)['state'] = 'uncertain';
    expect((standalone!.events.last['detail'] as Map)['state'], 'failed');
    final spec = standalone!.window;
    standalone!.close();
    standalone = null;
    standalone = AcceptanceLedger.open(getRoot(), spec);
    expect((standalone!.events.last['detail'] as Map)['state'], 'failed');
  });
  test(
    'request source and observation errors refuse before any storage/action',
    () {
      final w = window();
      for (final change in [
        {'go': 'true'},
        {'unknown': true},
        {
          'observation': {'slips': 1},
        },
        {
          'observation': {
            'slips': 1,
            'operator': '',
            'evidence': 'fixture',
            'note': 'fake',
          },
        },
      ]) {
        expect(
          () => AcceptanceRequest({
            'window': w.body,
            'go': true,
            ...change,
          }, 'a' * 64),
          throwsA(anything),
        );
      }
      expect(
        () => AcceptanceRequest({'window': w.body, 'go': true}, 'b' * 64),
        throwsFormatException,
      );
      expect(getRoot().existsSync(), false);
      expect(session, isNull);
    },
  );
  test(
    'missing, arbitrary, linked, occupied or mismatched output refuses before storage',
    () {
      final w = window();
      final request = AcceptanceRequest({
        'window': w.body,
        'go': true,
      }, 'a' * 64);
      expect(
        () => request.requireOwnedOutput(
          outputRoot: null,
          localAppData: temp.path,
        ),
        throwsStateError,
      );
      expect(
        () => request.requireOwnedOutput(
          outputRoot: temp.path,
          localAppData: temp.path,
        ),
        throwsStateError,
      );
      final dir = Directory(
        '${temp.path}/VynicPos02Acceptance/results/pos02-result-00000000-0000-0000-0000-000000000000',
      )..createSync(recursive: true);
      final marker = File('${dir.path}/OWNER.json');
      marker.writeAsStringSync('{}');
      expect(
        () => request.requireOwnedOutput(
          outputRoot: dir.path,
          localAppData: temp.path,
        ),
        throwsStateError,
      );
      marker.writeAsStringSync(
        jsonEncode({
          'owner': 'VYNIC_POS02_RESULT_V1',
          'candidateSha256': 'a' * 64,
          'windowId': w.id,
        }),
      );
      final output = File('${dir.path}/result.json')
        ..writeAsStringSync('PRESERVE');
      expect(
        () => request.requireOwnedOutput(
          outputRoot: dir.path,
          localAppData: temp.path,
        ),
        throwsStateError,
      );
      expect(output.readAsStringSync(), 'PRESERVE');
      output.deleteSync();
      final result = request.requireOwnedOutput(
        outputRoot: dir.path,
        localAppData: temp.path,
      );
      expect(jsonDecode(result.readAsStringSync())['status'], 'PREFLIGHT_ONLY');
      expect(getRoot().existsSync(), false);
      result.deleteSync();
      marker.deleteSync();
      dir.deleteSync();
      Link(dir.path).createSync(temp.path);
      expect(
        () => request.requireOwnedOutput(
          outputRoot: dir.path,
          localAppData: temp.path,
        ),
        throwsStateError,
      );
    },
  );

  Directory ownedOutput(AcceptanceWindow spec) {
    final dir = Directory(
      '${temp.path}/VynicPos02Acceptance/results/pos02-result-00000000-0000-0000-0000-000000000000',
    )..createSync(recursive: true);
    File('${dir.path}/OWNER.json').writeAsStringSync(
      jsonEncode({
        'owner': 'VYNIC_POS02_RESULT_V1',
        'candidateSha256': spec.body['candidateSha256'],
        'windowId': spec.id,
      }),
    );
    return dir;
  }

  test('fresh owned output accepts equivalent separator spelling', () {
    final spec = window();
    final request = AcceptanceRequest({
      'window': spec.body,
      'go': true,
    }, 'a' * 64);
    final dir = ownedOutput(spec);
    final marker = File('${dir.path}/OWNER.json');
    final ownerBytes = marker.readAsBytesSync();
    // A trailing forward slash also creates mixed separators on Windows.
    final result = request.requireOwnedOutput(
      outputRoot: '${dir.path}/',
      localAppData: temp.path,
    );
    expect(jsonDecode(result.readAsStringSync()), {
      'status': 'PREFLIGHT_ONLY',
      'milestoneDone': false,
    });
    expect(marker.readAsBytesSync(), ownerBytes);
    expect(spec.allowance, 0);
    expect(getRoot().existsSync(), false);
    expect(session, isNull);
    final evidence = result.readAsBytesSync();
    expect(
      () => request.requireOwnedOutput(
        outputRoot: '${dir.path}/',
        localAppData: temp.path,
      ),
      throwsStateError,
    );
    expect(result.readAsBytesSync(), evidence);
  });

  test('Windows drive and UNC owner paths normalize mixed separators', () {
    for (final root in [
      r'C:\Users\POS Operator\AppData\Local\VynicPos02Acceptance\results\pos02-result-00000000-0000-0000-0000-000000000000',
      r'\\pos-host\share\VynicPos02Acceptance\results\pos02-result-00000000-0000-0000-0000-000000000000',
    ]) {
      final native = '$root\\OWNER.json';
      final mixed = '$root/OWNER.json';
      expect(mixed, isNot(native));
      final owner = AcceptanceRequest.normalizedOutputPath(
        native,
        windows: true,
      );
      expect(
        AcceptanceRequest.normalizedOutputPath(mixed, windows: true),
        owner,
      );
      expect(
        AcceptanceRequest.normalizedOutputPath(
          '$root//OWNER.json',
          windows: true,
        ),
        owner,
      );
      for (final other in ['result.json', 'OWNER-alias.json', 'owner.json']) {
        expect(
          AcceptanceRequest.normalizedOutputPath('$root/$other', windows: true),
          isNot(owner),
        );
      }
    }
  });

  test('POSIX path identity preserves literal backslashes in names', () {
    expect(
      AcceptanceRequest.normalizedOutputPath(
        r'/tmp/pos\evidence/OWNER.json',
        windows: false,
      ),
      isNot(
        AcceptanceRequest.normalizedOutputPath(
          '/tmp/pos/evidence/OWNER.json',
          windows: false,
        ),
      ),
    );
  });

  void expectOutputRefused(AcceptanceWindow spec, Directory dir) {
    final request = AcceptanceRequest({
      'window': spec.body,
      'go': true,
    }, 'a' * 64);
    expect(
      () => request.requireOwnedOutput(
        outputRoot: '${dir.path}/',
        localAppData: temp.path,
      ),
      throwsStateError,
    );
    expect(spec.allowance, 0);
    expect(getRoot().existsSync(), false);
    expect(session, isNull);
  }

  for (final entryType in ['file', 'directory', 'ownerAlias']) {
    test('extra $entryType refuses equivalent output spelling', () {
      final spec = window();
      final dir = ownedOutput(spec);
      final marker = File('${dir.path}/OWNER.json');
      final ownerBytes = marker.readAsBytesSync();
      final extra = '${dir.path}/OWNER-alias.json';
      switch (entryType) {
        case 'file':
          File(extra).writeAsStringSync('PRESERVE');
        case 'directory':
          Directory(extra).createSync();
        case 'ownerAlias':
          Link(extra).createSync(marker.path);
      }
      final type = FileSystemEntity.typeSync(extra, followLinks: false);
      final targetBefore = entryType == 'ownerAlias'
          ? Link(extra).targetSync()
          : null;
      expectOutputRefused(spec, dir);
      expect(FileSystemEntity.typeSync(extra, followLinks: false), type);
      if (entryType == 'file')
        expect(File(extra).readAsStringSync(), 'PRESERVE');
      if (entryType == 'ownerAlias') {
        expect(Link(extra).targetSync(), targetBefore);
      }
      expect(marker.readAsBytesSync(), ownerBytes);
      expect(File('${dir.path}/result.json').existsSync(), false);
    });
  }

  for (final field in ['owner', 'candidateSha256', 'windowId']) {
    test('mismatched $field refuses equivalent output spelling', () {
      final spec = window();
      final dir = ownedOutput(spec);
      final marker = File('${dir.path}/OWNER.json');
      final owner =
          jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
      owner[field] = field == 'candidateSha256' ? 'b' * 64 : 'MISMATCH';
      marker.writeAsStringSync(jsonEncode(owner));
      final bytes = marker.readAsBytesSync();
      expectOutputRefused(spec, dir);
      expect(marker.readAsBytesSync(), bytes);
      expect(File('${dir.path}/result.json').existsSync(), false);
    });
  }

  test('linked owner refuses even when its provenance matches', () {
    final spec = window();
    final dir = ownedOutput(spec);
    final marker = File('${dir.path}/OWNER.json');
    final elsewhere = marker.copySync('${temp.path}/external-owner.json');
    final bytes = elsewhere.readAsBytesSync();
    marker.deleteSync();
    Link(marker.path).createSync(elsewhere.path);
    final targetBefore = Link(marker.path).targetSync();
    expectOutputRefused(spec, dir);
    expect(Link(marker.path).targetSync(), targetBefore);
    expect(elsewhere.readAsBytesSync(), bytes);
    expect(File('${dir.path}/result.json').existsSync(), false);
  });

  test('linked results parent refuses even when its child is owned', () {
    final spec = window();
    final dir = ownedOutput(spec);
    final markerBytes = File('${dir.path}/OWNER.json').readAsBytesSync();
    final parent = dir.parent;
    final elsewhere = parent.renameSync('${temp.path}/external-results');
    Link(parent.path).createSync(elsewhere.path);
    final targetBefore = Link(parent.path).targetSync();
    expectOutputRefused(spec, dir);
    expect(Link(parent.path).targetSync(), targetBefore);
    expect(File('${dir.path}/OWNER.json').readAsBytesSync(), markerBytes);
    expect(File('${dir.path}/result.json').existsSync(), false);
  });

  test('dangling result link refuses without replacing the link', () {
    final spec = window();
    final dir = ownedOutput(spec);
    final result = Link('${dir.path}/result.json');
    final target = '${temp.path}/missing-result.json';
    result.createSync(target);
    final targetBefore = result.targetSync();
    expectOutputRefused(spec, dir);
    expect(result.targetSync(), targetBefore);
    expect(File(target).existsSync(), false);
  });
}
