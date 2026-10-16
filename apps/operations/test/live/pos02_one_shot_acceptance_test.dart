/// Opt-in native Flutter entry for the standalone runner, never normal POS boot.
/// Broad test discovery skips it. The checked handoff launcher sets the config.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/pos02_acceptance_ledger.dart';
import '../support/pos02_acceptance_runner.dart';
import '../../tool/pos02_acceptance_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final configPath = Platform.environment['POS02_ACCEPTANCE_CONFIG'];
  test(
    'one explicitly requested standalone acceptance action',
    () async {
      final config =
          jsonDecode(File(configPath!).readAsStringSync())
              as Map<String, dynamic>;
      final request = AcceptanceRequest(
        config,
        Platform.environment['POS02_ACCEPTANCE_SOURCE_SHA'],
      );
      final window = request.window;
      final output = request.requireOwnedOutput(
        outputRoot: Platform.environment['POS02_ACCEPTANCE_OUTPUT_ROOT'],
        localAppData: Platform.environment['LOCALAPPDATA'],
      );
      final physical =
          Platform.environment['POS02_ACCEPTANCE_EXECUTE'] ==
          'EXPLICIT_APPROVED_ONE_SHOT';
      if (physical && (!Platform.isWindows || window.allowance != 1)) {
        throw StateError(
          'Physical execution requires Windows and one explicit allowance',
        );
      }
      Directory? disposable;
      final local = Platform.environment['LOCALAPPDATA'];
      if (physical &&
          (local == null ||
              local.trim().isEmpty ||
              !Directory(local).existsSync())) {
        throw StateError('Existing user LOCALAPPDATA is required');
      }
      final root = physical
          ? Directory('$local/VynicPos02Acceptance/$pos02BaseCandidate')
          : Directory(
              '${(disposable = await Directory.systemTemp.createTemp('vynic_pos02_acceptance_dry_')).path}/owned',
            );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw StateError(
          'Acceptance must not resolve normal application data',
        ),
      );
      Pos02AcceptanceSession? session;
      try {
        session = await Pos02AcceptanceSession.open(
          root: root,
          window: window,
          executePhysical: physical,
        );
        final job = await session.submit(go: request.go);
        final observation = request.observation;
        if (observation != null) {
          final o = observation;
          session.recordObservation(
            slips: o['slips'] as int,
            operator: o['operator'] as String,
            evidence: o['evidence'] as String,
            note: o['note'] as String,
          );
        }
        final result = {
          'baseCandidate': pos02BaseCandidate,
          'candidateSha256': window.body['candidateSha256'],
          'simulated': !physical,
          'window': window.body,
          'ledgerRoot': session.ledger.root.path,
          'events': session.ledger.events,
          'job': job?.toMap(),
          'connectionCalls': session.transport.connectionCalls,
          'paperConfirmed': false,
          'milestoneDone': false,
        };
        output.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result),
          flush: true,
        );
        stdout.writeln('POS02 acceptance evidence: ${output.path}');
      } catch (error) {
        output.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'status': 'FAILED',
            'error': error.toString(),
            'simulated': !physical,
            'window': window.body,
            'events': session?.ledger.events,
            'ledgerRoot': session?.ledger.root.path,
            'milestoneDone': false,
          }),
          flush: true,
        );
        rethrow;
      } finally {
        await session?.close();
        messenger.setMockMethodCallHandler(channel, null);
        if (disposable != null) await disposable.delete(recursive: true);
      }
    },
    skip: configPath == null,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
