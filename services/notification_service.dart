import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_store.dart';

/// Top-level entry point function for background messaging.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🚨 Background Message Received: ${message.messageId}');

  // Bug fix: this used to only log. A background isolate can't reach the
  // main isolate's in-memory NotificationStore (isolates don't share
  // memory), so notifications that arrive while the app is backgrounded or
  // killed -- including when the system suppresses the visible banner
  // under Do Not Disturb -- never made it into the Notifications page.
  // NotificationStore's persistence is a plain JSON file on disk keyed by
  // uid, which (unlike in-memory state) IS shared across isolates, so
  // loading/writing through the same store class here reaches the same
  // file the main isolate reads back on next launch.
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return; // No signed-in account to scope this save to.

    await notificationStore.loadForUser(uid);

    final notification = message.notification;
    final String? title = notification?.title?.trim().isNotEmpty == true
        ? notification!.title!.trim()
        : (message.data['title'] as String?)?.trim();
    final String? body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!.trim()
        : (message.data['body'] as String?)?.trim();

    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      // Fully silent data-only push with nothing to show the user --
      // nothing worth saving to the visible notifications list.
      return;
    }

    final String id = message.messageId ??
        'fcm_${DateTime.now().microsecondsSinceEpoch}_${message.hashCode}';

    await notificationStore.addOrUpdateAndFlush(
      NotificationItem(
        id: id,
        title: (title == null || title.isEmpty) ? 'AlertU' : title,
        description: (body == null || body.isEmpty)
            ? 'You have a new AlertU update.'
            : body,
        timestamp: DateTime.now(),
      ),
    );
  } catch (error) {
    debugPrint('Background notification persistence failed: $error');
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// High-priority notification channel for Android foreground alerts
  static const AndroidNotificationChannel _emergencyChannel =
  AndroidNotificationChannel(
    'emergency_alerts_channel',
    'Emergency Alerts',
    description: 'High priority alerts for safety and incident reports',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Main initialization sequence
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _requestPermission();
    await _setupLocalNotifications();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _setupForegroundHandler();
    await _setupNotificationTapHandlers();
    await getFcmToken();

    _isInitialized = true;
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: true,
    );

    debugPrint('🔔 FCM Permission Status: ${settings.authorizationStatus}');
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings =
    AndroidInitializationSettings('@drawable/logo1');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTapPayload(response.payload);
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_emergencyChannel);
    }
  }

  void _setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📨 Foreground Message Received: ${message.notification?.title}');

      final notification = message.notification;
      final android = message.notification?.android;

      final String body = notification?.body?.trim().isNotEmpty == true
          ? notification!.body!.trim()
          : 'You have a new AlertU update.';

      if (notification != null && android != null && !kIsWeb) {
        // showLocalNotification is what actually saves this to the shared
        // NotificationStore now (see below) -- it's the single funnel
        // every notification source in the app uses, so saving is done
        // there once rather than duplicated here. A data-only FCM message
        // (no `notification` block) never reaches this branch and is
        // intentionally not added to the visible Notifications page,
        // matching that it was never shown to the user as a banner either.
        showLocalNotification(
          id: message.hashCode,
          title: 'AlertU',
          body: body,
          payload: message.data.toString(),
        );
      }
    });
  }

  /// Extracts the relevant data from an incoming FCM [message] and stores
  /// it in the shared [NotificationStore] so NotificationsPage can display
  /// it. Deduplicated by `message.messageId` inside the store, so this is
  /// safe to call from multiple entry points (foreground message, tapped
  /// notification, cold-start initial message) for the same push.
  void _saveToNotificationStore({
    required RemoteMessage message,
    required String title,
    required String body,
  }) {
    final String id = message.messageId ??
        'fcm_${DateTime.now().microsecondsSinceEpoch}_${message.hashCode}';

    notificationStore.add(
      NotificationItem(
        id: id,
        title: title,
        description: body,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<bool> areNotificationsEnabled() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;

    try {
      final citizens = FirebaseFirestore.instance.collection('citizens');

      final directSnapshot = await citizens.doc(uid).get();
      if (directSnapshot.exists) {
        return directSnapshot.data()?['notificationsEnabled'] != false;
      }

      final authUidQuery = await citizens
          .where('authUid', isEqualTo: uid)
          .limit(1)
          .get();
      if (authUidQuery.docs.isNotEmpty) {
        return authUidQuery.docs.first.data()['notificationsEnabled'] != false;
      }

      final legacyUidQuery = await citizens
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (legacyUidQuery.docs.isNotEmpty) {
        return legacyUidQuery.docs.first.data()['notificationsEnabled'] != false;
      }

      return true;
    } catch (error) {
      debugPrint('⚠️ Could not read notification preference: $error');
      return true;
    }
  }

  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    // Link back to the incident this alert is about, so the Notifications
    // page can open its live details when the card is tapped.
    String? reportId,
    Map<String, dynamic>? reportData,
  }) async {
    if (!await areNotificationsEnabled()) {
      debugPrint('🔕 Local notification suppressed because notifications are disabled.');
      return;
    }

    // Bug 3/4 fix (revised): this is the single funnel every notification
    // source in the app already calls before showing a system-tray banner
    // -- FCM foreground messages, nearby-incident proximity alerts,
    // inside/exited hazard-zone alerts, and approved-report alerts (see
    // nearbyreports_notifs.dart, insidethereports_notifs.dart,
    // userexitedreport_notifs.dart, reportnotifs.dart). Saving here, once,
    // instead of only in the FCM handler, means every one of those real
    // alerts -- including the "AlertU Nearby Incident" case -- now reaches
    // the Notifications page, not just FCM pushes.
    notificationStore.addOrUpdate(
      NotificationItem(
        id: 'local_$id',
        title: title,
        description: body,
        timestamp: DateTime.now(),
        reportId: reportId ?? payload,
        reportData: reportData,
      ),
    );

    final androidDetails = AndroidNotificationDetails(
      _emergencyChannel.id,
      _emergencyChannel.name,
      channelDescription: _emergencyChannel.description,
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

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  Future<void> _setupNotificationTapHandlers() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _saveTappedMessageToStore(initialMessage);
      _handleNotificationTapPayload(initialMessage.data.toString());
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📲 User tapped notification from background!');
      _saveTappedMessageToStore(message);
      _handleNotificationTapPayload(message.data.toString());
    });
  }

  /// Covers the case where the message arrived while the app was
  /// backgrounded/terminated (so `_setupForegroundHandler` never ran for
  /// it) and the user opened it by tapping the system notification. The
  /// store's own id-based deduplication means this is a no-op if the same
  /// message was already saved by the foreground handler.
  void _saveTappedMessageToStore(RemoteMessage message) {
    final notification = message.notification;
    final String title = notification?.title?.trim().isNotEmpty == true
        ? notification!.title!.trim()
        : 'AlertU';
    final String body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!.trim()
        : 'You have a new AlertU update.';

    _saveToNotificationStore(message: message, title: title, body: body);
  }

  void _handleNotificationTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    debugPrint('👉 Navigating/Processing Payload: $payload');
  }

  Future<String?> getFcmToken() async {
    try {
      final token = await _messaging.getToken();

      debugPrint('=================== 🔑 FCM TOKEN ===================');
      debugPrint('🔥 FCM Token: $token');
      debugPrint('====================================================');

      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('================ 🔄 FCM TOKEN REFRESHED ================');
        debugPrint('🔄 FCM Token Refreshed: $newToken');
        debugPrint('========================================================');
      });

      return token;
    } catch (e) {
      debugPrint('❌ Error fetching FCM Token: $e');
      return null;
    }
  }
}