/// Strict preflight performed before storage/admission/physical actions.
library;

import 'dart:convert';
import 'dart:io';
import 'pos02_acceptance_ledger.dart';

class AcceptanceRequest {
  AcceptanceRequest(Map<String, dynamic> config, String? verifiedSha)
    : window = AcceptanceWindow(
        Map<String, dynamic>.from(config['window'] as Map),
      ) {
    if (config.keys.toSet().difference({
          'window',
          'go',
          'observation',
        }).isNotEmpty ||
        config['go'] is! bool ||
        window.body['candidateSha256'] != verifiedSha) {
      throw const FormatException(
        'Config differs from verified source or supported fields',
      );
    }
    go = config['go'] as bool;
    final raw = config['observation'];
    if (raw != null) {
      final o = Map<String, dynamic>.from(raw as Map);
      if (o.length != 4 ||
          o.keys.toSet().difference({
            'slips',
            'operator',
            'evidence',
            'note',
          }).isNotEmpty ||
          o['slips'] is! int ||
          o['slips'] < 0 ||
          o['slips'] > 20 ||
          ['operator', 'evidence', 'note'].any(
            (k) =>
                o[k] is! String ||
                (o[k] as String).trim().isEmpty ||
                (o[k] as String).length > 500,
          )) {
        throw const FormatException(
          'Invalid observation; no job has been submitted',
        );
      }
      observation = Map<String, dynamic>.unmodifiable(o);
    }
  }
  final AcceptanceWindow window;
  late final bool go;
  Map<String, dynamic>? observation;

  File requireOwnedOutput({
    required String? outputRoot,
    required String? localAppData,
  }) {
    if (outputRoot == null ||
        localAppData == null ||
        !Directory(localAppData).existsSync()) {
      throw StateError(
        'Launcher-owned result directory is required before any action',
      );
    }
    final dir = Directory(outputRoot);
    if (FileSystemEntity.typeSync(dir.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !RegExp(
          r'^pos02-result-[a-f0-9-]{36}$',
        ).hasMatch(dir.uri.pathSegments.where((v) => v.isNotEmpty).last)) {
      throw StateError('Refusing an unowned or linked result directory');
    }
    final expectedParent = Directory(
      '$localAppData/VynicPos02Acceptance/results',
    );
    if (!expectedParent.existsSync() ||
        dir.parent.resolveSymbolicLinksSync() !=
            expectedParent.resolveSymbolicLinksSync() ||
        FileSystemEntity.typeSync(expectedParent.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw StateError(
        'Result directory must be under the dedicated acceptance results root',
      );
    }
    final marker = File('${dir.path}/OWNER.json');
    if (FileSystemEntity.typeSync(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        marker.readAsStringSync() !=
            jsonEncode({
              'owner': 'VYNIC_POS02_RESULT_V1',
              'candidateSha256': window.body['candidateSha256'],
              'windowId': window.id,
            })) {
      throw StateError('Result provenance does not match this source/window');
    }
    final output = File('${dir.path}/result.json');
    final ownerPath = normalizedOutputPath(marker.absolute.path);
    if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        dir
            .listSync(followLinks: false)
            .any(
              (entry) => normalizedOutputPath(entry.absolute.path) != ownerPath,
            )) {
      throw StateError(
        'Result directory must be fresh; never overwrite any evidence or data',
      );
    }
    // Validate writability before an allowance is spent. This file is owned by
    // the fresh launcher directory and later replaced only by its final result.
    output.writeAsStringSync(
      jsonEncode({'status': 'PREFLIGHT_ONLY', 'milestoneDone': false}),
      flush: true,
    );
    return output;
  }

  /// Lexical file identity only: links and aliases retain their distinct names.
  /// [windows] allows verifying Windows spellings on any test host.
  static Uri normalizedOutputPath(String path, {bool? windows}) {
    final uri = Uri.file(path, windows: windows);
    return uri
        .replace(pathSegments: uri.pathSegments.where((v) => v.isNotEmpty))
        .normalizePath();
  }
}
