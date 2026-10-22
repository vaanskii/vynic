/// Preparation-only ledger. This file has no Flutter, Hive or network startup.
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const pos02BaseCandidate =
    'd194367f8fd0e2f6d9dcfea86f52d09cb605b32779b7904613b00466bd084de8';
String acceptanceHash(List<int> bytes) => sha256.convert(bytes).toString();

String _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

class AcceptanceWindow {
  AcceptanceWindow(Map<String, dynamic> input)
    : body = Map<String, dynamic>.unmodifiable(input) {
    const keys = {
      'protocol',
      'baseCandidate',
      'candidateSha256',
      'windowId',
      'approval',
      'startsAt',
      'expiresAt',
      'allowance',
      'host',
      'port',
      'target',
      'model',
      'firmware',
      'paperMm',
      'action',
      'actionId',
      'jobId',
    };
    if (input.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(input.keys.toSet()).isNotEmpty ||
        input['protocol'] != 1 ||
        input['baseCandidate'] != pos02BaseCandidate ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(input['candidateSha256'] as String? ?? '') ||
        !['kitchen', 'receipt'].contains(input['target']) ||
        !['original', 'copy'].contains(input['action']) ||
        ![0, 1].contains(input['allowance']) ||
        input['port'] != 9100 ||
        input['paperMm'] != 80) {
      throw const FormatException('Invalid or unsupported acceptance window');
    }
    for (final k in ['windowId', 'actionId', 'jobId']) {
      if (!RegExp(
        r'^pos02-[a-z0-9-]{1,90}$',
      ).hasMatch(input[k] as String? ?? '')) {
        throw FormatException('Invalid stable identity: $k');
      }
    }
    for (final k in ['approval', 'model', 'firmware']) {
      final v = input[k];
      if (v is! String || v.trim().isEmpty || v.length > 300) {
        throw FormatException('Missing acceptance provenance: $k');
      }
    }
    if (input['action'] == 'original' && input['jobId'] != input['actionId']) {
      throw const FormatException(
        'Original action and job identity must match',
      );
    }
    final start = DateTime.parse(input['startsAt'] as String);
    final end = DateTime.parse(input['expiresAt'] as String);
    if (!start.isUtc ||
        !end.isUtc ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(minutes: 5)) {
      throw const FormatException('Use one UTC window of at most five minutes');
    }
    if (!privateAcceptanceIPv4(input['host'] as String? ?? '')) {
      throw const FormatException('One literal private IPv4 endpoint required');
    }
  }

  final Map<String, dynamic> body;
  String get id => body['windowId'] as String;
  String get jobId => body['jobId'] as String;
  String get actionId => body['actionId'] as String;
  String get host => body['host'] as String;
  bool get copy => body['action'] == 'copy';
  int get allowance => body['allowance'] as int;
  void requireCurrent(DateTime now) {
    if (now.isBefore(DateTime.parse(body['startsAt'] as String)) ||
        !now.isBefore(DateTime.parse(body['expiresAt'] as String))) {
      throw StateError(
        'Acceptance window is not current; no allowance refunded',
      );
    }
  }
}

bool privateAcceptanceIPv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4 ||
      parts.any((v) => !RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(v)))
    return false;
  final n = parts.map(int.parse).toList();
  if (n.any((v) => v > 255)) return false;
  return n[0] == 10 ||
      n[0] == 192 && n[1] == 168 ||
      n[0] == 172 && n[1] >= 16 && n[1] <= 31;
}

/// A root lock spans the entire storage/transport session. Reservation, connect
/// and write events are append-only and flushed before the associated action.
class AcceptanceLedger {
  AcceptanceLedger._(this.root, this.window, this._lock, this._journal);
  final Directory root;
  final AcceptanceWindow window;
  final RandomAccessFile _lock;
  final RandomAccessFile _journal;
  final List<Map<String, dynamic>> _events = [];
  static final _held = <String>{};
  bool _closed = false;
  bool get isOpen => !_closed;

  List<Map<String, dynamic>> get events =>
      (jsonDecode(jsonEncode(_events)) as List).cast<Map<String, dynamic>>();
  bool has(String event) => _events.any((e) => e['event'] == event);

  static void _regular(String path, FileSystemEntityType expected) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type != FileSystemEntityType.notFound && type != expected) {
      throw StateError('Refusing linked or unexpected acceptance path: $path');
    }
  }

  static AcceptanceLedger open(
    Directory requestedRoot,
    AcceptanceWindow window,
  ) {
    _regular(requestedRoot.path, FileSystemEntityType.directory);
    // Canonical parent avoids legitimate OS temp aliases without accepting a
    // linked runner root or any linked child data/ledger path.
    requestedRoot.parent.createSync(recursive: true);
    final root = Directory(
      '${requestedRoot.parent.resolveSymbolicLinksSync()}/${requestedRoot.uri.pathSegments.where((v) => v.isNotEmpty).last}',
    );
    if (_held.contains(root.path)) throw AcceptanceRootBusy();
    final existed = root.existsSync();
    if (existed) {
      final marker = File('${root.path}/OWNER.json');
      _regular(marker.path, FileSystemEntityType.file);
      if (!marker.existsSync() ||
          marker.readAsStringSync() !=
              _canonical({
                'owner': 'VYNIC_POS02_ACCEPTANCE_V1',
                'baseCandidate': pos02BaseCandidate,
              }))
        throw StateError('Refusing unowned or corrupt acceptance root');
    } else {
      root.createSync();
      File('${root.path}/OWNER.json').writeAsStringSync(
        _canonical({
          'owner': 'VYNIC_POS02_ACCEPTANCE_V1',
          'baseCandidate': pos02BaseCandidate,
        }),
        flush: true,
      );
    }
    for (final child in ['session.lock', 'hive', 'windows']) {
      _regular(
        '${root.path}/$child',
        child.endsWith('.lock')
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory,
      );
    }
    if (existed &&
        root
            .listSync(recursive: true, followLinks: false)
            .any((entry) => entry is Link)) {
      throw StateError('Acceptance storage must not contain symbolic links');
    }
    final lock = File(
      '${root.path}/session.lock',
    ).openSync(mode: FileMode.append);
    try {
      try {
        lock.lockSync(FileLock.exclusive);
      } on FileSystemException catch (error) {
        if ([11, 13, 33, 35].contains(error.osError?.errorCode)) {
          throw AcceptanceRootBusy();
        }
        rethrow;
      }
      _held.add(root.path);
      final windows = Directory('${root.path}/windows')..createSync();
      final dir = Directory('${windows.path}/${window.id}');
      _regular(dir.path, FileSystemEntityType.directory);
      final spec = File('${dir.path}/spec.json');
      final journal = File('${dir.path}/journal.jsonl');
      _regular(spec.path, FileSystemEntityType.file);
      _regular(journal.path, FileSystemEntityType.file);
      if (!dir.existsSync()) {
        dir.createSync();
        spec.writeAsStringSync(_canonical(window.body), flush: true);
        // A crash between these writes leaves a missing pair and fails closed.
        journal.writeAsStringSync('', flush: true);
      } else if (!spec.existsSync() ||
          !journal.existsSync() ||
          spec.readAsStringSync() != _canonical(window.body)) {
        throw StateError('Acceptance window changed or incompletely created');
      }
      final raw = journal.readAsStringSync();
      if (raw.isNotEmpty && !raw.endsWith('\n')) {
        throw const FormatException(
          'Partial acceptance ledger; inspection required',
        );
      }
      final handle = journal.openSync(mode: FileMode.append);
      final ledger = AcceptanceLedger._(root, window, lock, handle);
      try {
        for (final line in const LineSplitter().convert(raw)) {
          final event = jsonDecode(line) as Map<String, dynamic>;
          ledger._check(event);
          ledger._events.add(event);
        }
      } catch (_) {
        handle.closeSync();
        rethrow;
      }
      return ledger;
    } catch (_) {
      _held.remove(root.path);
      lock.closeSync();
      rethrow;
    }
  }

  void _check(Map<String, dynamic> event) {
    final body = Map<String, dynamic>.from(event)..remove('sha256');
    final name = event['event'];
    if (event.keys.toSet().difference({
          'seq',
          'previous',
          'event',
          'at',
          'detail',
          'sha256',
        }).isNotEmpty ||
        event.length != 6 ||
        event['seq'] != _events.length ||
        event['previous'] !=
            (_events.isEmpty
                ? acceptanceHash(utf8.encode(_canonical(window.body)))
                : _events.last['sha256']) ||
        event['sha256'] != acceptanceHash(utf8.encode(_canonical(body))) ||
        event['detail'] is! Map ||
        event['at'] is! String ||
        ![
          'reserved',
          'admitted',
          'connect',
          'write',
          'completed',
          'cancelled',
          'observation',
        ].contains(name)) {
      throw const FormatException('Invalid acceptance ledger chain');
    }
    DateTime.parse(event['at'] as String);
    final detail = event['detail'] as Map;
    final expectedKeys = switch (name) {
      'reserved' => {'simulated', 'actionId', 'jobId'},
      'admitted' => {
        'jobId',
        'attemptId',
        'payloadSha256',
        'transmissionSha256',
      },
      'write' => {'transmissionSha256'},
      'completed' => {'state'},
      'observation' => {'slips', 'operator', 'evidence', 'note'},
      _ => <String>{},
    };
    if (detail.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(detail.keys.toSet()).isNotEmpty ||
        name == 'reserved' &&
            (detail['simulated'] is! bool ||
                detail['actionId'] != window.actionId ||
                detail['jobId'] != window.jobId ||
                detail['simulated'] == false && window.allowance == 0) ||
        name == 'admitted' &&
            (detail['jobId'] != window.jobId ||
                detail['attemptId'] != window.actionId ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(detail['payloadSha256'] as String? ?? '')) ||
        ['admitted', 'write'].contains(name) &&
            !RegExp(
              r'^[a-f0-9]{64}$',
            ).hasMatch(detail['transmissionSha256'] as String? ?? '') ||
        name == 'write' &&
            detail['transmissionSha256'] !=
                (_events.singleWhere((e) => e['event'] == 'admitted')['detail']
                    as Map)['transmissionSha256'] ||
        name == 'completed' &&
            !['sent', 'uncertain', 'failed'].contains(detail['state'])) {
      throw const FormatException('Invalid acceptance ledger detail');
    }
    if (name != 'observation' && has(name as String) ||
        name == 'reserved' && has('cancelled') ||
        name == 'cancelled' && has('reserved') ||
        ['admitted', 'connect', 'write', 'completed'].contains(name) &&
            !has('reserved') ||
        ['connect', 'write'].contains(name) && !has('admitted') ||
        name == 'write' && !has('connect')) {
      throw const FormatException('Invalid or duplicate acceptance action');
    }
  }

  void append(
    String event,
    DateTime now, [
    Map<String, dynamic> detail = const {},
  ]) {
    if (_closed) throw StateError('Acceptance ledger closed');
    final record = <String, dynamic>{
      'seq': _events.length,
      'previous': _events.isEmpty
          ? acceptanceHash(utf8.encode(_canonical(window.body)))
          : _events.last['sha256'],
      'event': event,
      'at': now.toUtc().toIso8601String(),
      'detail': jsonDecode(jsonEncode(detail)),
    };
    record['sha256'] = acceptanceHash(utf8.encode(_canonical(record)));
    _check(record);
    // Failure here poisons this process; no further action can use the budget.
    try {
      _journal.writeStringSync('${jsonEncode(record)}\n');
      _journal.flushSync();
      _events.add(record);
    } catch (_) {
      _closed = true;
      rethrow;
    }
  }

  void reserve(DateTime now, {required bool simulated}) {
    window.requireCurrent(now);
    if (has('reserved') ||
        has('cancelled') ||
        !simulated && window.allowance == 0) {
      throw StateError('No remaining allowance in this immutable window');
    }
    append('reserved', now, {
      'simulated': simulated,
      'actionId': window.actionId,
      'jobId': window.jobId,
    });
  }

  void close() {
    _journal.closeSync();
    _lock.closeSync();
    _held.remove(root.path);
    _closed = true;
  }
}

class AcceptanceRootBusy extends StateError {
  AcceptanceRootBusy()
    : super('Acceptance root already locked by another session');
}
