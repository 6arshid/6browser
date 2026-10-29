package com.sixarshid.sixbrowser

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Message
import android.view.KeyEvent
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.RequiresApi
import androidx.webkit.WebViewCompat
import java.net.URISyntaxException

/** Links to other apps (tel:, sms:, mailto:, whatsapp:, intent:...). */
object ExternalLinks {
    /** Schemes the WebView loads itself. */
    private val webSchemes =
        setOf("http", "https", "about", "data", "blob", "javascript", "file", "content")

    fun isExternal(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        return scheme !in webSchemes
    }

    /**
     * Makes [view] hand such links to [onLink] instead of showing
     * ERR_UNKNOWN_URL_SCHEME. webview_flutter's own client keeps every other
     * callback (its navigation callback would reload every link with loadUrl).
     */
    fun install(view: WebView, onLink: (String) -> Unit) {
        val inner = WebViewCompat.getWebViewClient(view)
        if (inner is ExternalLinkClient) return
        view.webViewClient = ExternalLinkClient(inner, onLink)
    }

    /**
     * Opens [url] in its app, as Chrome does: only activities that accept
     * links from browsers, never a component or permission the page names,
     * never this app. False when no app opened it.
     */
    fun open(activity: Activity, url: String): Boolean {
        val intent = try {
            if (url.startsWith("intent:", ignoreCase = true)) {
                Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
            } else {
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
            }
        } catch (_: URISyntaxException) {
            return false
        }
        if (intent.`package` == activity.packageName) return false
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null
        intent.selector = null
        intent.flags = 0 // e.g. no FLAG_GRANT_READ_URI_PERMISSION on our files
        return try {
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        } catch (_: RuntimeException) {
            false // e.g. FileUriExposedException
        }
    }
}

/**
 * Passes app links to [onLink] and everything else to [inner]. Like Chrome,
 * a page gets one app link until the user next taps, so a script cannot keep
 * opening apps, and frames inside it (ads) need a tap.
 */
@Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
private class ExternalLinkClient(
    private val inner: WebViewClient,
    private val onLink: (String) -> Unit,
) : WebViewClient() {
    private var allowed = true

    private fun offer(uri: Uri, gesture: Boolean, mainFrame: Boolean): Boolean {
        if (!ExternalLinks.isExternal(uri)) return false
        if (gesture) allowed = true
        if (allowed && (mainFrame || gesture)) {
            allowed = false
            onLink(uri.toString())
        }
        return true
    }

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
        offer(request.url, request.hasGesture(), request.isForMainFrame) ||
            inner.shouldOverrideUrlLoading(view, request)

    override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
        offer(Uri.parse(url), gesture = false, mainFrame = true) ||
            inner.shouldOverrideUrlLoading(view, url)

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) =
        inner.onPageStarted(view, url, favicon)

    override fun onPageFinished(view: WebView, url: String) = inner.onPageFinished(view, url)

    override fun onLoadResource(view: WebView, url: String) = inner.onLoadResource(view, url)

    override fun onPageCommitVisible(view: WebView, url: String) =
        inner.onPageCommitVisible(view, url)

    override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? =
        inner.shouldInterceptRequest(view, url)

    override fun shouldInterceptRequest(
        view: WebView,
        request: WebResourceRequest,
    ): WebResourceResponse? = inner.shouldInterceptRequest(view, request)

    override fun onTooManyRedirects(view: WebView, cancelMsg: Message, continueMsg: Message) =
        inner.onTooManyRedirects(view, cancelMsg, continueMsg)

    override fun onReceivedError(
        view: WebView,
        errorCode: Int,
        description: String,
        failingUrl: String,
    ) = inner.onReceivedError(view, errorCode, description, failingUrl)

    override fun onReceivedError(
        view: WebView,
        request: WebResourceRequest,
        error: WebResourceError,
    ) = inner.onReceivedError(view, request, error)

    override fun onReceivedHttpError(
        view: WebView,
        request: WebResourceRequest,
        errorResponse: WebResourceResponse,
    ) = inner.onReceivedHttpError(view, request, errorResponse)

    override fun onFormResubmission(view: WebView, dontResend: Message, resend: Message) =
        inner.onFormResubmission(view, dontResend, resend)

    override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) =
        inner.doUpdateVisitedHistory(view, url, isReload)

    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) =
        inner.onReceivedSslError(view, handler, error)

    override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) =
        inner.onReceivedClientCertRequest(view, request)

    override fun onReceivedHttpAuthRequest(
        view: WebView,
        handler: HttpAuthHandler,
        host: String,
        realm: String,
    ) = inner.onReceivedHttpAuthRequest(view, handler, host, realm)

    override fun shouldOverrideKeyEvent(view: WebView, event: KeyEvent): Boolean =
        inner.shouldOverrideKeyEvent(view, event)

    override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) =
        inner.onUnhandledKeyEvent(view, event)

    override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) =
        inner.onScaleChanged(view, oldScale, newScale)

    override fun onReceivedLoginRequest(
        view: WebView,
        realm: String,
        account: String?,
        args: String,
    ) = inner.onReceivedLoginRequest(view, realm, account, args)

    @RequiresApi(26)
    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean =
        inner.onRenderProcessGone(view, detail)

    @RequiresApi(27)
    override fun onSafeBrowsingHit(
        view: WebView,
        request: WebResourceRequest,
        threatType: Int,
        callback: SafeBrowsingResponse,
    ) = inner.onSafeBrowsingHit(view, request, threatType, callback)
}
