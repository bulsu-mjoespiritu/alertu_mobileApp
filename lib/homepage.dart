import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:alertu_flutter/services/socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adaptive_theme/adaptive_theme.dart';

import 'package:alertu_flutter/services/api_service.dart';
import 'package:alertu_flutter/services/quick_report_channel.dart';
import 'package:alertu_flutter/pages/notifspage.dart';
import 'package:alertu_flutter/pages/reportspage.dart';
import 'package:alertu_flutter/pages/settingspage.dart';
import '../subpages/livedetails_reports.dart';

import 'components/AnimatedMapMove.dart';
import 'components/DateandTime_Modal.dart';
import 'components/Emergency_Call_Button.dart';
import 'components/MapLegends_Button.dart';
import 'components/MapLegends_Modal.dart';
import 'components/Navigation_Bar.dart';
import 'components/SOS_Button.dart';
import 'components/Search_Bar.dart';
import 'components/SummaryReport_Button.dart';
import 'components/UserPinpoint_Button.dart';
import 'components/IsThisYourLocation.dart';
import 'package:alertu_flutter/disable_modal.dart';

// --- ANIMATION UI KIT UTILITIES ---
import 'package:alertu_flutter/services/reportnotifs.dart';
import 'package:alertu_flutter/services/nearbyreports_notifs.dart';
import 'package:alertu_flutter/services/insidethereports_notifs.dart';
import 'package:alertu_flutter/services/userexitedreport_notifs.dart';
import 'components/showreportifinsideuser.dart';
import 'components/slideup_animation.dart';
import 'components/slidedown_animation.dart';
import 'components/switch_to_navbar.dart';
import 'components/switch_to_reportmodalcard.dart';
import 'components/showReportInfoCard.dart';
import 'emergencycall_page.dart';
import 'global/navbarcount.dart';

// =========================================================================
// STRUCTURAL RESPONSIVE LAYOUT & HELPER ENGINE
// =========================================================================

enum ScreenType { compactMobile, regularMobile, tablet }

class ResponsiveLayoutBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenType screenType, bool isCompact) builder;

  const ResponsiveLayoutBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        ScreenType screenType = ScreenType.regularMobile;
        bool isCompact = false;

        if (constraints.maxWidth < 360) {
          screenType = ScreenType.compactMobile;
          isCompact = true;
        } else if (constraints.maxWidth >= 600) {
          screenType = ScreenType.tablet;
        }

        return builder(context, screenType, isCompact);
      },
    );
  }
}

class CenterandFixTheViewIncidents {
  static Future<void> focusCameraOnIncident({
    required MapLibreMapController controller,
    required double latitude,
    required double longitude,
    double targetZoom = 15.5,
  }) async {
    const double latBuffer = 0.0035;
    const double lngBuffer = 0.0035;

    final bounds = LatLngBounds(
      southwest: LatLng(latitude - latBuffer, longitude - lngBuffer),
      northeast: LatLng(latitude + latBuffer, longitude + lngBuffer),
    );

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 32.0,
        top: 130.0,
        right: 32.0,
        bottom: 430.0,
      ),
      duration: const Duration(milliseconds: 600),
    );
  }

  static Future<Position> getSafeUserPositionFallback() async {
    try {
      bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationServiceEnabled) return _getDefaultBulacanFallback();

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return _getDefaultBulacanFallback();
      }
      if (permission == LocationPermission.deniedForever) return _getDefaultBulacanFallback();

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
    } catch (_) {
      return _getDefaultBulacanFallback();
    }
  }

  static Position _getDefaultBulacanFallback() {
    return Position(
      latitude: 14.7925,
      longitude: 120.8970,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
  }
}

// =========================================================================
// MAIN HOMEPAGE STATEFUL MANAGEMENT CORE
// =========================================================================

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> with TickerProviderStateMixin {
  AnimationController? _pulseController;
  Animation<double>? _pulseRadiusAnimation;
  Animation<double>? _pulseOpacityAnimation;
  AnimationController? _incidentTransitionController;
  double _incidentFadeOpacity = 1.0;
  bool _incidentLayersInitialized = false;
  bool _isPulseLayerRendered = false;

  dynamic _activeSelectedReport;
  bool _isDeactivationModalShowing = false;
  bool _isInfoCardVisible = false;
  String? _selectedFeatureId;
  String? _lastCameraCenteredFeatureId;
  SymbolManager? _symbolManager;
  CircleManager? _circleManager;
  LineManager? _lineManager;
  Symbol? _userLocationSymbol;
  MapLibreMapController? mapController;
  int _currentIndex = 0;
  final ValueNotifier<bool> _notificationsTabVisibility = ValueNotifier<bool>(false);
  Position? _currentPosition;
  bool _isRecentering = false;
  bool _isLoadingLocation = false;

  Map<String, dynamic>? _insideHazardReport;
  bool _isInsideHazardCardVisible = false;
  bool _isInsideCardDismissAnimating = false;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _locationAnimationTimer;
  Timer? _cameraFollowScheduleTimer;
  LatLng? _pendingCameraFollowLocation;
  bool _cameraFollowInProgress = false;
  LatLng? _displayedUserLocation;
  LatLng? _targetUserLocation;
  double _displayedAccuracy = 30.0;
  double _targetAccuracy = 30.0;
  int _locationAnimationToken = 0;
  bool _locationRenderInProgress = false;
  LatLng? _pendingUserLocation;
  double _pendingUserAccuracy = 30.0;
  bool _isAccountDisabledChecked = false; // Flag to prevent multi-triggering modal

  Timer? _liveAccountSyncTimer;

  final List<Line> _incidentLines = [];
  List<dynamic> _incidentReports = [];
  bool _styleLoaded = false;
  bool? _lastMapDarkMode;

  static const String _lightMapStyle =
      'https://tiles.openfreemap.org/styles/liberty';
  static const String _darkMapStyle =
      'https://tiles.openfreemap.org/styles/dark';

  Map<String, dynamic> _cachedGeoJsonCollection = {
    "type": "FeatureCollection",
    "features": []
  };

  Map<String, dynamic> _cachedCircleGeoJsonCollection = {
    "type": "FeatureCollection",
    "features": []
  };

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(14.7925, 120.8970),
    zoom: 13.0,
  );

  final LatLngBounds _bulacanBounds = LatLngBounds(
    southwest: const LatLng(14.7000, 120.6000),
    northeast: const LatLng(15.2000, 121.3000),
  );

  final Map<String, String> _iconColorMap = {
    'fireicon.png': '#ef4444',
    'floodicon.png': '#3b82f6',
    'accicon.png': '#eab308',
    'caricon.png': '#eab308',
    'quakeicon.png': '#78350f',
    'warnicon.png': '#f97316'
  };

  /// React-created approved reports contain `incidentType`, while older
  /// Flutter-created reports may contain `selectedMarkerIcon`. Support both
  /// formats so missing icon metadata does not become an incorrect Others icon.
  String _resolveIncidentIcon(Map<String, dynamic> report) {
    final rawIcon = report['selectedMarkerIcon'] ??
        report['markerIcon'] ??
        report['icon'];

    if (rawIcon != null) {
      final iconName = rawIcon.toString().trim().split('/').last;
      if (_iconColorMap.containsKey(iconName)) return iconName;
    }

    final rawType = report['incidentType'] ??
        report['verifiedIncidentType'] ??
        report['type'];
    final incidentType = rawType?.toString().trim().toLowerCase() ?? '';

    if (incidentType.contains('fire')) return 'fireicon.png';
    if (incidentType.contains('flood')) return 'floodicon.png';
    if (incidentType.contains('accident') || incidentType.contains('vehicle')) {
      return 'accicon.png';
    }
    if (incidentType.contains('quake') || incidentType.contains('earthquake')) {
      return 'quakeicon.png';
    }

    return 'warnicon.png';
  }

  List<Widget> _pages = [];

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

  /// Helper to fetch Citizen Profile details (Citizen ID and Full Name) from Firestore
  Future<Map<String, String>> _getCitizenDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'citizenId': 'UNKNOWN',
        'citizenName': 'Emergency Citizen',
      };
    }

    try {
      // 1. Query 'citizens' collection by authUid or uid
      var docQuery = await FirebaseFirestore.instance
          .collection('citizens')
          .where('authUid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (docQuery.docs.isEmpty) {
        docQuery = await FirebaseFirestore.instance
            .collection('citizens')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
      }

      if (docQuery.docs.isNotEmpty) {
        final data = docQuery.docs.first.data();

        // Retrieve Citizen ID
        final rawCid = data['citizenID'] ?? data['citizenId'] ?? data['cid'] ?? data['CID'];
        final citizenId = rawCid?.toString() ?? 'UNKNOWN';

        // Retrieve Citizen Full Name
        final fullName = data['fullName']?.toString() ??
            data['name']?.toString() ??
            user.displayName ??
            user.email ??
            'Emergency Citizen';

        return {
          'citizenId': citizenId,
          'citizenName': fullName,
        };
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching citizen profile details: $e");
    }

    return {
      'citizenId': 'UNKNOWN',
      'citizenName': user.displayName ?? user.email ?? 'Emergency Citizen',
    };
  }

  @override
  void initState() {
    super.initState();

    // 🎯 Hand up the exact same trigger the in-app report button uses, so
    // the Quick Settings tile can fire it directly instead of a separate,
    // divergent path.
    QuickReportBridge.registerTrigger(_handleReportIncident);

    _setupSocketDeactivationListener();
    _setupIncidentNotificationSocketListener();

    LiveDetailsReports.selectedReportForMapNotifier.addListener(
      _onSelectedReportForMapChanged,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeSelectedReportForMap();
    });

    _pages = [
      const SizedBox.shrink(),
      const ReportsPage(),
      const SizedBox.shrink(),
      NotificationsPage(visibility: _notificationsTabVisibility),
      const SettingsPage(),
    ];

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat();

    // Short, interruptible transition used only when a report arrives or is updated.
    // Keeping the layers alive avoids the visible remove/re-add jump on the map.
    _incidentTransitionController = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    )
      ..addListener(() {
        _incidentFadeOpacity = Curves.easeOutCubic.transform(
          _incidentTransitionController!.value,
        );
        unawaited(_applyIncidentTransitionOpacity(_incidentFadeOpacity));
      });

    _pulseRadiusAnimation = Tween<double>(begin: 0.0, end: 45.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeOutCubic),
    );

    _pulseOpacityAnimation = Tween<double>(begin: 0.85, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInQuad),
    );

    _pulseController!.addListener(() async {

      // Guard against unmounted, missing controller, or pending modal navigation
      if (!mounted || mapController == null || !_styleLoaded || !_isPulseLayerRendered || _isAccountDisabledChecked) return;

      try {
        await mapController!.setLayerProperties(

          "incident-pulse-layer",
          CircleLayerProperties(
            circleRadius: _pulseRadiusAnimation!.value,
            circleOpacity: [
              "*",
              ["coalesce", ["get", "renderOpacity"], 1.0],
              _pulseOpacityAnimation!.value,
            ],
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
      } on MissingPluginException catch (e) {
        debugPrint("MapLibre pulse layer channel detached: $e");
      } on PlatformException catch (e) {
        if (e.code != 'STYLE_NOT_READY') {
          debugPrint("MapLibre pulse layer update error: $e");
        }
      } catch (_) {}

    });

    // Initial account verification
    _verifyUserAccountActiveStatus();

    // Start background sync polling every 10 seconds for real-time disables & reports
    _liveAccountSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_isAccountDisabledChecked) {
        _verifyUserAccountActiveStatus();
        _fetchApprovedIncidents();
      }
    });

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen(
      _onPositionUpdate,
      onError: (Object error) {
        debugPrint('Location stream error: $error');
      },
    );

    // Start the nearby notifier once. It reuses the shared notification setup
    // and receives positions from this same live GPS stream.
    unawaited(_startNearbyReportNotifications());
  }

  /// Verifies with backend or Firebase whether account is deactivated
  Future<void> _verifyUserAccountActiveStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Force refresh user token to pick up real-time account suspension/disable states
      await user.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      if ((e.code == 'user-disabled' || e.code == 'user-not-found') && mounted && !_isAccountDisabledChecked) {
        _isAccountDisabledChecked = true;
        _liveAccountSyncTimer?.cancel();
        DisableModal.show(context);
      }
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final bool isDarkMode = AdaptiveTheme.of(context).mode.isDark;
    if (_lastMapDarkMode == isDarkMode) return;

    _lastMapDarkMode = isDarkMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateMapStyle(isDarkMode);
      }
    });
  }

  Future<void> _updateMapStyle(bool isDarkMode) async {
    final controller = mapController;
    if (controller == null) return;

    try {
      _styleLoaded = false;
      _isPulseLayerRendered = false;
      _userLocationSymbol = null;
      _incidentLayersInitialized = false;
      _incidentFadeOpacity = 1.0;

      await controller.setStyle(
        isDarkMode ? _darkMapStyle : _lightMapStyle,
      );
    } catch (e) {
      debugPrint('MapLibre theme style update error: $e');
    }
  }

  void _onSelectedReportForMapChanged() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _consumeSelectedReportForMap();
    });
  }

  @override
  void dispose() {
    QuickReportBridge.unregisterTrigger(_handleReportIncident);

    LiveDetailsReports.selectedReportForMapNotifier.removeListener(
      _onSelectedReportForMapChanged,
    );

    _pulseController?.stop();
    _pulseController?.dispose();
    _incidentTransitionController?.stop();
    _incidentTransitionController?.dispose();
    _liveAccountSyncTimer?.cancel();
    _positionSubscription?.cancel();
    unawaited(nearbyReportsNotifService.stopListening());
    unawaited(insideReportsNotifService.stopListening());
    unawaited(userExitedReportNotifsService.stopListening());
    _locationAnimationTimer?.cancel();
    _cameraFollowScheduleTimer?.cancel();
    _pendingCameraFollowLocation = null;
    _locationAnimationToken++;
    _notificationsTabVisibility.dispose();
    super.dispose();
  }

  void _setupSocketDeactivationListener() {
    // Ensure socket is initialized
    SocketService.initSocket().then((_) {
      SocketService.listenForAccountDeactivation((data) async {
        if (!mounted || _isDeactivationModalShowing) return;

        // Extract current user ID
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final targetUid = data?['uid'] ?? data?['userId'] ?? data?['citizenId'];

        // If target matches current user (or if payload applies to active socket user)
        if (currentUid != null && (targetUid == null || targetUid == currentUid)) {
          _isDeactivationModalShowing = true;

          // 1. Show the non-dismissible dialog on top of Homepage
          await DisableModal.show(context);

          // 2. DisableModal's "Back to Login" handles disconnect & FirebaseAuth.signOut()
          _isDeactivationModalShowing = false;
        }
      });
    });
  }

  /// Listens for incoming real-time incident notifications and seamlessly triggers
  /// native pop-in transition, geometry rendering, and camera focus.
  void _setupIncidentNotificationSocketListener() {
    SocketService.initSocket().then((_) {
      final socket = SocketService.socket;
      if (socket == null) return;

      Future<void> handleIncomingIncident(dynamic data) async {
        if (!mounted || data == null) return;

        Map<String, dynamic>? newReport;
        if (data is Map<String, dynamic>) {
          if (data.containsKey('data') && data['data'] is Map<String, dynamic>) {
            newReport = Map<String, dynamic>.from(data['data']);
          } else if (data.containsKey('report') && data['report'] is Map<String, dynamic>) {
            newReport = Map<String, dynamic>.from(data['report']);
          } else {
            newReport = Map<String, dynamic>.from(data);
          }
        }

        if (newReport == null) return;

        // Verify report status is approved or verified
        final String status = (newReport['status'] ?? newReport['verificationStatus'] ?? 'approved').toString().toLowerCase();
        if (status != 'approved' && status != 'verified') return;

        final String reportId = (newReport['_id'] ?? newReport['id'] ?? '').toString();

        setState(() {
          // Check if report already exists and replace or append
          int existingIndex = -1;
          if (reportId.isNotEmpty) {
            existingIndex = _incidentReports.indexWhere((r) => (r['_id'] ?? r['id'] ?? '').toString() == reportId);
          }

          if (existingIndex != -1) {
            _incidentReports[existingIndex] = newReport;
          } else {
            _incidentReports.insert(0, newReport);
          }
        });

        // Keep nearby notification geometry synchronized with live report updates.
        _syncIncidentNotificationReports();

        // 1. Render updated geometries with a native map-layer fade/pop-in.
        // Awaiting the source update ensures the transition starts after the
        // new marker, radius, and polyline have been placed on the map.
        await _renderIncidentGeometries(animate: true);

        // Intentionally do not select the incoming report or open the report
        // information card. New approvals only pop into the map; the existing
        // tap interaction still opens the card when the user selects a marker.
      }

      socket.off('new_report');
      socket.off('incident_approved');
      socket.off('report_updated');
      socket.off('report_verified');
      socket.off('new_approved_admin_report');
      socket.off('admin_report_approved');
      socket.off('admin_report_updated');

      socket.on('new_report', handleIncomingIncident);
      socket.on('incident_approved', handleIncomingIncident);
      socket.on('report_updated', handleIncomingIncident);
      socket.on('report_verified', handleIncomingIncident);
      socket.on('new_approved_admin_report', handleIncomingIncident);
      socket.on('admin_report_approved', handleIncomingIncident);
      socket.on('admin_report_updated', handleIncomingIncident);
    });
  }

  void _initLiveDeactivationListener() {
    SocketService.initSocket().then((_) {
      SocketService.listenForAccountDeactivation((data) async {
        debugPrint('⚡ Socket deactivation triggered: $data');

        if (!mounted || _isDeactivationModalShowing) return;

        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final targetUid = data?['uid'] ?? data?['userId'] ?? data?['citizenId'] ?? data?['id'];

        // Match target user or fallback to current socket context
        if (currentUid != null && (targetUid == null || targetUid == currentUid)) {
          _isDeactivationModalShowing = true;

          // Show dialog over the root navigator
          await showDialog(
            context: context,
            barrierDismissible: false,
            useRootNavigator: true,
            builder: (dialogContext) => const PopScope(
              canPop: false,
              child: DisableModal(isDialog: true),
            ),
          );

          if (mounted) {
            _isDeactivationModalShowing = false;
          }
        }
      });
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    mapController = controller;
    _symbolManager = controller.symbolManager;
    _circleManager = controller.circleManager;
    _lineManager = controller.lineManager;
    QuickReportBridge.markMapReady(); // 🎯 map is now actually usable
  }

  Future<void> _onSearchPlaceSelected(
      LatLng coordinates,
      String displayName,
      ) async {
    final controller = mapController;
    if (controller == null) {
      debugPrint('Cannot center search result: map controller is not ready.');
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(coordinates, 16.0),
        duration: const Duration(milliseconds: 850),
      );
    } catch (error) {
      debugPrint('Could not center map on "$displayName": $error');
    }
  }

  String _reportIdentity(dynamic report) {
    if (report is! Map) return '';
    return (report['_id'] ??
        report['id'] ??
        report['reportId'] ??
        report['reportID'] ??
        report['verifiedReportId'] ??
        report['verifiedreportID'] ??
        '')
        .toString();
  }

  Future<void> _consumeSelectedReportForMap() async {
    final selected = LiveDetailsReports.selectedReportForMapNotifier.value ??
        LiveDetailsReports.selectedReportForMap;
    if (!mounted || selected == null) return;

    // ReportsPage can leave Homepage's internal tab index on the ReportsPage
    // slot. Return to the map slot before displaying the selected report,
    // while keeping this Homepage and its MapLibre instance mounted.
    if (_currentIndex != kNavPageHome) {
      setState(() => _currentIndex = kNavPageHome);
    }

    // Wait until the homepage map and its approved-report source are ready.
    if (mapController == null || !_styleLoaded || _incidentReports.isEmpty) return;

    final selectedId = _reportIdentity(selected);
    final reportIndex = _incidentReports.indexWhere(
          (report) => selectedId.isNotEmpty && _reportIdentity(report) == selectedId,
    );

    if (reportIndex < 0) return;

    final featureId = 'incident_feat_$reportIndex';
    final report = _incidentReports[reportIndex];
    LiveDetailsReports.selectedReportForMap = null;
    LiveDetailsReports.selectedReportForMapNotifier.value = null;

    await _triggerIncidentSelection(
      report,
      featureId,
      forceCenterCamera: true,
    );
  }

  void _processFeatureIdSelection(String featureId) {

    if (featureId.startsWith('incident_feat_')) {
      final String indexStr = featureId.replaceFirst('incident_feat_', '');
      final int? reportIdx = int.tryParse(indexStr);

      if (reportIdx != null && reportIdx >= 0 && reportIdx < _incidentReports.length) {
        _triggerIncidentSelection(_incidentReports[reportIdx], featureId);
      }
    }
  }

  void _showOverlappingIncidentsResolver(BuildContext context, List<dynamic> features) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.layers_outlined, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Text(
                    "${features.length} Incidents in this Spot",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Multiple emergency updates overlap here. Choose a report:",
                style: TextStyle(color: Color(0xFF475569), fontSize: 13),
              ),
              const Divider(height: 24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: features.length,
                  itemBuilder: (context, index) {
                    final featureId = features[index]['id'] ?? '';
                    final String indexStr = featureId.replaceFirst('incident_feat_', '');
                    final int? reportIdx = int.tryParse(indexStr);

                    if (reportIdx == null || reportIdx < 0 || reportIdx >= _incidentReports.length) {
                      return const SizedBox.shrink();
                    }

                    final report = _incidentReports[reportIdx];
                    final String title = report['title'] ?? report['type'] ?? 'Emergency Report';
                    final String subtitle = report['description'] ?? 'Tap to review incident particulars.';

                    return Card(
                      elevation: 0,
                      color: const Color(0xFFF8FAFC),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black45),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _processFeatureIdSelection(featureId);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMapLegendsModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss Legends",
      barrierColor: Colors.black.withOpacity(0.15),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ResponsiveLayoutBuilder(
          builder: (context, screenType, isCompact) {
            return Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + (isCompact ? 60 : 76),
                  left: isCompact ? 12 : 16,
                  right: isCompact ? 12 : 16,
                ),
                child: const MapLegendsModal(),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  void _onStyleLoaded() async {
    _styleLoaded = false;
    _isPulseLayerRendered = false;

    _symbolManager?.setIconAllowOverlap(true);
    _symbolManager?.setIconIgnorePlacement(true);

    try {
      final Uint8List userDotBytes = await _generateUserLocationDot();
      await mapController?.addImage('user-blue-dot', userDotBytes);
    } catch (e) {
      debugPrint("⚠️ Blue dot texture generation error: $e");
    }

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
        await mapController?.addImage(entry.key, resizedList);
      } catch (e) {
        debugPrint("⚠️ Failed to load asset '${entry.value}': $e");
      }
    }

    try {
      await mapController?.addGeoJsonSource("user-accuracy-source", {"type": "FeatureCollection", "features": []});
      await mapController?.addFillLayer("user-accuracy-source", "user-accuracy-fill-layer", const FillLayerProperties(fillColor: '#4285F4', fillOpacity: 0.18));
      await mapController?.addLineLayer("user-accuracy-source", "user-accuracy-line-layer", const LineLayerProperties(lineColor: '#4285F4', lineWidth: 2.0, lineOpacity: 0.60));

      await mapController?.addGeoJsonSource("incident-circles-source", {"type": "FeatureCollection", "features": []});
      await mapController?.addFillLayer("incident-circles-source", "incident-circles-fill-layer", const FillLayerProperties(
        fillColor: ["get", "color"],
        fillOpacity: ["*", ["coalesce", ["get", "renderOpacity"], 1.0], 0.20],
      ));
      await mapController?.addLineLayer("incident-circles-source", "incident-circles-line-layer", const LineLayerProperties(
        lineColor: ["get", "color"],
        lineWidth: 3.0,
        lineOpacity: ["*", ["coalesce", ["get", "renderOpacity"], 1.0], 0.80],
      ));
    } catch (e) {
      debugPrint("Error initializing accuracy layer geometries: $e");
    }

    if (mounted) {
      setState(() => _styleLoaded = true);
    }

    await _initializeUserLocation();
    await _fetchApprovedIncidents();
    await _consumeSelectedReportForMap();

    if (mounted) {

      await _checkAndPromptNotificationPermission();
    }
  }

  Future<void> _checkAndPromptNotificationPermission() async {
    final status = await Permission.notification.status;

    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();

      if (newStatus.isDenied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Notifications disabled. Real-time disaster & emergency alerts won't be pushed.",
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: "SETTINGS",
              textColor: const Color(0xFF38BDF8),
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _startNearbyReportNotifications() async {
    try {
      // Start both services sequentially so NotificationService is initialized
      // only once and both services use the same live report dataset.
      await nearbyReportsNotifService.startListening();
      await insideReportsNotifService.startListening(
        onEntered: _handleEnteredInsideReport,
      );
      await userExitedReportNotifsService.startListening(
        onExited: _handleExitedIncident,
      );
      _syncIncidentNotificationReports();

      final currentPosition = _currentPosition;
      if (currentPosition != null) {
        nearbyReportsNotifService.evaluateUserPosition(currentPosition);
        insideReportsNotifService.evaluateUserPosition(currentPosition);
        userExitedReportNotifsService.evaluateUserPosition(currentPosition);
      }
    } catch (error, stackTrace) {
      debugPrint('❌ Incident notification startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _syncIncidentNotificationReports() {
    final reports = _incidentReports.whereType<Map<String, dynamic>>();
    nearbyReportsNotifService.updateReports(reports);
    insideReportsNotifService.updateReports(reports);
    userExitedReportNotifsService.updateReports(reports);
  }

  Future<void> _handleEnteredInsideReport(
      Map<String, dynamic> report,
      double distanceMeters,
      Position userPosition,
      ) async {
    if (!mounted || _isAccountDisabledChecked) return;

    final reportId = (report['id'] ??
        report['_id'] ??
        report['reportID'] ??
        report['reportId'] ??
        '')
        .toString();

    if (_isInsideHazardCardVisible &&
        (_insideHazardReport?['id'] ??
            _insideHazardReport?['_id'] ??
            _insideHazardReport?['reportID'] ??
            _insideHazardReport?['reportId'] ??
            '')
            .toString() ==
            reportId) {
      return;
    }

    final LatLng userLocation = LatLng(
      userPosition.latitude,
      userPosition.longitude,
    );
    final double accuracy =
    userPosition.accuracy > 0 ? userPosition.accuracy : 30.0;

    // Guarantee that the exit service records the same GPS fix that caused
    // the inside event, even if its startup raced the first location update.
    userExitedReportNotifsService.evaluateUserPosition(userPosition);

    // Display the card immediately, then synchronize the marker and camera to
    // this exact GPS coordinate. The service has already gated this event to
    // one entry per report, so repeated GPS fixes cannot reopen the card.
    setState(() {
      _insideHazardReport = Map<String, dynamic>.from(report);
      _isInsideHazardCardVisible = true;
      _isInfoCardVisible = false;
    });

    await _snapMarkerAndRecenterCamera(userLocation, accuracy);
    if (!mounted || mapController == null) return;

    await mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(userLocation, 16.5),
      duration: const Duration(milliseconds: 900),
    );

    debugPrint(
      '🚨 Inside hazard card shown for $reportId '
          '(${distanceMeters.round()}m from boundary).',
    );
  }

  Future<void> _handleExitedIncident(
      Map<String, dynamic> report,
      double distanceMeters,
      Position userPosition,
      ) async {
    final exitedId = (report['id'] ??
        report['_id'] ??
        report['reportID'] ??
        report['reportId'] ??
        '')
        .toString();

    // Re-arm this report's inside notification gate. This is per-report, so
    // other active incident cards are not affected.
    insideReportsNotifService.clearReportInsideState(exitedId);

    if (!mounted || !_isInsideHazardCardVisible) return;
    final visibleId = (_insideHazardReport?['id'] ??
        _insideHazardReport?['_id'] ??
        _insideHazardReport?['reportID'] ??
        _insideHazardReport?['reportId'] ??
        '')
        .toString();

    // Only close the card belonging to the report that was exited. A visible
    // card for another incident must not disappear unexpectedly.
    if (exitedId.isNotEmpty && visibleId.isNotEmpty && exitedId != visibleId) {
      return;
    }

    await _dismissInsideHazardCardAnimated();
    debugPrint(
      '🚪 Inside hazard card closed after exiting $exitedId '
          '(${distanceMeters.round()}m outside boundary).',
    );
  }

  Future<void> _dismissInsideHazardCardAnimated() async {
    if (!mounted || _isInsideCardDismissAnimating) return;
    _isInsideCardDismissAnimating = true;
    setState(() => _isInsideHazardCardVisible = false);
    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (mounted) {
      setState(() {
        _insideHazardReport = null;
        _isInsideCardDismissAnimating = false;
      });
    }
  }

  void _dismissInsideHazardCard() {
    unawaited(_dismissInsideHazardCardAnimated());
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;

    nearbyReportsNotifService.evaluateUserPosition(position);
    insideReportsNotifService.evaluateUserPosition(position);
    // Keep exit detection synchronized with every live GPS fix after entry.
    userExitedReportNotifsService.evaluateUserPosition(position);

    final LatLng nextLocation = LatLng(position.latitude, position.longitude);
    final double nextAccuracy = position.accuracy > 0 ? position.accuracy : 30.0;

    _currentPosition = position;
    _targetUserLocation = nextLocation;
    _targetAccuracy = nextAccuracy;

    final LatLng? currentLocation = _displayedUserLocation;
    if (currentLocation == null || mapController == null || !_styleLoaded) {
      _displayedUserLocation = nextLocation;
      _displayedAccuracy = nextAccuracy;
      _queueUserLocationRender(nextLocation, nextAccuracy);
      return;
    }

    _animateUserLocation(
      currentLocation,
      nextLocation,
      _displayedAccuracy,
      nextAccuracy,
    );
  }

  void _animateUserLocation(
      LatLng from,
      LatLng to,
      double fromAccuracy,
      double toAccuracy,
      ) {
    _locationAnimationToken++;
    final int token = _locationAnimationToken;
    _locationAnimationTimer?.cancel();

    final double distanceMeters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final int durationMs = distanceMeters < 3
        ? 350
        : (distanceMeters * 45).clamp(450, 1400).round();
    final DateTime startedAt = DateTime.now();

    _locationAnimationTimer = Timer.periodic(
      const Duration(milliseconds: 33),
          (timer) {
        if (!mounted || token != _locationAnimationToken) {
          timer.cancel();
          return;
        }

        final double elapsedMs =
            DateTime.now().difference(startedAt).inMicroseconds / 1000.0;
        final double linearT = (elapsedMs / durationMs).clamp(0.0, 1.0);
        final double t = Curves.easeOutCubic.transform(linearT);

        final LatLng interpolated = LatLng(
          from.latitude + ((to.latitude - from.latitude) * t),
          from.longitude + ((to.longitude - from.longitude) * t),
        );
        final double interpolatedAccuracy =
            fromAccuracy + ((toAccuracy - fromAccuracy) * t);

        _displayedUserLocation = interpolated;
        _displayedAccuracy = interpolatedAccuracy;
        _queueUserLocationRender(interpolated, interpolatedAccuracy);

        if (linearT >= 1.0) {
          timer.cancel();
          _displayedUserLocation = to;
          _displayedAccuracy = toAccuracy;
          _queueUserLocationRender(to, toAccuracy);
        }
      },
    );
  }

  void _queueUserLocationRender(LatLng location, double accuracy) {
    _pendingUserLocation = location;
    _pendingUserAccuracy = accuracy;
    _scheduleCameraFollow(location);
    if (_locationRenderInProgress) return;
    unawaited(_flushUserLocationRenderQueue());
  }

  // Keeps the map center synchronized with the same interpolated location used
  // to render the blue user pinpoint. Throttling prevents camera-command buildup
  // when the GPS stream produces frequent fixes or the user is moving quickly.
  void _scheduleCameraFollow(LatLng location) {
    _pendingCameraFollowLocation = location;
    if (_cameraFollowScheduleTimer?.isActive ?? false) return;

    _cameraFollowScheduleTimer = Timer(
      const Duration(milliseconds: 70),
          () {
        _cameraFollowScheduleTimer = null;
        unawaited(_flushCameraFollow());
      },
    );
  }

  Future<void> _flushCameraFollow() async {
    if (_cameraFollowInProgress) return;
    _cameraFollowInProgress = true;

    try {
      while (mounted && _pendingCameraFollowLocation != null) {
        final controller = mapController;
        if (controller == null || !_styleLoaded || _isAccountDisabledChecked) {
          _pendingCameraFollowLocation = null;
          break;
        }

        final location = _pendingCameraFollowLocation!;
        _pendingCameraFollowLocation = null;

        try {
          await controller.animateCamera(
            CameraUpdate.newLatLng(location),
            duration: const Duration(milliseconds: 140),
          );
        } catch (error) {
          debugPrint('Camera follow update skipped: $error');
        }
      }
    } finally {
      _cameraFollowInProgress = false;
      if (mounted && _pendingCameraFollowLocation != null) {
        unawaited(_flushCameraFollow());
      }
    }
  }

  Future<void> _flushUserLocationRenderQueue() async {
    if (_locationRenderInProgress) return;
    _locationRenderInProgress = true;
    try {
      while (mounted && _pendingUserLocation != null) {
        final LatLng location = _pendingUserLocation!;
        final double accuracy = _pendingUserAccuracy;
        _pendingUserLocation = null;
        await _renderUserLocationLayer(location, accuracy);
      }
    } finally {
      _locationRenderInProgress = false;
      if (mounted && _pendingUserLocation != null) {
        unawaited(_flushUserLocationRenderQueue());
      }
    }
  }

  Future<void> _renderUserLocationLayer(
      LatLng location,
      double accuracy,
      ) async {
    if (!mounted ||
        mapController == null ||
        !_styleLoaded ||
        _isAccountDisabledChecked) {
      return;
    }

    const int steps = 64;
    final List<List<double>> outerRing = <List<double>>[];
    const double earthRadius = 6378137.0;
    final double latRad = location.latitude * (math.pi / 180.0);
    final double radius = accuracy > 0 ? accuracy : 30.0;

    for (int i = 0; i <= steps; i++) {
      final double theta = (i * 2 * math.pi) / steps;
      final double dLat = (radius * math.cos(theta)) / earthRadius;
      final double dLng =
          (radius * math.sin(theta)) / (earthRadius * math.cos(latRad));
      final double pLat = location.latitude + (dLat * (180.0 / math.pi));
      final double pLng = location.longitude + (dLng * (180.0 / math.pi));
      outerRing.add(<double>[pLng, pLat]);
    }

    final Map<String, dynamic> accuracyGeoJson = <String, dynamic>{
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'Feature',
          'geometry': <String, dynamic>{
            'type': 'Polygon',
            'coordinates': <List<List<double>>>[outerRing],
          },
          'properties': <String, dynamic>{},
        },
      ],
    };

    try {
      final controller = mapController;
      if (controller == null || !mounted || _isAccountDisabledChecked) return;

      await controller.setGeoJsonSource('user-accuracy-source', accuracyGeoJson);

      if (_userLocationSymbol == null) {
        _userLocationSymbol = await controller.addSymbol(
          SymbolOptions(
            geometry: location,
            iconImage: 'user-blue-dot',
            iconSize: 1.5,
            iconAnchor: 'center',
          ),
        );
      } else {
        await controller.updateSymbol(
          _userLocationSymbol!,
          SymbolOptions(geometry: location),
        );
      }
    } on MissingPluginException catch (e) {
      debugPrint('MapLibre channel detached safely: $e');
    } catch (e) {
      debugPrint('Error updating user tracking layers: $e');
    }
  }

  Future<Uint8List> _resizeMarkerAsset(Uint8List assetBytes, int targetWidth) async {
    final ui.Codec codec = await ui.instantiateImageCodec(assetBytes, targetWidth: targetWidth);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ByteData? byteData = await frameInfo.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _generateUserLocationDot() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Paint antiAliasPaint = Paint()..isAntiAlias = true..filterQuality = ui.FilterQuality.high;

    antiAliasPaint.color = Colors.white;
    canvas.drawCircle(const Offset(30, 30), 16, antiAliasPaint);
    antiAliasPaint.color = const Color(0xFF2196F3);
    canvas.drawCircle(const Offset(30, 30), 12, antiAliasPaint);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(60, 60);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _fetchApprovedIncidents() async {
    // If account is disabled or widget unmounted, don't attempt network or map sync
    if (!mounted || _isAccountDisabledChecked) return;

    try {
      if (ApiService.baseUrl == null) { await ApiService.initBackend(); }
      String targetBase = ApiService.baseUrl ?? 'http://10.0.2.2:3000/api';
      final String requestUrl = targetBase.endsWith('/api')
          ? '$targetBase/reports?view=approved'
          : '$targetBase/api/reports?view=approved';

      final response = await http.get(Uri.parse(requestUrl)).timeout(const Duration(seconds: 5));
      final resData = json.decode(response.body);

      // --- LIVE DISABLE & DEACTIVATED ACCOUNT CHECK ---
      bool isAccountDisabled = false;

      if (response.statusCode == 403 || response.statusCode == 401) {
        if (resData is Map) {
          final msg = resData['message']?.toString().toLowerCase() ?? '';
          if (msg.contains('deactivated') || msg.contains('disabled') || resData['isDisable'] == true) {
            isAccountDisabled = true;
          }
        }
      } else if (resData is Map && (resData['isDisable'] == true || resData['userDisabled'] == true)) {
        isAccountDisabled = true;
      }

      if (isAccountDisabled) {
        if (mounted && !_isAccountDisabledChecked) {
          setState(() {
            _isAccountDisabledChecked = true;
          });
          _liveAccountSyncTimer?.cancel(); // Immediately stop background timer
          DisableModal.show(context);
        }
        return; // Stop execution here - do NOT proceed to _renderIncidentGeometries()
      }
      // ------------------------------------------------

      if (response.statusCode == 200 && mounted && !_isAccountDisabledChecked) {
        setState(() {
          if (resData is Map && resData.containsKey('data')) {
            _incidentReports = List<Map<String, dynamic>>.from(resData['data']);
          } else if (resData is List) {
            _incidentReports = List<Map<String, dynamic>>.from(resData);
          }
        });

        _syncIncidentNotificationReports();
        _renderIncidentGeometries();
      }
    } catch (e) {
      debugPrint("Incident Network Sync Error: $e");
      if (mounted && !_isAccountDisabledChecked) {
        _renderIncidentGeometries();
      }
    }
  }

  Future<void> _applyIncidentTransitionOpacity(double opacity) async {
    if (!mounted || mapController == null || !_styleLoaded || _isAccountDisabledChecked) return;

    final value = opacity.clamp(0.0, 1.0).toDouble();
    try {
      // Animate only source data opacity. Do not replace layer properties:
      // iconImage, iconSize, colors, radius expressions, and line styling must
      // remain exactly as configured by the map renderer.
      final markerFeatures = List<dynamic>.from(
        _cachedGeoJsonCollection['features'] ?? const [],
      );
      for (final feature in markerFeatures) {
        if (feature is Map && feature['properties'] is Map) {
          feature['properties']['renderOpacity'] = value;
        }
      }

      final circleFeatures = List<dynamic>.from(
        _cachedCircleGeoJsonCollection['features'] ?? const [],
      );
      for (final feature in circleFeatures) {
        if (feature is Map && feature['properties'] is Map) {
          feature['properties']['renderOpacity'] = value;
        }
      }

      await mapController!.setGeoJsonSource(
        'incident-symbols-source',
        {'type': 'FeatureCollection', 'features': markerFeatures},
      );
      await mapController!.setGeoJsonSource(
        'incident-circles-source',
        {'type': 'FeatureCollection', 'features': circleFeatures},
      );

      for (final line in List<Line>.from(_incidentLines)) {
        try {
          await mapController!.updateLine(
            line,
            LineOptions(lineOpacity: 0.85 * value),
          );
        } catch (_) {
          // A line can disappear during a style reload; the next render will
          // recreate it without interrupting the rest of the transition.
        }
      }
    } on MissingPluginException catch (e) {
      debugPrint('MapLibre transition channel disconnected gracefully: $e');
    } on PlatformException catch (e) {
      if (e.code != 'STYLE_NOT_READY') {
        debugPrint('MapLibre incident transition update error: $e');
      }
    } catch (_) {}
  }

  Future<void> _animateIncidentTransition() async {
    final controller = _incidentTransitionController;
    if (controller == null || !mounted) return;

    controller.stop();
    _incidentFadeOpacity = 0.0;
    await _applyIncidentTransitionOpacity(0.0);
    if (!mounted) return;

    await controller.forward(from: 0.0);
    _incidentFadeOpacity = 1.0;
  }

  Future<void> _renderIncidentGeometries({bool animate = false}) async {
    if (!mounted || mapController == null || !_styleLoaded || _isAccountDisabledChecked) return;

    for (var line in _incidentLines) {
      try { await mapController?.removeLine(line); } catch (_) {}
    }
    _incidentLines.clear();

    // Do not remove and recreate the incident source/layers on every poll or
    // socket event. MapLibre can update the source in place, which prevents the
    // marker/radius/polyline flash and the sudden appearance effect.
    if (!_incidentLayersInitialized) {
      _isPulseLayerRendered = false;
    }

    List<Map<String, dynamic>> pendingLines = [];
    List<Map<String, dynamic>> geoJsonFeatures = [];
    List<Map<String, dynamic>> circleGeoJsonFeatures = [];

    for (var i = 0; i < _incidentReports.length; i++) {
      final report = _incidentReports[i];
      final radiusData = report['radius'];
      final polylineData = report['polyline'];
      final routeCoords = report['routeCoords'] as List?;
      final locationData = report['location'];

      // React admin-created reports usually provide incidentType instead of
      // selectedMarkerIcon. Resolve both formats before rendering the map.
      final String iconFile = _resolveIncidentIcon(report);
      final String hexColor = _iconColorMap[iconFile] ?? '#f97316';

      double lat = radiusData?['centerLat']?.toDouble() ?? locationData?['latitude']?.toDouble() ?? 14.75;
      double lng = radiusData?['centerLng']?.toDouble() ?? locationData?['longitude']?.toDouble() ?? 120.95;
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
        circleGeoJsonFeatures.add(_createGeoJsonCirclePolygon(pinTarget, radiusMeters, hexColor, i));
      }

      String featureStringId = 'incident_feat_$i';
      String pulseType = 'others';
      if (iconFile == 'fireicon.png') pulseType = 'fire';
      else if (iconFile == 'floodicon.png') pulseType = 'flood';
      else if (iconFile == 'accicon.png' || iconFile == 'caricon.png') pulseType = 'accident';

      geoJsonFeatures.add({
        'type': 'Feature',
        'id': featureStringId,
        'geometry': {'type': 'Point', 'coordinates': [pinTarget.longitude, pinTarget.latitude]},
        'properties': {
          'icon': iconFile,
          'pulseType': pulseType,
          'isSelected': featureStringId == _selectedFeatureId,
          'renderOpacity': 1.0,
        }
      });
    }

    // Safety check before updating sources
    if (!mounted || _isAccountDisabledChecked) return;

    try {
      final initialOpacity = animate ? 0.0 : 1.0;
      for (final feature in circleGeoJsonFeatures) {
        feature['properties']['renderOpacity'] = initialOpacity;
      }
      _cachedCircleGeoJsonCollection = {'type': 'FeatureCollection', 'features': circleGeoJsonFeatures};
      await mapController?.setGeoJsonSource("incident-circles-source", _cachedCircleGeoJsonCollection);

      for (var lineData in pendingLines) {
        if (!mounted || _isAccountDisabledChecked) return;
        try {
          final addedLine = await mapController?.addLine(
            LineOptions(
              geometry: lineData['geometry'] as List<LatLng>,
              lineColor: lineData['color'] as String,
              lineWidth: 4.5,
              lineOpacity: animate ? 0.0 : 0.85,
              lineJoin: "round",
            ),
          );
          if (addedLine != null) _incidentLines.add(addedLine);
        } catch (e) {
          debugPrint("Error rendering polyline: $e");
        }
      }

      if (mounted && !_isAccountDisabledChecked) {
        for (final feature in geoJsonFeatures) {
          feature['properties']['renderOpacity'] = initialOpacity;
        }
        _cachedGeoJsonCollection = {'type': 'FeatureCollection', 'features': geoJsonFeatures};

        if (!_incidentLayersInitialized) {
          await mapController?.addGeoJsonSource("incident-symbols-source", _cachedGeoJsonCollection);

          await mapController?.addCircleLayer(
            "incident-symbols-source",
            "incident-pulse-layer",
            const CircleLayerProperties(
              circleColor: ["match", ["get", "pulseType"], "fire", "#ef4444", "flood", "#3b82f6", "accident", "#eab308", "others", "#f97316", "#f97316"],
              circlePitchAlignment: "map",
              circleStrokeWidth: 0.0,
            ),
          );

          _isPulseLayerRendered = true;

          await mapController?.addSymbolLayer(
            "incident-symbols-source",
            "incident-symbols-layer",
            SymbolLayerProperties(
              iconImage: ["get", "icon"],
              iconOpacity: ["coalesce", ["get", "renderOpacity"], 1.0],
              // Keep the icon size constant after selection so repeated taps
              // never make the marker appear smaller or change its hit area.
              iconSize: 1.0,
              iconAnchor: "bottom",
              iconAllowOverlap: true,
              iconIgnorePlacement: true,
            ),
          );
          _incidentLayersInitialized = true;
        } else {
          await mapController?.setGeoJsonSource(
            "incident-symbols-source",
            _cachedGeoJsonCollection,
          );
        }

        if (animate && geoJsonFeatures.isNotEmpty) {
          await _animateIncidentTransition();
        }
      }
    } on MissingPluginException catch (e) {
      debugPrint("MapLibre platform channel disconnected gracefully: $e");
    } catch (e) {
      debugPrint("Error updating incident geometries: $e");
    }
  }

  Future<void> _triggerIncidentSelection(
      dynamic report,
      String? featureId, {
        bool forceCenterCamera = false,
      }) async {
    final shouldCenterCamera = forceCenterCamera ||
        (featureId != null && featureId != _lastCameraCenteredFeatureId);

    setState(() {
      _activeSelectedReport = report;
      _isInfoCardVisible = true;
      _selectedFeatureId = featureId;
    });

    if (featureId != null && mapController != null) {
      final features = List<dynamic>.from(
        _cachedGeoJsonCollection['features'] ?? const [],
      );
      for (final feature in features) {
        if (feature is Map && feature['properties'] is Map) {
          feature['properties']['isSelected'] = feature['id'] == featureId;
        }
      }
      await mapController!.setGeoJsonSource(
        "incident-symbols-source",
        {"type": "FeatureCollection", "features": features},
      );
    }

    // Center only once for each newly selected marker. Repeated taps on the
    // same marker still open/keep the card but do not restart the camera.
    if (shouldCenterCamera && mapController != null) {
      final radiusData = report['radius'];
      final locationData = report['location'];
      final lat = radiusData?['centerLat']?.toDouble() ??
          locationData?['latitude']?.toDouble() ?? 14.75;
      final lng = radiusData?['centerLng']?.toDouble() ??
          locationData?['longitude']?.toDouble() ?? 120.95;

      _lastCameraCenteredFeatureId = featureId;
      await CenterandFixTheViewIncidents.focusCameraOnIncident(

        controller: mapController!,
        latitude: lat,
        longitude: lng,
      );
    }
  }

  void _clearIncidentSelection() async {
    setState(() {
      _isInfoCardVisible = false;
      _activeSelectedReport = null;
      _selectedFeatureId = null;
      _lastCameraCenteredFeatureId = null;
    });

    if (mapController != null && _cachedGeoJsonCollection['features'] != null) {
      List<dynamic> features = List.from(_cachedGeoJsonCollection['features']);
      for (var f in features) { f['properties']['isSelected'] = false; }
      await mapController!.setGeoJsonSource("incident-symbols-source", {"type": "FeatureCollection", "features": features});
    }
  }

  bool _isCoordinateInsideCircle(LatLng point, LatLng center, double radiusMeters) {
    return Geolocator.distanceBetween(point.latitude, point.longitude, center.latitude, center.longitude) <= radiusMeters;
  }

  Future<void> _snapMarkerAndRecenterCamera(
      LatLng location,
      double accuracy,
      ) async {
    // Cancel any in-progress marker interpolation first. Otherwise the marker
    // can continue moving while the camera is animating to its old coordinate.
    _locationAnimationToken++;
    _locationAnimationTimer?.cancel();

    _displayedUserLocation = location;
    _displayedAccuracy = accuracy;
    _targetUserLocation = location;
    _targetAccuracy = accuracy;
    _pendingUserLocation = location;
    _pendingUserAccuracy = accuracy;

    if (!_locationRenderInProgress) {
      await _flushUserLocationRenderQueue();
    } else {
      while (mounted && _locationRenderInProgress) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (mounted && _pendingUserLocation != null) {
        await _flushUserLocationRenderQueue();
      }
    }
  }

  Future<void> _initializeUserLocation() async {
    if (_isRecentering || mapController == null || !mounted) return;
    setState(() => _isRecentering = true);

    try {
      Position? position = _currentPosition;
      position ??= await CenterandFixTheViewIncidents.getSafeUserPositionFallback();
      if (!mounted || mapController == null) return;

      _currentPosition = position;
      final LatLng targetLocation = LatLng(position.latitude, position.longitude);
      final double targetAccuracy = position.accuracy > 0 ? position.accuracy : 30.0;

      // Snap the displayed marker first, then animate the camera to that exact
      // same coordinate. This guarantees the circle is at the screen center.
      await _snapMarkerAndRecenterCamera(targetLocation, targetAccuracy);

      if (!mounted || mapController == null) return;
      await mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(targetLocation, 16.0),
        duration: const Duration(milliseconds: 900),
      );
    } catch (e) {
      debugPrint('Critical Geo Exception: $e');
    } finally {
      if (mounted) setState(() => _isRecentering = false);
    }
  }

  Future<void> _handleReportIncident() async {
    if (_isLoadingLocation) return;
    setState(() => _isLoadingLocation = true);

    try {
      var status = await Permission.location.status;
      if (status.isDenied || status.isRestricted) { status = await Permission.location.request(); }
      if (!status.isGranted) return;

      LatLng? targetLatLng;
      if (_currentPosition != null) {
        targetLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      } else {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 4));
        targetLatLng = LatLng(position.latitude, position.longitude);
      }

      if (mapController != null && targetLatLng != null) {
        await AnimatedMapMove.trigger(mapController: mapController!, targetLocation: targetLatLng, zoom: 18.0, duration: const Duration(milliseconds: 1200));
        if (mounted) _showReportModal();
      }
    } catch (e) {
      debugPrint("Location error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _onItemTapped(int index) {
    if (index == kNavPageAddIncident) {
      _handleReportIncident();
    } else {
      setState(() {
        _currentIndex = index;
        _notificationsTabVisibility.value = index == kNavPageNotifications;
        if (index != kNavPageHome) {
          _isInfoCardVisible = false;
          _clearIncidentSelection();
        }
      });
    }
  }

  void _showReportModal() {
    double lat = _currentPosition?.latitude ?? 14.7925;
    double lon = _currentPosition?.longitude ?? 120.8970;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => IsThisYourLocation(latitude: lat, longitude: lon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return ResponsiveLayoutBuilder(
      builder: (context, screenType, isCompact) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Stack(
            children: [
              MapLibreMap(
                styleString: AdaptiveTheme.of(context).mode.isDark
                    ? _darkMapStyle
                    : _lightMapStyle,

                initialCameraPosition: _initialPosition,
                onMapCreated: _onMapCreated,
                onStyleLoadedCallback: _onStyleLoaded,
                // Prevent a repeated marker tap from being interpreted as
                // MapLibre's double-tap zoom gesture. Pinch zoom remains on.
                doubleClickZoomEnabled: false,
                // MapLibre can otherwise consume taps on rendered symbols
                // before onMapClick runs. Forward feature taps so the marker
                // query can dispatch to showReportInfoCard.
                featureTapsTriggersMapClick: true,
                myLocationEnabled: false,
                onMapClick: (Point<double> point, LatLng coords) async {
                  if (mapController == null) return;

                  // Query the visible marker icon layer itself. The small
                  // padding accommodates the icon's rendered bounds without
                  // making the incident radius or general map area clickable.
                  const double padding = 20.0;
                  final rect = Rect.fromLTRB(
                    point.x - padding,
                    point.y - padding,
                    point.x + padding,
                    point.y + padding,
                  );

                  final List<dynamic> features = await mapController!.queryRenderedFeaturesInRect(
                    rect,
                    ['incident-symbols-layer'],
                    null,
                  );

                  if (features.isNotEmpty) {
                    final Map<String, dynamic> uniqueFeatures = {};
                    for (final feature in features) {
                      final id = feature['id']?.toString();
                      if (id != null && id.isNotEmpty) uniqueFeatures[id] = feature;
                    }
                    final resolvedFeatures = uniqueFeatures.values.toList();

                    if (resolvedFeatures.length == 1) {
                      _processFeatureIdSelection(
                        resolvedFeatures.first['id'].toString(),
                      );
                    } else if (resolvedFeatures.isNotEmpty) {
                      _showOverlappingIncidentsResolver(context, resolvedFeatures);
                    }
                  }
                  // No radius-based or coordinate-based selection: only the
                  // incident marker icon can open the report information card.
                },
              ),

              // Keep every tab mounted so NotificationsPage does not lose its
              // socket listener or in-memory notification items when Home is shown.
              Positioned.fill(
                bottom: 70 + bottomPadding,
                child: Offstage(
                  offstage: _currentIndex == kNavPageHome,
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    child: IndexedStack(index: _currentIndex, children: _pages),
                  ),
                ),
              ),

              if (_currentIndex == kNavPageHome)
                Positioned(
                  top: MediaQuery.of(context).padding.top + (isCompact ? 10 : 16),
                  left: isCompact ? 12 : 16,
                  right: isCompact ? 12 : 16,
                  child: SlideDownAnimation(
                    child: MapSearchBar(
                      searchBounds: _bulacanBounds,
                      onPlaceSelected: _onSearchPlaceSelected,
                      onClear: () {},
                    ),
                  ),
                ),

              if (_currentIndex == kNavPageHome && _isInfoCardVisible && _activeSelectedReport != null)
                Positioned(
                  left: isCompact ? 12 : 16,
                  right: isCompact ? 12 : 16,
                  bottom: 16 + bottomPadding,
                  child: SwitchToReportModalCard(
                    child: ShowReportInfoCard(
                      key: ValueKey(_activeSelectedReport['_id'] ?? _selectedFeatureId),
                      report: _activeSelectedReport,
                      onClose: _clearIncidentSelection,
                    ),
                  ),
                ),

              if (_currentIndex == kNavPageHome &&
                  (_isInsideHazardCardVisible || _insideHazardReport != null))
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_isInsideHazardCardVisible,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      opacity: _isInsideHazardCardVisible ? 1.0 : 0.0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _dismissInsideHazardCard,
                        child: Container(
                          color: Colors.black.withOpacity(0.10),
                          alignment: Alignment.bottomCenter,
                          padding: EdgeInsets.only(
                            left: isCompact ? 12 : 16,
                            right: isCompact ? 12 : 16,
                            bottom: 16 + bottomPadding,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 520),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final slide = Tween<Offset>(
                                  begin: const Offset(0, 0.18),
                                  end: Offset.zero,
                                ).animate(animation);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: slide,
                                    child: child,
                                  ),
                                );
                              },
                              child: _isInsideHazardCardVisible &&
                                  _insideHazardReport != null
                                  ? ShowReportIfInsideUserCard(
                                key: ValueKey(
                                  _insideHazardReport!['id'] ??
                                      _insideHazardReport!['_id'] ??
                                      _insideHazardReport!['reportID'],
                                ),
                                report: _insideHazardReport!,
                                onClose: _dismissInsideHazardCard,
                              )
                                  : const SizedBox.shrink(
                                key: ValueKey('inside-card-hidden'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (_currentIndex == kNavPageHome &&
                  !_isInfoCardVisible &&
                  !_isInsideHazardCardVisible)
                Positioned(
                  left: isCompact ? 12 : 16,
                  right: isCompact ? 12 : 16,
                  bottom: (isCompact ? 75 : 85) + bottomPadding,
                  child: SlideUpAnimation(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          flex: 2,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SOS_Button(),
                              const SizedBox(height: 12),
                              FutureBuilder<Map<String, String>>(
                                future: _getCitizenDetails(),
                                builder: (context, snapshot) {
                                  final citizenData = snapshot.data ?? {
                                    'citizenId': 'UNKNOWN',
                                    'citizenName': FirebaseAuth.instance.currentUser?.displayName ??
                                        FirebaseAuth.instance.currentUser?.email ??
                                        'Emergency Citizen',
                                  };

                                  return EmergencyCallButton(
                                    targetRoom: "admins",
                                    callerName: citizenData['citizenName']!,
                                    citizenId: citizenData['citizenId']!,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        if (screenType != ScreenType.compactMobile)
                          Flexible(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: PHClockCard(
                                timeStream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
                              ),
                            ),
                          ),
                        Flexible(
                          flex: 2,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MapLegendsButton(onPressed: _showMapLegendsModal),
                              const SizedBox(height: 12),
                              UserPinpointButton(
                                onPressed: _initializeUserLocation,
                                isLoading: _isRecentering,
                              ),
                              const SizedBox(height: 12),
                              const SummaryReport_Button(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                left: 0,
                right: 0,
                bottom: (_isInfoCardVisible || _isInsideHazardCardVisible)
                    ? -100
                    : 0,
                child: SwitchToNavbar(
                  child: CustomNavigationBar(
                    currentIndex: _currentIndex,
                    onTap: _onItemTapped,
                    onReportPressed: _handleReportIncident,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}