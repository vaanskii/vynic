import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Process-owned report; never imported from restaurant backups or Hive.
class MenuClientCompatibility {
  static const capability = 'CANONICAL_MENU_V2';
  static const updateMessage =
      'ამ POS ვერსიას ამ რესტორნის მენიუს რეჟიმი აღარ უჭერს მხარს. '
      'განაახლეთ Vynic POS. რესტორნის მონაცემები არ შეცვლილა.';
  static final updateRequired = ValueNotifier<String?>(null);

  static Map<String, Object?> get report => {
    'version': 1,
    'capabilities': [capability],
    'appVersion':
        Platform.environment['VYNIC_POS_UPDATE_VERSION'] ??
        const String.fromEnvironment(
          'VYNIC_APP_VERSION',
          defaultValue: '1.0.0+1',
        ),
    // Packaging supplies an integer build separately; never compare SemVer or
    // infer an updater release sequence from a marketing version.
    'buildNumber': int.tryParse(
      const String.fromEnvironment('VYNIC_APP_BUILD'),
    ),
  };
  static Map<String, String> get headers => {
    'X-Vynic-Menu-Client': jsonEncode(report),
  };

  static bool observe(int status, Object? body) {
    if (status == 426 &&
        body is Map &&
        (body['code'] == 'MENU_UPDATE_REQUIRED' ||
            body['code'] == 'CANONICAL_MENU_SNAPSHOT_UNSUPPORTED')) {
      updateRequired.value =
          body['code'] == 'CANONICAL_MENU_SNAPSHOT_UNSUPPORTED'
          ? 'რესტორანი Cloud მენიუს იყენებს. მენიუს სინქრონიზაცია შეჩერებულია. '
                'მენიუს მართვაში დაადასტურეთ Cloud მენიუზე გადასვლა; ადგილობრივი ცვლილებები შენახულია.'
          : updateMessage;
      return false;
    }
    if (status >= 200 && status < 300) updateRequired.value = null;
    return true;
  }
}
