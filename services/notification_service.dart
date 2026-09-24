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

  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await notificationStore.loadForUser(uid);
    }

    final notification = message.notification;
    final String? title = notification?.title?.trim().isNotEmpty == true
        ? notification!.title!.trim()
        : (message.data['title'] as String?)?.trim();
    final String? body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!.trim()
        : ((message.data['message'] ?? message.data['body']) as String?)?.trim();

    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    // Admin broadcast alerts share the 'admin_alert_<id>' id used by the
    // Notifications page's Firestore/socket listeners, so the same alert
    // arriving over several channels collapses into one card.
    final String? alertId = message.data['alertId']?.toString();
    final String id = (alertId != null && alertId.isNotEmpty)
        ? 'admin_alert_$alertId'
        : (message.data['id'] ??
            message.messageId ??
            'fcm_${DateTime.now().microsecondsSinceEpoch}_${message.hashCode}');

    final bool isAlert = message.data['isAdminAlert'] == 'true' ||
        message.data.containsKey('alertId') ||
        (title != null && (title.contains('🚨') || title.toLowerCase().contains('alert') || title.toLowerCase().contains('warning')));

    await notificationStore.addOrUpdateAndFlush(
      NotificationItem(
        id: id,
        title: (title == null || title.isEmpty) ? 'AlertU Emergency' : title,
        description: (body == null || body.isEmpty)
            ? 'Emergency broadcast update from MDRRMO.'
            : body,
        timestamp: DateTime.now(),
        isAlert: isAlert,
        alertId: (alertId != null && alertId.isNotEmpty) ? alertId : null,
      ),
    );
  } catch (error) {
    debugPrint('Background notification persistence failed: $error');
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Admin alert ids that already raised a system notification this
  /// session, so the same alert arriving over FCM, the socket and the
  /// Firestore stream only buzzes the phone once.
  final Set<String> _deviceNotifiedAlertIds = <String>{};

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
    await subscribeToPublicTopics();

    _isInitialized = true;
  }

  /// Subscribes this device to broadcast emergency alert topics
  Future<void> subscribeToPublicTopics() async {
    try {
      await _messaging.subscribeToTopic('all_residents');
      await _messaging.subscribeToTopic('approved_reports');
      debugPrint('📢 Successfully subscribed to FCM topics: all_residents, approved_reports');
    } catch (e) {
      debugPrint('⚠️ Error subscribing to public topics: $e');
    }
  }

  static const List<String> paombongBarangays = [
    'Poblacion',
    'San Isidro',
    'San Jose',
    'Santo Rosario',
    'Santo Niño',
    'San Roque',
    'Binakod',
    'Kapitangan',
    'Malumot',
    'Masukol',
    'Pinalagdan',
    'San Vicente',
    'Santa Cruz',
    'Santo Cristo',
  ];

  /// Detects and extracts the canonical Paombong barangay name from any address or zone string
  static String? matchPaombongBarangay(String? addressOrZone) {
    if (addressOrZone == null || addressOrZone.trim().isEmpty) return null;
    final text = addressOrZone.toLowerCase().replaceAll('ñ', 'n').replaceAll('Ñ', 'n');

    final Map<String, String> lookup = {
      'poblacion': 'Poblacion',
      'san isidro': 'San Isidro',
      'san jose': 'San Jose',
      'santo rosario': 'Santo Rosario',
      'sto. rosario': 'Santo Rosario',
      'sto rosario': 'Santo Rosario',
      'santo nino': 'Santo Niño',
      'sto. nino': 'Santo Niño',
      'sto nino': 'Santo Niño',
      'san roque': 'San Roque',
      'binakod': 'Binakod',
      'kapitangan': 'Kapitangan',
      'malumot': 'Malumot',
      'masukol': 'Masukol',
      'pinalagdan': 'Pinalagdan',
      'san vicente': 'San Vicente',
      'santa cruz': 'Santa Cruz',
      'sta. cruz': 'Santa Cruz',
      'sta cruz': 'Santa Cruz',
      'santo cristo': 'Santo Cristo',
      'sto. cristo': 'Santo Cristo',
      'sto cristo': 'Santo Cristo',
    };

    for (final entry in lookup.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return addressOrZone.trim();
  }

  /// Normalizes a barangay name to match the server FCM topic format: [a-zA-Z0-9-_.~%]+
  static String normalizeBarangayTopic(String barangayName) {
    final matched = matchPaombongBarangay(barangayName) ?? barangayName;
    final cleaned = matched
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'^(brgy\.?|barangay)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bsto\.?\s*', caseSensitive: false), 'santo_')
        .replaceAll(RegExp(r'\bsta\.?\s*', caseSensitive: false), 'santa_')
        .replaceAll(RegExp(r'[ñÑ]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'barangay_$cleaned';
  }

  String? _currentSubscribedBarangayTopic;

  /// Syncs user's barangay topic subscription dynamically
  Future<void> syncBarangaySubscription(String? barangayName) async {
    if (barangayName == null || barangayName.trim().isEmpty) return;
    final newTopic = normalizeBarangayTopic(barangayName);
    if (newTopic == 'barangay_' || _currentSubscribedBarangayTopic == newTopic) return;

    try {
      if (_currentSubscribedBarangayTopic != null) {
        await _messaging.unsubscribeFromTopic(_currentSubscribedBarangayTopic!);
        debugPrint('🔕 Unsubscribed from previous barangay topic: $_currentSubscribedBarangayTopic');
      }
      await _messaging.subscribeToTopic(newTopic);
      _currentSubscribedBarangayTopic = newTopic;
      debugPrint('📢 Successfully subscribed to barangay topic: $newTopic');
    } catch (e) {
      debugPrint('⚠️ Error syncing barangay topic subscription: $e');
    }
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
      debugPrint('📨 Foreground Message Received: ${message.notification?.title ?? message.data['title']}');

      final notification = message.notification;
      final String title = notification?.title?.trim().isNotEmpty == true
          ? notification!.title!.trim()
          : (message.data['title']?.toString().trim() ?? '🚨 Emergency Alert');

      final String body = notification?.body?.trim().isNotEmpty == true
          ? notification!.body!.trim()
          : (message.data['message']?.toString().trim() ??
             message.data['body']?.toString().trim() ??
             'You have a new AlertU update.');

      final bool isAlert = message.data['isAdminAlert'] == 'true' ||
          message.data.containsKey('alertId') ||
          title.contains('🚨') ||
          title.toLowerCase().contains('alert') ||
          title.toLowerCase().contains('warning');

      if (!kIsWeb) {
        showLocalNotification(
          id: message.hashCode,
          title: title,
          body: body,
          payload: message.data.toString(),
          // An admin alert id is not a report id -- passing it as one made
          // the card try (and fail) to open incident details.
          alertId: message.data['alertId']?.toString(),
          reportId: message.data['alertId'] != null
              ? null
              : message.data['reportId']?.toString(),
          isAlertOverride: isAlert,
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
    final String? alertId = message.data['alertId']?.toString();
    final String id = (alertId != null && alertId.isNotEmpty)
        ? 'admin_alert_$alertId'
        : (message.data['id'] ??
            message.messageId ??
            'fcm_${DateTime.now().microsecondsSinceEpoch}_${message.hashCode}');

    final bool isAlert = message.data['isAdminAlert'] == 'true' ||
        message.data.containsKey('alertId') ||
        title.contains('🚨') ||
        title.toLowerCase().contains('alert') ||
        title.toLowerCase().contains('warning');

    notificationStore.add(
      NotificationItem(
        id: id,
        title: title,
        description: body,
        timestamp: DateTime.now(),
        isAlert: isAlert,
        alertId: (alertId != null && alertId.isNotEmpty) ? alertId : null,
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
    // Set for admin broadcast alerts so a tap opens the Alert Details card
    // instead of the incident details screen.
    String? alertId,
    bool? isAlertOverride,
    // Pass false when the caller has already saved a richer copy of this
    // notification to the store (e.g. the Notifications page, which keeps
    // the alert's details snapshot). Otherwise the store entry below would
    // overwrite it with a bare one.
    bool saveToStore = true,
  }) async {
    if (!await areNotificationsEnabled()) {
      debugPrint('🔕 Local notification suppressed because notifications are disabled.');
      return;
    }

    final bool isAlert = isAlertOverride ??
        (title.contains('🚨') ||
         title.toLowerCase().contains('alert') ||
         title.toLowerCase().contains('warning') ||
         title.toLowerCase().contains('danger'));

    if (saveToStore) {
      notificationStore.addOrUpdate(
        NotificationItem(
          id: (alertId != null && alertId.isNotEmpty)
              ? 'admin_alert_$alertId'
              : (reportId != null ? 'local_$reportId' : 'local_$id'),
          title: title,
          description: body,
          timestamp: DateTime.now(),
          isAlert: isAlert,
          reportId: (alertId != null && alertId.isNotEmpty)
              ? null
              : (reportId ?? payload),
          reportData: reportData,
          alertId: (alertId != null && alertId.isNotEmpty) ? alertId : null,
        ),
      );
    }

    // An admin alert can reach the phone by several routes at once (FCM,
    // the socket, the Firestore stream). Only the first one raises the
    // system notification; the rest just refresh the store above.
    if (alertId != null && alertId.isNotEmpty) {
      if (!_deviceNotifiedAlertIds.add(alertId)) {
        debugPrint('🔕 System notification for alert $alertId already shown.');
        return;
      }
    }

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
        : (message.data['title']?.toString().trim() ?? '🚨 Emergency Alert');
    final String body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!.trim()
        : (message.data['message']?.toString().trim() ??
           message.data['body']?.toString().trim() ??
           'You have a new AlertU update.');

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