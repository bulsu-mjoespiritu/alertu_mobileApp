import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:alertu_flutter/services/api_service.dart';
import 'package:alertu_flutter/services/my_reports_store.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import your subpages
import '../subpages/reportshistory_page.dart';
import '../subpages/livedetails_reports.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with SingleTickerProviderStateMixin {
  // Bug fix / feature: tab order is now 0 = My Reports, 1 = Active
  // Reports, 2 = Reports History (was 0 = Active, 1 = History).
  int _selectedTabIndex = 0;
  late TabController _tabController;
  List<dynamic> _approvedReports = [];
  List<dynamic> _myReports = [];
  bool _isLoading = true;
  bool _isLoadingMyReports = true;
  String _searchQuery = "";
  int _resolvedCount = 0;

  // Filter States
  String? _selectedIncidentType;
  String? _selectedSeverity;
  DateTimeRange? _selectedDateRange;

  final Map<String, VideoPlayerController> _activeVideoControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // The Reports tab stays mounted inside Homepage's IndexedStack, so it
    // never re-runs initState after a report is submitted. Listening to the
    // local submission ledger is what makes a brand-new report show up in
    // "My Reports" (and pull the fresh server lists for "Active Reports")
    // the moment the submit succeeds, instead of only after a manual
    // pull-to-refresh or an app restart.
    myReportsStore.submissions.addListener(_handleSubmissionRecorded);
    _loadData();
  }

  void _handleSubmissionRecorded() {
    if (!mounted) return;
    _loadData();
  }

  @override
  void dispose() {
    myReportsStore.submissions.removeListener(_handleSubmissionRecorded);
    _tabController.dispose();
    for (var controller in _activeVideoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isLoadingMyReports = true;
      });
    }
    await Future.wait([
      _fetchReports(),
      _fetchResolvedCount(),
      _fetchMyReports(),
    ]);
  }

  /// Fetches the count of resolved reports using your backend endpoint /api/resolved-incidents
  /// with a fallback to direct Firestore collection querying.
  Future<void> _fetchResolvedCount() async {
    try {
      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      String targetBase = ApiService.baseUrl ?? 'http://10.0.2.2:3000/api';
      final String requestUrl = targetBase.endsWith('/api')
          ? '$targetBase/resolved-incidents'
          : '$targetBase/api/resolved-incidents';

      final response = await http.get(Uri.parse(requestUrl)).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        if (mounted) {
          setState(() {
            if (resData is Map && resData.containsKey('count')) {
              _resolvedCount = resData['count'] as int;
            } else if (resData is Map && resData.containsKey('data')) {
              _resolvedCount = (resData['data'] as List).length;
            }
          });
        }
        debugPrint("✅ Resolved count synced via backend endpoint: $_resolvedCount");
        return;
      }
    } catch (e) {
      debugPrint("⚠️ API Sync for Resolved reports fallback triggered: $e");
    }

    // Direct Firestore fallback if network/API fails
    try {
      final querySnapshot = await FirebaseFirestore.instance.collection('ResolvedReports').get();
      if (mounted) {
        setState(() {
          _resolvedCount = querySnapshot.docs.length;
        });
        debugPrint("✅ Resolved count synced via Firestore fallback: $_resolvedCount");
      }
    } catch (e) {
      debugPrint("❌ Error fetching resolved count from Firestore: $e");
    }
  }

  /// Fetches approved active reports and sorts them from newest to oldest
  Future<void> _fetchReports() async {
    try {
      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      String targetBase = ApiService.baseUrl ?? 'http://10.0.2.2:3000/api';
      final String requestUrl = targetBase.endsWith('/api')
          ? '$targetBase/reports?view=approved'
          : '$targetBase/api/reports?view=approved';

      final response = await http.get(Uri.parse(requestUrl)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        List<dynamic> fetchedList = [];

        if (resData is Map && resData.containsKey('data')) {
          fetchedList = resData['data'];
        } else if (resData is List) {
          fetchedList = resData;
        }

        // Sort latest to oldest
        fetchedList.sort((a, b) {
          DateTime timeA = _parseDateTime(a['verifiedAt'] ?? a['createdAt'] ?? a['timestamp']);
          DateTime timeB = _parseDateTime(b['verifiedAt'] ?? b['createdAt'] ?? b['timestamp']);
          return timeB.compareTo(timeA);
        });

        if (!mounted) return;
        setState(() {
          _approvedReports = fetchedList;
        });
        debugPrint("✅ Active Reports synced: ${_approvedReports.length} items.");
      }
    } catch (e) {
      debugPrint("❌ Incident Network Sync Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Builds the "My Reports" list: every report this citizen has personally
  /// submitted, at every status, kept forever.
  ///
  /// Bug fix: this used to be a single Firestore query on the `reports`
  /// collection filtered by `authUid`. That made the tab lossy -- the
  /// backend moves a report OUT of `reports` when it is verified (into
  /// `approved_reports`) and again when it is closed (into
  /// `ResolvedReports`), so a citizen's own report silently vanished from
  /// "My Reports" the moment it became active, and again when it was
  /// resolved. It also showed nothing until the round trip finished, so a
  /// just-submitted report didn't appear at all.
  ///
  /// The list is now the union of:
  ///   * the device-local submission ledger (see MyReportsStore), which is
  ///     written the instant a submit succeeds and never expires, and
  ///   * live queries across all three collections, so status, admin notes
  ///     and verification times stay current.
  ///
  /// Entries collapse by report id, the most advanced status wins, and the
  /// only thing that ever takes a report out of this list is the citizen
  /// tapping its own "x" -- which hides it here and nowhere else.
  Future<void> _fetchMyReports() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _isLoadingMyReports = false);
      return;
    }

    try {
      // Make sure this account's local ledger (submissions + the ids the
      // citizen has cleared with the "x") is in memory before merging.
      await myReportsStore.loadForUser(uid);

      // Keyed by normalised report id so the same report arriving from
      // more than one collection collapses into a single card.
      final Map<String, Map<String, dynamic>> merged = {};

      void absorb(Map<String, dynamic> report, String status, int rank) {
        final id = MyReportsStore.idOf(report);
        if (id == null) return;

        final existing = merged[id];
        final existingRank = existing?[r'$statusRank'] as int? ?? -1;
        if (existing != null && existingRank >= rank) {
          // Keep the more advanced record, but let it inherit any fields
          // the earlier/less advanced copy had and this one is missing
          // (e.g. the original media URL or notes).
          report.forEach((key, value) {
            existing.putIfAbsent(key, () => value);
          });
          return;
        }

        final combined = <String, dynamic>{
          if (existing != null) ...existing,
          ...report,
          'id': id,
          'reportId': id,
          'reportID': id,
          'myReportStatus': status,
          r'$statusRank': rank,
        };
        merged[id] = combined;
      }

      // Local snapshots first (rank 0): these guarantee a just-submitted
      // report appears immediately, and that a report the backend has since
      // moved between collections never disappears from this tab.
      for (final local in myReportsStore.submissions.value) {
        absorb(Map<String, dynamic>.from(local), 'Pending', 0);
      }

      // Then the server, newest status wins. Each collection is queried
      // independently and failures are tolerated -- a project may not have
      // every collection, or may not index authUid on all of them.
      await Future.wait<void>([
        _absorbCollection('reports', uid, absorb, 'Pending', 1),
        _absorbCollection('approved_reports', uid, absorb, 'Active', 2),
        _absorbCollection('ResolvedReports', uid, absorb, 'Resolved', 3),
      ]);

      // Reports the citizen cleared with the "x" are filtered out of MY
      // list only. They are untouched on the server and still show in the
      // global "Report History" tab.
      final List<dynamic> fetchedList = merged.values
          .where((report) => !myReportsStore.isHidden(MyReportsStore.idOf(report)))
          .toList();

      fetchedList.sort((a, b) {
        DateTime timeA = _parseDateTime(_myReportTimestamp(a));
        DateTime timeB = _parseDateTime(_myReportTimestamp(b));
        return timeB.compareTo(timeA);
      });

      if (!mounted) return;
      setState(() {
        _myReports = fetchedList;
      });
      debugPrint("\u2705 My Reports synced: ${_myReports.length} items.");
    } catch (e) {
      debugPrint("\u274c My Reports Sync Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingMyReports = false);
    }
  }

  /// Queries one collection for documents belonging to [uid] and feeds them
  /// into the merge function. `authUid` is what report_submission.dart
  /// writes; `citizenID` is checked as a fallback for records copied by the
  /// backend without carrying the auth uid across.
  Future<void> _absorbCollection(
      String collection,
      String uid,
      void Function(Map<String, dynamic> report, String status, int rank) absorb,
      String status,
      int rank,
      ) async {
    Future<void> runQuery(String field, dynamic value) async {
      final snapshot = await FirebaseFirestore.instance
          .collection(collection)
          .where(field, isEqualTo: value)
          .get();

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= doc.id;
        data['reportId'] ??= doc.id;
        absorb(data, status, rank);
      }
    }

    try {
      await runQuery('authUid', uid);
    } catch (e) {
      debugPrint("\u26a0\ufe0f My Reports: $collection/authUid query skipped: $e");
    }

    // Only worth a second round trip if the local ledger knows a citizenID
    // for this account -- otherwise there is nothing to match on.
    final String? citizenId = myReportsStore.submissions.value
        .map((report) => report['citizenID']?.toString())
        .firstWhere((value) => value != null && value.isNotEmpty,
        orElse: () => null);
    if (citizenId == null) return;

    try {
      await runQuery('citizenID', citizenId);
    } catch (e) {
      debugPrint("\u26a0\ufe0f My Reports: $collection/citizenID query skipped: $e");
    }
  }

  /// Best available "when did this happen" value for one of the citizen's
  /// own reports, whichever collection it came back from.
  dynamic _myReportTimestamp(dynamic report) {
    if (report is! Map) return null;
    return report['submittedAt'] ??
        report['createdAt'] ??
        report['verifiedAt'] ??
        report['resolvedAt'] ??
        report['timestamp'];
  }

  /// Confirms before the small "x" removes a report from this citizen's
  /// own list, so a stray tap on a small target isn't destructive.
  Future<void> _confirmClearMyReport(dynamic report) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove from My Reports?',
          style: _textStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This only clears it from your own list. The report itself is not '
              'deleted and will still appear in Report History.',
          style: _textStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: _textStyle(fontSize: 13)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Remove',
              style: _textStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearMyReport(report);
    }
  }

  /// Removes one report from the "My Reports" list only (the small "x").
  /// The report stays on the server and keeps appearing in "Report
  /// History" -- this is a personal-list tidy-up, not a deletion.
  Future<void> _clearMyReport(dynamic report) async {
    final String? id = MyReportsStore.idOf(report);
    if (id == null) return;

    await myReportsStore.hide(id);
    if (!mounted) return;

    setState(() {
      _myReports = _myReports
          .where((item) => MyReportsStore.idOf(item) != id)
          .toList();
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 4),
        content: Text(
          "Removed from My Reports. It's still in Report History.",
          style: _textStyle(fontSize: 12),
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await myReportsStore.unhide(id);
            await _fetchMyReports();
          },
        ),
      ),
    );
  }

  DateTime _parseDateTime(dynamic rawTimestamp) {
    if (rawTimestamp == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      if (rawTimestamp is String) return DateTime.parse(rawTimestamp).toLocal();
      if (rawTimestamp is int) return DateTime.fromMillisecondsSinceEpoch(rawTimestamp).toLocal();
      if (rawTimestamp is Timestamp) return rawTimestamp.toDate().toLocal();
    } catch (_) {}
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  String _formatDateTime(dynamic rawTimestamp) {
    final dt = _parseDateTime(rawTimestamp);
    if (dt.millisecondsSinceEpoch == 0) return 'Recently verified';

    final List<String> months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final String month = months[dt.month - 1];
    final String day = dt.day.toString().padLeft(2, '0');
    final String year = dt.year.toString();

    int hour = dt.hour;
    final String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    final String minute = dt.minute.toString().padLeft(2, '0');

    return '$month $day, $year • $hour:$minute $period';
  }

  /// Groups dates into "Today", "Yesterday", or formatted full dates
  String _getDateGroupHeader(dynamic rawTimestamp) {
    final dt = _parseDateTime(rawTimestamp);
    if (dt.millisecondsSinceEpoch == 0) return "Recent Reports";

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final reportDate = DateTime(dt.year, dt.month, dt.day);

    if (reportDate == today) return "Today";
    if (reportDate == yesterday) return "Yesterday";

    final List<String> months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return "${months[dt.month - 1]} ${dt.day}, ${dt.year}";
  }

  TextStyle _textStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.montserrat(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  bool get _hasActiveFilters =>
      _selectedIncidentType != null ||
          _selectedSeverity != null ||
          _selectedDateRange != null;

  void _showFilterModal(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
            final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

            final double bottomSafeArea = MediaQuery.of(modalContext).padding.bottom;
            final double keyboardOffset = MediaQuery.of(modalContext).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: keyboardOffset + bottomSafeArea + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Filter Incidents",
                        style: _textStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(modalContext),
                        icon: Icon(Icons.close, color: titleColor),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),

                  // Incident Type Filter
                  Text("Incident Type", style: _textStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleColor)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Flood', 'Fire', 'Accident', 'Earthquake', 'Others'].map((type) {
                      final isSelected = _selectedIncidentType?.toLowerCase() == type.toLowerCase();
                      return ChoiceChip(
                        label: Text(type),
                        selected: isSelected,
                        selectedColor: Theme.of(context).colorScheme.primary,
                        labelStyle: _textStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.black87),
                        ),
                        onSelected: (selected) {
                          setModalState(() {
                            _selectedIncidentType = selected ? type : null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Severity / Hazard Filter
                  Text("Severity (Hazard Level)", style: _textStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleColor)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['High', 'Medium', 'Low'].map((sev) {
                      final isSelected = _selectedSeverity?.toLowerCase() == sev.toLowerCase();
                      return ChoiceChip(
                        label: Text(sev),
                        selected: isSelected,
                        selectedColor: Theme.of(context).colorScheme.primary,
                        labelStyle: _textStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.black87),
                        ),
                        onSelected: (selected) {
                          setModalState(() {
                            _selectedSeverity = selected ? sev : null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Date Range Filter
                  Text("Date Range", style: _textStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleColor)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: modalContext,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: _selectedDateRange,
                      );
                      if (picked != null) {
                        setModalState(() {
                          _selectedDateRange = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cardBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDateRange == null
                                ? "Select date range..."
                                : "${_selectedDateRange!.start.toString().split(' ')[0]} - ${_selectedDateRange!.end.toString().split(' ')[0]}",
                            style: _textStyle(fontSize: 12, color: titleColor),
                          ),
                          Icon(Icons.calendar_today, size: 16, color: titleColor),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedIncidentType = null;
                              _selectedSeverity = null;
                              _selectedDateRange = null;
                            });
                            setState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: cardBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text("Reset", style: _textStyle(fontSize: 13, color: titleColor)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {});
                            Navigator.pop(modalContext);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text("Apply Filters", style: _textStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SHIMMER SKELETON BUILDERS
  // ---------------------------------------------------------------------------
  Widget _buildStatCardsSkeleton(bool isDark) {
    final baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final highlightColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Row(
        children: List.generate(
          3,
              (index) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index == 2 ? 0 : 10),
              height: 60,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentSkeletons(bool isDark) {
    final baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final highlightColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 2,
        itemBuilder: (context, index) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: baseColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(width: 100, height: 16, color: baseColor),
                        Container(width: 80, height: 14, color: baseColor),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(width: double.infinity, height: 18, color: baseColor),
                    const SizedBox(height: 8),
                    Container(width: 200, height: 14, color: baseColor),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      height: 40,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN BUILD METHOD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final scaffoldBg = theme.scaffoldBackgroundColor;
    final appBarBg = theme.appBarTheme.backgroundColor ?? (isDark ? const Color(0xFF121212) : Colors.white);
    final titleTextColor = theme.textTheme.titleLarge?.color ?? (isDark ? Colors.white : const Color(0xFF1E293B));

    final inputFillColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final inputBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final inputHintColor = isDark ? Colors.grey.shade400 : const Color(0xFF94A3B8);

    final tabContainerBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    // Multi-criteria Filter Logic
    final List<dynamic> filteredReports = _approvedReports.where((report) {
      final String title = (report['reportTitle'] ?? report['incidentType'] ?? '').toString().toLowerCase();
      final String desc = (report['adminNotes'] ?? report['location']?['address'] ?? '').toString().toLowerCase();
      final String type = (report['incidentType'] ?? '').toString().toLowerCase();
      final String sev = (report['severity'] ?? '').toString().toLowerCase();
      final DateTime reportDate = _parseDateTime(report['verifiedAt'] ?? report['createdAt'] ?? report['timestamp']);

      final matchesSearch = title.contains(_searchQuery) || desc.contains(_searchQuery);
      final matchesType = _selectedIncidentType == null || type.contains(_selectedIncidentType!.toLowerCase());
      final matchesSeverity = _selectedSeverity == null || sev == _selectedSeverity!.toLowerCase();

      bool matchesDate = true;
      if (_selectedDateRange != null) {
        matchesDate = reportDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            reportDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }

      return matchesSearch && matchesType && matchesSeverity && matchesDate;
    }).toList();

    // Same multi-criteria filter, applied to the current citizen's own
    // reports for the "My Reports" tab.
    final List<dynamic> filteredMyReports = _myReports.where((report) {
      final String title = (report['reportTitle'] ?? report['incidentType'] ?? '').toString().toLowerCase();
      final String desc = (report['adminNotes'] ?? report['location']?['address'] ?? report['address'] ?? '').toString().toLowerCase();
      final String type = (report['incidentType'] ?? '').toString().toLowerCase();
      final String sev = (report['severity'] ?? '').toString().toLowerCase();
      final DateTime reportDate = _parseDateTime(report['submittedAt'] ?? report['createdAt'] ?? report['timestamp']);

      final matchesSearch = title.contains(_searchQuery) || desc.contains(_searchQuery);
      final matchesType = _selectedIncidentType == null || type.contains(_selectedIncidentType!.toLowerCase());
      final matchesSeverity = _selectedSeverity == null || sev == _selectedSeverity!.toLowerCase();

      bool matchesDate = true;
      if (_selectedDateRange != null) {
        matchesDate = reportDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            reportDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }

      return matchesSearch && matchesType && matchesSeverity && matchesDate;
    }).toList();

    // Total Incidents = Active + Resolved
    final int totalCount = filteredReports.length + _resolvedCount;

    return Scaffold(
      // Keyboard fix: the only text field on this page is the "Search
      // incidents..." box, and this Scaffold is nested inside Homepage's
      // already height-constrained page container. Letting it resize for the
      // keyboard squashed the whole list and fought with the outer layout
      // while the keyboard animated -- the stutter the user sees. A search
      // field at the top of a scrollable list never needs the layout to move
      // for it; real text boxes elsewhere keep their normal avoidance.
      resizeToAvoidBottomInset: false,
      backgroundColor: scaffoldBg,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: theme.colorScheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: appBarBg,
              elevation: 0,
              floating: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Incident Reports", style: _textStyle(fontSize: 18, fontWeight: FontWeight.w700, color: titleTextColor)),
                  const SizedBox(width: 8),
                  Image.asset('assets/images/logo1.png', height: 28, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ],
              ),
              centerTitle: false,
            ),

            // Shortened Search Bar + Filter Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                          style: _textStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            hintText: "Search incidents...",
                            hintStyle: _textStyle(fontSize: 13, color: inputHintColor),
                            prefixIcon: Icon(Icons.search, size: 20, color: inputHintColor),
                            filled: true,
                            fillColor: inputFillColor,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: inputBorderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 44,
                      width: 44,
                      child: Stack(
                        children: [
                          InkWell(
                            onTap: () => _showFilterModal(isDark),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: inputFillColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: inputBorderColor),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.tune_rounded,
                                color: _hasActiveFilters ? theme.colorScheme.primary : inputHintColor,
                                size: 20,
                              ),
                            ),
                          ),
                          if (_hasActiveFilters)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tab Selector
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: tabContainerBg, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      _buildCustomTab("My Reports", 0, isDark),
                      _buildCustomTab("Active Reports", 1, isDark),
                      _buildCustomTab("Report History", 2, isDark),
                    ],
                  ),
                ),
              ),
            ),

            // Dynamic Stats Bar (Active, Resolved, Total) -- Active Reports tab only
            if (_selectedTabIndex == 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isLoading
                        ? _buildStatCardsSkeleton(isDark)
                        : Row(
                      key: const ValueKey("stats_row"),
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            "TOTAL",
                            "$totalCount".padLeft(2, '0'),
                            isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                            isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            "ACTIVE",
                            "${filteredReports.length}".padLeft(2, '0'),
                            isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                            isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            "RESOLVED",
                            "$_resolvedCount".padLeft(2, '0'),
                            isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE),
                            isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Tab Content Output with Animated Transition
            // 0 = My Reports (this citizen's own submissions, any status)
            // 1 = Active Reports (globally approved/active)
            // 2 = Reports History (globally resolved)
            if (_selectedTabIndex == 0)
              (_isLoadingMyReports
                  ? SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(child: _buildIncidentSkeletons(isDark)),
              )
                  : _buildGroupedActiveReports(
                filteredMyReports,
                isDark,
                theme,
                emptyStateText: "You haven't submitted any reports yet.",
                isMyReports: true,
              ))
            else if (_selectedTabIndex == 1)
              (_isLoading
                  ? SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(child: _buildIncidentSkeletons(isDark)),
              )
                  : _buildGroupedActiveReports(filteredReports, isDark, theme))
            else
              SliverToBoxAdapter(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _selectedTabIndex == 2 ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: SizedBox(
                      height: 650,
                      child: ReportsHistoryPage(
                        searchQuery: _searchQuery,
                        selectedIncidentType: _selectedIncidentType,
                        selectedSeverity: _selectedSeverity,
                        selectedDateRange: _selectedDateRange,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Groups active reports with chronological headers (Today, Yesterday, Date)
  Widget _buildGroupedActiveReports(
      List<dynamic> reports,
      bool isDark,
      ThemeData theme, {
        String emptyStateText = "No active incidents reported.",
        bool isMyReports = false,
      }) {
    if (reports.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              emptyStateText,
              style: _textStyle(fontSize: 14, color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B)),
            ),
          ),
        ),
      );
    }

    final Map<String, List<dynamic>> grouped = {};
    for (var report in reports) {
      final header = _getDateGroupHeader(
        isMyReports
            ? _myReportTimestamp(report)
            : (report['verifiedAt'] ?? report['createdAt'] ?? report['timestamp']),
      );
      grouped.putIfAbsent(header, () => []).add(report);
    }

    final List<Widget> sliverChildren = [];

    grouped.forEach((header, items) {
      sliverChildren.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Text(
                header,
                style: _textStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  thickness: 1,
                ),
              ),
            ],
          ),
        ),
      );

      for (var report in items) {
        sliverChildren.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildIncidentCard(
              report,
              isDark,
              theme,
              isMyReport: isMyReports,
            ),
          ),
        );
      }
    });

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) => AnimatedOpacity(
          duration: Duration(milliseconds: 250 + (index * 40).clamp(0, 500)),
          opacity: 1.0,
          child: sliverChildren[index],
        ),
        childCount: sliverChildren.length,
      ),
    );
  }

  Widget _buildCustomTab(String title, int index, bool isDark) {
    final bool isSelected = _selectedTabIndex == index;

    final selectedBg = isDark ? const Color(0xFF334155) : Colors.white;
    final selectedTextColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final unselectedTextColor = isDark ? Colors.grey.shade400 : const Color(0xFF94A3B8);

    return Expanded(
      // Bug 5 fix: a unique key per tab keeps these two as distinct,
      // independent elements rather than relying purely on list position.
      key: ValueKey('report_tab_$index'),
      // A Material scoped to just this tab confines its InkWell's press
      // feedback (ripple/highlight) to this widget's own bounds. Before,
      // a bare GestureDetector had no press feedback of its own, so the
      // shared-state AnimatedContainer color swap on BOTH tabs (one
      // becoming selected, the other becoming unselected) was the only
      // visible reaction to a tap -- which reads as "both buttons
      // animated" even though only one was actually tapped.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          splashColor: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
          highlightColor: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
          onTap: () {
            if (_selectedTabIndex == index) return;
            setState(() {
              _selectedTabIndex = index;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected
                  ? [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ]
                  : [],
            ),
            alignment: Alignment.center,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: _textStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? selectedTextColor : unselectedTextColor,
              ),
              child: Text(title),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color bg, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _textStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.withOpacity(0.85))),
          const SizedBox(height: 2),
          Text(value, style: _textStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(
      dynamic report,
      bool isDark,
      ThemeData theme, {
        bool isMyReport = false,
      }) {
    final String title = (report['reportTitle'] ?? report['incidentType'] ?? 'INCIDENT').toString().toUpperCase();
    final String description = report['adminNotes'] ?? report['location']?['address'] ?? report['address'] ?? 'Verified emergency incident zone.';
    final String hazardType = (report['incidentType'] ?? 'General Emergency').toString();
    final String severity = (report['severity'] ?? 'LOW').toUpperCase();
    final String typeLower = hazardType.toLowerCase();

    final dynamic rawTime = isMyReport
        ? _myReportTimestamp(report)
        : (report['verifiedAt'] ?? report['createdAt'] ?? report['timestamp']);
    final String formattedTime = _formatDateTime(rawTime);

    // Status of one of MY reports: Pending -> Active -> Resolved. The tab
    // deliberately keeps every one of these, so the card has to say which
    // it is.
    final String myStatus =
    (report['myReportStatus'] ?? report['status'] ?? 'Pending').toString();
    final String myStatusLabel = myStatus.toUpperCase() == 'RESOLVED'
        ? 'RESOLVED'
        : (myStatus.toUpperCase() == 'PENDING' ? 'PENDING' : 'ACTIVE');
    final Color myStatusColor = myStatusLabel == 'RESOLVED'
        ? const Color(0xFF2563EB)
        : (myStatusLabel == 'ACTIVE'
        ? const Color(0xFF059669)
        : const Color(0xFF64748B));

    // Hazard Color and Icon configurations
    Color incidentThemeColor = const Color(0xFFF97316);
    IconData incidentIcon = Icons.warning_amber_rounded;

    if (typeLower.contains('flood')) {
      incidentThemeColor = const Color(0xFF3B82F6);
      incidentIcon = Icons.water_drop_rounded;
    } else if (typeLower.contains('fire')) {
      incidentThemeColor = const Color(0xFFEF4444);
      incidentIcon = Icons.local_fire_department_rounded;
    } else if (typeLower.contains('acc') || typeLower.contains('car')) {
      incidentThemeColor = const Color(0xFFEAB308);
      incidentIcon = Icons.car_crash_rounded;
    } else if (typeLower.contains('quake')) {
      incidentThemeColor = const Color(0xFF8B5CF6);
      incidentIcon = Icons.landslide_rounded;
    }

    // Severity Colors
    Color sevColor = const Color(0xFFF59E0B);
    if (severity == 'HIGH') sevColor = const Color(0xFFEF4444);
    if (severity == 'LOW') sevColor = const Color(0xFF10B981);

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final cardTitleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final cardDescColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    final buttonBg = isDark ? theme.colorScheme.primary : const Color(0xFF2563EB);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Image Header
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: _buildMediaPreview(
                    report['mediaUrl'],
                    "https://images.unsplash.com/photo-1547683905-f686c993aae5?auto=format&fit=crop&q=80&w=600",
                    isDark,
                    isSensitive: report['isSensitive'] == true,
                    mediaIdentity: '${report['_id'] ?? report['id'] ?? ''}_${report['mediaUrl'] ?? ''}',
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: sevColor, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          "$severity SEVERITY",
                          style: _textStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      // "My Reports" keeps a report through every status, so
                      // each card states where it currently stands.
                      if (isMyReport) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: myStatusColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            myStatusLabel,
                            style: _textStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Per-report "clear" control -- My Reports only. Removes
                // this one entry from the citizen's personal list; the
                // report itself is untouched and still appears under
                // "Report History".
                if (isMyReport)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black.withOpacity(0.45),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _confirmClearMyReport(report),
                        child: const Padding(
                          padding: EdgeInsets.all(5.0),
                          child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Content Container
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hazard Tag & Time Timestamp
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: incidentThemeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(incidentIcon, size: 12, color: incidentThemeColor),
                          const SizedBox(width: 4),
                          Text(
                            hazardType,
                            style: _textStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: incidentThemeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.access_time_rounded, size: 12, color: cardDescColor),
                    const SizedBox(width: 4),
                    Text(
                      formattedTime,
                      style: _textStyle(fontSize: 10, fontWeight: FontWeight.w500, color: cardDescColor),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Incident Title
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _textStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cardTitleColor),
                ),
                const SizedBox(height: 4),

                // Description
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _textStyle(fontSize: 12, color: cardDescColor, height: 1.35),
                ),
                const SizedBox(height: 14),

                // View Details Button
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => LiveDetailsReports(reportData: report)),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonBg,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "View Live Details",
                          style: _textStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview(
      String? url,
      String fallback,
      bool isDark, {
        required bool isSensitive,
        required String mediaIdentity,
      }) {
    final String? mediaUrl = url?.trim();
    final bool isVideo = mediaUrl != null &&
        mediaUrl.isNotEmpty &&
        (mediaUrl.toLowerCase().contains('.mp4') ||
            mediaUrl.toLowerCase().contains('video/'));

    final Widget mediaChild;
    if (isVideo) {
      mediaChild = _ReportVideoPreview(
        videoUrl: mediaUrl,
        fallbackImageUrl: fallback,
        isDark: isDark,
      );
    } else {
      final String img = (mediaUrl == null || mediaUrl.isEmpty) ? fallback : mediaUrl;
      final baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
      final highlightColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

      mediaChild = Image.network(
        img,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Container(color: baseColor),
          );
        },
        errorBuilder: (_, __, ___) => Image.network(
          fallback,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    return _SensitiveMediaPreview(
      isSensitive: isSensitive,
      mediaIdentity: mediaIdentity,
      child: mediaChild,
    );


  }
}

class _SensitiveMediaPreview extends StatefulWidget {
  final bool isSensitive;
  final String mediaIdentity;
  final Widget child;

  const _SensitiveMediaPreview({
    required this.isSensitive,
    required this.mediaIdentity,
    required this.child,
  });

  @override
  State<_SensitiveMediaPreview> createState() => _SensitiveMediaPreviewState();
}

class _SensitiveMediaPreviewState extends State<_SensitiveMediaPreview> {
  bool _isRevealed = false;

  @override
  void didUpdateWidget(covariant _SensitiveMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaIdentity != widget.mediaIdentity ||
        oldWidget.isSensitive != widget.isSensitive) {
      _isRevealed = false;
    }
  }

  void _reveal() {
    if (!widget.isSensitive || _isRevealed) return;
    setState(() => _isRevealed = true);
  }

  @override
  Widget build(BuildContext context) {
    final bool showCensor = widget.isSensitive && !_isRevealed;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.isSensitive)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showCensor,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: showCensor ? _reveal : null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  child: showCensor
                      ? Container(
                    key: const ValueKey('reports-sensitive-overlay'),
                    color: Colors.black.withOpacity(0.48),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        color: Colors.black.withOpacity(0.18),
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_off_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Sensitive content',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tap to view',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                      : const SizedBox.expand(
                    key: ValueKey('reports-sensitive-revealed'),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportVideoPreview extends StatefulWidget {
  final String videoUrl;
  final String fallbackImageUrl;
  final bool isDark;

  const _ReportVideoPreview({
    required this.videoUrl,
    required this.fallbackImageUrl,
    required this.isDark,
  });

  @override
  State<_ReportVideoPreview> createState() => _ReportVideoPreviewState();
}

class _ReportVideoPreviewState extends State<_ReportVideoPreview> {
  VideoPlayerController? _controller;
  bool _hasFailed = false;
  bool _isPlaying = false;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(covariant _ReportVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    final previousController = _controller;
    _controller = null;
    _hasFailed = false;
    await previousController?.dispose();

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      controller.addListener(_handleVideoProgress);
      await controller.play();

      if (!mounted) {
        controller.removeListener(_handleVideoProgress);
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isPlaying = true;
        _hasFinished = false;
      });
    } catch (error) {
      debugPrint('❌ Report video initialization failed: $error');
      controller.removeListener(_handleVideoProgress);
      await controller.dispose();
      if (mounted) setState(() => _hasFailed = true);
    }
  }

  void _handleVideoProgress() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final value = controller.value;
    if (value.duration == Duration.zero) return;

    if (value.position >= value.duration && !value.isPlaying) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _hasFinished = true;
      });
    }
  }

  Future<void> _replayVideo() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (_hasFinished || controller.value.position >= controller.value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
    if (mounted) {
      setState(() {
        _isPlaying = true;
        _hasFinished = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleVideoProgress);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_hasFailed) {
      return Image.network(
        widget.fallbackImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: widget.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(
          color: Color(0xFF2563EB),
          strokeWidth: 2.5,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isPlaying ? null : _replayVideo,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          if (!_isPlaying)
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.60),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.replay_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
