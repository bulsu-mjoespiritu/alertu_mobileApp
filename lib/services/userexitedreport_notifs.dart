import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'clicksoundringtone.dart';
import 'notification_service.dart';

typedef UserExitedReportCallback = FutureOr<void> Function(
    Map<String, dynamic> report,
    double distanceMeters,
    Position userPosition,
    );

/// Detects when a user exits an active incident radius or polyline area.
/// Tracks active inside states and triggers an exit alert when the boundary is crossed.
class UserExitedReportNotifsService {
  UserExitedReportNotifsService._();

  static final UserExitedReportNotifsService instance =
  UserExitedReportNotifsService._();

  // Corridor width for polyline segments in meters.
  static const double defaultPolylineCorridorMeters = 35.0;

  // Hysteresis buffer in meters to avoid rapid triggering back and forth when on boundary edge.
  static const double exitHysteresisBufferMeters = 5.0;

  // Tracks IDs of reports the user is currently inside.
  final Set<String> _currentlyInsideReportIds = <String>{};

  // Tracks reports that have already triggered an exit alert to avoid repeated alerts.
  final Set<String> _exitedReportIds = <String>{};

  final List<_ReportZone> _activeReports = <_ReportZone>[];

  UserExitedReportCallback? _onExited;
  Position? _lastPosition;
  bool _isListening = false;

  Future<void> startListening({
    required UserExitedReportCallback onExited,
  }) async {
    if (_isListening) {
      _onExited = onExited;
      return;
    }

    await NotificationService.instance.initialize();
    _onExited = onExited;
    _isListening = true;
    debugPrint('🚪 User-exited report boundary service started.');
  }

  Future<void> stopListening() async {
    _isListening = false;
    _onExited = null;
    _lastPosition = null;
    _activeReports.clear();
    debugPrint('🛑 User-exited report boundary service stopped.');
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
    if (position != null) _evaluateUserExitZone(position);
  }

  /// Feeds the service from the homepage's existing live GPS stream.
  void evaluateUserPosition(Position position) {
    if (!_isListening) return;
    _lastPosition = position;
    _evaluateUserExitZone(position);
  }

  void clearExitCache() {
    _currentlyInsideReportIds.clear();
    _exitedReportIds.clear();
  }

  void _evaluateUserExitZone(Position position) {
    if (!_isListening || _activeReports.isEmpty) return;

    for (final report in _activeReports) {
      final distanceMeters = report.distanceToIncidentMeters(
        position.latitude,
        position.longitude,
      );

      final bool isInside = distanceMeters <= 0.0;
      final bool isOutsideWithBuffer =
          distanceMeters > exitHysteresisBufferMeters;

      if (isInside) {
        // A new entry starts a new inside/exit cycle. Remove the old exit gate
        // so the next exit can notify the user again.
        _exitedReportIds.remove(report.id);
        _currentlyInsideReportIds.add(report.id);
      } else if (isOutsideWithBuffer &&
          _currentlyInsideReportIds.contains(report.id) &&
          !_exitedReportIds.contains(report.id)) {
        // User was inside and has now crossed beyond the perimeter
        _currentlyInsideReportIds.remove(report.id);
        _exitedReportIds.add(report.id);

        unawaited(_triggerExitAlert(report, distanceMeters, position));

        final callback = _onExited;
        if (callback != null) {
          unawaited(Future<void>.sync(
                () => callback(report.data, distanceMeters, position),
          ));
        }
      }
    }
  }

  Future<void> _triggerExitAlert(
      _ReportZone report,
      double distanceMeters,
      Position position,
      ) async {
    try {
      final body =
          'SAFE ZONE: You have exited the active hazard perimeter for ${report.title}. '
          'Please remain vigilant and keep emergency channels open.';

      unawaited(ClickSoundRingtoneService.playClickSound());
      await NotificationService.instance.showLocalNotification(
        id: _notificationId(report.id),
        title: 'NOTICE: Exited Incident Area',
        body: body,
        payload: report.id,
      );

      debugPrint(
        '🚪 Exit alert triggered for ${report.id} '
            'at ${distanceMeters.round()}m boundary distance; '
            'user ${position.latitude},${position.longitude}.',
      );
    } catch (error, stackTrace) {
      debugPrint('❌ Error sending exit-zone notification: $error');
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
      final nested =
          value['radiusMeters'] ?? value['radius'] ?? value['distance'];
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
    final hash = (reportId.hashCode ^ 0x0F0F0F0F) & 0x7fffffff;
    return hash == 0 ? 4 : hash;
  }

  Future<void> dispose() async {
    await stopListening();
    _currentlyInsideReportIds.clear();
    _exitedReportIds.clear();
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
        ) -
            math.max(incidentRadiusMeters, polylineCorridorMeters));
      } else {
        for (var i = 0; i < polyline.length - 1; i++) {
          distances.add(_distanceToSegmentMeters(
            latitude,
            longitude,
            polyline[i],
            polyline[i + 1],
          ) -
              math.max(incidentRadiusMeters, polylineCorridorMeters));
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

final userExitedReportNotifsService = UserExitedReportNotifsService.instance;