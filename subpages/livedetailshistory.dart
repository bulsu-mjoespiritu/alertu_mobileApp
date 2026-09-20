import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class LiveDetailsHistory extends StatefulWidget {
  final Map<String, dynamic> reportData;

  const LiveDetailsHistory({super.key, required this.reportData});

  @override
  State<LiveDetailsHistory> createState() => _LiveDetailsHistoryState();
}

class _LiveDetailsHistoryState extends State<LiveDetailsHistory> with TickerProviderStateMixin {
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
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
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
        debugPrint("⚠️ Details history view failed to load asset '${entry.value}': $e");
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
        debugPrint("Error drawing trace routing in history details map: $e");
      }
    }

    String pulseType = 'others';
    if (iconFile == 'fireicon.png') pulseType = 'fire';
    else if (iconFile == 'floodicon.png') pulseType = 'flood';
    else if (iconFile == 'accicon.png' || iconFile == 'caricon.png') pulseType = 'accident';

    geoJsonFeatures.add({
      'type': 'Feature',
      'id': 'incident_feat_history_detail',
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
        duration: const Duration(milliseconds: 500),
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

    final String? reportId = widget.reportData['id']?.toString() ?? widget.reportData['_id']?.toString();
    final backgroundColor = isDark ? theme.colorScheme.surface : const Color(0xFFF8FAFC);
    final appBarColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final titleColor = isDark ? theme.colorScheme.onSurface : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          "Resolved Incident Log",
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, color: titleColor),
        ),
        backgroundColor: appBarColor,
        elevation: 0,
        iconTheme: IconThemeData(color: titleColor),
      ),
      body: (reportId == null || reportId.isEmpty)
          ? _buildContent(widget.reportData)
          : StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('ResolvedReports').doc(reportId).snapshots(),
        builder: (context, snapshot) {
          final data = (snapshot.hasData && snapshot.data!.exists)
              ? (snapshot.data!.data() as Map<String, dynamic>..['id'] = snapshot.data!.id)
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

    final dynamic rawTimestamp = data['resolvedAt'] ?? data['verifiedAt'] ?? data['createdAt'] ?? data['timestamp'];
    final DateTime? dt = _parseTimestamp(rawTimestamp);
    final String address = data['location']?['address'] ?? data['address'] ?? "No address recorded";

    final titleColor = isDark ? theme.colorScheme.onSurface : Colors.black;
    final subtitleColor = isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[700];
    final addressColor = isDark ? theme.colorScheme.primary : Colors.blueGrey;
    final cardColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final mapStyle = isDark ? 'https://tiles.openfreemap.org/styles/bright' : 'https://tiles.openfreemap.org/styles/liberty';
    final primaryAccent = isDark ? theme.colorScheme.primary : const Color(0xFF1E3A8A);

    final double responsiveMapHeight = (mediaQuery.size.height * 0.32).clamp(220.0, 320.0);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges Row
          Row(
            children: [
              _buildTag(data['severity']?.toString().toUpperCase() ?? "RESOLVED", const Color(0xFF166534), bgColor: const Color(0xFFDCFCE7)),
              const SizedBox(width: 8),
              _buildTag(data['status']?.toString().toUpperCase() ?? "RESOLVED", const Color(0xFF15803D)),
            ],
          ),
          const SizedBox(height: 12),

          // Title & Timestamp Meta
          Text(
            data['reportTitle'] ?? data['incidentType'] ?? "Resolved Incident Record",
            style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w900, color: titleColor),
          ),
          const SizedBox(height: 4),
          Text(
            "Type: ${data['incidentType'] ?? 'General Emergency'} • ${dt != null ? DateFormat('MMM dd, yyyy • hh:mm a').format(dt) : 'Date N/A'}",
            style: GoogleFonts.montserrat(color: subtitleColor, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            "📍 $address",
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, color: addressColor, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Embedded Map Frame (Primary Visual Component)
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
          Text(
            "Resolution & Dispatch Notes",
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 16, color: titleColor),
          ),
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
              data['adminNotes'] ?? data['description'] ?? data['notes'] ?? "No accompanying resolution notes or final dispatch logs recorded for this resolved incident.",
              style: GoogleFonts.montserrat(height: 1.5, fontSize: 14, color: isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[800]),
            ),
          ),

          SizedBox(height: mediaQuery.padding.bottom + 24),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color textColor, {Color? bgColor}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: bgColor ?? textColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        color: bgColor != null ? textColor : Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    ),
  );
}