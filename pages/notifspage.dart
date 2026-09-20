import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../services/socket.dart';
import '../services/notification_store.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../subpages/livedetails_reports.dart';

// NotificationItem now lives in notification_store.dart (Bug 3/4 fix) so
// that NotificationService (FCM) and this page share one model and one
// source of real data instead of each keeping a disconnected copy.

class NotificationsPage extends StatefulWidget {
  final ValueNotifier<bool>? visibility;

  const NotificationsPage({
    super.key,
    this.visibility,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late tz.Location _phLocation;
  bool _isTzInitialized = false;

  List<NotificationItem> _notifications = [];

  // 🛡️ Track processed event keys to eliminate multi-channel duplicates
  final Set<String> _processedEventKeys = {};

  // Track recent processing/approval timestamps for strict debouncing
  DateTime? _lastProcessingEventTime;
  DateTime? _lastApprovalEventTime;

  // Single shared event listener reference
  void Function(dynamic)? _socketEventListener;

  // Bug fix: notifications used to delete themselves. Any "transient"
  // notification (approval / rejection / nearby alert) that had been seen
  // started a 30-second timer and then slid itself off the list, and a
  // stray swipe could drop one too. A safety alert quietly vanishing while
  // the user is still reading it is the opposite of what an emergency app
  // should do, so the timers and the swipe-to-dismiss gesture are gone.
  //
  // A notification now leaves the list in exactly two ways, both explicit:
  //   * the "Clear All" button in the header, or
  //   * the small "x" on the notification itself.
  //
  // Report id currently being opened, used to show a spinner on that one
  // card while its details are fetched.
  String? _openingNotificationId;

  @override
  void initState() {
    super.initState();
    _initTimezone();

    // Bug 3/4 fix: pick up real notifications from the shared store (FCM
    // pushes today) instead of ever seeding fake data. _loadInitialNotifications
    // performs the first sync; the listener keeps the page updated as new
    // pushes arrive while it stays mounted.
    notificationStore.notifications.addListener(_syncFromStore);
    _loadInitialNotifications();

    widget.visibility?.addListener(_handleVisibilityChanged);

    if (widget.visibility?.value == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markVisibleNotificationsAsRead();
      });
    }

    // SocketService.on attaches to the live socket instance, so initialize
    // the socket first and register page listeners immediately afterward.
    _initializeRealtimeNotifications();
  }

  void _handleVisibilityChanged() {
    if (widget.visibility?.value == true && mounted) {
      _markVisibleNotificationsAsRead();
    }
  }

  void _markVisibleNotificationsAsRead() {
    if (!mounted) return;

    final unreadTransient = _notifications.where((item) =>
    !item.isRead && (item.isSuccess || item.isAlert));
    if (unreadTransient.isEmpty) return;

    final ids = unreadTransient.map((item) => item.id).toSet();
    setState(() {
      _notifications = _notifications.map((item) {
        return ids.contains(item.id) ? item.copyWith(isRead: true) : item;
      }).toList();
    });

    // Marking as read is purely cosmetic now -- it no longer starts a
    // countdown to deletion.
    for (final id in ids) {
      notificationStore.update(id, (current) => current.copyWith(isRead: true));
    }
  }

  /// Inserts or updates a notification in both the page's list and the
  /// shared store, keyed by id.
  ///
  /// Socket-driven notifications used to live only in this page's state,
  /// so they were lost on restart and could be silently replaced. Routing
  /// them through the store means they persist like every other
  /// notification and survive until the user clears them.
  void _upsertNotification(NotificationItem item) {
    setState(() {
      final index =
      _notifications.indexWhere((existing) => existing.id == item.id);
      if (index == -1) {
        _notifications.insert(0, item);
      } else {
        _notifications[index] = item;
      }
    });
    notificationStore.addOrUpdate(item);
  }

  /// Replaces the currently-open "Report Under Review" card with its
  /// outcome, in place, instead of deleting it and inserting a new one.
  /// Keeping the same entry means nothing ever disappears from the list on
  /// its own -- the card just changes what it says.
  NotificationItem? _findProcessingNotification() {
    final index = _notifications.indexWhere((item) => item.isProcessing);
    return index == -1 ? null : _notifications[index];
  }

  Future<void> _initializeRealtimeNotifications() async {
    try {
      await SocketService.initSocket();

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        SocketService.registerUserRoom(user.uid, null, 'citizen');
      }

      if (!mounted) return;
      _listenToRealtimeSocketEvents();
      debugPrint('✅ [NotificationsPage] Realtime listeners registered.');
    } catch (error) {
      debugPrint('❌ [NotificationsPage] Socket initialization failed: $error');
    }
  }

  void _initTimezone() {
    tz.initializeTimeZones();
    _phLocation = tz.getLocation('Asia/Manila');
    if (mounted) {
      setState(() => _isTzInitialized = true);
    }
  }

  // Bug 4 fix: this used to unconditionally replace _notifications with a
  // single hardcoded "Profile Ready" NotificationItem, both on first load
  // and on every pull-to-refresh (which also had the side effect of
  // wiping out any real socket-driven notifications already in the list).
  // There is no "initial notifications" data source in this app beyond
  // what the socket listeners and the shared NotificationStore produce, so
  // this now just re-syncs from the store and otherwise leaves the list
  // alone.
  void _loadInitialNotifications() {
    _syncFromStore();
  }

  /// Merges any NotificationStore entries (real FCM notifications) that
  /// aren't already reflected in [_notifications] into the page's list.
  /// Additive only: never removes or reorders existing socket-driven
  /// entries, so the review/approved/rejected dedup & expiry logic above
  /// is unaffected.
  void _syncFromStore() {
    if (!mounted) return;

    final storeItems = notificationStore.notifications.value;
    if (storeItems.isEmpty) return;

    final existingIds = _notifications.map((item) => item.id).toSet();
    final newItems =
        storeItems.where((item) => !existingIds.contains(item.id)).toList();
    if (newItems.isEmpty) return;

    setState(() {
      _notifications.insertAll(0, newItems);
    });
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      _loadInitialNotifications();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Notifications updated",
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  void _listenToRealtimeSocketEvents() {
    _cleanupSocketListeners();

    _socketEventListener = (dynamic data) {
      debugPrint('⚡ [NotificationsPage] Received real-time event: $data');
      if (!mounted) return;

      final Map<String, dynamic> eventData = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};

      final dynamic metadataValue = eventData['metadata'];
      Map<String, dynamic> metadata = <String, dynamic>{};
      if (metadataValue is Map) {
        metadata = Map<String, dynamic>.from(metadataValue);
      } else if (metadataValue is String && metadataValue.isNotEmpty) {
        try {
          final decoded = jsonDecode(metadataValue);
          if (decoded is Map) {
            metadata = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          debugPrint('⚠️ Invalid notification metadata JSON.');
        }
      }

      // 🔍 1. EXTRACT & INFER ACTION TYPE
      String action = (
          eventData['action'] ??
              eventData['eventType'] ??
              eventData['type'] ??
              eventData['status'] ??
              ''
      ).toString().trim().toUpperCase();

      final String status = (
          eventData['status'] ??
              metadata['status'] ??
              ''
      ).toString().trim().toUpperCase();

      // Fallback: If DISPATCH_VERIFIED_INCIDENT is emitted without explicit 'action' key
      if (action.isEmpty &&
          (eventData.containsKey('verifiedReportID') ||
              eventData.containsKey('agencies') ||
              eventData.containsKey('severity'))) {
        action = 'VERIFIED_REPORT_DISPATCH';
      }

      // 🔍 2. EXTRACT REPORT / TARGET IDENTIFIER
      final String reportId = (
          eventData['reportId'] ??
              eventData['reportID'] ??
              eventData['verifiedReportID'] ??
              metadata['reportId'] ??
              metadata['reportID'] ??
              ''
      ).toString().trim();

      final String fallbackTarget =
          eventData['target']?.toString().trim() ?? '';
      final String target = reportId.isNotEmpty ? reportId : fallbackTarget;
      final String rawEventId = (
          eventData['eventId'] ??
              eventData['id'] ??
              ''
      ).toString().trim();

      final now = DateTime.now();

      // 🛡️ 3. DEDUPLICATION CHECK: Generate a unique signature for every incoming payload
      final String eventSignature = rawEventId.isNotEmpty
          ? rawEventId
          : '${action}_${status}_${target}_${now.millisecondsSinceEpoch ~/ 3000}'; // 3-second bucket fallback

      if (_processedEventKeys.contains(eventSignature)) {
        debugPrint(
            '🛑 [NotificationsPage] Duplicate event payload ($eventSignature) suppressed.');
        return;
      }
      _processedEventKeys.add(eventSignature);

      // Keep cache small (max 50 recent events)
      if (_processedEventKeys.length > 50) {
        _processedEventKeys.remove(_processedEventKeys.first);
      }

      // 🛑 ACTION 1: CLOSE / CANCEL MODAL -> REMOVE REVIEW NOTIFICATION
      final bool isCloseAction = action == 'CLOSE_VERIFY_MODAL' ||
          action == 'CANCEL_VERIFY_MODAL' ||
          action == 'MODAL_CLOSED' ||
          action == 'VERIFY_MODAL_CLOSED' ||
          status == 'CANCELLED';

      if (isCloseAction) {
        // Previously this DELETED the "Report Under Review" card outright.
        // Notifications are no longer removed by anything except the user's
        // own "Clear All" / "x", so the card stays and simply stops showing
        // the in-progress spinner.
        final processing = _findProcessingNotification();
        if (processing != null) {
          _upsertNotification(
            processing.copyWith(
              title: 'Report Review Paused',
              description:
              'Dispatch operators have stepped away from reviewing your '
                  'report. You will be notified when the review resumes.',
              isProcessing: false,
              timestamp: now,
            ),
          );
        }
        debugPrint(
            'ℹ️ [NotificationsPage] Verification modal closed. Review card updated in place.');
        return;
      }

      // 🎉 Resolve approval before review matching. A verified event may
      // still contain stale IN_PROGRESS metadata.
      final bool isApprovedAction = action == 'REPORT_APPROVED' ||
          action == 'REPORT_VERIFIED' ||
          action == 'VERIFIED_REPORT_DISPATCH' ||
          action == 'DISPATCH_FINALIZED' ||
          action == 'DISPATCH_VERIFIED_INCIDENT' ||
          action == 'APPROVED' ||
          action == 'VERIFIED' ||
          status == 'APPROVED' ||
          status == 'VERIFIED' ||
          status == 'DISPATCHED' ||
          status == 'COMPLETED';

      // ⛔ ACTION 2: REPORT REJECTED
      final bool isRejectedAction = action == 'REPORT_REJECTED' ||
          action == 'REJECTED_REPORT' ||
          status == 'REJECTED';

      if (isRejectedAction) {
        final String uniqueId = rawEventId.isNotEmpty
            ? rawEventId
            : 'rejected_${target}_${now.microsecondsSinceEpoch}';
        final String reportLabel = target.isNotEmpty ? target : 'your incident';

        // The under-review card for this report is TRANSFORMED into the
        // outcome rather than deleted and replaced, so the list never
        // loses an entry on its own. Reusing the same id also means a
        // repeated rejection event updates the existing card instead of
        // stacking a duplicate -- which is what the old
        // "removeWhere(description.contains(...))" hack was working around.
        final processing = _findProcessingNotification();
        _upsertNotification(
          NotificationItem(
            id: processing?.id ?? 'rejected_$uniqueId',
            title: 'Report Rejected',
            description:
            'Your emergency report for $reportLabel was not approved and has been moved to the rejected archive.',
            timestamp: now,
            isProcessing: false,
            isSuccess: false,
            isAlert: true,
            reportId: reportId.isNotEmpty ? reportId : null,
          ),
        );
        if (widget.visibility?.value == true) {
          _markVisibleNotificationsAsRead();
        }

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFBE123C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            content: Row(
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Report rejected. View Notifications for details.',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // 🟢 ACTION 3: OPEN / ADVANCE VERIFICATION MODAL
      final bool isReviewAction = !isApprovedAction && !isRejectedAction &&
          (action == 'REPORT_UNDER_REVIEW' ||
              action == 'OPEN_VERIFY_MODAL' ||
              action == 'START_VERIFY_WORKFLOW' ||
              action == 'VERIFY_STEP_ADVANCE' ||
              action == 'UNDER_REVIEW' ||
              status == 'UNDER_REVIEW' ||
              status == 'IN_PROGRESS');

      if (isReviewAction) {
        _lastProcessingEventTime = now;

        final String eventKey = rawEventId.isNotEmpty
            ? rawEventId
            : '${action}_${target}_${now.microsecondsSinceEpoch}';
        final String newDescription =
            'Your incident report ${target.isNotEmpty ? "($target) " : ""}'
            'is being reviewed by dispatch operators.';

        // Update the existing under-review card if there is one, otherwise
        // open a new one. Either way it goes through the shared store so it
        // survives an app restart like every other notification.
        final existing = _findProcessingNotification();
        _upsertNotification(
          (existing ??
              NotificationItem(
                id: eventKey,
                title: 'Report Under Review',
                description: newDescription,
                timestamp: now,
                isProcessing: true,
                isSuccess: false,
              ))
              .copyWith(
            title: 'Report Under Review',
            description: newDescription,
            timestamp: now,
            isProcessing: true,
            reportId: reportId.isNotEmpty ? reportId : null,
          ),
        );
        if (widget.visibility?.value == true) {
          _markVisibleNotificationsAsRead();
        }
        return;
      }

      // 🎉 ACTION 3: REPORT VERIFIED & DISPATCHED (ROBUST MATCHING FIX)
      if (isApprovedAction) {
        // Strict 4-second approval debounce window
        if (_lastApprovalEventTime != null &&
            now.difference(_lastApprovalEventTime!).inSeconds < 4) {
          debugPrint(
              '⚠️ [NotificationsPage] Suppressed duplicate approval event within 4s window.');
          return;
        }
        _lastApprovalEventTime = now;

        final String uniqueId =
            '${now.microsecondsSinceEpoch}_${rawEventId.isNotEmpty ? rawEventId : 'evt'}';
        final String reportLabel =
        target.isNotEmpty ? target : 'your incident';

        // Same idea as the rejection branch: the existing under-review card
        // becomes the approval card in place. Nothing is deleted, and
        // keying on that card's id makes a duplicate approval event update
        // it rather than add a second one.
        final processing = _findProcessingNotification();
        _upsertNotification(
          NotificationItem(
            id: processing?.id ?? 'approved_$uniqueId',
            title: 'Report Approved & Dispatched',
            description:
            'Emergency responders have been dispatched for $reportLabel. Help is on the way!',
            timestamp: now,
            isProcessing: false,
            isSuccess: true,
            isAlert: false,
            reportId: reportId.isNotEmpty ? reportId : null,
          ),
        );
        if (widget.visibility?.value == true) {
          _markVisibleNotificationsAsRead();
        }

        // 4. Show EXACTLY 1 floating banner toast
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            content: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle2,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Report Approved! Responders notified.",
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    };

    // 🔗 Register all real-time events emitted by Web Admin / Node Backend
    SocketService.on('CITIZEN_NOTIFICATION', _socketEventListener!);
    SocketService.on('ADMIN_ACTION_EVENT', _socketEventListener!);
    SocketService.on('CITIZEN_REPORT_UPDATED', _socketEventListener!);
    SocketService.on('DISPATCH_VERIFIED_INCIDENT', _socketEventListener!);
  }

  void _cleanupSocketListeners() {
    SocketService.off('CITIZEN_NOTIFICATION');
    SocketService.off('ADMIN_ACTION_EVENT');
    SocketService.off('CITIZEN_REPORT_UPDATED');
    SocketService.off('DISPATCH_VERIFIED_INCIDENT');
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_handleVisibilityChanged);
    notificationStore.notifications.removeListener(_syncFromStore);
    _cleanupSocketListeners();
    super.dispose();
  }

  tz.TZDateTime _toPhTime(DateTime dt) {
    return tz.TZDateTime.from(dt, _phLocation);
  }

  String _formatTime(DateTime dt) {
    if (!_isTzInitialized) return '';
    final phTime = _toPhTime(dt);
    final hour = phTime.hour == 0
        ? 12
        : (phTime.hour > 12 ? phTime.hour - 12 : phTime.hour);
    final minute = phTime.minute.toString().padLeft(2, '0');
    final period = phTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _getSectionHeader(DateTime dt) {
    if (!_isTzInitialized) return 'Notifications';
    final phNow = tz.TZDateTime.now(_phLocation);
    final phTarget = _toPhTime(dt);

    final todayDate =
    tz.TZDateTime(_phLocation, phNow.year, phNow.month, phNow.day);
    final targetDate = tz.TZDateTime(
        _phLocation, phTarget.year, phTarget.month, phTarget.day);

    final differenceInDays = todayDate.difference(targetDate).inDays;

    if (differenceInDays == 0) return 'Today';
    if (differenceInDays == 1) return 'Yesterday';
    return 'Earlier';
  }

  Map<String, List<NotificationItem>> _groupNotifications() {
    final Map<String, List<NotificationItem>> grouped = {
      'Today': [],
      'Yesterday': [],
      'Earlier': [],
    };

    for (var item in _notifications) {
      final section = _getSectionHeader(item.timestamp);
      grouped[section]?.add(item);
    }

    grouped.removeWhere((key, value) => value.isEmpty);
    return grouped;
  }

  void _deleteNotification(NotificationItem item) {
    setState(() {
      _notifications.removeWhere((element) => element.id == item.id);
    });
    // Keep the shared store in sync so a swiped-away FCM notification
    // doesn't get re-merged back in by _syncFromStore on the next store
    // change. No-op if this item never came from the store.
    notificationStore.remove(item.id);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Notification dismissed",
          style: GoogleFonts.montserrat(fontSize: 12),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Shows a confirmation dialog before wiping every notification -- this
  /// is destructive and unrecoverable (there's no persistence layer behind
  /// it), so a stray tap shouldn't silently empty the list.
  void _confirmClearAll() {
    if (_notifications.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Clear All Notifications"),
        content: const Text(
          "This will remove all notifications from this list. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _clearAllNotifications();
            },
            child: const Text("Clear All", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _clearAllNotifications() {
    // One of only two ways a notification ever leaves this list (the other
    // being the per-item "x" below).
    setState(() {
      _notifications.clear();
    });
    // Clears the shared store too, so real (FCM/local) notifications don't
    // silently repopulate the list on the next _syncFromStore call.
    notificationStore.clear();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "All notifications cleared",
          style: GoogleFonts.montserrat(fontSize: 12),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupNotifications();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = theme.colorScheme.primary;
    final headerTextColor = theme.textTheme.titleLarge?.color ??
        (isDark ? Colors.white : const Color(0xFF0F172A));
    final sectionHeaderColor =
    isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    final emptyIconBg =
    isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final emptyTextColor =
    isDark ? Colors.grey.shade400 : const Color(0xFF64748B);

    return FScaffold(
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: primaryColor,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // 1. TOP-LEFT HEADER + CLEAR ALL
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Notifications",
                      style: GoogleFonts.montserrat(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: headerTextColor,
                      ),
                    ),
                    if (_notifications.isNotEmpty)
                      TextButton.icon(
                        onPressed: _confirmClearAll,
                        style: TextButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.grey.shade300
                              : const Color(0xFF64748B),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(LucideIcons.trash2, size: 15),
                        label: Text(
                          "Clear All",
                          style: GoogleFonts.montserrat(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 2. EMPTY STATE OR GROUPED LIST
              if (_notifications.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: emptyIconBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.bellOff,
                            size: 28,
                            color: isDark
                                ? Colors.grey.shade500
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No notifications yet",
                          style: GoogleFonts.montserrat(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: emptyTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...grouped.keys.map((sectionKey) {
                  final items = grouped[sectionKey]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // DATE SECTION HEADER
                      Padding(
                        padding:
                        const EdgeInsets.only(top: 8, bottom: 6, left: 2),
                        child: Text(
                          sectionKey.toUpperCase(),
                          style: GoogleFonts.montserrat(
                            color: sectionHeaderColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      ...items.map((item) =>
                          _buildNotificationCard(item, isDark)),
                    ],
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(NotificationItem item, bool isDark) {
    // Dynamic theme colors for light/dark modes
    final Color cardBorderColor = item.isSuccess
        ? (isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0))
        : (item.isAlert
        ? (isDark ? const Color(0xFF881337) : const Color(0xFFFECDD3))
        : (item.isProcessing
        ? (isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE))
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))));

    final Color cardBgColor = item.isSuccess
        ? (isDark ? const Color(0xFF022C22) : const Color(0xFFECFDF5))
        : (item.isAlert
        ? (isDark ? const Color(0xFF4C0519) : const Color(0xFFFFF1F2))
        : (item.isProcessing
        ? (isDark ? const Color(0xFF172554) : const Color(0xFFEFF6FF))
        : (isDark ? const Color(0xFF1E293B) : Colors.white)));

    final Color titleTextColor = item.isSuccess
        ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46))
        : (item.isAlert
        ? (isDark ? const Color(0xFFFDA4AF) : const Color(0xFF9F1239))
        : (isDark ? Colors.white : const Color(0xFF0F172A)));

    final Color bodyTextColor = item.isSuccess
        ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF047857))
        : (item.isAlert
        ? (isDark ? const Color(0xFFFECACA) : const Color(0xFFBE123C))
        : (isDark ? Colors.grey.shade300 : const Color(0xFF475569)));

    final Color timeTextColor =
    isDark ? Colors.grey.shade400 : const Color(0xFF94A3B8);

    final bool canOpenDetails = item.hasReportDetails;
    final bool isOpening = _openingNotificationId == item.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Tapping a notification that is about a specific incident now
          // opens that incident's live details -- the same screen the
          // Reports page's "View Live Details" button opens. Notifications
          // with no report behind them (generic app updates) stay inert.
          onTap: canOpenDetails && !isOpening
              ? () => _openReportDetails(item)
              : null,
          child: Container(
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0xFF0F172A))
                  .withOpacity(isDark ? 0.2 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeadingIndicator(item, isDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: titleTextColor,
                          ),
                        ),
                      ),
                      Text(
                        _formatTime(item.timestamp),
                        style: GoogleFonts.montserrat(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: timeTextColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // The per-item "x" -- one of the only two ways a
                      // notification is ever removed (the other being
                      // "Clear All"). Swipe-to-dismiss used to do this too
                      // and has been taken out, because an accidental swipe
                      // silently losing a safety alert is not acceptable in
                      // an emergency app.
                      InkWell(
                        onTap: () => _deleteNotification(item),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Icon(
                            LucideIcons.x,
                            size: 14,
                            color: timeTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    style: TextStyle(
                      fontFamily:
                      Theme.of(context).textTheme.bodyMedium?.fontFamily,
                      fontSize: 11.5,
                      color: bodyTextColor,
                      height: 1.35,
                      fontWeight:
                      item.isSuccess ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                  // Affordance so it's obvious the card leads somewhere.
                  if (canOpenDetails) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (isOpening)
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              valueColor:
                              AlwaysStoppedAnimation<Color>(bodyTextColor),
                            ),
                          )
                        else
                          Icon(
                            LucideIcons.arrowRight,
                            size: 12,
                            color: bodyTextColor,
                          ),
                        const SizedBox(width: 5),
                        Text(
                          isOpening ? 'Opening...' : 'View incident details',
                          style: GoogleFonts.montserrat(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: bodyTextColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  /// Opens the live details screen for the incident a notification is
  /// about. Uses the snapshot captured when the alert was raised if there
  /// is one; otherwise looks the report up by id across the collections it
  /// could have moved into (pending -> approved -> resolved).
  Future<void> _openReportDetails(NotificationItem item) async {
    final Map<String, dynamic>? cached = item.reportData;
    if (cached != null && cached.isNotEmpty) {
      _pushDetails(Map<String, dynamic>.from(cached));
      return;
    }

    final String? reportId = item.reportId?.trim();
    if (reportId == null || reportId.isEmpty) return;

    setState(() => _openingNotificationId = item.id);

    Map<String, dynamic>? found;
    const collections = <String>[
      'approved_reports',
      'reports',
      'ResolvedReports',
    ];

    for (final collection in collections) {
      if (found != null) break;
      try {
        final ref = FirebaseFirestore.instance.collection(collection);

        // Direct document id first -- the common case.
        final doc = await ref.doc(reportId).get();
        if (doc.exists && doc.data() != null) {
          found = Map<String, dynamic>.from(doc.data()!);
          found['id'] ??= doc.id;
          break;
        }

        // Then the report's own business id, which is not always the
        // Firestore document id.
        for (final field in const <String>['reportID', 'reportId', 'verifiedReportID']) {
          final query =
          await ref.where(field, isEqualTo: reportId).limit(1).get();
          if (query.docs.isNotEmpty) {
            found = Map<String, dynamic>.from(query.docs.first.data());
            found['id'] ??= query.docs.first.id;
            break;
          }
        }
      } catch (error) {
        debugPrint('Notification details lookup failed in $collection: $error');
      }
    }

    if (!mounted) return;
    setState(() => _openingNotificationId = null);

    if (found == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          content: Text(
            'This incident is no longer available.',
            style: GoogleFonts.montserrat(fontSize: 12),
          ),
        ),
      );
      return;
    }

    _pushDetails(found);
  }

  void _pushDetails(Map<String, dynamic> reportData) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveDetailsReports(reportData: reportData),
      ),
    );
  }

  Widget _buildLeadingIndicator(NotificationItem item, bool isDark) {
    if (item.isProcessing) {
      return AnimatedLeadingIndicator(isDark: isDark);
    }

    if (item.isSuccess) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          LucideIcons.checkCircle2,
          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
          size: 18,
        ),
      );
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        item.isAlert ? LucideIcons.triangleAlert : LucideIcons.mailCheck,
        color: item.isAlert
            ? (isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48))
            : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
        size: 16,
      ),
    );
  }
}

class AnimatedLeadingIndicator extends StatelessWidget {
  final bool isDark;

  const AnimatedLeadingIndicator({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final primaryBlue =
    isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    final trackColor =
    isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final circleBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return RepaintBoundary(
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                backgroundColor: trackColor,
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: circleBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.fileSearch,
                size: 14,
                color: primaryBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}