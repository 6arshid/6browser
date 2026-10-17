package com.sixarshid.sixbrowser

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.ActivityManager
import android.content.Context

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "6browser/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "factoryReset") {
                    val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    if (!manager.clearApplicationUserData()) {
                        result.error("RESET_FAILED", "Unable to clear application data", null)
                    }
                    // Android terminates this process after clearing all app data.
                } else {
                    result.notImplemented()
                }
            }
    }
}
