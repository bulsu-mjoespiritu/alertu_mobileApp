import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_store.dart';

class SOSNotifService {

  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  /// High-priority notification channel specifically for SOS Emergency Alerts
  static const AndroidNotificationChannel _sosChannel =
  AndroidNotificationChannel(
    'emergency_sos_channel',
    'Emergency SOS Alerts',
    description: 'High-priority notifications for active SOS emergency alerts and status updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initializes local notification settings for SOS emergency alerts
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
        debugPrint('🚨 SOS notification banner tapped: ${response.payload}');
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_sosChannel);
    }

    _isInitialized = true;
    debugPrint('✅ SOSNotifService initialized successfully.');
  }

  /// Displays a local heads-up push notification banner for SOS alerts and status updates
  static Future<void> showSOSNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Bug fix: SOS alerts never reached the shared NotificationStore, so
    // they never showed up in the in-app Notifications list even though a
    // system-tray banner appeared -- the single most safety-critical
    // notification in the app was also the one that could "disappear" the
    // moment the banner was dismissed. This is the same funnel every other
    // notification source uses (see NotificationService.showLocalNotification)
    // so the SOS alert is saved unconditionally, before anything that could
    // fail or return early below.
    notificationStore.addOrUpdate(
      NotificationItem(
        id: 'sos_$id',
        title: title,
        description: body,
        timestamp: DateTime.now(),
        isAlert: true,
      ),
    );

    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _sosChannel.id,
      _sosChannel.name,
      channelDescription: _sosChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/logo1',
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
      // Bug fix: this used to always show the same generic placeholder
      // text regardless of the title/body the caller actually passed in,
      // so every SOS banner (and now, every saved history entry above)
      // looked identical no matter what actually happened.
      await _localNotifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
      debugPrint('🔔 Local SOS notification displayed: $title - $body');
    } catch (e) {
      debugPrint('❌ Failed to display local SOS notification: $e');
    }
  }
}