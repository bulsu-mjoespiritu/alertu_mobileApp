import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';

class NotifMessageService {

  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  /// High-priority notification channel specifically for Chat Messages
  static const AndroidNotificationChannel _chatChannel =
  AndroidNotificationChannel(
    'emergency_chat_channel',
    'Emergency Chat Messages',
    description: 'Real-time notifications for incoming dispatcher chat messages',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initializes local notification settings for chat alerts
  static Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings =
    AndroidInitializationSettings('drawable/logo1');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('💬 Chat notification banner tapped: ${response.payload}');
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_chatChannel);
    }

    _isInitialized = true;
    debugPrint('✅ NotifMessageService initialized successfully.');
  }

  /// Displays a local heads-up push notification banner for incoming chat messages
  static Future<void> showChatNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final notificationsEnabled =
    await NotificationService.instance.areNotificationsEnabled();
    if (!notificationsEnabled) {
      debugPrint('🔕 Chat push suppressed: notifications disabled.');
      return;
    }

    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _chatChannel.id,
      _chatChannel.name,
      channelDescription: _chatChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      icon: 'drawable/logo1',
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _localNotifications.show(
        id: id,
        title: 'AlertU',
        body: 'New message from the emergency team.',
        notificationDetails: notificationDetails,
        payload: payload,
      );
      debugPrint('🔔 Local chat notification displayed: $title - $body');
    } catch (e) {
      debugPrint('❌ Failed to display local chat notification: $e');
    }
  }
}