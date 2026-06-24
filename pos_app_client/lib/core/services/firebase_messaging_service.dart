import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vynic/firebase_options.dart';
import 'package:vynic/core/services/auth_token_service.dart';
import 'package:vynic/core/services/local_notifications_service.dart';
import 'package:vynic/core/services/manager_notification_inbox.dart';
import 'package:vynic/core/services/mobile_api_service.dart';

class FirebaseMessagingService {
  FirebaseMessagingService._internal();

  static final FirebaseMessagingService _instance =
      FirebaseMessagingService._internal();

  factory FirebaseMessagingService.instance() => _instance;

  LocalNotificationsService? _localNotificationsService;
  bool _initialized = false;

  /// FCM only runs on Android/iOS. On desktop (Windows POS, or the macOS
  /// manager/tester client) Firebase is never initialized, so every messaging
  /// call must no-op instead of throwing "No Firebase App has been created".
  static bool get _fcmSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init({
    required LocalNotificationsService localNotificationsService,
  }) async {
    if (!_fcmSupported) return;
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
      debugPrint('FCM Token: $token');
      await _registerTokenWithBackend(token);
    }

    FirebaseMessaging.instance.onTokenRefresh
        .listen((fcmToken) async {
          debugPrint('FCM Token refreshed: $fcmToken');
          await _registerTokenWithBackend(fcmToken);
        })
        .onError((error) {
          debugPrint('Error refreshing FCM Token: $error');
        });
  }

  Future<void> syncCurrentTokenWithBackend() async {
    if (!_fcmSupported) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _registerTokenWithBackend(token);
  }

  Future<void> unregisterCurrentTokenFromBackend() async {
    if (!_fcmSupported) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    try {
      await MobileApiService.unregisterPushDevice(token);
    } catch (error) {
      debugPrint('Failed to unregister FCM token: $error');
    }
  }

  Future<void> _registerTokenWithBackend(String token) async {
    if (!AuthTokenService.hasValidToken) return;
    try {
      await MobileApiService.registerPushDevice(token);
    } catch (error) {
      debugPrint('Failed to register FCM token: $error');
    }
  }

  Future<void> _requestPermissions() async {
    final result = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('User granted permission: ${result.authorizationStatus}');
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint("foreground message received: ${message.data.toString()}");

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
    debugPrint("Notification caused to open the app: ${message.data.toString()}");
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background handlers run in a separate isolate with no Firebase context,
  // so Firebase must be initialized here before any Firebase API is used.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("background message received: ${message.data.toString()}");
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
  final envelopeRaw = message.data['envelope'];
  if (envelopeRaw is String && envelopeRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(envelopeRaw);
      if (decoded is Map<String, dynamic>) {
        ManagerNotificationInbox.ingestWsEnvelope(decoded, source: 'fcm');
        final title =
            message.data['title']?.toString() ??
            message.notification?.title ??
            _titleFromData(message.data);
        final body =
            message.data['body']?.toString() ??
            message.notification?.body ??
            _bodyFromData(message.data);
        if (title != null &&
            title.isNotEmpty &&
            body != null &&
            body.isNotEmpty) {
          await show(title, body, jsonEncode(message.data));
        }
        return;
      }
    } catch (_) {}
  }

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
        if (eventType == 'orders_bulk_touch') {
          final payload = decoded['payload'];
          if (payload is Map<String, dynamic>) {
            final touches = payload['touches'];
            if (touches is List &&
                touches.isNotEmpty &&
                touches.first is Map<String, dynamic>) {
              final kind = (touches.first['changeKind'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (kind == 'service_fee') return 'მაგიდები';
            }
          }
          return 'სალარო';
        }
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
  if (eventType == 'orders_bulk_touch') {
    final body = data['body']?.toString() ?? '';
    if (body.contains('სერვისის საფასური')) return 'მაგიდები';
    return 'სალარო';
  }
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
              final kind =
                  (first['changeKind'] ?? '').toString().trim().toLowerCase();
              final tableLabel = (first['tableLabel'] ?? '').toString().trim();
              final summary = first['changeSummary']?.toString() ?? '';
              final orderIdInt = int.tryParse(orderId ?? '');
              if (kind == 'service_fee' && orderIdInt != null) {
                return ManagerNotificationInbox.formatServiceFeeMessage(
                  orderId: orderIdInt,
                  tableLabel: tableLabel,
                  summary: summary,
                );
              }
              if (orderId != null && orderId.isNotEmpty) {
                final normalized =
                    ManagerNotificationInbox.normalizeServiceFeeSummary(
                  summary,
                );
                return summary.isNotEmpty
                    ? 'შეკვეთა #$orderId — $normalized'
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
