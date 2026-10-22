/// Native process-kill probe for synthetic ledger durability, no Flutter/TCP.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'pos02_acceptance_ledger.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) throw ArgumentError('root spec phase [ready-file]');
  final spec = AcceptanceWindow(
    Map<String, dynamic>.from(
      jsonDecode(File(args[1]).readAsStringSync()) as Map,
    ),
  );
  AcceptanceLedger ledger;
  try {
    ledger = AcceptanceLedger.open(Directory(args[0]), spec);
  } on AcceptanceRootBusy {
    if (args[2] != 'lock-check') rethrow;
    stdout.writeln(jsonEncode({'status': 'LOCK_REJECTED'}));
    exitCode = 3;
    return;
  }
  if (args[2] == 'lock-check') {
    ledger.close();
    stdout.writeln(jsonEncode({'status': 'UNEXPECTED_LOCK_ACQUIRED'}));
    exitCode = 2;
    return;
  }
  if (args[2] == 'inspect') {
    final events = ledger.events;
    var consumed = false;
    try {
      ledger.reserve(DateTime.now().toUtc(), simulated: false);
    } on StateError {
      consumed = true;
    }
    ledger.close();
    stdout.writeln(jsonEncode({'consumed': consumed, 'events': events}));
    if (!consumed) exitCode = 2;
    return;
  }
  final phases = ['reserved', 'admitted', 'connect', 'write'];
  if (!phases.contains(args[2]) || args.length != 4)
    throw ArgumentError('Invalid hold phase');
  final hash = acceptanceHash(utf8.encode('SYNTHETIC; no bytes sent'));
  ledger.reserve(DateTime.now().toUtc(), simulated: false);
  if (phases.indexOf(args[2]) >= 1)
    ledger.append('admitted', DateTime.now().toUtc(), {
      'jobId': spec.jobId,
      'attemptId': spec.actionId,
      'payloadSha256': hash,
      'transmissionSha256': hash,
    });
  if (phases.indexOf(args[2]) >= 2)
    ledger.append('connect', DateTime.now().toUtc());
  if (phases.indexOf(args[2]) >= 3)
    ledger.append('write', DateTime.now().toUtc(), {
      'transmissionSha256': hash,
    });
  File(args[3]).writeAsStringSync(
    jsonEncode({'pid': pid, 'events': ledger.events}),
    flush: true,
  );
  // Only the owned proof controller kills this process after its durable signal.
  Timer.periodic(const Duration(seconds: 1), (_) {});
  await Completer<void>().future;
}
