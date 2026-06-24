import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  LocalNotificationsService._internal();
  static const String androidChannelId = 'vynic_manager_notifications';
  static const String androidChannelName = 'Vynic Manager Notifications';
  static const String androidChannelDescription =
      'Order and manager updates from Vynic';

  static final LocalNotificationsService _instance =
      LocalNotificationsService._internal();

  factory LocalNotificationsService.instance() => _instance;

  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

  final _androidInitializationSettings = const AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );

  final _iosInitializationSettings = const DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final _androidChannel = const AndroidNotificationChannel(
    androidChannelId,
    androidChannelName,
    description: androidChannelDescription,
    importance: Importance.max,
  );

  bool _isFlutterLocalNotificationsInitialized = false;

  int _notificationIdCounter = 0;
  String? _lastNotificationFingerprint;
  DateTime? _lastNotificationAt;
  final Map<String, DateTime> _serviceFeePushAtByKey = {};

  Future<void> init() async {
    // check if already initialized
    if (_isFlutterLocalNotificationsInitialized) {
      return;
    }

    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    final initializationSettings = InitializationSettings(
      android: _androidInitializationSettings,
      iOS: _iosInitializationSettings,
      // macOS uses the same Darwin settings as iOS. Required, otherwise the
      // plugin throws "macOS settings must be set" on the macOS manager client.
      macOS: _iosInitializationSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification tapped: ${response.payload}');
      },
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);

    _isFlutterLocalNotificationsInitialized = true;
  }

  Future<void> showNotification(
    String? title,
    String? body,
    String? payload,
  ) async {
    final normalizedTitle = (title ?? '').trim();
    final normalizedBody = (body ?? '').trim();
    if (normalizedTitle.isEmpty || normalizedBody.isEmpty) return;
    final now = DateTime.now();
    final serviceFeeKey = _serviceFeeDedupeKey(normalizedTitle, normalizedBody);
    if (serviceFeeKey != null) {
      final last = _serviceFeePushAtByKey[serviceFeeKey];
      if (last != null && now.difference(last).inSeconds <= 10) {
        return;
      }
      _serviceFeePushAtByKey[serviceFeeKey] = now;
    }
    final fp = '$normalizedTitle|$normalizedBody';
    if (_lastNotificationFingerprint == fp &&
        _lastNotificationAt != null &&
        now.difference(_lastNotificationAt!).inSeconds <= 8) {
      return;
    }
    _lastNotificationFingerprint = fp;
    _lastNotificationAt = now;

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.max,
      priority: Priority.high,
    );

    DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      id: _notificationIdCounter++,
      title: normalizedTitle,
      body: normalizedBody,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  /// Collapse rapid service-fee on/off pushes for the same table/order.
  String? _serviceFeeDedupeKey(String title, String body) {
    if (title != 'მაგიდები' && title != 'სალარო') return null;
    if (!body.contains('სერვისის საფასური')) return null;
    final tableMatch = RegExp(r'მაგიდა\s+(\S+)').firstMatch(body);
    if (tableMatch != null) {
      return 'service_fee:table:${tableMatch.group(1)}';
    }
    final orderMatch = RegExp(r'#(\d+)').firstMatch(body);
    if (orderMatch != null) {
      return 'service_fee:order:${orderMatch.group(1)}';
    }
    return 'service_fee:generic';
  }
}
