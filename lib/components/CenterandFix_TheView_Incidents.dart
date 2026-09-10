import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';

class CenterandFixTheViewIncidents {
  /// Safely builds a payload injection map to prevent type compiling exceptions
  /// inside the MapLibre engine while resolving symbol markers dynamically.
  static Map<String, dynamic> getFixedSymbolLayout() {
    return {
      "icon-image": ["get", "icon"],
      "icon-size": [
        "case",
        ["boolean", ["get", "isSelected"], false],
        1.8,
        1.0
      ],
      "icon-anchor": "bottom",
      "icon-allow-overlap": true,
      "icon-ignore-placement": true,
    };
  }

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
        top: 130.0,    // clears search bar
        right: 32.0,
        bottom: 430.0, // clears Report Info Card
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