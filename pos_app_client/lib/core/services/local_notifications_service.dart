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

  Future<void> init() async {
    // check if already initialized
    if (_isFlutterLocalNotificationsInitialized) {
      return;
    }

    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    final initializationSettings = InitializationSettings(
      android: _androidInitializationSettings,
      iOS: _iosInitializationSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('Notification tapped: ${response.payload}');
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
    final fp = '$normalizedTitle|$normalizedBody';
    final now = DateTime.now();
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
}
