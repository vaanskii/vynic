import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

void main() {
  test(
    'public build endpoint and explicit developer override have separate authority',
    () async {
      final before = ManagerAppPreferences.backendUrlOverride.value;
      try {
        await ManagerAppPreferences.setBackendUrlOverride(
          'http://127.0.0.1:3000',
        );
        if (ApiConfig.allowDeveloperOverride) {
          expect(ApiConfig.baseUrl, 'http://127.0.0.1:3000');
          await ManagerAppPreferences.setBackendUrlOverride(null);
          if (ApiConfig.configuredUrl.isNotEmpty) {
            expect(
              ApiConfig.baseUrl,
              ApiConfig.configuredUrl.replaceFirst(RegExp(r'/$'), ''),
            );
          } else if (Platform.isMacOS) {
            expect(ApiConfig.baseUrl, 'http://api.vynic.localhost');
          }
        } else {
          expect(ApiConfig.allowDeveloperOverride, isFalse);
          expect(
            ApiConfig.baseUrl,
            ApiConfig.configuredUrl.replaceFirst(RegExp(r'/$'), ''),
          );
          expect(Uri.parse(ApiConfig.baseUrl).scheme, 'https');
        }
      } finally {
        await ManagerAppPreferences.setBackendUrlOverride(before);
      }
    },
  );
}
