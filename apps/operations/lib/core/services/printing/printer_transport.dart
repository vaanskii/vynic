import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'print_job.dart';
import 'printer_connection.dart';

/// Narrow seam for deterministic partial-write tests. Production wraps only
/// a Dart TCP socket; no printer status protocol is claimed without qualification.
abstract interface class PrinterWriteSocket {
  void add(List<int> bytes);
  Future<void> flush();
  Future<void> close();
  void destroy();
}

class _TcpPrinterSocket implements PrinterWriteSocket {
  _TcpPrinterSocket(this.socket);
  final Socket socket;
  @override
  void add(List<int> bytes) => socket.add(bytes);
  @override
  Future<void> flush() => socket.flush();
  @override
  Future<void> close() async {
    await socket.close();
  }

  @override
  void destroy() => socket.destroy();
}

class PrinterTransport {
  PrinterTransport._();
  static const _connectionTimeout = Duration(seconds: 5);
  static const _writeTimeout = Duration(seconds: 8);
  @visibleForTesting
  static Future<PrinterWriteSocket> Function(String host, int port)?
  connectOverride;
  @visibleForTesting
  static Future<void> Function(Duration)? delayOverride;

  static Future<PrintTransmissionResult> sendToPrinter({
    required String printerIp,
    required int port,
    required List<int> bytes,
    required String printerName,
    required bool usePersistentConnection,
    bool Function()? mayWrite,
  }) async {
    const held = PrintTransmissionResult(
      PrintTransmissionState.uncertain,
      'Venue or confirmed Order changed; delivery held without writing bytes',
    );
    if (mayWrite != null && !mayWrite()) return held;
    if (usePersistentConnection && connectOverride == null) {
      final manager = PrinterConnectionManager.instance;
      final connection = printerName == 'Kitchen'
          ? manager.kitchenPrinter
          : printerName == 'Receipt'
          ? manager.receiptPrinter
          : null;
      if (connection != null &&
          connection.ip == printerIp &&
          connection.port == port) {
        if (mayWrite != null && !mayWrite()) return held;
        final result = await connection.send(
          Uint8List.fromList(bytes),
          mayWrite: mayWrite,
        );
        if (result.state != PrintTransmissionState.notSent) return result;
        // Fallback is allowed only when no write was attempted.
      }
    }
    String lastError = 'Connection unavailable';
    for (var attempt = 0; attempt < 3; attempt++) {
      PrinterWriteSocket? socket;
      var writeAttempted = false;
      try {
        socket = connectOverride == null
            ? _TcpPrinterSocket(
                await Socket.connect(
                  printerIp,
                  port,
                  timeout: _connectionTimeout,
                ),
              )
            : await connectOverride!(
                printerIp,
                port,
              ).timeout(_connectionTimeout);
        if (mayWrite != null && !mayWrite()) {
          socket.destroy();
          return held;
        }
        writeAttempted =
            true; // Set BEFORE add: an exception can follow a partial write.
        socket.add(bytes);
        await socket.flush().timeout(_writeTimeout);
        await socket.close().timeout(_writeTimeout);
        return const PrintTransmissionResult(
          PrintTransmissionState.sent,
          'TCP bytes sent; physical paper output is not confirmed',
        );
      } catch (error) {
        lastError = error.toString();
        socket?.destroy();
        if (writeAttempted)
          return PrintTransmissionResult(
            PrintTransmissionState.uncertain,
            'Transmission was attempted; check paper before a labeled reprint. $lastError',
          );
        if (attempt < 2) {
          final delay = Duration(milliseconds: 500 * (attempt + 1));
          await (delayOverride?.call(delay) ?? Future<void>.delayed(delay));
        }
      }
    }
    return PrintTransmissionResult(
      PrintTransmissionState.notSent,
      'Connection failed before any bytes were written. $lastError',
    );
  }

  /// Reachability only. Opening a TCP connection is not a paper/printing test.
  static Future<Map<String, bool>> testConnections({
    required String kitchenIp,
    required String receiptIp,
    required int kitchenPort,
    required int receiptPort,
  }) async {
    Future<bool> probe(String host, int port) async {
      if (host.isEmpty) return false;
      Socket? socket;
      try {
        socket = await Socket.connect(host, port, timeout: _connectionTimeout);
        return true;
      } catch (error) {
        developer.log('Printer TCP reachability failed: $error');
        return false;
      } finally {
        socket?.destroy();
      }
    }

    return {
      'kitchen': await probe(kitchenIp, kitchenPort),
      'receipt': await probe(receiptIp, receiptPort),
    };
  }
}
