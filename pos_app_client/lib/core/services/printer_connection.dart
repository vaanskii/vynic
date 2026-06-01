import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:developer' as developer;

/// Persistent TCP connection to a thermal printer
/// Manages connection lifecycle, reconnection, and data transmission
class PrinterConnection {
  final String ip;
  final int port;
  final String name; // e.g., "Kitchen", "Receipt"

  Socket? _socket;
  bool _isConnecting = false;
  bool _isDisposed = false;

  PrinterConnection({required this.ip, required this.port, required this.name});

  /// Check if the connection is currently active
  bool get isConnected => _socket != null;

  /// Establish connection to the printer
  /// If already connected, does nothing
  /// If connection fails, logs error but doesn't throw
  Future<void> connect() async {
    if (_isDisposed) {
      return;
    }

    if (_socket != null) {
      // Check if socket is still alive
      try {
        // If we can still access the socket properties, it's likely alive
        if (_socket!.address.address.isNotEmpty) {
          return;
        }
      } catch (e) {
        // Socket is dead, clean it up
        _socket?.destroy();
        _socket = null;
      }
    }

    if (_isConnecting) {
      return;
    }

    _isConnecting = true;
    try {
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );

      // Listen for connection errors/closures
      _socket!.done
          .then((_) {
            _socket = null;
          })
          .catchError((error) {
            _socket = null;
          });
    } catch (e) {
      _socket = null;
    } finally {
      _isConnecting = false;
    }
  }

  /// Send data to the printer
  /// Automatically reconnects if connection is lost
  /// Returns true if data was sent successfully, false otherwise
  Future<bool> send(Uint8List data) async {
    if (_isDisposed) {
      return false;
    }

    // Ensure connection is alive
    await connect();

    if (_socket == null) {
      return false;
    }

    try {
      _socket!.add(data);
      await _socket!.flush();
      return true;
    } catch (e) {
      // Connection might be dead, clean it up for next attempt
      _socket?.destroy();
      _socket = null;
      return false;
    }
  }

  /// Disconnect and clean up the connection
  void disconnect() {
    if (_socket != null) {
      try {
        _socket!.destroy();
      } catch (e) {
        developer.log('Error disconnecting from $name printer: $e');
      }
      _socket = null;
    }
  }

  /// Dispose the connection permanently
  void dispose() {
    _isDisposed = true;
    disconnect();
  }
}

/// Manager for all printer connections
/// Provides singleton access to kitchen and receipt printers
class PrinterConnectionManager {
  static PrinterConnectionManager? _instance;

  PrinterConnection? _kitchenPrinter;
  PrinterConnection? _receiptPrinter;
  Timer? _keepAliveTimer;

  PrinterConnectionManager._();

  /// Get the singleton instance
  static PrinterConnectionManager get instance {
    _instance ??= PrinterConnectionManager._();
    return _instance!;
  }

  /// Initialize printer connections
  /// Call this once during app startup
  Future<void> initialize({
    required String kitchenIp,
    required String receiptIp,
    required int kitchenPort,
    required int receiptPort,
  }) async {
    // Clean up existing connections if any
    dispose();

    // Create new connections if configured
    final trimmedKitchenIp = kitchenIp.trim();
    final trimmedReceiptIp = receiptIp.trim();

    if (trimmedKitchenIp.isNotEmpty) {
      _kitchenPrinter = PrinterConnection(
        ip: trimmedKitchenIp,
        port: kitchenPort,
        name: 'Kitchen',
      );
    } else {
      _kitchenPrinter = null;
    }

    if (trimmedReceiptIp.isNotEmpty) {
      _receiptPrinter = PrinterConnection(
        ip: trimmedReceiptIp,
        port: receiptPort,
        name: 'Receipt',
      );
    } else {
      _receiptPrinter = null;
    }

    final futures = <Future<void>>[];
    if (_kitchenPrinter != null) {
      futures.add(_kitchenPrinter!.connect());
    }
    if (_receiptPrinter != null) {
      futures.add(_receiptPrinter!.connect());
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    // Start keep-alive timer to maintain connections
    _startKeepAlive();
  }

  /// Get the kitchen printer connection
  PrinterConnection? get kitchenPrinter => _kitchenPrinter;

  /// Get the receipt printer connection
  PrinterConnection? get receiptPrinter => _receiptPrinter;

  /// Start a background timer to keep connections alive
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      // Reconnect if disconnected
      await _kitchenPrinter?.connect();
      await _receiptPrinter?.connect();
    });
  }

  /// Stop the keep-alive timer
  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Disconnect all printers and clean up
  void dispose() {
    _stopKeepAlive();
    _kitchenPrinter?.dispose();
    _receiptPrinter?.dispose();
    _kitchenPrinter = null;
    _receiptPrinter = null;
  }
}
