import 'dart:convert';

import 'package:hive/hive.dart';

import 'domain.dart';

abstract interface class OperationalProofFrameStore {
  Map<String, dynamic>? read();
  Future<void> writeAndFlush(Map<String, dynamic> frame);
}

/// Caller-owned, dedicated isolated Hive storage. This adapter deliberately
/// rejects normal POS box names and additional values. It never opens a box,
/// accesses DatabaseCore, registers workers, or dispatches retained effects.
class HiveOperationalProofFrameStore implements OperationalProofFrameStore {
  HiveOperationalProofFrameStore(this.box) {
    _isolated();
  }
  static const frameKey = 'operational-proof:frame:v1';
  static const boxPrefix = 'isolated_operational_proof_';
  final Box<dynamic> box;

  void _isolated() {
    if (!box.isOpen ||
        !box.name.startsWith(boxPrefix) ||
        box.keys.any((key) => key != frameKey)) {
      throw StateError(
        'An explicitly dedicated isolated proof box is required',
      );
    }
  }

  @override
  Map<String, dynamic>? read() {
    _isolated();
    final raw = box.get(frameKey);
    if (raw == null) return null;
    proofRequire(
      raw is String && utf8.encode(raw).length <= ProofBounds.frameBytes,
      'Hive frame encoding/bounds',
    );
    return Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
  }

  @override
  Future<void> writeAndFlush(Map<String, dynamic> frame) async {
    _isolated();
    final detached = jsonEncode(frame);
    proofRequire(
      utf8.encode(detached).length <= ProofBounds.frameBytes,
      'Hive frame bound',
    );
    await box.put(frameKey, detached);
    await box.flush();
  }
}
