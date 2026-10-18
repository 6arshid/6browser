package com.sixarshid.sixbrowser

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.ActivityManager
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    private var pendingMediaResult: MethodChannel.Result? = null
    private val screenShare = ScreenShareBridge(this)
    private var pendingScreenCapture: ((String?) -> Unit)? = null
    private var screenConsentOpen = false
    private var screenSiteDialog: AlertDialog? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "6browser/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installScreenShare" -> {
                        val id = call.argument<Number>("webViewId")?.toLong()
                        val view = id?.let { WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, it) }
                        if (view == null) result.error("NO_WEBVIEW", "WebView is unavailable", null)
                        else {
                            screenShare.install(view)
                            result.success(null)
                        }
                    }
                    "stopScreenShare" -> {
                        val id = call.argument<Number>("webViewId")?.toLong()
                        val view = id?.let { WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, it) }
                        if (view != null) screenShare.stop(view)
                        result.success(null)
                    }
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

    fun requestScreenCapture(origin: String, callback: (String?) -> Unit) {
        if (screenConsentOpen || pendingScreenCapture != null || ScreenShareService.instance != null) {
            callback("Another screen capture request is active")
            return
        }
        pendingScreenCapture = callback
        screenSiteDialog = AlertDialog.Builder(this)
            .setTitle("Share your screen?")
            .setMessage("$origin\n\nThis site will see the screen or app you choose in the Android dialog.")
            .setPositiveButton("Continue") { _, _ ->
                screenConsentOpen = true
                val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                @Suppress("DEPRECATION")
                startActivityForResult(manager.createScreenCaptureIntent(), SCREEN_REQUEST_CODE)
            }
            .setNegativeButton("Cancel") { _, _ -> finishScreenCapture("Screen sharing cancelled") }
            .setOnCancelListener { finishScreenCapture("Screen sharing cancelled") }
            .show()
    }

    private fun finishScreenCapture(error: String?) {
        val callback = pendingScreenCapture
        pendingScreenCapture = null
        callback?.invoke(error)
    }

    fun cancelScreenCapture() {
        screenSiteDialog?.dismiss()
        screenSiteDialog = null
        finishScreenCapture("Screen sharing stopped")
        ScreenShareService.onStarted = null
    }

    @Deprecated("Activity result API used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SCREEN_REQUEST_CODE) return
        screenConsentOpen = false
        if (pendingScreenCapture == null) return
        if (resultCode != RESULT_OK || data == null) {
            finishScreenCapture("Screen sharing cancelled")
            return
        }
        ScreenShareService.onStarted = { error -> finishScreenCapture(error) }
        try {
            val service = Intent(this, ScreenShareService::class.java).putExtra("data", data)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
        } catch (error: Exception) {
            ScreenShareService.onStarted = null
            finishScreenCapture(error.message ?: "Unable to start screen capture")
        }
    }

    override fun onDestroy() {
        screenShare.stop()
        super.onDestroy()
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
        const val SCREEN_REQUEST_CODE = 6002
    }
}
