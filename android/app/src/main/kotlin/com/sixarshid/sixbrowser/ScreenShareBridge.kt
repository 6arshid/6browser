package com.sixarshid.sixbrowser

import android.content.Intent
import android.net.Uri
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject

/** Origin-aware messaging avoids exposing an unrestricted JavascriptInterface. */
class ScreenShareBridge(private val activity: MainActivity) {
    private var owner: WebView? = null
    private var ownerOrigin: Uri? = null
    private var generation = 0

    fun install(view: WebView) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
        WebViewCompat.addWebMessageListener(view, "SixScreenCapture", setOf("https://*")) {
                _, message, origin, mainFrame, reply ->
            if (!mainFrame || origin.scheme != "https") return@addWebMessageListener
            val input = try { JSONObject(message.data ?: "") } catch (_: Exception) {
                return@addWebMessageListener
            }
            val id = input.optInt("id")
            fun respond(error: String? = null, ended: Boolean = false, jpeg: String? = null) {
                val output = JSONObject().put("id", id).put("ended", ended)
                if (error != null) output.put("error", error)
                if (jpeg != null) output.put("jpeg", jpeg)
                reply.postMessage(output.toString())
            }
            when (input.optString("op")) {
                "start" -> {
                    if (!sameOrigin(view.url, origin)) respond("The page has changed")
                    else if (owner != null) respond("Screen sharing is already active")
                    else {
                        owner = view
                        ownerOrigin = origin
                        val request = ++generation
                        activity.requestScreenCapture(origin.toString()) { error ->
                            if (request != generation) return@requestScreenCapture
                            if (error != null) { owner = null; ownerOrigin = null }
                            respond(error)
                        }
                    }
                }
                "frame" -> {
                    if (owner !== view || ownerOrigin != origin || !sameOrigin(view.url, origin)) respond(ended = true)
                    else {
                        val (active, frame) = ScreenShareService.frame()
                        respond(ended = !active, jpeg = frame)
                    }
                }
                "stop" -> { stop(view); respond() }
            }
        }
        val script = activity.assets.open("screen_share.js").bufferedReader().use { it.readText() }
        WebViewCompat.addDocumentStartJavaScript(view, script, setOf("https://*"))
    }

    private fun sameOrigin(url: String?, origin: Uri): Boolean {
        val current = url?.let { Uri.parse(it) } ?: return false
        return current.scheme == origin.scheme && current.host == origin.host && current.port == origin.port
    }

    fun stop(view: WebView? = null) {
        if (view != null && owner !== view) return
        generation++
        owner = null
        ownerOrigin = null
        activity.cancelScreenCapture()
        activity.stopService(Intent(activity, ScreenShareService::class.java))
    }
}
