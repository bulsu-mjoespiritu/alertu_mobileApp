package com.ndrrmo.alertu.alertu_flutter

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ndrrmo.alertu.alertu_flutter/quick_actions"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Dart asks this on startup: "was I just cold-launched from the tile?"
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLaunchAction" -> {
                    val launchedFromTile = intent?.action == QuickReportTileService.ACTION_QUICK_REPORT
                    if (launchedFromTile) intent.action = Intent.ACTION_MAIN // consume so it won't re-fire
                    result.success(launchedFromTile)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Fires when the app was ALREADY running and the tile is tapped again
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == QuickReportTileService.ACTION_QUICK_REPORT) {
            methodChannel?.invokeMethod("openQuickReport", null)
        }
    }
}
