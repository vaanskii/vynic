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

    final notificationData = message.notification;
    if (notificationData != null) {
      _localNotificationsService?.showNotification(
        notificationData.title,
        notificationData.body,
        message.data.toString(),
      );
    }
  }

  //Handle notification taps when the app is opened from background or terminated state
  void _onMessageOpenedApp(RemoteMessage message) {
    print("Notification caused to open the app: ${message.data.toString()}");
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("background message received: ${message.data.toString()}");
}
