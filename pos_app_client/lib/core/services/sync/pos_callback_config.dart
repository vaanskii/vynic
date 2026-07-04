/// Runtime POS callback registration (server → Windows HTTP ingest).
class PosCallbackConfig {
  PosCallbackConfig._();

  /// e.g. `http://192.168.1.50:8081`
  static String? baseUrl;

  /// Shared secret sent to cloud on sync; server echoes as `x-connection-key`.
  static String? connectionKey;
}
