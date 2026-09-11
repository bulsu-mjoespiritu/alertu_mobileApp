import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets [Homepage] hand up its own "start a report" trigger
/// (permission check → center map on the user → show "Is this your
/// location?"), so the Quick Settings tile can fire the EXACT same flow
/// your in-app report button uses, instead of a separate path that can
/// drift out of sync with it.
class QuickReportBridge {
  static Future<void> Function()? _trigger;
  static bool _isMapReady = false;

  static void registerTrigger(Future<void> Function() trigger) {
    _trigger = trigger;
  }

  static void unregisterTrigger(Future<void> Function() trigger) {
    if (identical(_trigger, trigger)) {
      _trigger = null;
    }
    _isMapReady = false;
  }

  /// Call from Homepage's onMapCreated — the trigger being registered
  /// doesn't mean the map controller is ready yet, and _handleReportIncident
  /// silently no-ops if mapController is still null.
  static void markMapReady() {
    _isMapReady = true;
  }

  /// True once Homepage has mounted, registered its trigger, AND its map
  /// controller is actually initialized.
  static bool get isReady => _trigger != null && _isMapReady;

  static Future<void> fire() async {
    await _trigger?.call();
  }
}

/// Bridges the native Quick Settings tile to Flutter navigation.
class QuickReportChannel {
  static const MethodChannel _channel =
      MethodChannel('com.ndrrmo.alertu.alertu_flutter/quick_actions');

  // Prevents a rapid double-tap (or a race between the cold-launch check
  // and a near-simultaneous onNewIntent call) from firing the trigger twice.
  static bool _isTriggering = false;

  /// Call once, early — before runApp() — so taps are caught while the
  /// app is already running (a "warm" launch, native onNewIntent path).
  static void listenForWarmLaunch(GlobalKey<NavigatorState> navigatorKey) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openQuickReport') {
        await _triggerReportFlow(navigatorKey);
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
      await _triggerReportFlow(navigatorKey);
    }
  }

  static Future<void> _triggerReportFlow(GlobalKey<NavigatorState> navigatorKey) async {
    if (_isTriggering) return;
    _isTriggering = true;

    try {
      final NavigatorState? navState = navigatorKey.currentState;
      if (navState == null) return;

      // Return to the home screen — where Homepage's report trigger lives —
      // no matter what screen was open before. Mirrors LocalSend always
      // landing cleanly on its target screen regardless of prior state.
      navState.popUntil((route) => route.isFirst);

      // On a cold start especially, Homepage (and its map) may not have
      // finished mounting/initializing yet. Poll briefly instead of firing
      // into a callback that isn't registered yet.
      const pollInterval = Duration(milliseconds: 150);
      const maxWait = Duration(seconds: 8);
      var waited = Duration.zero;
      while (!QuickReportBridge.isReady && waited < maxWait) {
        await Future.delayed(pollInterval);
        waited += pollInterval;
      }

      if (QuickReportBridge.isReady) {
        await QuickReportBridge.fire();
      } else {
        debugPrint('⚠️ Quick report tile: Homepage never became ready in time.');
      }
    } finally {
      _isTriggering = false;
    }
  }
}
