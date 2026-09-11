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
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLaunchAction" -> {
                    val fromIntent =
                        intent?.action == QuickReportTileService.ACTION_QUICK_REPORT
                    val prefs = getSharedPreferences(
                        QuickReportTileService.PREFS,
                        MODE_PRIVATE
                    )
                    val fromPrefs =
                        prefs.getBoolean(QuickReportTileService.KEY_PENDING, false)

                    if (fromIntent || fromPrefs) {
                        intent.action = Intent.ACTION_MAIN
                        prefs.edit()
                            .putBoolean(QuickReportTileService.KEY_PENDING, false)
                            .apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == QuickReportTileService.ACTION_QUICK_REPORT) {
            getSharedPreferences(QuickReportTileService.PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(QuickReportTileService.KEY_PENDING, false)
                .apply()
            methodChannel?.invokeMethod("openQuickReport", null)
        }
    }
}