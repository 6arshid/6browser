package com.sixarshid.sixbrowser

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.Base64
import java.io.ByteArrayOutputStream

/** Owns the projection for one consent session; no frames are written to disk. */
class ScreenShareService : Service() {
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var worker: HandlerThread? = null
    @Volatile private var jpeg: String? = null
    @Volatile private var active = false

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent == null || instance != null) {
            stopSelf()
            return START_NOT_STICKY
        }
        instance = this
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(
                    "screen_share", "Screen sharing", NotificationManager.IMPORTANCE_LOW))
            }
            val stop = PendingIntent.getService(this, 0,
                Intent(this, ScreenShareService::class.java).setAction("stop"),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val builder = if (Build.VERSION.SDK_INT >= 26)
                Notification.Builder(this, "screen_share") else Notification.Builder(this)
            val notification = builder.setSmallIcon(android.R.drawable.ic_menu_view)
                .setContentTitle("6browser is sharing your screen")
                .setContentText("Tap Stop to end screen sharing")
                .setOngoing(true).addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stop)
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(6002, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else startForeground(6002, notification)

            @Suppress("DEPRECATION")
            val data = intent.getParcelableExtra<Intent>("data")
                ?: throw IllegalArgumentException("Missing screen capture consent")
            val capture = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val session = capture.getMediaProjection(Activity.RESULT_OK, data)
                ?: throw IllegalStateException("Screen capture consent is unavailable")
            projection = session
            worker = HandlerThread("6browser-screen-share").also { it.start() }
            val handler = Handler(worker!!.looper)
            session.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() { stopSelf() }
            }, Handler(Looper.getMainLooper()))
            // Bound the bridge bandwidth; frames are encoded off the UI thread.
            val metrics = resources.displayMetrics
            val scale = minOf(1.0, 1280.0 / maxOf(metrics.widthPixels, metrics.heightPixels))
            val width = (metrics.widthPixels * scale).toInt().coerceAtLeast(2)
            val height = (metrics.heightPixels * scale).toInt().coerceAtLeast(2)
            val images = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            reader = images
            var previous = 0L
            images.setOnImageAvailableListener({ source ->
                val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val now = SystemClock.elapsedRealtime()
                    if (now - previous >= 100) {
                        previous = now
                        val plane = image.planes[0]
                        val paddedWidth = plane.rowStride / plane.pixelStride
                        val padded = Bitmap.createBitmap(paddedWidth, height, Bitmap.Config.ARGB_8888)
                        padded.copyPixelsFromBuffer(plane.buffer)
                        val bitmap = Bitmap.createBitmap(padded, 0, 0, width, height)
                        val bytes = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 70, bytes)
                        jpeg = Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
                        if (bitmap !== padded) bitmap.recycle()
                        padded.recycle()
                    }
                } finally { image.close() }
            }, handler)
            display = session.createVirtualDisplay("6browser screen share", width, height,
                metrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                images.surface, null, handler)
            active = true
            completeStart(null)
        } catch (error: Exception) {
            completeStart(error.message ?: "Unable to capture screen")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        active = false
        jpeg = null
        display?.release()
        display = null
        reader?.setOnImageAvailableListener(null, null)
        // Close after any frame currently being encoded has finished.
        val images = reader
        worker?.let { thread -> Handler(thread.looper).post { images?.close(); thread.quitSafely() } }
        reader = null
        projection?.stop()
        projection = null
        if (instance === this) instance = null
        completeStart("Screen sharing stopped")
        super.onDestroy()
    }

    companion object {
        var instance: ScreenShareService? = null
            private set
        var onStarted: ((String?) -> Unit)? = null
        private fun completeStart(error: String?) {
            val callback = onStarted
            onStarted = null
            callback?.invoke(error)
        }
        fun frame(): Pair<Boolean, String?> = instance?.let { it.active to it.jpeg } ?: (false to null)
    }
}
