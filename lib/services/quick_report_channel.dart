import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tile path only — opens camera / create-report.
/// Location is chosen later on the report form (no GPS gate on the tile).
class QuickReportBridge {
  static Future<void> Function()? _cameraTrigger;

  static void registerCameraTrigger(Future<void> Function() trigger) {
    _cameraTrigger = trigger;
  }

  static void unregisterCameraTrigger(Future<void> Function() trigger) {
    if (identical(_cameraTrigger, trigger)) {
      _cameraTrigger = null;
    }
  }

  static bool get isReady => _cameraTrigger != null;

  static Future<void> fireCamera() async {
    await _cameraTrigger?.call();
  }
}

/// Bridges the native Quick Settings tile to Flutter navigation.
class QuickReportChannel {
  static const MethodChannel _channel =
  MethodChannel('com.ndrrmo.alertu.alertu_flutter/quick_actions');

  static bool _isTriggering = false;

  /// Call once early (e.g. in main before/after runApp setup) for warm launches.
  static void listenForWarmLaunch(GlobalKey<NavigatorState> navigatorKey) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openQuickReport') {
        await _openCameraReport(navigatorKey);
      }
    });
  }

  /// Call after splash → home is mounted (cold start from tile).
  static Future<void> checkColdLaunch(
      GlobalKey<NavigatorState> navigatorKey,
      ) async {
    final bool launchedFromTile =
        await _channel.invokeMethod<bool>('checkLaunchAction') ?? false;
    if (launchedFromTile) {
      await _openCameraReport(navigatorKey);
    }
  }

  static Future<void> _openCameraReport(
      GlobalKey<NavigatorState> navigatorKey,
      ) async {
    if (_isTriggering) return;
    _isTriggering = true;

    try {
      final NavigatorState? nav = navigatorKey.currentState;
      if (nav == null) return;

      nav.popUntil((route) => route.isFirst);

      // Wait only until Homepage registers the camera trigger (no map/GPS wait).
      const poll = Duration(milliseconds: 100);
      const maxWait = Duration(seconds: 6);
      var waited = Duration.zero;
      while (!QuickReportBridge.isReady && waited < maxWait) {
        await Future.delayed(poll);
        waited += poll;
      }

      if (QuickReportBridge.isReady) {
        await QuickReportBridge.fireCamera();
      } else {
        debugPrint('⚠️ Quick report tile: camera trigger never registered.');
      }
    } finally {
      _isTriggering = false;
    }
  }
}