import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'clicksoundringtone.dart';
import 'notification_service.dart';

/// Evaluates the user's live position against the incident geometries currently
/// displayed by the homepage. Each report is notified once per app session.
class NearbyReportsNotifService {
  NearbyReportsNotifService._();

  static final NearbyReportsNotifService instance =
  NearbyReportsNotifService._();

  static const double warningDistanceMeters = 250.0;

  final Set<String> _notifiedReportIds = <String>{};
  final List<_ReportGeometry> _activeReports = <_ReportGeometry>[];

  Position? _lastPosition;
  bool _isListening = false;

  /// Initializes the shared local-notification service.
  ///
  /// The homepage supplies positions through [evaluateUserPosition], so this
  /// service does not start a second GPS stream.
  Future<void> startListening() async {
    if (_isListening) return;

    await NotificationService.instance.initialize();
    _isListening = true;
    debugPrint('📍 Nearby report notification service started.');
  }

  Future<void> stopListening() async {
    _isListening = false;
    _lastPosition = null;
    _activeReports.clear();
    debugPrint('🛑 Nearby report notification service stopped.');
  }

  /// Replaces the report geometries used for proximity checks.
  ///
  /// Call this after every successful report fetch and after every real-time
  /// report insert/update. A new snapshot does not clear the notified set, so
  /// Firestore/API refreshes cannot spam the user with the same alert.
  void updateReports(Iterable<Map<String, dynamic>> reports) {
    final nextReports = <_ReportGeometry>[];

    for (final report in reports) {
      final geometry = _parseReport(report);
      if (geometry != null) nextReports.add(geometry);
    }

    _activeReports
      ..clear()
      ..addAll(nextReports);

    final position = _lastPosition;
    if (position != null) {
      _evaluate(position);
    }
  }

  /// Feeds the service from the homepage's existing Geolocator stream.
  void evaluateUserPosition(Position position) {
    if (!_isListening) return;
    _lastPosition = position;
    _evaluate(position);
  }

  /// Clears the one-time cache manually, for example after the user logs out.
  void clearProximityCache() {
    _notifiedReportIds.clear();
  }

  void _evaluate(Position position) {
    if (!_isListening || _activeReports.isEmpty) return;

    for (final report in _activeReports) {
      final double distanceToIncident = report.distanceToIncidentMeters(
        position.latitude,
        position.longitude,
      );

      if (distanceToIncident <= warningDistanceMeters &&
          _notifiedReportIds.add(report.id)) {
        unawaited(_triggerProximityAlert(report, distanceToIncident));
      }
    }
  }

  Future<void> _triggerProximityAlert(
      _ReportGeometry report,
      double distance,
      ) async {
    try {
      final int roundedDistance = math.max(0, distance.round());
      final String body =
          'Caution: You are within approximately $roundedDistance meters of '
          '${report.title}. Please stay alert and stay safe.';

      unawaited(ClickSoundRingtoneService.playClickSound());

      await NotificationService.instance.showLocalNotification(
        id: _notificationId(report.id),
        title: 'AlertU Nearby Incident',
        body: body,
        payload: report.id,
      );

      debugPrint(
        '🔔 Nearby incident notification sent for ${report.id} '
            'at ${roundedDistance}m.',
      );
    } catch (error, stackTrace) {
      debugPrint('❌ Nearby notification failed for ${report.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  _ReportGeometry? _parseReport(Map<String, dynamic> report) {
    final String? id = _readString(report, <String>[
      'id',
      '_id',
      'reportID',
      'reportId',
      'verifiedReportId',
      'verifiedReportID',
    ]);
    if (id == null) return null;

    final title = _readString(report, <String>[
      'reportTitle',
      'title',
      'category',
      'incidentType',
      'hazard',
    ]) ??
        'active incident';

    final center = _extractCoordinate(report['location']) ??
        _extractCoordinate(report['radius']) ??
        _extractCoordinate(report);

    final polyline = <_Coordinate>[];
    _appendCoordinates(polyline, report['polyline']);
    if (polyline.isEmpty) {
      _appendCoordinates(polyline, report['routeCoords']);
    }

    final double? incidentRadius = _readRadiusMeters(report);
    if (center == null && polyline.isEmpty) return null;

    return _ReportGeometry(
      id: id,
      title: title,
      center: center,
      incidentRadiusMeters: incidentRadius ?? 0.0,
      polyline: polyline,
    );
  }

  double? _readRadiusMeters(Map<String, dynamic> report) {
    final radius = report['radius'];
    if (radius is num) return radius.toDouble();
    if (radius is Map) {
      final value = radius['radiusMeters'] ?? radius['radius'] ?? radius['distance'];
      if (value is num) return value.toDouble();
    }

    final value = report['radiusMeters'] ?? report['incidentRadiusMeters'];
    return value is num ? value.toDouble() : null;
  }

  _Coordinate? _extractCoordinate(dynamic value) {
    if (value is Map) {
      final lat = value['latitude'] ?? value['lat'] ?? value['centerLat'];
      final lng = value['longitude'] ?? value['lng'] ?? value['lon'] ?? value['centerLng'];
      if (lat is num && lng is num) {
        return _Coordinate(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  void _appendCoordinates(List<_Coordinate> output, dynamic value) {
    if (value is! List) return;

    for (final point in value) {
      final coordinate = _extractCoordinate(point);
      if (coordinate != null) {
        output.add(coordinate);
        continue;
      }

      // Also support GeoJSON-style [longitude, latitude] pairs.
      if (point is List && point.length >= 2 && point[0] is num && point[1] is num) {
        output.add(_Coordinate(
          (point[1] as num).toDouble(),
          (point[0] as num).toDouble(),
        ));
      }
    }
  }

  String? _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  int _notificationId(String reportId) {
    final hash = reportId.hashCode & 0x7fffffff;
    return hash == 0 ? 2 : hash;
  }

  Future<void> dispose() async {
    await stopListening();
    _notifiedReportIds.clear();
  }
}

class _ReportGeometry {
  const _ReportGeometry({
    required this.id,
    required this.title,
    required this.center,
    required this.incidentRadiusMeters,
    required this.polyline,
  });

  final String id;
  final String title;
  final _Coordinate? center;
  final double incidentRadiusMeters;
  final List<_Coordinate> polyline;

  double distanceToIncidentMeters(double latitude, double longitude) {
    final distances = <double>[];

    if (center != null) {
      final centerDistance = Geolocator.distanceBetween(
        latitude,
        longitude,
        center!.latitude,
        center!.longitude,
      );
      distances.add(math.max(0.0, centerDistance - incidentRadiusMeters));
    }

    if (polyline.isNotEmpty) {
      if (polyline.length == 1) {
        distances.add(Geolocator.distanceBetween(
          latitude,
          longitude,
          polyline.first.latitude,
          polyline.first.longitude,
        ));
      } else {
        for (var i = 0; i < polyline.length - 1; i++) {
          distances.add(math.max(
            0.0,
            _distanceToSegmentMeters(
              latitude,
              longitude,
              polyline[i],
              polyline[i + 1],
            ) - incidentRadiusMeters,
          ));
        }
      }
    }

    return distances.isEmpty ? double.infinity : distances.reduce(math.min);
  }

  double _distanceToSegmentMeters(
      double latitude,
      double longitude,
      _Coordinate start,
      _Coordinate end,
      ) {
    // Local equirectangular projection is accurate enough for short incident
    // polylines and avoids expensive spherical segment calculations.
    const earthRadius = 6371000.0;
    final meanLatitude = ((start.latitude + end.latitude + latitude) / 3) *
        (math.pi / 180.0);
    final scaleX = earthRadius * math.cos(meanLatitude) * (math.pi / 180.0);
    final scaleY = earthRadius * (math.pi / 180.0);

    final px = (longitude - start.longitude) * scaleX;
    final py = (latitude - start.latitude) * scaleY;
    final sx = 0.0;
    final sy = 0.0;
    final ex = (end.longitude - start.longitude) * scaleX;
    final ey = (end.latitude - start.latitude) * scaleY;

    final dx = ex - sx;
    final dy = ey - sy;
    final lengthSquared = (dx * dx) + (dy * dy);
    final projection = lengthSquared == 0
        ? 0.0
        : (((px - sx) * dx) + ((py - sy) * dy)) / lengthSquared;
    final t = projection.clamp(0.0, 1.0).toDouble();
    final closestX = sx + (dx * t);
    final closestY = sy + (dy * t);

    return math.sqrt(
      math.pow(px - closestX, 2) + math.pow(py - closestY, 2),
    );
  }
}

class _Coordinate {
  const _Coordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

final nearbyReportsNotifService = NearbyReportsNotifService.instance;
