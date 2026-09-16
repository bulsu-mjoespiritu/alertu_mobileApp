import 'package:flutter/foundation.dart';

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

  NotificationItem({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
    this.isProcessing = false,
    this.isSuccess = false,
    this.isAlert = false,
    this.isRead = false,
  });

  NotificationItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? timestamp,
    bool? isProcessing,
    bool? isSuccess,
    bool? isAlert,
    bool? isRead,
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
    );
  }
}

/// App-wide, in-memory store of notifications the user has actually
/// received (FCM pushes today; any future source can call [add]).
///
/// This follows the same singleton-service pattern already used elsewhere
/// in the app (see `ReportNotifService` / `NotificationService`) rather
/// than introducing a new state-management dependency.
///
/// Scope note: this store does NOT persist across app restarts. The
/// project has no local database (no Hive/SQLite/SharedPreferences) and
/// adding one is out of scope for this fix. Firestore, which the app
/// already uses extensively elsewhere, would be the natural place to add
/// real cross-restart persistence later -- this store is structured
/// (single `add`/`remove`/`update` entry points) so that swapping the
/// backing storage for a Firestore-backed one later is a small,
/// contained change rather than another repo-wide refactor.
class NotificationStore {
  NotificationStore._();

  static final NotificationStore instance = NotificationStore._();

  final ValueNotifier<List<NotificationItem>> notifications =
      ValueNotifier<List<NotificationItem>>(<NotificationItem>[]);

  final Set<String> _knownIds = <String>{};

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
  }

  void remove(String id) {
    _knownIds.remove(id);
    notifications.value =
        notifications.value.where((item) => item.id != id).toList();
  }

  void update(
    String id,
    NotificationItem Function(NotificationItem current) transform,
  ) {
    notifications.value = notifications.value
        .map((item) => item.id == id ? transform(item) : item)
        .toList();
  }

  void clear() {
    _knownIds.clear();
    notifications.value = <NotificationItem>[];
  }
}

/// Convenience top-level reference, matching the app's existing
/// `reportNotifService`-style singleton accessors.
final notificationStore = NotificationStore.instance;
