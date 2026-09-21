import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/sync/local_lab_api.dart';

void main() {
  test(
    'HTTP exception requires Windows, development, opt-in and exact lab origin',
    () {
      for (final environment in ['development', 'staging', 'production']) {
        for (final enabled in [false, true]) {
          for (final windows in [false, true]) {
            for (final url in [
              'http://10.10.10.3:3000',
              'http://172.20.10.2:3000',
              'http://172.20.10.2:8443',
              'http://example.com:3000',
              'http://10.10.10.3:8443',
              'http://user@10.10.10.3:3000',
              'http://10.10.10.3:3000/path',
            ]) {
              expect(
                permitsLocalLabApi(
                  Uri.parse(url),
                  environment: environment,
                  enabled: enabled,
                  windows: windows,
                ),
                environment == 'development' &&
                    enabled &&
                    windows &&
                    const {'http://10.10.10.3:3000', 'http://172.20.10.2:3000'}.contains(url),
              );
            }
          }
        }
      }
    },
  );
}
