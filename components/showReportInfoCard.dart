import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../subpages/livedetails_reports.dart';

class ShowReportInfoCard extends StatefulWidget {
  final dynamic report;
  final VoidCallback onClose;

  const ShowReportInfoCard({
    super.key,
    required this.report,
    required this.onClose,
  });

  @override
  State<ShowReportInfoCard> createState() => _ShowReportInfoCardState();
}

class _ShowReportInfoCardState extends State<ShowReportInfoCard> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isSensitiveRevealed = false;

  @override
  void initState() {
    super.initState();
    _initializeMedia();
  }

  @override
  void didUpdateWidget(ShowReportInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report['mediaUrl'] != widget.report['mediaUrl'] ||
        oldWidget.report['isSensitive'] != widget.report['isSensitive']) {
      _initializeMedia();
    }
  }

  void _initializeMedia() {
    _isSensitiveRevealed = false;
    _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;

    final String? mediaUrl = widget.report['mediaUrl'];
    if (mediaUrl != null && mediaUrl.toLowerCase().contains('.mp4')) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(mediaUrl))
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _isVideoInitialized = true);
            _videoController?.setLooping(true);
            _videoController?.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  // Helper method to format raw ISO strings or timestamps cleanly
  String _formatDateTime(dynamic rawTimestamp) {
    if (rawTimestamp == null) return 'Recently verified';
    try {
      DateTime dt;
      if (rawTimestamp is String) {
        dt = DateTime.parse(rawTimestamp).toLocal();
      } else if (rawTimestamp is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(rawTimestamp).toLocal();
      } else {
        return 'Recently verified';
      }

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
    } catch (_) {
      return 'Recently verified';
    }
  }

  Widget _buildFallbackGraphic(Color themeColor, IconData icon) {
    return Container(
      color: themeColor.withOpacity(0.12),
      child: Center(
        child: Icon(
          icon,
          size: 52,
          color: themeColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Data Extraction
    final String title = (report['reportTitle'] != null && report['reportTitle'].toString().trim().isNotEmpty)
        ? report['reportTitle']
        : (report['incidentType'] ?? 'Verified Incident');

    final String description = report['adminNotes'] ??
        report['location']?['address'] ??
        'Active emergency operational zone context.';

    final String hazardType = (report['incidentType'] ?? 'General Emergency').toString();
    final String severity = (report['severity'] ?? 'Medium').toString();
    final String typeLower = hazardType.toLowerCase();
    final String? firebaseMediaUrl = report['mediaUrl'];
    final bool isSensitive = report['isSensitive'] == true ||
        report['isSensitive']?.toString().toLowerCase() == 'true';

    // Timestamp logic: checked in order of verifiedAt -> createdAt -> fallback
    final dynamic rawTime = report['verifiedAt'] ?? report['createdAt'];
    final String formattedTime = _formatDateTime(rawTime);

    // Hazard Theme Configuration
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

    // Severity Theme Configuration
    Color severityColor = const Color(0xFFF59E0B); // Medium
    if (severity.toLowerCase() == 'high') severityColor = const Color(0xFFEF4444);
    if (severity.toLowerCase() == 'low') severityColor = const Color(0xFF10B981);

    // Adaptive Theme Colors
    final Color cardBackground = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color primaryTextColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final Color secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final Color borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final Color tagBackground = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    return Container(
      key: const ValueKey('EnteringCard'),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.4) : const Color(0xFF0F172A).withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ================= MEDIA / HERO BANNER =================
          AspectRatio(
            aspectRatio: screenWidth > 600 ? 21 / 9 : 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _videoController != null
                          ? (_isVideoInitialized
                          ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                          : Container(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF2563EB),
                            strokeWidth: 2.5,
                          ),
                        ),
                      ))
                          : (firebaseMediaUrl != null &&
                          firebaseMediaUrl.isNotEmpty &&
                          !firebaseMediaUrl.toLowerCase().contains('.mp4'))
                          ? Image.network(
                        firebaseMediaUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildFallbackGraphic(incidentThemeColor, incidentIcon),
                      )
                          : _buildFallbackGraphic(incidentThemeColor, incidentIcon),

                      if (isSensitive)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (!_isSensitiveRevealed) {
                                setState(() => _isSensitiveRevealed = true);
                              }
                            },
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 420),
                              reverseDuration: const Duration(milliseconds: 300),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) => Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              ),
                              child: _isSensitiveRevealed
                                  ? const SizedBox.expand(key: ValueKey('sensitive-revealed'))
                                  : BackdropFilter(
                                key: const ValueKey('sensitive-censored'),
                                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                child: Container(
                                  color: Colors.black.withOpacity(0.56),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.16),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                                            ),
                                            child: const Icon(
                                              Icons.visibility_off_rounded,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Sensitive content',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            'Tap anywhere to view this media',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.82),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Top Gradient Overlay for Badge Visibility
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.black.withOpacity(0.55),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Severity Badge (Top-Left)
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: severityColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Text(
                      "${severity.toUpperCase()} SEVERITY",
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                // Close Button (Top-Right)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.5),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ================= CONTENT BODY =================
          Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hazard Type & Time Row
                Row(
                  children: [
                    // Hazard Type Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: incidentThemeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(incidentIcon, size: 14, color: incidentThemeColor),
                          const SizedBox(width: 4),
                          Text(
                            hazardType,
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              color: incidentThemeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Date & Time Timestamp
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 13, color: secondaryTextColor),
                        const SizedBox(width: 4),
                        Text(
                          formattedTime,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            color: secondaryTextColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Incident Title
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: primaryTextColor,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),

                // Description / Details
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: secondaryTextColor,
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 18),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {
                      final reportData = Map<String, dynamic>.from(
                        widget.report as Map,
                      );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => LiveDetailsReports(
                            reportData: reportData,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "View Live Details",
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}