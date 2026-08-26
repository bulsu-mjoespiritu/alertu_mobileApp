import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as libre;
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'homepage.dart';

class ConfirmationSubpage extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> reportDetails;

  const ConfirmationSubpage({
    super.key,
    required this.reportId,
    required this.reportDetails,
  });

  @override
  State<ConfirmationSubpage> createState() => _ConfirmationSubpageState();
}

class _ConfirmationSubpageState extends State<ConfirmationSubpage> {
  libre.MapLibreMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dynamic Theme Color Palette
    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final surfaceBg = isDark ? theme.colorScheme.surface : const Color(0xFFF8FAFC);
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final cardBorder = isDark
        ? theme.colorScheme.outline.withOpacity(0.3)
        : const Color(0xFFE2E8F0);
    final textMain = isDark ? theme.colorScheme.onSurface : const Color(0xFF0F172A);
    final textMuted = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);
    final dividerColor = isDark
        ? theme.colorScheme.outline.withOpacity(0.2)
        : const Color(0xFFE2E8F0);
    final fallbackBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : const Color(0xFFF1F5F9);

    // Map Tile Style for MapLibre
    final mapStyleUrl = isDark
        ? 'https://tiles.openfreemap.org/styles/dark'
        : 'https://tiles.openfreemap.org/styles/liberty';

    // Shimmer Colors based on theme
    final baseShimmerColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightShimmerColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    final double screenWidth = MediaQuery.of(context).size.width;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double contentPadding = screenWidth > 600 ? 24.0 : 16.0;

    // Safely extract coordinates
    final double? latitude = widget.reportDetails['latitude'] != null
        ? double.tryParse(widget.reportDetails['latitude'].toString())
        : null;
    final double? longitude = widget.reportDetails['longitude'] != null
        ? double.tryParse(widget.reportDetails['longitude'].toString())
        : null;

    final bool hasValidCoords = latitude != null && longitude != null;

    final String? mediaUrl = widget.reportDetails['mediaUrl']?.toString();
    final String? mediaType = widget.reportDetails['mediaType']?.toString(); // optional explicit type ('video' or 'image')

    return Scaffold(
      backgroundColor: surfaceBg,
      appBar: AppBar(
        title: Text(
          'Submission Status',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: textMain,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // Prevents going back to submission screen
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: dividerColor, height: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              contentPadding,
              20.0,
              contentPadding,
              bottomPadding > 0 ? bottomPadding + 16.0 : 24.0,
            ),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SUCCESS BANNER
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(isDark ? 0.2 : 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: primaryColor,
                              size: 60,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.reportDetails['isDuplicate'] == true
                                ? 'Duplicate Report Logged'
                                : 'Report Submitted Successfully',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textMain,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Text(
                              widget.reportDetails['isDuplicate'] == true
                                  ? 'An active incident matching this location was already reported. Your submission has been linked to assist emergency responders.'
                                  : 'Your incident report has been sent to emergency responders. Thank you for helping keep the community safe.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20.0),
                      child: Divider(color: dividerColor, height: 1),
                    ),

                    // INCIDENT & SEVERITY CARDS
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            'Incident Type',
                            (widget.reportDetails['incidentType'] != null &&
                                widget.reportDetails['incidentType'].toString().isNotEmpty)
                                ? widget.reportDetails['incidentType']
                                : 'N/A',
                            primaryColor,
                            cardBg,
                            cardBorder,
                            isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInfoCard(
                            'Severity',
                            (widget.reportDetails['severity'] != null &&
                                widget.reportDetails['severity'].toString().isNotEmpty)
                                ? widget.reportDetails['severity']
                                : 'N/A',
                            isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B),
                            cardBg,
                            cardBorder,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 👤 REPORTER IDENTITY SECTION
                    _buildSectionTitle('Reporter Identity', isDark),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          _buildIdentityRow(
                            Icons.person_outline_rounded,
                            'Name',
                            widget.reportDetails['submitterName'] ?? 'Anonymous Citizen',
                            textMain,
                            textMuted,
                          ),
                          Divider(height: 16, color: dividerColor),
                          _buildIdentityRow(
                            Icons.email_outlined,
                            'Email',
                            widget.reportDetails['submitterEmail'] ?? 'No email provided',
                            textMain,
                            textMuted,
                          ),
                          Divider(height: 16, color: dividerColor),
                          _buildIdentityRow(
                            Icons.phone_outlined,
                            'Phone',
                            widget.reportDetails['submitterPhone'] ?? 'No contact number',
                            textMain,
                            textMuted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // CAPTURED EVIDENCE (IMAGE OR VIDEO)
                    _buildSectionTitle('Captured Evidence', isDark),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: mediaUrl != null && mediaUrl.isNotEmpty
                            ? MediaPreviewWidget(
                          url: mediaUrl,
                          mediaType: mediaType,
                          baseShimmerColor: baseShimmerColor,
                          highlightShimmerColor: highlightShimmerColor,
                          fallbackBg: fallbackBg,
                          textMuted: textMuted,
                        )
                            : _buildFallbackContainer(
                          Icons.image_not_supported_rounded,
                          'No Evidence Attached',
                          fallbackBg,
                          textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // LOCATION INFORMATION & MAPLIBRE MAP
                    _buildSectionTitle('Incident Location', isDark),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, color: primaryColor, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.reportDetails['address'] ?? 'Location not specified',
                            style: TextStyle(
                              color: textMain,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // MAPLIBRE MAP CONTAINER
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: hasValidCoords
                              ? libre.MapLibreMap(
                            key: ValueKey('${latitude}_${longitude}_$isDark'),
                            styleString: mapStyleUrl,
                            initialCameraPosition: libre.CameraPosition(
                              target: libre.LatLng(latitude, longitude),
                              zoom: 15.0,
                            ),
                            myLocationEnabled: false,
                            onMapCreated: (libre.MapLibreMapController controller) {
                              _mapController = controller;
                            },
                            onStyleLoadedCallback: () async {
                              if (_mapController != null) {
                                try {
                                  await _mapController!.addCircle(
                                    libre.CircleOptions(
                                      geometry: libre.LatLng(latitude, longitude),
                                      circleRadius: 8.0,
                                      circleColor: isDark ? '#60A5FA' : '#1E40AF',
                                      circleStrokeWidth: 2.5,
                                      circleStrokeColor: '#FFFFFF',
                                    ),
                                  );
                                } catch (e) {
                                  debugPrint("Map marker error: $e");
                                }
                              }
                            },
                          )
                              : _buildFallbackContainer(
                            Icons.map_rounded,
                            'Coordinates unavailable',
                            fallbackBg,
                            textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // CONTINUE BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const Homepage(),
                            ),
                                (route) => false,
                          );
                        },
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Helper Methods
  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
      ),
    );
  }

  Widget _buildInfoCard(
      String title,
      String value,
      Color accentColor,
      Color cardBg,
      Color cardBorder,
      bool isDark,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityRow(
      IconData icon,
      String label,
      String value,
      Color textMain,
      Color textMuted,
      ) {
    return Row(
      children: [
        Icon(icon, color: textMuted, size: 18),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 13,
            color: textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              color: textMain,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackContainer(
      IconData icon,
      String message,
      Color fallbackBg,
      Color textMuted,
      ) {
    return Container(
      height: 150,
      color: fallbackBg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textMuted, size: 28),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// MEDIA PREVIEW WIDGET (HANDLES IMAGE & VIDEO)
// ==========================================
class MediaPreviewWidget extends StatefulWidget {
  final String url;
  final String? mediaType;
  final Color baseShimmerColor;
  final Color highlightShimmerColor;
  final Color fallbackBg;
  final Color textMuted;

  const MediaPreviewWidget({
    super.key,
    required this.url,
    this.mediaType,
    required this.baseShimmerColor,
    required this.highlightShimmerColor,
    required this.fallbackBg,
    required this.textMuted,
  });

  @override
  State<MediaPreviewWidget> createState() => _MediaPreviewWidgetState();
}

class _MediaPreviewWidgetState extends State<MediaPreviewWidget> {
  VideoPlayerController? _videoController;
  bool _isInitializingVideo = false;
  bool _videoError = false;

  bool get _isVideo {
    if (widget.mediaType != null) {
      return widget.mediaType!.toLowerCase() == 'video';
    }
    final lowerUrl = widget.url.toLowerCase();
    return lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mov') ||
        lowerUrl.endsWith('.mkv') ||
        lowerUrl.endsWith('.webm') ||
        lowerUrl.endsWith('.avi');
  }

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    setState(() {
      _isInitializingVideo = true;
    });

    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _videoController!.initialize();
      _videoController!.setLooping(true);
      setState(() {
        _isInitializingVideo = false;
      });
    } catch (e) {
      debugPrint("Video initialization failed: $e");
      setState(() {
        _isInitializingVideo = false;
        _videoError = true;
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isVideo) {
      if (_isInitializingVideo) {
        return _buildShimmerBox();
      }

      if (_videoError || _videoController == null || !_videoController!.value.isInitialized) {
        return _buildFallback(Icons.videocam_off_rounded, 'Video preview unavailable');
      }

      return SizedBox(
        height: 180,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _videoController!.value.isPlaying
                      ? _videoController!.pause()
                      : _videoController!.play();
                });
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _videoController!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default to Image rendering
    return Image.network(
      widget.url,
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _buildShimmerBox();
      },
      errorBuilder: (context, error, stackTrace) =>
          _buildFallback(Icons.broken_image_rounded, 'Media could not be loaded'),
    );
  }

  Widget _buildShimmerBox() {
    return Shimmer.fromColors(
      baseColor: widget.baseShimmerColor,
      highlightColor: widget.highlightShimmerColor,
      child: Container(
        height: 180,
        width: double.infinity,
        color: widget.baseShimmerColor,
      ),
    );
  }

  Widget _buildFallback(IconData icon, String message) {
    return Container(
      height: 180,
      color: widget.fallbackBg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: widget.textMuted, size: 28),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: widget.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}