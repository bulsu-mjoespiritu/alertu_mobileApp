import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'clicksoundringtone.dart';
import 'notification_service.dart';

typedef InsideReportEnteredCallback = FutureOr<void> Function(
    Map<String, dynamic> report,
    double distanceMeters,
    Position userPosition,
    );

/// Detects when the user enters an active incident radius or polyline area.
/// Each report can trigger only once until [clearInsideCache] is called.
class InsideReportsNotifService {
  InsideReportsNotifService._();

  static final InsideReportsNotifService instance =
  InsideReportsNotifService._();

  // A polyline is mathematically zero-width, but GPS fixes have error. Treat
  // the rendered line as a practical corridor so users can enter it reliably.
  static const double defaultPolylineCorridorMeters = 35.0;

  final Set<String> _insideReportIds = <String>{};
  final List<_ReportZone> _activeReports = <_ReportZone>[];

  InsideReportEnteredCallback? _onEntered;
  Position? _lastPosition;
  bool _isListening = false;

  Future<void> startListening({
    required InsideReportEnteredCallback onEntered,
  }) async {
    if (_isListening) {
      _onEntered = onEntered;
      return;
    }

    await NotificationService.instance.initialize();
    _onEntered = onEntered;
    _isListening = true;
    debugPrint('🚨 Inside-report boundary service started.');
  }

  Future<void> stopListening() async {
    _isListening = false;
    _onEntered = null;
    _lastPosition = null;
    _activeReports.clear();
    debugPrint('🛑 Inside-report boundary service stopped.');
  }

  /// Replaces the geometry list with the same reports rendered by the map.
  void updateReports(Iterable<Map<String, dynamic>> reports) {
    final nextReports = <_ReportZone>[];
    for (final report in reports) {
      final zone = _parseReport(report);
      if (zone != null) nextReports.add(zone);
    }

    _activeReports
      ..clear()
      ..addAll(nextReports);

    final position = _lastPosition;
    if (position != null) _evaluateUserInsideZone(position);
  }

  /// Feeds the service from the homepage's existing live GPS stream.
  void evaluateUserPosition(Position position) {
    if (!_isListening) return;
    _lastPosition = position;
    _evaluateUserInsideZone(position);
  }

  void clearInsideCache() {
    _insideReportIds.clear();
  }

  /// Arms one report for a future notification after the user exits it.
  void clearReportInsideState(String reportId) {
    final id = reportId.trim();
    if (id.isNotEmpty) _insideReportIds.remove(id);
  }

  void _evaluateUserInsideZone(Position position) {
    if (!_isListening || _activeReports.isEmpty) return;

    for (final report in _activeReports) {
      final distanceMeters = report.distanceToIncidentMeters(
        position.latitude,
        position.longitude,
      );
      final bool isInside = distanceMeters <= 0.0;
      if (isInside && !_insideReportIds.contains(report.id)) {
        // Add before starting async work. This is the anti-spam gate for
        // repeated GPS fixes, API refreshes, and socket updates.
        _insideReportIds.add(report.id);
        unawaited(_triggerInsideAlert(report, distanceMeters, position));

        final callback = _onEntered;
        if (callback != null) {
          unawaited(Future<void>.sync(
                () => callback(report.data, distanceMeters, position),
          ));
        }
      }
    }
  }

  Future<void> _triggerInsideAlert(
      _ReportZone report,
      double distanceMeters,
      Position position,
      ) async {
    try {
      final body =
          'WARNING: You have entered the active hazard area for ${report.title}. '
          'Please exercise extreme caution or leave the area immediately.';

      unawaited(ClickSoundRingtoneService.playClickSound());
      await NotificationService.instance.showLocalNotification(
        id: _notificationId(report.id),
        title: 'DANGER: Inside Incident Area',
        body: body,
        payload: report.id,
      );

      debugPrint(
        '🚨 Inside-zone alert sent for ${report.id} '
            'at ${distanceMeters.round()}m boundary distance; '
            'user ${position.latitude},${position.longitude}.',
      );
    } catch (error, stackTrace) {
      debugPrint('❌ Error sending inside-zone notification: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  _ReportZone? _parseReport(Map<String, dynamic> report) {
    final id = _readString(report, <String>[
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
        'active hazard';

    final center = _extractCoordinate(report['location']) ??
        _extractCoordinate(report['radius']) ??
        _extractCoordinate(report['geometry']) ??
        _extractCoordinate(report);

    final polyline = <_Coordinate>[];
    _appendCoordinates(polyline, report['polyline']);
    if (polyline.isEmpty) _appendCoordinates(polyline, report['routeCoords']);
    if (polyline.isEmpty && report['geometry'] is Map) {
      _appendCoordinates(
        polyline,
        (report['geometry'] as Map)['coordinates'],
      );
    }

    final radiusMeters = _readRadiusMeters(report);
    if (center == null && polyline.isEmpty) return null;

    return _ReportZone(
      id: id,
      data: Map<String, dynamic>.from(report),
      title: title,
      center: center,
      incidentRadiusMeters: radiusMeters,
      polylineCorridorMeters: defaultPolylineCorridorMeters,
      polyline: polyline,
    );
  }

  double _readRadiusMeters(Map<String, dynamic> report) {
    final value = report['radius'];
    if (value is num) return math.max(0.0, value.toDouble());
    if (value is String) return double.tryParse(value) ?? 0.0;
    if (value is Map) {
      final nested = value['radiusMeters'] ?? value['radius'] ?? value['distance'];
      if (nested is num) return math.max(0.0, nested.toDouble());
      if (nested is String) return double.tryParse(nested) ?? 0.0;
    }

    final direct = report['radiusMeters'] ?? report['incidentRadiusMeters'];
    if (direct is num) return math.max(0.0, direct.toDouble());
    if (direct is String) return double.tryParse(direct) ?? 0.0;
    return 0.0;
  }

  _Coordinate? _extractCoordinate(dynamic value) {
    if (value is Map) {
      final lat = value['latitude'] ??
          value['lat'] ??
          value['centerLat'] ??
          value['_latitude'];
      final lng = value['longitude'] ??
          value['lng'] ??
          value['lon'] ??
          value['centerLng'] ??
          value['_longitude'];
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
      } else if (point is List &&
          point.length >= 2 &&
          point[0] is num &&
          point[1] is num) {
        // GeoJSON convention is [longitude, latitude].
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
    return hash == 0 ? 3 : hash;
  }

  Future<void> dispose() async {
    await stopListening();
    _insideReportIds.clear();
  }
}

class _ReportZone {
  const _ReportZone({
    required this.id,
    required this.data,
    required this.title,
    required this.center,
    required this.incidentRadiusMeters,
    required this.polylineCorridorMeters,
    required this.polyline,
  });

  final String id;
  final Map<String, dynamic> data;
  final String title;
  final _Coordinate? center;
  final double incidentRadiusMeters;
  final double polylineCorridorMeters;
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
      distances.add(centerDistance - incidentRadiusMeters);
    }

    if (polyline.isNotEmpty) {
      if (polyline.length == 1) {
        distances.add(Geolocator.distanceBetween(
          latitude,
          longitude,
          polyline.first.latitude,
          polyline.first.longitude,
        ) - math.max(incidentRadiusMeters, polylineCorridorMeters));
      } else {
        for (var i = 0; i < polyline.length - 1; i++) {
          distances.add(_distanceToSegmentMeters(
            latitude,
            longitude,
            polyline[i],
            polyline[i + 1],
          ) - math.max(incidentRadiusMeters, polylineCorridorMeters));
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
    const earthRadius = 6371000.0;
    final meanLatitude =
        ((start.latitude + end.latitude + latitude) / 3) * (math.pi / 180.0);
    final scaleX = earthRadius * math.cos(meanLatitude) * (math.pi / 180.0);
    final scaleY = earthRadius * (math.pi / 180.0);

    final px = (longitude - start.longitude) * scaleX;
    final py = (latitude - start.latitude) * scaleY;
    final ex = (end.longitude - start.longitude) * scaleX;
    final ey = (end.latitude - start.latitude) * scaleY;
    final lengthSquared = (ex * ex) + (ey * ey);
    final projection = lengthSquared == 0
        ? 0.0
        : ((px * ex) + (py * ey)) / lengthSquared;
    final t = projection.clamp(0.0, 1.0).toDouble();
    final closestX = ex * t;
    final closestY = ey * t;

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

final insideReportsNotifService = InsideReportsNotifService.instance;
