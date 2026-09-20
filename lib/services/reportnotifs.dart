import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'clicksoundringtone.dart';
import 'my_reports_store.dart';
import 'notification_service.dart';

/// Watches `approved_reports` and displays a local notification when a new
/// approved report is added after the initial Firestore snapshot or received via FCM.
///
/// This service deliberately reuses NotificationService so the application
/// keeps one notification-plugin initialization, one FCM setup, and the
/// existing emergency notification channel.
class ReportNotifService {
  ReportNotifService._();

  static final ReportNotifService instance = ReportNotifService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _approvedReportsSubscription;

  final Set<String> _notifiedReportIds = <String>{};

  bool _hasReceivedInitialSnapshot = false;
  bool _isListening = false;

  /// Initializes the existing notification service and starts the Firestore
  /// listener. Call this after Firebase.initializeApp().
  Future<void> initializeAndStart() async {
    await NotificationService.instance.initialize();
    await startListening();
  }

  /// Starts listening for newly added documents in approved_reports.
  /// Existing documents from the first snapshot are ignored intentionally.
  Future<void> startListening() async {
    if (_isListening) return;

    await NotificationService.instance.initialize();

    _hasReceivedInitialSnapshot = false;
    _isListening = true;

    _approvedReportsSubscription = _firestore
        .collection('approved_reports')
        .snapshots()
        .listen(
      _handleSnapshot,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('❌ approved_reports snapshot error: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );

    debugPrint('👂 Listening for new documents in approved_reports.');
  }

  /// Stops the approved_reports listener without disposing the shared
  /// NotificationService used by the rest of the application.
  Future<void> stopListening() async {
    await _approvedReportsSubscription?.cancel();
    _approvedReportsSubscription = null;
    _isListening = false;
    _hasReceivedInitialSnapshot = false;
    debugPrint('🛑 Stopped approved_reports listener.');
  }

  /// Clears the in-memory set of notified report IDs.
  void clearNotifiedReportCache() {
    _notifiedReportIds.clear();
  }

  /// Public handler to process external or FCM notification payloads safely
  /// while ensuring duplicates are not re-triggered by the snapshot listener.
  Future<void> handleExternalReportNotification({
    required String documentId,
    required Map<String, dynamic> reportData,
  }) async {
    if (_notifiedReportIds.contains(documentId)) {
      debugPrint('ℹ️ Report $documentId already notified. Skipping duplicate.');
      return;
    }

    _notifiedReportIds.add(documentId);
    await _notifyForReport(documentId, reportData);
  }

  void _handleSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!_hasReceivedInitialSnapshot) {
      _hasReceivedInitialSnapshot = true;
      debugPrint(
        '📚 Initial approved_reports snapshot received '
            '(${snapshot.docs.length} existing reports ignored).',
      );
      return;
    }

    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;

      final documentId = change.doc.id;
      if (_notifiedReportIds.contains(documentId)) continue;

      final reportData = change.doc.data();
      if (reportData == null) {
        debugPrint('⚠️ approved_reports document has no data: $documentId');
        continue;
      }

      _notifiedReportIds.add(documentId);
      unawaited(_notifyForReport(documentId, reportData));
    }
  }

  Future<void> _notifyForReport(
      String documentId,
      Map<String, dynamic> report,
      ) async {
    try {
      final reportId = _readString(
        report,
        const <String>[
          'verifiedReportId',
          'verifiedReportID',
          'verifiedreportID',
          'reportID',
          'reportId',
        ],
      ) ??
          documentId;

      // The notification used to be a generic, contentless line ("A new
      // incident has been reported. Please stay alert and stay safe.")
      // that told the reader nothing about WHICH incident, WHERE, or how
      // serious -- and tapping it went nowhere. It now carries a short
      // summary of the actual report, and the report's id + a snapshot of
      // its data travel with it so the Notifications page can open the
      // same live details screen the Reports page opens.
      final String details = _buildIncidentSummary(report);

      // Play click ringtone concurrently with showing notification
      unawaited(ClickSoundRingtoneService.playClickSound());

      await NotificationService.instance.showLocalNotification(
        id: _notificationId(documentId),
        title: 'New Incident Reported',
        body: details,
        payload: reportId,
        reportId: reportId,
        reportData: MyReportsStore.sanitize(report),
      );

      debugPrint(
        '🔔 Approved-report notification displayed for $documentId ($reportId).',
      );
    } catch (error, stackTrace) {
      debugPrint('❌ Failed to notify for approved report $documentId: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Builds the one-line preview shown in the notification: what kind of
  /// incident it is, how severe, and where -- e.g.
  /// "Flood - HIGH severity - Brgy. Poblacion, Bulacan".
  String _buildIncidentSummary(Map<String, dynamic> report) {
    final String type = _readString(report, const <String>[
      'reportTitle',
      'incidentType',
      'title',
      'category',
      'hazard',
    ]) ??
        'Incident';

    final String? severity = _readString(report, const <String>[
      'severity',
      'hazardLevel',
      'severityLevel',
    ]);

    final String? location = _readLocation(report);

    final parts = <String>[
      type,
      if (severity != null && severity.isNotEmpty)
        '${severity.toUpperCase()} severity',
      if (location != null && location.isNotEmpty) location,
    ];

    return parts.join(' \u2022 ');
  }

  String? _readString(
      Map<String, dynamic> data,
      List<String> keys,
      ) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String? _readLocation(Map<String, dynamic> report) {
    final directLocation = _readString(
      report,
      const <String>['address', 'locationName', 'locationAddress'],
    );
    if (directLocation != null) return directLocation;

    final location = report['location'];
    if (location is Map) {
      final locationMap = Map<String, dynamic>.from(location);
      return _readString(
        locationMap,
        const <String>['address', 'name', 'formattedAddress'],
      );
    }

    return null;
  }

  int _notificationId(String documentId) {
    final positiveHash = documentId.hashCode & 0x7fffffff;
    return positiveHash == 0 ? 1 : positiveHash;
  }

  Future<void> dispose() async {
    await stopListening();
    _notifiedReportIds.clear();
  }
}

/// Convenience singleton reference for projects that prefer a top-level name.
final reportNotifService = ReportNotifService.instance;