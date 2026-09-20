import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class AnimatedMapMove {
  static Future<void> trigger({
    required MapLibreMapController mapController,
    required LatLng targetLocation,
    required double zoom,
    Duration duration = const Duration(milliseconds: 1200),
  }) async {
    await mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: targetLocation,
          zoom: zoom,
        ),
      ),
      duration: duration,
    );
  }
}