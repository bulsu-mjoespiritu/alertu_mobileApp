import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A single notification entry shown on the Notifications page.
///
/// This model previously lived only inside `notifspage.dart` as page-local
/// state. It is now shared so that [NotificationService] (FCM) and any
/// other source can push real notifications into the same list the
/// Notifications page renders, instead of every source keeping its own
/// disconnected copy.
class NotificationItem {
  final String id;
  final String title;
  final String description;
  final DateTime timestamp;
  final bool isProcessing;
  final bool isSuccess;
  final bool isAlert;
  final bool isRead;

  /// Id of the incident report this notification is about, when there is
  /// one. Notifications used to be flat text ("A new incident has been
  /// reported. Please stay alert and stay safe.") with no way back to the
  /// thing they were about. Carrying the report id means tapping the
  /// notification can open the same live details screen the Reports page's
  /// "View Live Details" button opens.
  final String? reportId;

  /// Optional snapshot of the report itself, captured at the moment the
  /// notification was raised. When present the details screen opens
  /// instantly and works offline; when absent the page falls back to
  /// fetching by [reportId].
  final Map<String, dynamic>? reportData;

  NotificationItem({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
    this.isProcessing = false,
    this.isSuccess = false,
    this.isAlert = false,
    this.isRead = false,
    this.reportId,
    this.reportData,
  });

  /// True when this notification can open an incident details screen.
  bool get hasReportDetails =>
      (reportId != null && reportId!.trim().isNotEmpty) ||
      (reportData != null && reportData!.isNotEmpty);

  NotificationItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? timestamp,
    bool? isProcessing,
    bool? isSuccess,
    bool? isAlert,
    bool? isRead,
    String? reportId,
    Map<String, dynamic>? reportData,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      timestamp: timestamp ?? this.timestamp,
      isProcessing: isProcessing ?? this.isProcessing,
      isSuccess: isSuccess ?? this.isSuccess,
      isAlert: isAlert ?? this.isAlert,
      isRead: isRead ?? this.isRead,
      reportId: reportId ?? this.reportId,
      reportData: reportData ?? this.reportData,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'isProcessing': isProcessing,
        'isSuccess': isSuccess,
        'isAlert': isAlert,
        'isRead': isRead,
        if (reportId != null) 'reportId': reportId,
        if (reportData != null) 'reportData': reportData,
      };

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final rawReportData = json['reportData'];
    return NotificationItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      isProcessing: json['isProcessing'] as bool? ?? false,
      isSuccess: json['isSuccess'] as bool? ?? false,
      isAlert: json['isAlert'] as bool? ?? false,
      isRead: json['isRead'] as bool? ?? false,
      reportId: json['reportId'] as String?,
      reportData: rawReportData is Map
          ? Map<String, dynamic>.from(rawReportData)
          : null,
    );
  }
}

/// App-wide store of notifications the user has actually received (FCM
/// pushes and local proximity/status alerts today; any future source can
/// call [add] or [addOrUpdate]).
///
/// Follows the same singleton-service pattern already used elsewhere in
/// the app (see `ReportNotifService` / `NotificationService`).
///
/// Persistence: notifications are written to a small JSON file per signed
/// -in account under the app's documents directory (using `path_provider`,
/// already a dependency of this project -- no new package needed). This
/// means notifications now survive the app being closed, force-stopped, or
/// swiped from recent tasks, and are still there the next time the same
/// account signs back in. They are only ever removed by an explicit user
/// action ("Clear All" / the per-item "X") -- never by app lifecycle
/// events. See [loadForUser] / [clearInMemoryOnly] for how account
/// switches are handled without leaking one account's notifications into
/// another's view on a shared device.
class NotificationStore {
  NotificationStore._();

  static final NotificationStore instance = NotificationStore._();

  final ValueNotifier<List<NotificationItem>> notifications =
      ValueNotifier<List<NotificationItem>>(<NotificationItem>[]);

  final Set<String> _knownIds = <String>{};

  /// uid of the account the in-memory list currently belongs to. Null
  /// means "no account context yet" (signed out, or not loaded yet) --
  /// in that state nothing is persisted, since there's nowhere safe to
  /// scope the file to.
  String? _uid;

  /// Loads [uid]'s previously-saved notifications from disk and makes them
  /// the store's current contents, replacing whatever is in memory.
  ///
  /// Call this once per signed-in user -- e.g. from `Wrapper` when
  /// FirebaseAuth's uid changes -- not on every rebuild, since it always
  /// re-reads from disk. Safe to call again with the same uid; it's a
  /// no-op in that case.
  Future<void> loadForUser(String uid) async {
    if (_uid == uid) return;

    _uid = uid;
    _knownIds.clear();

    try {
      final file = await _fileForUser(uid);
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as List<dynamic>;
        final items = decoded
            .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final item in items) {
          _knownIds.add(item.id);
        }
        notifications.value = items;
      } else {
        notifications.value = <NotificationItem>[];
      }
    } catch (error) {
      debugPrint('NotificationStore: failed to load persisted notifications: $error');
      notifications.value = <NotificationItem>[];
    }
  }

  /// Drops the in-memory view only -- nothing on disk is touched.
  ///
  /// Call this immediately on sign-out (or the instant a different uid is
  /// detected, before [loadForUser] for the new uid finishes) so that a
  /// second account signing into the same device never sees the previous
  /// account's notifications, even briefly. The previous account's saved
  /// notifications are untouched and will reappear next time *they* sign
  /// in and [loadForUser] runs for their uid.
  void clearInMemoryOnly() {
    _uid = null;
    _knownIds.clear();
    notifications.value = <NotificationItem>[];
  }

  /// Adds a real notification to the shared list, newest first.
  ///
  /// Safe to call multiple times with the same [NotificationItem.id];
  /// duplicates are ignored so the same FCM message can't be counted twice
  /// (e.g. once via `onMessage` and again via `getInitialMessage` /
  /// `onMessageOpenedApp`).
  void add(NotificationItem item) {
    if (_knownIds.contains(item.id)) return;
    _knownIds.add(item.id);

    final updated = List<NotificationItem>.from(notifications.value)
      ..insert(0, item);
    notifications.value = updated;
    unawaited(_persist());
  }

  /// Adds [item] if its id hasn't been seen before; otherwise refreshes the
  /// existing entry with [item]'s content and moves it back to the top.
  /// Use this (instead of [add]) for sources that legitimately re-fire for
  /// the same id with updated content -- e.g. a proximity alert whose
  /// distance changes as the user keeps moving, still tied to the same
  /// report id. Repeated calls with identical content are a no-op beyond
  /// the reorder, so this also satisfies "notifications do not duplicate
  /// on repeated shows of the same id".
  void addOrUpdate(NotificationItem item) {
    final withoutExisting =
        notifications.value.where((existing) => existing.id != item.id).toList();
    _knownIds.add(item.id);
    notifications.value = <NotificationItem>[item, ...withoutExisting];
    unawaited(_persist());
  }

  /// Same as [addOrUpdate], but the returned Future only completes once the
  /// write to disk has actually finished. Background isolates (the FCM
  /// background message handler) can be torn down by the OS shortly after
  /// the handler returns, so a fire-and-forget write there risks never
  /// completing -- callers in that context should await this instead.
  Future<void> addOrUpdateAndFlush(NotificationItem item) async {
    final withoutExisting =
        notifications.value.where((existing) => existing.id != item.id).toList();
    _knownIds.add(item.id);
    notifications.value = <NotificationItem>[item, ...withoutExisting];
    await _persist();
  }

  void remove(String id) {
    _knownIds.remove(id);
    notifications.value =
        notifications.value.where((item) => item.id != id).toList();
    unawaited(_persist());
  }

  void update(
    String id,
    NotificationItem Function(NotificationItem current) transform,
  ) {
    notifications.value = notifications.value
        .map((item) => item.id == id ? transform(item) : item)
        .toList();
    unawaited(_persist());
  }

  /// Wipes every notification for the current account, in memory AND on
  /// disk. This is the one thing that should ever actually delete saved
  /// notifications -- call it from an explicit user action ("Clear All"),
  /// never automatically.
  void clear() {
    _knownIds.clear();
    notifications.value = <NotificationItem>[];

    final uid = _uid;
    if (uid != null) {
      unawaited(_deletePersistedFile(uid));
    }
  }

  Future<File> _fileForUser(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    // One file per account, so notifications never leak across accounts
    // signed into the same device.
    return File('${dir.path}/notifications_$uid.json');
  }

  Future<void> _persist() async {
    final uid = _uid;
    if (uid == null) return; // No signed-in account context -- nothing to save to.

    try {
      final file = await _fileForUser(uid);
      final raw =
          jsonEncode(notifications.value.map((item) => item.toJson()).toList());
      await file.writeAsString(raw);
    } catch (error) {
      debugPrint('NotificationStore: failed to persist notifications: $error');
    }
  }

  Future<void> _deletePersistedFile(String uid) async {
    try {
      final file = await _fileForUser(uid);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('NotificationStore: failed to delete persisted notifications: $error');
    }
  }
}

/// Convenience top-level reference, matching the app's existing
/// `reportNotifService`-style singleton accessors.
final notificationStore = NotificationStore.instance;
