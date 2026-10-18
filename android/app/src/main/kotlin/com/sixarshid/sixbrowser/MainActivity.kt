package com.sixarshid.sixbrowser

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.ActivityManager
import android.app.AlertDialog
import android.content.Context
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private var pendingMediaResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "6browser/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "factoryReset" -> {
                        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        if (!manager.clearApplicationUserData()) {
                            result.error("RESET_FAILED", "Unable to clear application data", null)
                        }
                        // Android terminates this process after clearing all app data.
                    }
                    "requestMediaAccess" -> requestMediaAccess(
                        call.argument<String>("origin") ?: "",
                        call.argument<Boolean>("camera") == true,
                        call.argument<Boolean>("microphone") == true,
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    // Asks the user whether the site may use the devices, then makes sure the
    // app itself holds the matching Android runtime permissions. Resolves to
    // true only when every requested device is allowed. Not remembered.
    private fun requestMediaAccess(
        origin: String,
        camera: Boolean,
        microphone: Boolean,
        result: MethodChannel.Result,
    ) {
        if (pendingMediaResult != null || (!camera && !microphone)) {
            result.success(false)
            return
        }
        val devices = listOfNotNull(
            if (microphone) "microphone" else null,
            if (camera) "camera" else null,
        ).joinToString(" and ")
        var answered = false
        AlertDialog.Builder(this)
            .setTitle("Site permission")
            .setMessage("$origin\n\nAllow this site to use your $devices?\n\nThis permission applies to this request only.")
            .setPositiveButton("Allow") { _, _ ->
                answered = true
                val needed = listOfNotNull(
                    if (camera) Manifest.permission.CAMERA else null,
                    if (microphone) Manifest.permission.RECORD_AUDIO else null,
                ).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                if (needed.isEmpty()) {
                    result.success(true)
                } else {
                    pendingMediaResult = result
                    requestPermissions(needed.toTypedArray(), MEDIA_REQUEST_CODE)
                }
            }
            .setNegativeButton("Block") { _, _ ->
                answered = true
                result.success(false)
            }
            .setOnDismissListener { if (!answered) result.success(false) }
            .show()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MEDIA_REQUEST_CODE) return
        val result = pendingMediaResult ?: return
        pendingMediaResult = null
        result.success(
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED },
        )
    }

    private companion object {
        const val MEDIA_REQUEST_CODE = 6001
    }
}
