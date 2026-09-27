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
      "icon-anchor": "bottom", // Pin drop baseline fix
      "icon-allow-overlap": true,
      "icon-ignore-placement": true,
    };
  }

  /// Approximate meters covered by 1 degree of latitude. This value barely
  /// changes with latitude (unlike degrees of longitude), so a constant is
  /// accurate enough for a UI-framing nudge like this.
  static const double _metersPerDegreeLatitude = 111320.0;

  /// Centers the camera on an incident, then nudges the target south so the
  /// marker visually lands in the space between the search bar (top) and
  /// the Report Info Card (bottom), instead of the dead-center of the
  /// screen. This avoids CameraUpdate.padding()/setPadding(), which aren't
  /// available on the maplibre_gl version currently pinned in this project.
  static Future<void> focusCameraOnIncident({
    required MapLibreMapController controller,
    required double latitude,
    required double longitude,
    double targetZoom = 15.5,
    double topClearance = 110.0,    // Clears the custom location search bar
    double bottomClearance = 410.0, // Clears the Report Info Card
  }) async {
    final incidentTarget = LatLng(latitude, longitude);

    // 1. Move to the raw target first so getMetersPerPixelAtLatitude()
    //    reflects the zoom level we're actually about to display at.
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(incidentTarget, targetZoom),
      duration: const Duration(milliseconds: 300),
    );

    // 2. Figure out how many degrees of latitude correspond to the pixel
    //    offset needed to visually re-center the marker within the
    //    unobstructed band of the screen.
    final double verticalOffsetPixels = (bottomClearance - topClearance) / 2;

    if (verticalOffsetPixels.abs() > 0.5) {
      final double metersPerPixel = await controller.getMetersPerPixelAtLatitude(latitude);
      final double offsetMeters = verticalOffsetPixels * metersPerPixel;
      final double deltaLat = offsetMeters / _metersPerDegreeLatitude;

      // Shifting the camera's center south makes the (unmoved) incident
      // marker appear further up the screen — i.e. out from behind the
      // bottom card and into the clear band below the search bar.
      final LatLng adjustedTarget = LatLng(latitude - deltaLat, longitude);

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(adjustedTarget, targetZoom),
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  /// Attempts to get the user's real position. Returns `null` — never a
  /// made-up coordinate — when location services are off, permission is
  /// denied, or the fix otherwise fails. Callers must treat `null` as "we
  /// don't know where the user is" and avoid drawing a "you are here"
  /// marker or moving the camera to a guessed location.
  static Future<Position?> getSafeUserPositionFallback() async {
    try {
      bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationServiceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
    } catch (_) {
      return null;
    }
  }
}
