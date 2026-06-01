import 'dart:async';
import 'dart:io';

class DiscoveredPrinter {
  const DiscoveredPrinter({
    required this.ip,
    required this.port,
    required this.responseTimeMs,
  });

  final String ip;
  final int port;
  final int responseTimeMs;
}

class PrinterScannerService {
  PrinterScannerService._();

  static Future<List<DiscoveredPrinter>> scanLocalNetwork({
    int port = 9100,
    int timeoutMs = 450,
    int batchSize = 20,
    List<String> seedIps = const <String>[],
  }) async {
    final prefixes = <String>{};
    final localIp = await _resolveLocalIpv4();
    if (localIp != null) {
      final localPrefix = _ipv4Prefix(localIp);
      if (localPrefix != null) {
        prefixes.add(localPrefix);
      }
    }
    for (final ip in seedIps) {
      final prefix = _ipv4Prefix(ip);
      if (prefix != null && _isPrivateIpv4('${prefix}1')) {
        prefixes.add(prefix);
      }
    }

    if (prefixes.isEmpty) {
      return const <DiscoveredPrinter>[];
    }

    final ownHostByPrefix = <String, int>{};
    if (localIp != null) {
      final localPrefix = _ipv4Prefix(localIp);
      final lastDot = localIp.lastIndexOf('.');
      if (localPrefix != null && lastDot > 0) {
        final host = int.tryParse(localIp.substring(lastDot + 1));
        if (host != null) {
          ownHostByPrefix[localPrefix] = host;
        }
      }
    }

    final hosts = <String>[];
    for (final prefix in prefixes) {
      final ownHost = ownHostByPrefix[prefix];
      for (var i = 1; i <= 254; i++) {
        if (ownHost != null && i == ownHost) {
          continue;
        }
        hosts.add('$prefix$i');
      }
    }

    final discovered = <DiscoveredPrinter>[];
    for (var i = 0; i < hosts.length; i += batchSize) {
      final slice = hosts.sublist(
        i,
        (i + batchSize) > hosts.length ? hosts.length : i + batchSize,
      );
      final results = await Future.wait(
        slice.map((host) => _probeHost(host, port, timeoutMs)),
      );
      for (final result in results) {
        if (result != null) {
          discovered.add(result);
        }
      }
    }

    discovered.sort((a, b) {
      final ipCompare = _compareIpv4(a.ip, b.ip);
      if (ipCompare != 0) {
        return ipCompare;
      }
      return a.port.compareTo(b.port);
    });

    return discovered;
  }

  static String? _ipv4Prefix(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return null;
    }
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);
    final d = int.tryParse(parts[3]);
    if (a == null || b == null || c == null || d == null) {
      return null;
    }
    if (a < 0 ||
        a > 255 ||
        b < 0 ||
        b > 255 ||
        c < 0 ||
        c > 255 ||
        d < 0 ||
        d > 255) {
      return null;
    }
    return '$a.$b.$c.';
  }

  static Future<DiscoveredPrinter?> _probeHost(
    String host,
    int port,
    int timeoutMs,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      Socket? socket;
      final stopwatch = Stopwatch()..start();
      try {
        socket = await Socket.connect(
          host,
          port,
          timeout: Duration(milliseconds: timeoutMs),
        );
        stopwatch.stop();
        return DiscoveredPrinter(
          ip: host,
          port: port,
          responseTimeMs: stopwatch.elapsedMilliseconds,
        );
      } catch (_) {
        if (attempt == 1) {
          return null;
        }
      } finally {
        try {
          await socket?.close();
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<String?> _resolveLocalIpv4() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback) {
          continue;
        }
        final ip = address.address;
        if (_isPrivateIpv4(ip)) {
          return ip;
        }
      }
    }

    return null;
  }

  static bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) {
      return false;
    }
    if (a == 10) {
      return true;
    }
    if (a == 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a == 192 && b == 168) {
      return true;
    }
    return false;
  }

  static int _compareIpv4(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 4; i++) {
      final cmp = pa[i].compareTo(pb[i]);
      if (cmp != 0) {
        return cmp;
      }
    }
    return 0;
  }
}
