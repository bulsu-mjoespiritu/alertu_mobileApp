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

  // A timer is created only after a transient notification becomes visible/read.
  final Map<String, Timer> _expiryTimers = {};
  final Set<String> _expiringNotificationIds = {};
  static const Duration _readExpiryDuration = Duration(seconds: 30);
  static const Duration _swipeOutDuration = Duration(milliseconds: 420);

  @override
  void initState() {
    super.initState();
    _initTimezone();
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

    for (final id in ids) {
      _scheduleExpiry(id);
    }
  }

  void _scheduleExpiry(String notificationId) {
    _expiryTimers[notificationId]?.cancel();
    _expiryTimers[notificationId] = Timer(_readExpiryDuration, () {
      _expireNotification(notificationId);
    });
  }

  Future<void> _expireNotification(String notificationId) async {
    if (!mounted || !_notifications.any((item) => item.id == notificationId)) {
      _expiryTimers.remove(notificationId);
      return;
    }

    _expiryTimers.remove(notificationId);
    setState(() => _expiringNotificationIds.add(notificationId));

    await Future.delayed(_swipeOutDuration);
    if (!mounted) return;

    setState(() {
      _notifications.removeWhere((item) => item.id == notificationId);
      _expiringNotificationIds.remove(notificationId);
    });
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

  void _loadInitialNotifications() {
    final user = FirebaseAuth.instance.currentUser;

    final DateTime createdAt = user?.metadata.creationTime ??
        DateTime.now().subtract(const Duration(days: 1));

    setState(() {
      _notifications = [
        NotificationItem(
          id: '0',
          title: 'Profile Ready',
          description:
          'Your emergency reporting profile is active and ready.',
          timestamp: createdAt,
          isProcessing: false,
          isSuccess: false,
          isAlert: false,
        ),
      ];
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
        setState(() {
          _notifications.removeWhere((item) => item.isProcessing);
        });
        debugPrint(
            '🗑️ [NotificationsPage] Verification modal closed. Active review notifications removed.');
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

        setState(() {
          _notifications.removeWhere((item) => item.isProcessing);
          _notifications.removeWhere((item) =>
          item.isAlert &&
              item.description.contains(reportLabel) &&
              now.difference(item.timestamp).inMinutes < 5);
          _notifications.insert(
            0,
            NotificationItem(
              id: uniqueId,
              title: 'Report Rejected',
              description:
              'Your emergency report for $reportLabel was not approved and has been moved to the rejected archive.',
              timestamp: now,
              isProcessing: false,
              isSuccess: false,
              isAlert: true,
            ),
          );
        });
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

        setState(() {
          // Check if an under-review card is already present in list
          final existingIndex =
          _notifications.indexWhere((item) => item.isProcessing);

          if (existingIndex != -1) {
            // Update existing processing notification in-place instead of creating a second card
            _notifications[existingIndex] =
                _notifications[existingIndex].copyWith(
                  description: newDescription,
                  timestamp: now,
                );
          } else {
            // Insert brand new card if none existed
            _notifications.insert(
              0,
              NotificationItem(
                id: eventKey,
                title: 'Report Under Review',
                description: newDescription,
                timestamp: now,
                isProcessing: true,
                isSuccess: false,
              ),
            );
          }
        });
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

        setState(() {
          // 1. Remove active under-review card
          _notifications.removeWhere((item) => item.isProcessing);

          // 2. Prevent duplicate approval cards for the exact same report ID if already added
          _notifications.removeWhere((item) =>
          item.isSuccess &&
              item.description.contains(reportLabel) &&
              now.difference(item.timestamp).inMinutes < 5);

          // 3. Insert single success notification card
          _notifications.insert(
            0,
            NotificationItem(
              id: uniqueId,
              title: 'Report Approved & Dispatched',
              description:
              'Emergency responders have been dispatched for $reportLabel. Help is on the way!',
              timestamp: now,
              isProcessing: false,
              isSuccess: true,
              isAlert: false,
            ),
          );
        });
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
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    _expiringNotificationIds.clear();
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
              // 1. TOP-LEFT HEADER
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Notifications",
                    style: GoogleFonts.montserrat(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: headerTextColor,
                    ),
                  ),
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
                      ...items.asMap().entries.map((entry) =>
                          _buildDismissibleCard(
                              entry.value, entry.key, isDark)),
                    ],
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDismissibleCard(NotificationItem item, int index, bool isDark) {
    final bool isExpiring = _expiringNotificationIds.contains(item.id);

    return AnimatedSize(
      duration: _swipeOutDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        duration: _swipeOutDuration,
        curve: Curves.easeInCubic,
        offset: isExpiring ? const Offset(1.15, 0) : Offset.zero,
        child: AnimatedOpacity(
          duration: _swipeOutDuration,
          curve: Curves.easeIn,
          opacity: isExpiring ? 0.0 : 1.0,
          child: Dismissible(
            key: ValueKey(
                '${item.id}_${index}_${item.timestamp.microsecondsSinceEpoch}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _deleteNotification(item),
            background: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    LucideIcons.trash2,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text(
                    "Delete",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            child: _buildNotificationCard(item, isDark),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                ],
              ),
            ),
          ],
        ),
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