import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class SummaryReport_Button extends StatelessWidget {
  const SummaryReport_Button({super.key});

  void _showSummaryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TodaySummaryModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double buttonSize = 54.0;

    return GestureDetector(
      onTap: () => _showSummaryModal(context),
      child: Container(
        width: buttonSize,
        height: buttonSize,
        decoration: BoxDecoration(
          color: Colors.orange,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.white, width: 1.5),
        ),
        child: const Center(
          child: Icon(
            Icons.bar_chart_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class TodaySummaryModal extends StatefulWidget {
  const TodaySummaryModal({super.key});

  @override
  State<TodaySummaryModal> createState() => _TodaySummaryModalState();
}

class _TodaySummaryModalState extends State<TodaySummaryModal> {
  // Streams listening ONLY to approved_reports and ResolvedReports
  late Stream<QuerySnapshot> _approvedReportsStream;
  late Stream<QuerySnapshot> _resolvedReportsStream;

  @override
  void initState() {
    super.initState();
    final firestore = FirebaseFirestore.instance;

    // Fetch ONLY approved_reports collection
    _approvedReportsStream = firestore.collection('approved_reports').snapshots();
    _resolvedReportsStream = firestore.collection('ResolvedReports').snapshots();
  }

  TextStyle _font({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    return GoogleFonts.montserrat(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate().toLocal();
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      return parsed?.toLocal();
    }
    if (val is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        val < 10000000000 ? val * 1000 : val,
      ).toLocal();
    }
    return null;
  }

  bool _isToday(dynamic dateVal) {
    final parsed = _parseDate(dateVal);
    if (parsed == null) return false;
    final now = DateTime.now();
    return parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day;
  }

  /// Counts ALL approved reports in approved_reports collection
  int _countApprovedReports(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().toLowerCase();

      // Skip resolved or archived items if present in approved_reports
      if (status == 'resolved' || status == 'archived') {
        return false;
      }
      return true;
    }).length;
  }

  /// Counts reports resolved TODAY from ResolvedReports
  int _countResolvedTodayReports(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _isToday(data['resolvedAt']) ||
          _isToday(data['timestamp']) ||
          _isToday(data['updatedAt']);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.85;

    // Dark Mode color theme adjustments
    final modalBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final handleColor = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    final titleColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final closeIconColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: modalBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: mediaQuery.viewInsets.bottom + 16,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle Bar
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: handleColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Reports Overview",
                          style: _font(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Live summary of approved reports",
                          style: _font(fontSize: 12, color: subtitleColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: closeIconColor),
                    splashRadius: 20,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              StreamBuilder<QuerySnapshot>(
                stream: _approvedReportsStream,
                builder: (context, snapApproved) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _resolvedReportsStream,
                    builder: (context, snapResolved) {
                      if (snapApproved.hasError || snapResolved.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24.0),
                          child: Text(
                            "Failed to load summary",
                            style: _font(color: Colors.red.shade400),
                          ),
                        );
                      }

                      if (!snapApproved.hasData || !snapResolved.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: CircularProgressIndicator(color: Colors.orange),
                        );
                      }

                      // Counts EXCLUSIVELY from approved_reports
                      final int approvedCount = _countApprovedReports(snapApproved.data!.docs);

                      // Counts resolved today from ResolvedReports
                      final int resolvedTodayCount = _countResolvedTodayReports(snapResolved.data!.docs);

                      final int totalCombinedCount = approvedCount + resolvedTodayCount;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Total Header Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orange.shade500,
                                  Colors.deepOrange.shade400,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(isDark ? 0.35 : 0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.assignment_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Total Reports Handled",
                                        style: _font(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          "$totalCombinedCount",
                                          style: _font(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Cards Breakdown Row
                          Row(
                            children: [
                              // Approved Reports Card
                              Expanded(
                                child: _StatCard(
                                  title: "Approved Reports",
                                  count: approvedCount,
                                  subtitle: "Approved collection",
                                  icon: Icons.check_circle_outline_rounded,
                                  iconColor: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                  backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F9FF),
                                  borderColor: isDark ? const Color(0xFF0284C7).withOpacity(0.4) : const Color(0xFFBAE6FD),
                                  titleColor: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                  subtitleColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  fontHelper: _font,
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Resolved Today Card
                              Expanded(
                                child: _StatCard(
                                  title: "Resolved Today",
                                  count: resolvedTodayCount,
                                  subtitle: "Completed today",
                                  icon: Icons.task_alt_rounded,
                                  iconColor: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
                                  backgroundColor: isDark ? const Color(0xFF052E16) : const Color(0xFFF0FDF4),
                                  borderColor: isDark ? const Color(0xFF16A34A).withOpacity(0.4) : const Color(0xFFBBF7D0),
                                  titleColor: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                  subtitleColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  fontHelper: _font,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int count;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color subtitleColor;
  final TextStyle Function({
  double fontSize,
  FontWeight fontWeight,
  Color? color,
  }) fontHelper;

  const _StatCard({
    required this.title,
    required this.count,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.subtitleColor,
    required this.fontHelper,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 20),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  "$count",
                  style: fontHelper(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: fontHelper(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: fontHelper(
              fontSize: 10,
              color: subtitleColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}