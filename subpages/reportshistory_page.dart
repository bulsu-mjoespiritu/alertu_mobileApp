import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:alertu_flutter/services/api_service.dart';

// Import live details subpage for viewing resolved history details
import 'livedetailshistory.dart';

class ReportsHistoryPage extends StatefulWidget {
  final List<dynamic> historyReports;
  final String searchQuery;
  final String? selectedIncidentType;
  final String? selectedSeverity;
  final DateTimeRange? selectedDateRange;

  const ReportsHistoryPage({
    super.key,
    this.historyReports = const [],
    this.searchQuery = "",
    this.selectedIncidentType,
    this.selectedSeverity,
    this.selectedDateRange,
  });

  @override
  State<ReportsHistoryPage> createState() => _ReportsHistoryPageState();
}

class _ReportsHistoryPageState extends State<ReportsHistoryPage> {
  List<dynamic> _resolvedReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.historyReports.isNotEmpty) {
      _resolvedReports = _sortReportsNewestFirst(widget.historyReports);
      _isLoading = false;
    } else {
      _fetchResolvedReports();
    }
  }

  /// Sorts reports chronologically (Newest top -> Oldest bottom)
  List<dynamic> _sortReportsNewestFirst(List<dynamic> reports) {
    List<dynamic> sorted = List.from(reports);
    sorted.sort((a, b) {
      DateTime timeA = _parseDateTime(a['resolvedAt'] ?? a['verifiedAt'] ?? a['createdAt'] ?? a['timestamp']);
      DateTime timeB = _parseDateTime(b['resolvedAt'] ?? b['verifiedAt'] ?? b['createdAt'] ?? b['timestamp']);
      return timeB.compareTo(timeA); // Newest top, oldest bottom
    });
    return sorted;
  }

  /// Fetches resolved reports from API endpoint with Firestore fallback
  Future<void> _fetchResolvedReports() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      String targetBase = ApiService.baseUrl ?? 'http://10.0.2.2:3000/api';
      final String requestUrl = targetBase.endsWith('/api')
          ? '$targetBase/resolved-incidents'
          : '$targetBase/api/resolved-incidents';

      final response = await http.get(Uri.parse(requestUrl)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        List<dynamic> fetchedList = [];

        if (resData is Map && resData.containsKey('data')) {
          fetchedList = resData['data'];
        } else if (resData is List) {
          fetchedList = resData;
        }

        if (!mounted) return;
        setState(() {
          _resolvedReports = _sortReportsNewestFirst(fetchedList);
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint("⚠️ API Sync fallback triggered for history: $e");
    }

    // Direct Firestore fallback
    try {
      final querySnapshot = await FirebaseFirestore.instance.collection('ResolvedReports').get();
      List<dynamic> fetchedList = querySnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _resolvedReports = _sortReportsNewestFirst(fetchedList);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching resolved history: $e");
      if (mounted) setState(() => _isLoading = false);
    }
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
    if (dt.millisecondsSinceEpoch == 0) return 'Recently resolved';

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

  String _getDateGroupHeader(dynamic rawTimestamp) {
    final dt = _parseDateTime(rawTimestamp);
    if (dt.millisecondsSinceEpoch == 0) return "Resolved Reports";

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Search and Modal Filter logic synced from parent ReportsPage
    final List<dynamic> filteredList = _resolvedReports.where((report) {
      final String title = (report['reportTitle'] ?? report['incidentType'] ?? '').toString().toLowerCase();
      final String desc = (report['adminNotes'] ?? report['description'] ?? report['location']?['address'] ?? '').toString().toLowerCase();
      final String type = (report['incidentType'] ?? '').toString().toLowerCase();
      final String sev = (report['severity'] ?? '').toString().toLowerCase();
      final DateTime reportDate = _parseDateTime(report['resolvedAt'] ?? report['verifiedAt'] ?? report['createdAt'] ?? report['timestamp']);

      final query = widget.searchQuery.toLowerCase();
      final matchesSearch = title.contains(query) || desc.contains(query);
      final matchesType = widget.selectedIncidentType == null || type.contains(widget.selectedIncidentType!.toLowerCase());
      final matchesSeverity = widget.selectedSeverity == null || sev == widget.selectedSeverity!.toLowerCase();

      bool matchesDate = true;
      if (widget.selectedDateRange != null) {
        matchesDate = reportDate.isAfter(widget.selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            reportDate.isBefore(widget.selectedDateRange!.end.add(const Duration(days: 1)));
      }

      return matchesSearch && matchesType && matchesSeverity && matchesDate;
    }).toList();

    return RefreshIndicator(
      onRefresh: _fetchResolvedReports,
      color: theme.colorScheme.primary,
      child: _isLoading
          ? _buildHistorySkeletons(isDark)
          : filteredList.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 48,
                  color: isDark ? Colors.grey.shade600 : const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 12),
                Text(
                  "No resolved reports found",
                  style: _textStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade300 : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Try clearing your search or filters.",
                  style: _textStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      )
          : _buildGroupedHistoryList(filteredList, isDark, theme),
    );
  }

  Widget _buildGroupedHistoryList(List<dynamic> reports, bool isDark, ThemeData theme) {
    final Map<String, List<dynamic>> grouped = {};

    for (var report in reports) {
      final header = _getDateGroupHeader(report['resolvedAt'] ?? report['verifiedAt'] ?? report['createdAt'] ?? report['timestamp']);
      grouped.putIfAbsent(header, () => []).add(report);
    }

    final List<Widget> listWidgets = [];

    grouped.forEach((header, items) {
      // Date Header Divider
      listWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              Text(
                header,
                style: _textStyle(
                  fontSize: 13,
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

      // Report Cards
      for (var report in items) {
        listWidgets.add(_buildHistoryCard(report, isDark, theme));
      }
    });

    // Generous bottom inset ensures phone navigation bars don't cover bottom cards
    final double extraBottomSpace = MediaQuery.of(context).padding.bottom + 120.0;

    return ListView.builder(
      // Smooth native scrolling physics
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: extraBottomSpace,
      ),
      itemCount: listWidgets.length,
      itemBuilder: (context, index) => listWidgets[index],
    );
  }

  Widget _buildHistoryCard(dynamic report, bool isDark, ThemeData theme) {
    final String title = (report['reportTitle'] ?? report['incidentType'] ?? 'INCIDENT').toString().toUpperCase();
    final String description = report['adminNotes'] ?? report['description'] ?? report['location']?['address'] ?? 'Resolved emergency incident zone.';
    final String hazardType = (report['incidentType'] ?? 'General').toString();
    final String status = (report['status'] ?? 'RESOLVED').toUpperCase();
    final String typeLower = hazardType.toLowerCase();

    final dynamic rawTime = report['resolvedAt'] ?? report['verifiedAt'] ?? report['createdAt'] ?? report['timestamp'];
    final String formattedTime = _formatDateTime(rawTime);

    // Hazard Color Scheme
    Color incidentColor = const Color(0xFFF97316);
    IconData incidentIcon = Icons.warning_amber_rounded;

    if (typeLower.contains('flood')) {
      incidentColor = const Color(0xFF3B82F6);
      incidentIcon = Icons.water_drop_rounded;
    } else if (typeLower.contains('fire')) {
      incidentColor = const Color(0xFFEF4444);
      incidentIcon = Icons.local_fire_department_rounded;
    } else if (typeLower.contains('acc') || typeLower.contains('car')) {
      incidentColor = const Color(0xFFEAB308);
      incidentIcon = Icons.car_crash_rounded;
    } else if (typeLower.contains('quake')) {
      incidentColor = const Color(0xFF8B5CF6);
      incidentIcon = Icons.landslide_rounded;
    }

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final cardTitleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final cardDescColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    final buttonBg = isDark ? theme.colorScheme.primary : const Color(0xFF2563EB);

    final statusBgColor = isDark ? const Color(0xFF14532D).withOpacity(0.6) : const Color(0xFFDCFCE7);
    final statusTextColor = isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Badges & Timestamp
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: incidentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(incidentIcon, size: 12, color: incidentColor),
                    const SizedBox(width: 4),
                    Text(
                      hazardType,
                      style: _textStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: incidentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: _textStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: statusTextColor,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.check_circle_outline, size: 12, color: cardDescColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  formattedTime,
                  overflow: TextOverflow.ellipsis,
                  style: _textStyle(fontSize: 10, fontWeight: FontWeight.w500, color: cardDescColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Report Title
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _textStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cardTitleColor),
          ),
          const SizedBox(height: 4),

          // Description Summary
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _textStyle(fontSize: 12, color: cardDescColor, height: 1.35),
          ),
          const SizedBox(height: 12),

          // Details Action Button connected to LiveDetailsHistory
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LiveDetailsHistory(
                      reportData: report is Map<String, dynamic> ? report : Map<String, dynamic>.from(report),
                    ),
                  ),
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
                    "View Report Details",
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
    );
  }

  Widget _buildHistorySkeletons(bool isDark) {
    final baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final highlightColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (context, index) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: baseColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(width: 70, height: 14, color: baseColor),
                  Container(width: 80, height: 12, color: baseColor),
                ],
              ),
              const SizedBox(height: 10),
              Container(width: double.infinity, height: 16, color: baseColor),
              const SizedBox(height: 6),
              Container(width: 200, height: 12, color: baseColor),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 38,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}