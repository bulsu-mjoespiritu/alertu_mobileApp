import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Device-local ledger of the reports the signed-in citizen has personally
/// submitted -- the backing store for the "My Reports" tab.
///
/// Why this exists
/// ---------------
/// "My Reports" used to be a single Firestore query against the `reports`
/// collection filtered by `authUid`. That made the tab lossy in two ways:
///
///  * A report vanished from the tab the moment the backend/admin moved it
///    out of `reports` (into `approved_reports` when verified, into
///    `ResolvedReports` when closed) -- so a citizen's own report stopped
///    being "theirs" as soon as it became active or resolved, which is the
///    exact opposite of what the tab is for.
///  * Nothing appeared at all until the round trip finished, so a report
///    the user had just submitted didn't show up right away.
///
/// This store records a snapshot of every report at submission time and
/// keeps it forever, so "My Reports" piles up across every status. The
/// live data (status, admin notes, verification time) is still merged in
/// from the server on each load -- the local snapshot is only the floor,
/// never the ceiling.
///
/// Removal is strictly a user action: [hide] records an id the citizen
/// tapped the small "x" on. Hidden ids are filtered out of "My Reports"
/// only; the report itself is untouched on the server, so it still appears
/// in the global "Report History" tab exactly as before.
///
/// Persistence mirrors NotificationStore: one small JSON file per account
/// under the app documents directory (`path_provider`, already a
/// dependency), so nothing is lost when the app is closed or force-stopped.
class MyReportsStore {
  MyReportsStore._();

  static final MyReportsStore instance = MyReportsStore._();

  /// Locally recorded submissions, newest first.
  final ValueNotifier<List<Map<String, dynamic>>> submissions =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);

  /// Ids the citizen explicitly cleared from their "My Reports" list.
  final Set<String> _hiddenIds = <String>{};

  String? _uid;
  bool _isLoaded = false;

  Set<String> get hiddenIds => Set<String>.unmodifiable(_hiddenIds);

  /// Normalises the many id spellings used across this codebase
  /// (`id`, `_id`, `reportId`, `reportID`, `verifiedReportId`, ...) down to
  /// one comparable key, so the same report coming back from a different
  /// collection is recognised as the same report.
  static String? idOf(dynamic report) {
    if (report is! Map) return null;
    const keys = <String>[
      'reportId',
      'reportID',
      'verifiedReportId',
      'verifiedReportID',
      'verifiedreportID',
      'id',
      '_id',
    ];
    for (final key in keys) {
      final value = report[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// Loads [uid]'s ledger from disk. Safe to call repeatedly; re-reads only
  /// when the account actually changes.
  Future<void> loadForUser(String uid) async {
    if (_uid == uid && _isLoaded) return;

    _uid = uid;
    _hiddenIds.clear();
    submissions.value = <Map<String, dynamic>>[];

    try {
      final file = await _fileForUser(uid);
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final rawItems = decoded['submissions'];
          if (rawItems is List) {
            submissions.value = rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          final rawHidden = decoded['hidden'];
          if (rawHidden is List) {
            _hiddenIds.addAll(rawHidden.map((e) => e.toString()));
          }
        }
      }
    } catch (error) {
      debugPrint('MyReportsStore: failed to load ledger: $error');
    }

    _isLoaded = true;
  }

  /// Drops the in-memory view on sign-out. Nothing on disk is touched, so
  /// the same account sees their list again next time they sign in.
  void clearInMemoryOnly() {
    _uid = null;
    _isLoaded = false;
    _hiddenIds.clear();
    submissions.value = <Map<String, dynamic>>[];
  }

  /// Records a freshly submitted report so it shows in "My Reports"
  /// immediately -- before any backend round trip -- and stays there for
  /// good. Call this right after a successful submit.
  Future<void> recordSubmission(Map<String, dynamic> report) async {
    final uid = _uid;
    if (uid == null) return;

    final id = idOf(report);
    if (id == null) return;

    final sanitized = sanitize(report);
    sanitized['id'] = id;
    sanitized['reportId'] = id;
    sanitized['reportID'] = id;
    sanitized['isMySubmission'] = true;

    // A re-submit of the same id replaces the old snapshot rather than
    // stacking a second copy of it.
    final next = submissions.value
        .where((existing) => idOf(existing) != id)
        .toList()
      ..insert(0, sanitized);
    submissions.value = next;

    // Re-showing a report the user had previously cleared is the right
    // behaviour here: they just submitted it again.
    _hiddenIds.remove(id);

    await _persist();
  }

  /// Hides a single report from "My Reports" (the small "x"). The report
  /// stays on the server and keeps appearing in "Report History".
  Future<void> hide(String reportId) async {
    if (reportId.trim().isEmpty) return;
    _hiddenIds.add(reportId.trim());
    await _persist();
  }

  /// Undo for [hide] -- used by the "Undo" action on the confirmation
  /// snack bar.
  Future<void> unhide(String reportId) async {
    if (_hiddenIds.remove(reportId.trim())) {
      await _persist();
    }
  }

  bool isHidden(String? reportId) =>
      reportId != null && _hiddenIds.contains(reportId.trim());

  /// Converts Firestore-specific values (Timestamp, GeoPoint,
  /// DocumentReference) into plain JSON-safe values so a report map can be
  /// written to disk and read back without loss.
  static Map<String, dynamic> sanitize(Map<dynamic, dynamic> source) {
    final result = <String, dynamic>{};
    source.forEach((key, value) {
      result['$key'] = _sanitizeValue(value);
    });
    return result;
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value == null ||
        value is String ||
        value is num ||
        value is bool) {
      return value;
    }
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is GeoPoint) {
      return <String, dynamic>{
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    }
    if (value is DocumentReference) return value.path;
    if (value is Map) return sanitize(value);
    if (value is Iterable) return value.map(_sanitizeValue).toList();
    return value.toString();
  }

  Future<File> _fileForUser(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/my_reports_$uid.json');
  }

  Future<void> _persist() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final file = await _fileForUser(uid);
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'submissions': submissions.value,
        'hidden': _hiddenIds.toList(),
      }));
    } catch (error) {
      debugPrint('MyReportsStore: failed to persist ledger: $error');
    }
  }
}

/// Convenience top-level reference, matching the app's existing
/// `notificationStore` / `reportNotifService` style accessors.
final myReportsStore = MyReportsStore.instance;
