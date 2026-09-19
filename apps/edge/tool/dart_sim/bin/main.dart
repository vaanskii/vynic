// Isolated protocol consumer. Production Flutter/Hive does not import this.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:grpc/grpc.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';

String secret(int n) => base64Url
    .encode(List.generate(n, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
String uuid() {
  final b = List.generate(16, (_) => Random.secure().nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Future<void> main(List<String> args) async {
  if (args.length != 7)
    throw ArgumentError(
      'data host port cert venue installation ticket-json-or-dash',
    );
  final dir = Directory(args[0]);
  await dir.create(recursive: true);
  final lock = await File(
    '${dir.path}/terminal.lock',
  ).open(mode: FileMode.append);
  await lock.lock(FileLock.exclusive);
  try {
    final file = File('${dir.path}/terminal.json');
    Map<String, dynamic> state;
    if (await file.exists()) {
      state = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } else {
      state = {
        'terminal': uuid(),
        'secret': secret(32),
        'request': uuid(),
        'session': uuid(),
        'venue': args[4],
        'installation': args[5],
      };
      await file.writeAsString(jsonEncode(state), flush: true);
    }
    if (state['venue'] != args[4] || state['installation'] != args[5])
      throw StateError('Immutable terminal binding mismatch');
    final certificateBytes = await File(args[3]).readAsBytes();
    final certificatePem = utf8.decode(certificateBytes);
    final expectedDer = base64.decode(
      certificatePem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''),
    );
    // The supplied file is an explicit out-of-band certificate pin. macOS Dart
    // may reject a self-signed certificate in platform trust validation; accept
    // only this exact certificate, for this authority, within its validity dates.
    // Never use allowBadCertificates or trust-on-first-use.
    final channel = ClientChannel(
      args[1],
      port: int.parse(args[2]),
      options: ChannelOptions(
        credentials: ChannelCredentials.secure(
          certificates: certificateBytes,
          authority: 'vynic-edge.local',
          onBadCertificate: (certificate, host) {
            final now = DateTime.now();
            final actual = certificate.der;
            if (host != 'vynic-edge.local' ||
                now.isBefore(certificate.startValidity) ||
                now.isAfter(certificate.endValidity) ||
                actual.length != expectedDer.length)
              return false;
            for (var i = 0; i < actual.length; i++) {
              if (actual[i] != expectedDer[i]) return false;
            }
            return true;
          },
        ),
      ),
    );
    try {
      final client = FoundationClient(
        channel,
        options: CallOptions(timeout: const Duration(seconds: 10)),
      );
      final scope = Scope(
        venueId: args[4],
        installationId: args[5],
        protocol: Protocol(major: 1),
      );
      if (args[6] != '-') {
        final ticket =
            jsonDecode(await File(args[6]).readAsString())['ticket'] as String;
        await client.pair(
          PairRequest(
            scope: scope,
            ticket: ticket,
            requestId: state['request'] as String,
            terminalId: state['terminal'] as String,
            terminalSecret: state['secret'] as String,
            displayName: 'Dart simulator',
          ),
        );
      }
      final status = await client.handshake(
        HandshakeRequest(
          auth: AuthenticatedRequest(
            scope: scope,
            terminalId: state['terminal'] as String,
            terminalSecret: state['secret'] as String,
          ),
          sessionId: state['session'] as String,
          clientVersion: 'dart-sim/1',
        ),
      );
      if (status.businessMutationsEnabled || status.mode != 'FOUNDATION_ONLY')
        throw StateError('Unexpected operational authority');
      print(
        jsonEncode({
          'terminalId': status.terminalId,
          'installationId': status.installationId,
          'bootId': status.bootId,
          'mode': status.mode,
        }),
      );
    } finally {
      await channel.shutdown();
    }
  } finally {
    await lock.unlock();
    await lock.close();
  }
}
