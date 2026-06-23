import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import '../printer_connection.dart';

/// Low-level TCP transport for ESC/POS printer bytes.
class PrinterTransport {
  const PrinterTransport._();

  static const int _maxRetries = 2;
  static const Duration _connectionTimeout = Duration(seconds: 5);

  /// Send byte data to printer via persistent connection or fallback to raw TCP.
  static Future<bool> sendToPrinter({
    required String printerIp,
    required int port,
    required List<int> bytes,
    required String printerName,
    required bool usePersistentConnection,
  }) async {
    // Try persistent connection first (instant, no handshake delay)
    if (usePersistentConnection) {
      final manager = PrinterConnectionManager.instance;
      PrinterConnection? connection;

      // Get the appropriate printer connection
      if (printerName == 'Kitchen') {
        connection = manager.kitchenPrinter;
      } else if (printerName == 'Receipt') {
        connection = manager.receiptPrinter;
      }

      // Attempt to send via persistent connection
      if (connection != null) {
        developer.log(
          '[$printerName Printer] Using persistent connection to $printerIp:$port',
        );
        final success = await connection.send(Uint8List.fromList(bytes));
        if (success) {
          return true;
        }
        developer.log(
          '⚠️ [$printerName Printer] Persistent connection failed, falling back to traditional method',
        );
      }
    }

    // Fallback: Traditional connection method with retry logic
    developer.log('[$printerName Printer] Using fallback connection method');
    int attempt = 0;

    // Retry loop - attempt up to maxRetries + 1 times
    while (attempt <= _maxRetries) {
      Socket? socket;

      try {
        // Establish raw TCP socket connection to printer
        socket = await Socket.connect(
          printerIp,
          port,
          timeout: _connectionTimeout,
        );

        developer.log('[$printerName Printer] Connected successfully');

        // Send ESC/POS command bytes to printer
        socket.add(bytes);

        // Ensure all data is sent before closing
        await socket.flush();

        developer.log(
          '[$printerName Printer] Data sent successfully (${bytes.length} bytes)',
        );

        // Close the socket connection
        await socket.close();

        // Print successful
        return true;
      } on SocketException catch (e) {
        // Network-related errors (connection refused, timeout, etc.)
        developer.log(
          '[$printerName Printer] Socket error on attempt ${attempt + 1}: ${e.message}',
        );

        // Close socket if it was opened
        try {
          await socket?.close();
        } catch (_) {}
      } catch (e) {
        // Any other unexpected errors (including timeouts)
        developer.log(
          '[$printerName Printer] Error on attempt ${attempt + 1}: $e',
        );

        // Close socket if it was opened
        try {
          await socket?.close();
        } catch (_) {}
      }

      // Increment attempt counter
      attempt++;

      // Wait before retrying (exponential backoff)
      if (attempt <= _maxRetries) {
        final waitTime = Duration(milliseconds: 500 * attempt);
        developer.log(
          '[$printerName Printer] Waiting ${waitTime.inMilliseconds}ms before retry...',
        );
        await Future.delayed(waitTime);
      }
    }

    // All retry attempts failed
    developer.log(
      '[$printerName Printer] Failed after ${_maxRetries + 1} attempts',
    );
    return false;
  }

  /// Test direct temporary socket connections to both printers.
  static Future<Map<String, bool>> testConnections({
    required String kitchenIp,
    required String receiptIp,
    required int kitchenPort,
    required int receiptPort,
  }) async {
    final results = <String, bool>{};

    if (kitchenIp.isEmpty) {
      results['kitchen'] = false;
    } else {
      Socket? kitchenSocket;
      try {
        kitchenSocket = await Socket.connect(
          kitchenIp,
          kitchenPort,
          timeout: _connectionTimeout,
        );
        results['kitchen'] = true;
        await kitchenSocket.close();
      } catch (e) {
        developer.log('Kitchen printer connection test failed: $e');
        results['kitchen'] = false;
      }
    }

    if (receiptIp.isEmpty) {
      results['receipt'] = false;
    } else {
      Socket? receiptSocket;
      try {
        receiptSocket = await Socket.connect(
          receiptIp,
          receiptPort,
          timeout: _connectionTimeout,
        );
        results['receipt'] = true;
        await receiptSocket.close();
      } catch (e) {
        developer.log('Receipt printer connection test failed: $e');
        results['receipt'] = false;
      }
    }

    return results;
  }
}
