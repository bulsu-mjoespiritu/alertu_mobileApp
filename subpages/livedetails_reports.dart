import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:alertu_flutter/homepage.dart';

class LiveDetailsReports extends StatefulWidget {
  final Map<String, dynamic> reportData;

  /// Global carrier so Homepage can inspect which report was selected
  /// when returning via Navigator.popUntil.
  static Map<String, dynamic>? selectedReportForMap;
  static final ValueNotifier<Map<String, dynamic>?> selectedReportForMapNotifier =
  ValueNotifier<Map<String, dynamic>?>(null);

  const LiveDetailsReports({super.key, required this.reportData});

  @override
  State<LiveDetailsReports> createState() => _LiveDetailsReportsState();
}

class _LiveDetailsReportsState extends State<LiveDetailsReports> with TickerProviderStateMixin {
  final Map<String, String> _typeToColor = {
    'fireicon.png': '#ef4444',
    'floodicon.png': '#3b82f6',
    'accicon.png': '#eab308',
    'caricon.png': '#eab308',
    'quakeicon.png': '#78350f',
    'warnicon.png': '#f97316'
  };

  MapLibreMapController? _mapController;
  bool _styleLoaded = false;
  bool _isPulseLayerRendered = false;

  AnimationController? _pulseController;
  Animation<double>? _pulseRadiusAnimation;
  Animation<double>? _pulseOpacityAnimation;

  final List<Line> _incidentLines = [];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat();

    _pulseRadiusAnimation = Tween<double>(begin: 0.0, end: 45.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeOutCubic),
    );

    _pulseOpacityAnimation = Tween<double>(begin: 0.85, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInQuad),
    );

    _pulseController!.addListener(() {
      if (_mapController == null || !_styleLoaded || !_isPulseLayerRendered) return;

      try {
        _mapController!.setLayerProperties(
          "incident-pulse-layer",
          CircleLayerProperties(
            circleRadius: _pulseRadiusAnimation!.value,
            circleOpacity: _pulseOpacityAnimation!.value,
            circleColor: [
              "match",
              ["string", ["get", "icon"]],
              "fireicon.png", "#ef4444",
              "floodicon.png", "#3b82f6",
              "accicon.png", "#eab308",
              "caricon.png", "#eab308",
              "quakeicon.png", "#78350f",
              "warnicon.png", "#f97316",
              "#f97316"
            ],
          ),
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is String) return DateTime.tryParse(timestamp);
    return null;
  }

  String _normalizeIconFile(String type, String? selectedIcon) {
    if (selectedIcon != null && selectedIcon.isNotEmpty) return selectedIcon;

    final normalized = type.toLowerCase().trim();
    if (normalized.contains('fire')) return 'fireicon.png';
    if (normalized.contains('flood')) return 'floodicon.png';
    if (normalized.contains('acc') || normalized.contains('car')) return 'accicon.png';
    if (normalized.contains('quake')) return 'quakeicon.png';
    return 'warnicon.png';
  }

  Future<Uint8List> _resizeMarkerAsset(Uint8List assetBytes, int targetWidth) async {
    final ui.Codec codec = await ui.instantiateImageCodec(assetBytes, targetWidth: targetWidth);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ByteData? byteData = await frameInfo.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onStyleLoaded(Map<String, dynamic> data) async {
    if (_mapController == null) return;
    setState(() => _styleLoaded = true);

    final Map<String, String> iconAssetPaths = {
      'fireicon.png': 'images/markericons/fireicon.png',
      'floodicon.png': 'images/markericons/floodicon.png',
      'accicon.png': 'images/markericons/accicon.png',
      'caricon.png': 'images/markericons/caricon.png',
      'quakeicon.png': 'images/markericons/quakeicon.png',
      'warnicon.png': 'images/markericons/warnicon.png',
    };

    for (var entry in iconAssetPaths.entries) {
      try {
        final ByteData bytes = await rootBundle.load(entry.value);
        final Uint8List rawList = bytes.buffer.asUint8List();
        final Uint8List resizedList = await _resizeMarkerAsset(rawList, 140);
        await _mapController?.addImage(entry.key, resizedList);
      } catch (e) {
        debugPrint("⚠️ Details view failed to load asset '${entry.value}': $e");
      }
    }

    try {
      await _mapController?.addGeoJsonSource("incident-circles-source", {"type": "FeatureCollection", "features": []});
      await _mapController?.addFillLayer("incident-circles-source", "incident-circles-fill-layer", const FillLayerProperties(fillColor: ["get", "color"], fillOpacity: 0.20));
      await _mapController?.addLineLayer("incident-circles-source", "incident-circles-line-layer", const LineLayerProperties(lineColor: ["get", "color"], lineWidth: 3.0, lineOpacity: 0.80));
    } catch (e) {
      debugPrint("Error initializing incident boundary geometry structures: $e");
    }

    _renderIncidentGeometries(data);
  }

  void _renderIncidentGeometries(Map<String, dynamic> data) async {
    if (_mapController == null) return;

    for (var line in _incidentLines) {
      try { await _mapController!.removeLine(line); } catch (_) {}
    }
    _incidentLines.clear();

    try {
      _isPulseLayerRendered = false;
      await _mapController!.removeLayer("incident-symbols-layer");
      await _mapController!.removeLayer("incident-pulse-layer");
      await _mapController!.removeSource("incident-symbols-source");
    } catch (_) {}

    List<Map<String, dynamic>> pendingLines = [];
    List<Map<String, dynamic>> geoJsonFeatures = [];
    List<Map<String, dynamic>> circleGeoJsonFeatures = [];

    final radiusData = data['radius'];
    final polylineData = data['polyline'];
    final routeCoords = data['routeCoords'] as List?;
    final locationData = data['location'];

    String rawType = data['incidentType']?.toString() ?? 'warn';
    String iconFile = _normalizeIconFile(rawType, data['selectedMarkerIcon']?.toString());
    String hexColor = _typeToColor[iconFile] ?? '#f97316';

    double lat = radiusData?['centerLat']?.toDouble() ?? locationData?['latitude']?.toDouble() ?? data['latitude']?.toDouble() ?? 14.7925;
    double lng = radiusData?['centerLng']?.toDouble() ?? locationData?['longitude']?.toDouble() ?? data['longitude']?.toDouble() ?? 120.8970;
    LatLng pinTarget = LatLng(lat, lng);

    if ((routeCoords != null && routeCoords.isNotEmpty) || (polylineData != null && polylineData.length >= 2)) {
      List<LatLng> points = [];
      if (routeCoords != null && routeCoords.isNotEmpty) {
        var sorted = List.from(routeCoords)..sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));
        points = sorted.map<LatLng>((pt) => LatLng(pt['lat'].toDouble(), pt['lng'].toDouble())).toList();
      } else {
        points = polylineData.map<LatLng>((pt) => LatLng(pt['lat'].toDouble(), pt['lng'].toDouble())).toList();
      }

      if (points.isNotEmpty) {
        pinTarget = points[points.length ~/ 2];
        pendingLines.add({'geometry': points, 'color': hexColor});
      }
    } else if (radiusData != null) {
      double radiusMeters = radiusData['radiusMeters']?.toDouble() ?? 300.0;
      circleGeoJsonFeatures.add(_createGeoJsonCirclePolygon(pinTarget, radiusMeters, hexColor, 0));
    }

    final Map<String, dynamic> cachedCircleGeoJsonCollection = {'type': 'FeatureCollection', 'features': circleGeoJsonFeatures};
    await _mapController!.setGeoJsonSource("incident-circles-source", cachedCircleGeoJsonCollection);

    for (var lineData in pendingLines) {
      try {
        final addedLine = await _mapController!.addLine(
          LineOptions(
            geometry: lineData['geometry'] as List<LatLng>,
            lineColor: lineData['color'] as String,
            lineWidth: 4.5,
            lineOpacity: 0.85,
            lineJoin: "round",
          ),
        );
        _incidentLines.add(addedLine);
      } catch (e) {
        debugPrint("Error drawing trace routing in details map: $e");
      }
    }

    String pulseType = 'others';
    if (iconFile == 'fireicon.png') pulseType = 'fire';
    else if (iconFile == 'floodicon.png') pulseType = 'flood';
    else if (iconFile == 'accicon.png' || iconFile == 'caricon.png') pulseType = 'accident';

    geoJsonFeatures.add({
      'type': 'Feature',
      'id': 'incident_feat_detail',
      'geometry': {'type': 'Point', 'coordinates': [pinTarget.longitude, pinTarget.latitude]},
      'properties': {
        'icon': iconFile,
        'pulseType': pulseType,
        'isSelected': true,
      }
    });

    if (geoJsonFeatures.isNotEmpty) {
      final Map<String, dynamic> cachedGeoJsonCollection = {'type': 'FeatureCollection', 'features': geoJsonFeatures};
      await _mapController!.addGeoJsonSource("incident-symbols-source", cachedGeoJsonCollection);

      await _mapController!.addCircleLayer(
        "incident-symbols-source",
        "incident-pulse-layer",
        const CircleLayerProperties(
          circleColor: ["match", ["get", "pulseType"], "fire", "#ef4444", "flood", "#3b82f6", "accident", "#eab308", "others", "#f97316", "#f97316"],
          circlePitchAlignment: "map",
          circleStrokeWidth: 0.0,
        ),
      );

      _isPulseLayerRendered = true;

      await _mapController!.addSymbolLayer(
        "incident-symbols-source",
        "incident-symbols-layer",
        const SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 1.4,
          iconAnchor: "bottom",
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(pinTarget, 15.2),
          duration: const Duration(milliseconds: 500)
      );
    }
  }

  Map<String, dynamic> _createGeoJsonCirclePolygon(LatLng center, double radiusMeters, String color, int reportIndex) {
    const int steps = 64;
    List<List<double>> coordinates = [];
    const double earthRadius = 6378137.0;
    double latRad = center.latitude * (math.pi / 180.0);

    for (int i = 0; i <= steps; i++) {
      double theta = (i * 2 * math.pi) / steps;
      double dLat = (radiusMeters * math.cos(theta)) / earthRadius;
      double dLng = (radiusMeters * math.sin(theta)) / (earthRadius * math.cos(latRad));

      double pLat = center.latitude + (dLat * (180.0 / math.pi));
      double pLng = center.longitude + (dLng * (180.0 / math.pi));
      coordinates.add([pLng, pLat]);
    }

    return {
      "type": "Feature",
      "geometry": {
        "type": "Polygon",
        "coordinates": [coordinates]
      },
      "properties": {
        "color": color,
        "reportIndex": reportIndex,
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String? reportId = widget.reportData['_id']?.toString();
    final backgroundColor = isDark ? theme.colorScheme.surface : const Color(0xFFF8FAFC);
    final appBarColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final titleColor = isDark ? theme.colorScheme.onSurface : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          "Incident Details",
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, color: titleColor),
        ),
        backgroundColor: appBarColor,
        elevation: 0,
        iconTheme: IconThemeData(color: titleColor),
      ),
      body: (reportId == null || reportId.isEmpty)
          ? _buildContent(widget.reportData)
          : StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('reports').doc(reportId).snapshots(),
        builder: (context, snapshot) {
          final data = (snapshot.hasData && snapshot.data!.exists)
              ? snapshot.data!.data() as Map<String, dynamic>
              : widget.reportData;
          return _buildContent(data);
        },
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);

    final radiusData = data['radius'];
    final locationData = data['location'];

    final double lat = radiusData?['centerLat']?.toDouble() ?? locationData?['latitude']?.toDouble() ?? data['latitude']?.toDouble() ?? 14.7925;
    final double lng = radiusData?['centerLng']?.toDouble() ?? locationData?['longitude']?.toDouble() ?? data['longitude']?.toDouble() ?? 120.8970;

    final DateTime? dt = _parseTimestamp(data['timestamp']);
    final String address = data['location']?['address'] ?? data['address'] ?? "No address available";
    final Uri googleMapsUri = Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{
        'api': '1',
        'query': '$lat,$lng',
      },
    );

    final titleColor = isDark ? theme.colorScheme.onSurface : Colors.black;
    final subtitleColor = isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[700];
    final addressColor = isDark ? theme.colorScheme.primary : Colors.blueGrey;
    final cardColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final mapStyle = isDark ? 'https://tiles.openfreemap.org/styles/bright' : 'https://tiles.openfreemap.org/styles/liberty';
    final primaryAccent = isDark ? theme.colorScheme.primary : const Color(0xFF1E3A8A);

    final double responsiveMapHeight = (mediaQuery.size.height * 0.26).clamp(180.0, 260.0);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Image / Video
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _buildMediaPreview(
              data['mediaUrl']?.toString(),
              height: (mediaQuery.size.height * 0.28).clamp(180.0, 280.0),
              isDark: isDark,
              isSensitive: data['isSensitive'] == true,
              mediaIdentity: '${data['_id'] ?? data['id'] ?? ''}_${data['mediaUrl'] ?? ''}',
            ),
          ),

          const SizedBox(height: 16),

          // Badges
          Row(
            children: [
              _buildTag(data['severity']?.toString().toUpperCase() ?? "LOW", Colors.red),
              const SizedBox(width: 8),
              _buildTag(data['status']?.toString().toUpperCase() ?? "ACTIVE", Colors.green),
            ],
          ),
          const SizedBox(height: 12),

          // Title & Meta Information
          Text(
            data['reportTitle'] ?? "Incident Update",
            style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w900, color: titleColor),
          ),
          const SizedBox(height: 4),
          Text(
            "Type: ${data['incidentType'] ?? 'N/A'} | ${dt != null ? DateFormat('MMM dd, yyyy HH:mm').format(dt) : 'Date N/A'}",
            style: GoogleFonts.montserrat(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            "📍 $address",
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, color: addressColor, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Embedded Map Frame
          SizedBox(
            height: responsiveMapHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MapLibreMap(
                styleString: mapStyle,
                initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 14.5),
                onMapCreated: _onMapCreated,
                onStyleLoadedCallback: () => _onStyleLoaded(data),
                myLocationEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Description Header & Card
          Text("Description", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 16, color: titleColor)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(left: BorderSide(color: primaryAccent, width: 4)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              data['adminNotes'] ?? data['notes'] ?? "No accompanying structural description or operational dispatch notes provided for this log.",
              style: GoogleFonts.montserrat(height: 1.5, fontSize: 14, color: isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[800]),
            ),
          ),

          const SizedBox(height: 24),

          // Action Buttons
          Column(
            children: [
              _buildButton(
                "View on Map",
                Icons.navigation,
                primaryAccent,
                Colors.white,
                onTap: () {
                  // Return the selected report to Homepage for map centering
                  // and report-card presentation.
                  final selected = Map<String, dynamic>.from(data);
                  LiveDetailsReports.selectedReportForMap = selected;
                  LiveDetailsReports.selectedReportForMapNotifier.value = selected;

                  // Return through the existing route stack. Homepage remains
                  // mounted, so its MapLibre map is not recreated or reloaded.
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },

              ),
              const SizedBox(height: 12),
              _buildButton(
                "Open in Google Maps",
                Icons.map,
                Colors.transparent,
                titleColor,
                bordered: true,
                leading: Image.asset(
                  'images/googleicon.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                ),
                onTap: () async {
                  final opened = await launchUrl(
                    googleMapsUri,
                    mode: LaunchMode.externalApplication,
                  );

                  if (!opened && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Unable to open Google Maps on this device.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),

            ],
          ),

          SizedBox(height: mediaQuery.padding.bottom + 24),
        ],
      ),
    );
  }

  Widget _buildMediaPreview(
      String? mediaUrl, {
        required double height,
        required bool isDark,
        required bool isSensitive,
        required String mediaIdentity,
      }) {
    final String? url = mediaUrl?.trim();
    final bool isVideo = url != null &&
        url.isNotEmpty &&
        (url.toLowerCase().contains('.mp4') || url.toLowerCase().contains('video/'));

    final Widget mediaChild;
    if (!isVideo) {
      mediaChild = Image.network(
        url ?? '',
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: height,
            color: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : Colors.grey[200],
            alignment: Alignment.center,
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 50,
              color: isDark ? Colors.grey.shade400 : Colors.grey,
            ),
          );
        },
      );
    } else {
      mediaChild = _DetailsVideoPreview(videoUrl: url, height: height, isDark: isDark);
    }

    return _SensitiveDetailsMediaPreview(
      height: height,
      isSensitive: isSensitive,
      mediaIdentity: mediaIdentity,
      child: mediaChild,
    );
  }

  Widget _buildTag(String text, Color color) => Container(

    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: GoogleFonts.montserrat(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
  );

  Widget _buildButton(
      String text,
      IconData icon,
      Color bg,
      Color textColor, {
        bool bordered = false,
        Widget? leading,
        VoidCallback? onTap,
      }) {

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap ?? () {},
        icon: leading ?? Icon(icon, color: textColor, size: 18),

        label: Text(text, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: textColor, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          side: bordered
              ? BorderSide(color: isDark ? theme.colorScheme.outline.withOpacity(0.5) : Colors.grey[400]!, width: 1.5)
              : BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: bg != Colors.transparent ? 2 : 0,
        ),
      ),
    );
  }
}

class _SensitiveDetailsMediaPreview extends StatefulWidget {
  final double height;
  final bool isSensitive;
  final String mediaIdentity;
  final Widget child;

  const _SensitiveDetailsMediaPreview({
    required this.height,
    required this.isSensitive,
    required this.mediaIdentity,
    required this.child,
  });

  @override
  State<_SensitiveDetailsMediaPreview> createState() => _SensitiveDetailsMediaPreviewState();
}

class _SensitiveDetailsMediaPreviewState extends State<_SensitiveDetailsMediaPreview> {
  bool _isRevealed = false;

  @override
  void didUpdateWidget(covariant _SensitiveDetailsMediaPreview oldWidget) {
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

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
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
                      key: const ValueKey('details-sensitive-overlay'),
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
                      key: ValueKey('details-sensitive-revealed'),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailsVideoPreview extends StatefulWidget {
  final String videoUrl;
  final double height;
  final bool isDark;

  const _DetailsVideoPreview({
    required this.videoUrl,
    required this.height,
    required this.isDark,
  });

  @override
  State<_DetailsVideoPreview> createState() => _DetailsVideoPreviewState();
}

class _DetailsVideoPreviewState extends State<_DetailsVideoPreview> {
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
  void didUpdateWidget(covariant _DetailsVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    final previousController = _controller;
    _controller = null;
    _hasFailed = false;
    _isPlaying = false;
    _hasFinished = false;
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
      });
    } catch (error) {
      debugPrint('❌ Live details video initialization failed: $error');
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
      return Container(
        height: widget.height,
        color: widget.isDark ? const Color(0xFF1E293B) : Colors.grey[200],
        alignment: Alignment.center,
        child: Icon(
          Icons.video_library_outlined,
          size: 50,
          color: widget.isDark ? Colors.grey.shade400 : Colors.grey,
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return SizedBox(
        height: widget.height,
        child: Container(
          color: widget.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            color: Color(0xFF2563EB),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
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
      ),
    );
  }
}
