import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alertu_flutter/camera_page.dart';
import 'package:alertu_flutter/components/CenterandFix_TheView_Incidents.dart';

/// Bridges the native Quick Settings tile to Flutter navigation.
///
/// Mirrors LocalSend's tile behavior: tapping it always opens the app
/// directly on the report/camera screen, whether the app was killed,
/// backgrounded, or already open on some other screen.
class QuickReportChannel {
  static const MethodChannel _channel =
      MethodChannel('com.ndrrmo.alertu.alertu_flutter/quick_actions');

  // Prevents a rapid double-tap (or a race between cold-launch check and
  // a near-simultaneous onNewIntent call) from pushing the screen twice.
  static bool _isNavigating = false;

  /// Call once, early — before runApp() — so taps are caught while the
  /// app is already running (a "warm" launch, native onNewIntent path).
  static void listenForWarmLaunch(GlobalKey<NavigatorState> navigatorKey) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openQuickReport') {
        await _openReportScreen(navigatorKey);
      }
    });
  }

  /// Call once the navigator is actually mounted (e.g. right after your
  /// splash screen finishes its transition), to catch the case where the
  /// tile is what cold-started the app in the first place.
  static Future<void> checkColdLaunch(GlobalKey<NavigatorState> navigatorKey) async {
    final bool launchedFromTile =
        await _channel.invokeMethod<bool>('checkLaunchAction') ?? false;
    if (launchedFromTile) {
      await _openReportScreen(navigatorKey);
    }
  }

  static Future<void> _openReportScreen(GlobalKey<NavigatorState> navigatorKey) async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final NavigatorState? navState = navigatorKey.currentState;
      if (navState == null) return;

      // Grab a location fast — real GPS if available within the timeout,
      // otherwise a safe fallback — so the camera isn't blocked waiting
      // on a slow fix. The user can still correct the pin afterwards.
      final position = await CenterandFixTheViewIncidents.getSafeUserPositionFallback();

      // Clear back to the app's root route, then push the camera on top.
      // This is what makes it feel like LocalSend: no matter what screen
      // was open before, the tile always lands cleanly on the report flow,
      // and the back button returns to the normal home screen afterward.
      navState.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CameraPage(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        ),
        (route) => route.isFirst,
      );
    } finally {
      _isNavigating = false;
    }
  }
}
