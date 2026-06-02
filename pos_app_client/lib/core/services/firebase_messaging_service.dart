import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vynic/core/services/local_notifications_service.dart';
import 'package:vynic/core/services/mobile_api_service.dart';

class FirebaseMessagingService {
  FirebaseMessagingService._internal();

  static final FirebaseMessagingService _instance =
      FirebaseMessagingService._internal();

  factory FirebaseMessagingService.instance() => _instance;

  LocalNotificationsService? _localNotificationsService;
  bool _initialized = false;

  Future<void> init({
    required LocalNotificationsService localNotificationsService,
  }) async {
    if (_initialized) return;
    _localNotificationsService = localNotificationsService;

    await _requestPermissions();

    await _handlePushNotificationsToken();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Listen for notification taps when the app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // Check initial message that opened the app from terminated state
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _onMessageOpenedApp(initialMessage);
    }
    _initialized = true;
  }

  Future<void> _handlePushNotificationsToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      print('FCM Token: $token');
      await _registerTokenWithBackend(token);
    }

    FirebaseMessaging.instance.onTokenRefresh
        .listen((fcmToken) async {
          print('FCM Token refreshed: $fcmToken');
          await _registerTokenWithBackend(fcmToken);
        })
        .onError((error) {
          print('Error refreshing FCM Token: $error');
        });
  }

  Future<void> syncCurrentTokenWithBackend() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _registerTokenWithBackend(token);
  }

  Future<void> unregisterCurrentTokenFromBackend() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    try {
      await MobileApiService.unregisterPushDevice(token);
    } catch (error) {
      print('Failed to unregister FCM token: $error');
    }
  }

  Future<void> _registerTokenWithBackend(String token) async {
    try {
      await MobileApiService.registerPushDevice(token);
    } catch (error) {
      print('Failed to register FCM token: $error');
    }
  }

  Future<void> _requestPermissions() async {
    final result = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('User granted permission: ${result.authorizationStatus}');
  }

  void _onForegroundMessage(RemoteMessage message) {
    print("foreground message received: ${message.data.toString()}");

    _showNotificationFromMessage(
      message,
      show: (title, body, payload) async {
        final service = _localNotificationsService;
        if (service == null) return;
        await service.showNotification(title, body, payload);
      },
    );
  }

  //Handle notification taps when the app is opened from background or terminated state
  void _onMessageOpenedApp(RemoteMessage message) {
    print("Notification caused to open the app: ${message.data.toString()}");
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("background message received: ${message.data.toString()}");
  final localNotifications = LocalNotificationsService.instance();
  await localNotifications.init();
  await _showNotificationFromMessage(
    message,
    show: (title, body, payload) =>
        localNotifications.showNotification(title, body, payload),
  );
}

Future<void> _showNotificationFromMessage(
  RemoteMessage message, {
  required Future<void> Function(String? title, String? body, String? payload)
  show,
}) async {
  final notification = message.notification;
  final title = notification?.title ?? _titleFromData(message.data);
  final body = notification?.body ?? _bodyFromData(message.data);
  if ((title == null || title.isEmpty) || (body == null || body.isEmpty)) {
    return;
  }
  await show(title, body, jsonEncode(message.data));
}

String? _titleFromData(Map<String, dynamic> data) {
  final envelopeRaw = data['envelope'];
  if (envelopeRaw is String && envelopeRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(envelopeRaw);
      if (decoded is Map<String, dynamic>) {
        final eventType = decoded['type']?.toString();
        if (eventType == 'orders_bulk_touch') return 'სალარო';
        if (eventType == 'order_updated') return 'შეკვეთა';
        if (eventType == 'order_created') return 'შეკვეთა';
        if (eventType == 'order_cancelled') return 'შეკვეთა';
        if (eventType == 'tables_bulk_touch') return 'მაგიდები';
        if (eventType == 'table_updated') return null;
        if (eventType == 'data_updated') return null;
      }
    } catch (_) {}
  }
  final eventType = data['eventType']?.toString();
  if (eventType == 'orders_bulk_touch') return 'სალარო';
  if (eventType == 'order_updated') return 'შეკვეთა';
  if (eventType == 'order_created') return 'შეკვეთა';
  if (eventType == 'order_cancelled') return 'შეკვეთა';
  if (eventType == 'tables_bulk_touch') return 'მაგიდები';
  if (eventType == 'table_updated' || eventType == 'data_updated') return null;
  return null;
}

String? _bodyFromData(Map<String, dynamic> data) {
  final envelopeRaw = data['envelope'];
  if (envelopeRaw is String && envelopeRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(envelopeRaw);
      if (decoded is Map<String, dynamic>) {
        final payload = decoded['payload'];
        if (payload is Map<String, dynamic>) {
          final touches = payload['touches'];
          if (touches is List && touches.isNotEmpty) {
            final first = touches.first;
            if (first is Map<String, dynamic>) {
              final orderId = first['posOrderId']?.toString();
              final summary = first['changeSummary']?.toString() ?? '';
              if (orderId != null && orderId.isNotEmpty) {
                return summary.isNotEmpty
                    ? 'შეკვეთა #$orderId — $summary'
                    : 'შეკვეთა #$orderId განახლდა';
              }
            }
          }
        }
      }
    } catch (_) {}
  }
  return null;
}
