// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "webview_handler.h"

#include <sstream>
#include <string>
#include <iostream>
#include <chrono>
#include <unordered_map>
#include <cstdint>
#include <cstdio>
#include <cmath>

#include "include/base/cef_callback.h"
#include "include/cef_app.h"
#include "include/cef_parser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"

#include <sstream>

// std::to_string fails for ints on Ubuntu 24.04:
// webview_handler.cc:86:86: error: no matching function for call to 'to_string'
// webview_handler.cc:567:24: error: no matching function for call to 'to_string'
namespace stringpatch
{
    template < typename T > std::string to_string( const T& n )
    {
        std::ostringstream stm ;
        stm << n ;
        return stm.str() ;
    }
}

#include "webview_js_handler.h"


WebviewHandler::WebviewHandler() {

}

WebviewHandler::~WebviewHandler() {
    browser_map_.clear();
    js_callbacks_.clear();
}

#if defined(OS_WIN)
namespace {
// CEF may ask about one getUserMedia call twice: OnShowPermissionPrompt
// (Chrome's permission layer) and OnRequestMediaAccessPermission (device
// access). Both must be granted, so a "Yes" is reused for a few seconds for
// the same origin and devices instead of prompting twice.
struct RecentMediaGrant {
    std::wstring origin;
    bool audio = false;
    bool video = false;
    std::chrono::steady_clock::time_point at;
};
RecentMediaGrant recent_media_grant_;

void LogPermission(const std::wstring& line) {
    wchar_t temp[MAX_PATH];
    if (!GetTempPathW(MAX_PATH, temp)) return;
    const std::wstring path = std::wstring(temp) + L"6browser-permissions.log";
    FILE* f = nullptr;
    if (_wfopen_s(&f, path.c_str(), L"a, ccs=UTF-8") != 0) return;
    if (!f) return;
    fwprintf(f, L"%ls\n", line.c_str());
    fclose(f);
}

bool AskMediaPermission(CefRefPtr<CefBrowser> browser, const std::wstring& origin,
                        bool audio, bool video) {
    const auto now = std::chrono::steady_clock::now();
    if (recent_media_grant_.origin == origin &&
        (!audio || recent_media_grant_.audio) &&
        (!video || recent_media_grant_.video) &&
        now - recent_media_grant_.at < std::chrono::seconds(10)) {
        return true;
    }
    std::wstring resources;
    if (audio) resources = L"microphone";
    if (video) {
        if (!resources.empty()) resources += L" and ";
        resources += L"camera";
    }
    const std::wstring message = origin +
        L"\n\nAllow this site to use your " + resources +
        L"?\n\nThis permission applies to this request only.";
    const int result = MessageBoxW(browser->GetHost()->GetWindowHandle(),
        message.c_str(), L"6browser - Site permission",
        MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2 | MB_SETFOREGROUND);
    if (result != IDYES) return false;
    recent_media_grant_ = {origin, audio, video, std::chrono::steady_clock::now()};
    return true;
}
}  // namespace
#endif

bool WebviewHandler::OnRequestMediaAccessPermission(
    CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
    const CefString& requesting_origin, uint32_t requested_permissions,
    CefRefPtr<CefMediaAccessCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
#if defined(OS_WIN)
    // Alloy's callback captures the entire desktop when no source ID was
    // supplied. It does NOT open Chrome's source picker. Obtain explicit,
    // uncached consent for that scope before continuing the request.
    constexpr uint32_t display = CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE |
                                 CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE;
    if ((requested_permissions & CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE) &&
        !(requested_permissions & ~display)) {
        const std::wstring message = requesting_origin.ToWString() +
            L"\n\nShare your ENTIRE desktop with this site?"
            L"\nEverything visible on your screens may be shared, including other apps and notifications."
            L"\n\nUse the site's Stop presenting / Stop sharing control to stop."
            L"\nThis permission applies to this request only.";
        const bool allowed = MessageBoxW(browser->GetHost()->GetWindowHandle(),
            message.c_str(), L"6browser - Share entire screen",
            MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2 | MB_SETFOREGROUND) == IDYES;
        // System audio is never granted: CEF captures it with a plain
        // "loopback" device that includes this browser's own playback, so the
        // other people in a call (e.g. Google Meet) hear themselves echoed.
        // getDisplayMedia treats audio as optional, so video alone is valid.
        callback->Continue(allowed ? CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE : 0);
        return true;
    }
    // Alloy's default is to deny silently. Ask for each request rather than
    // enabling --enable-media-stream, which grants every site access.
    constexpr uint32_t devices = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE |
                                 CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
    LogPermission(L"media access " + requesting_origin.ToWString() +
                  L" permissions=" + std::to_wstring(requested_permissions));
    // Deny unknown permissions rather than treating them as camera/microphone.
    if (!requested_permissions || (requested_permissions & ~devices)) {
        callback->Cancel();
        return true;
    }
    const bool allowed = AskMediaPermission(browser, requesting_origin.ToWString(),
        requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE,
        requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE);
    LogPermission(allowed ? L"  -> allowed" : L"  -> denied");
    callback->Continue(allowed ? requested_permissions : 0);
    return true;
#else
    return false;
#endif
}

bool WebviewHandler::OnShowPermissionPrompt(
    CefRefPtr<CefBrowser> browser, uint64_t prompt_id,
    const CefString& requesting_origin, uint32_t requested_permissions,
    CefRefPtr<CefPermissionPromptCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
#if defined(OS_WIN)
    // With Alloy style the default is IGNORE, which also blocks getUserMedia.
    constexpr uint32_t devices = CEF_PERMISSION_TYPE_CAMERA_STREAM |
                                 CEF_PERMISSION_TYPE_MIC_STREAM;
    LogPermission(L"prompt " + requesting_origin.ToWString() +
                  L" permissions=" + std::to_wstring(requested_permissions));
    if (!requested_permissions || (requested_permissions & ~devices)) {
        return false;
    }
    const bool allowed = AskMediaPermission(browser, requesting_origin.ToWString(),
        requested_permissions & CEF_PERMISSION_TYPE_MIC_STREAM,
        requested_permissions & CEF_PERMISSION_TYPE_CAMERA_STREAM);
    LogPermission(allowed ? L"  -> allowed" : L"  -> denied");
    callback->Continue(allowed ? CEF_PERMISSION_RESULT_ACCEPT
                               : CEF_PERMISSION_RESULT_DENY);
    return true;
#else
    return false;
#endif
}

bool WebviewHandler::OnProcessMessageReceived(
    CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
     CefProcessId source_process, CefRefPtr<CefProcessMessage> message)
{
	std::string message_name = message->GetName();
    if (message_name == kFocusedNodeChangedMessage)
    {
        bool editable = message->GetArgumentList()->GetBool(0);
        onFocusedNodeChangeMessage(browser->GetIdentifier(), editable);
        if (editable) {
            onImeCompositionRangeChangedMessage(browser->GetIdentifier(), message->GetArgumentList()->GetInt(1), message->GetArgumentList()->GetInt(2), message->GetArgumentList()->GetInt(3));
        }
    }
    else if(message_name == kJSCallCppFunctionMessage)
    {
        CefString fun_name = message->GetArgumentList()->GetString(0);
		CefString param = message->GetArgumentList()->GetString(1);
		int js_callback_id = message->GetArgumentList()->GetInt(2);

        if (fun_name.empty() || !(browser.get())) {
		    return false;
	    }

        onJavaScriptChannelMessage(
            fun_name,param,stringpatch::to_string(js_callback_id), browser->GetIdentifier(), frame->GetIdentifier().ToString());
    }
    else if(message_name == kEvaluateCallbackMessage){
        CefString callbackId = message->GetArgumentList()->GetString(0);
        CefRefPtr<CefValue> param = message->GetArgumentList()->GetValue(1);

        if(!callbackId.empty()){
            auto it = js_callbacks_.find(callbackId.ToString());
            if(it != js_callbacks_.end()){
                it->second(param);
                js_callbacks_.erase(it);
            }
        }
    }
    return false;
}

// ---- 6browser patch: downloads ----
#include <filesystem>
#ifdef _WIN32
#include <shlobj.h>
#endif

static std::filesystem::path UniquePath(std::filesystem::path p) {
    std::error_code ec;
    if (!std::filesystem::exists(p, ec)) return p;
    const auto stem = p.stem().wstring();
    const auto ext = p.extension().wstring();
    for (int i = 1; i < 10000; i++) {
        auto candidate = p.parent_path() / (stem + L" (" + std::to_wstring(i) + L")" + ext);
        if (!std::filesystem::exists(candidate, ec)) return candidate;
    }
    return p;
}

bool WebviewHandler::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                                      CefRefPtr<CefDownloadItem> download_item,
                                      const CefString& suggested_name,
                                      CefRefPtr<CefBeforeDownloadCallback> callback) {
#ifdef _WIN32
    PWSTR dir = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr, &dir)) && dir) {
        // Strip any directory part from the server-suggested name.
        std::filesystem::path name = std::filesystem::path(suggested_name.ToWString()).filename();
        if (name.empty()) name = L"download";
        std::filesystem::path target = UniquePath(std::filesystem::path(dir) / name);
        CoTaskMemFree(dir);
        callback->Continue(CefString(target.wstring()), false);
        return true;
    }
#endif
    // Other platforms (not yet handled natively): let CEF ask the user.
    callback->Continue(CefString(), true);
    return true;
}

void WebviewHandler::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefDownloadItem> download_item,
                                       CefRefPtr<CefDownloadItemCallback> callback) {
    if (!onDownloadEvent) return;
    int state = 0;
    if (download_item->IsComplete()) state = 1;
    else if (download_item->IsCanceled() || download_item->IsInterrupted()) state = 2;
    onDownloadEvent(static_cast<int>(download_item->GetId()),
                    download_item->GetURL().ToString(),
                    download_item->GetFullPath().ToString(),
                    download_item->GetReceivedBytes(),
                    download_item->GetTotalBytes(),
                    state,
                    isIncognito(browser->GetIdentifier()));
}

void WebviewHandler::OnTitleChange(CefRefPtr<CefBrowser> browser,
                                  const CefString& title) {
    //todo: title change
    if(onTitleChangedEvent) {
        onTitleChangedEvent(browser->GetIdentifier(), title);
    }
}

void WebviewHandler::OnAddressChange(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                     const CefString& url) {
    if(onUrlChangedEvent) {
        onUrlChangedEvent(browser->GetIdentifier(), url);
    }
}

bool WebviewHandler::OnCursorChange(CefRefPtr<CefBrowser> browser,
                            CefCursorHandle cursor,
                            cef_cursor_type_t type,
                            const CefCursorInfo& custom_cursor_info){
    if(onCursorChangedEvent) {
        onCursorChangedEvent(browser->GetIdentifier(), type);
        return true;
    }
    return false;
}

bool WebviewHandler::OnTooltip(CefRefPtr<CefBrowser> browser, CefString& text) {
    if(onTooltipEvent) {
        onTooltipEvent(browser->GetIdentifier(), text);
        return true;
    }
    return false;
}

bool WebviewHandler::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                      cef_log_severity_t level,
                                      const CefString& message,
                                      const CefString& source,
                                      int line){
    if(onConsoleMessageEvent){
        onConsoleMessageEvent(browser->GetIdentifier(), level, message, source, line);
    }
    return false;
}

void WebviewHandler::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    if (!browser->IsPopup()) {
        browser_map_.emplace(browser->GetIdentifier(), browser_info());
        browser_map_[browser->GetIdentifier()].browser = browser;
    }
}

bool WebviewHandler::DoClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();    
    // Allow the close. For windowed browsers this will result in the OS close
    // event being sent.
    return false;
}

void WebviewHandler::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
}

bool WebviewHandler::OnBeforePopup(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefFrame> frame,
                                  int popup_id,
                                  const CefString& target_url,
                                  const CefString& target_frame_name,
                                  CefLifeSpanHandler::WindowOpenDisposition target_disposition,
                                  bool user_gesture,
                                  const CefPopupFeatures& popupFeatures,
                                  CefWindowInfo& windowInfo,
                                  CefRefPtr<CefClient>& client,
                                  CefBrowserSettings& settings,
                                  CefRefPtr<CefDictionaryValue>& extra_info,
                                  bool* no_javascript_access) {
    // 6browser patch: Document Picture-in-Picture (e.g. Google Meet's "Open
    // picture-in-picture") must get its own popup. Cancelling it, as done for
    // ordinary popups below, crashes the browser process inside libcef. Use
    // CEF's default handling (a native always-on-top window, as cefclient
    // does); a null client keeps it out of our off-screen browser bookkeeping.
    if (target_disposition == CEF_WOD_NEW_PICTURE_IN_PICTURE) {
        client = nullptr;
#if defined(OS_WIN)
        // Off-screen browsers have no native video PiP, so this window also
        // hosts <video> PiP (see the shim in webview_app.cc). Make it behave
        // like Chrome's: always on top, in the bottom-right corner of the
        // monitor that shows the app. Sizes from the page are in DIP.
        HWND app = browser->GetHost()->GetWindowHandle();
        MONITORINFO monitor = {sizeof(monitor)};
        if (GetMonitorInfoW(MonitorFromWindow(app, MONITOR_DEFAULTTONEAREST), &monitor)) {
            const UINT dpi = (app && GetDpiForWindow(app)) ? GetDpiForWindow(app) : 96;
            const double scale = dpi / 96.0;
            const RECT& work = monitor.rcWork;
            const int width = static_cast<int>(
                (popupFeatures.widthSet ? popupFeatures.width : 480) * scale);
            const int height = static_cast<int>(
                (popupFeatures.heightSet ? popupFeatures.height : 270) * scale);
            const int margin = static_cast<int>(16 * scale);
            windowInfo.bounds.width = (std::min)(width, static_cast<int>(work.right - work.left));
            windowInfo.bounds.height = (std::min)(height, static_cast<int>(work.bottom - work.top));
            windowInfo.bounds.x = work.right - windowInfo.bounds.width - margin;
            // Bounds are the content area; CEF adds the frame around it.
            windowInfo.bounds.y = work.bottom - windowInfo.bounds.height - margin -
                                  GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
        }
        windowInfo.ex_style |= WS_EX_TOPMOST;
#endif
        return false;
    }
    // 6browser patch: target=_blank links, window.open and Ctrl/middle clicks
    // become tabs in the host, as in Chrome. Without a user gesture it is an
    // unrequested popup, which Chrome's popup blocker drops too.
    openInNewTab(browser, target_url, target_disposition, user_gesture);
    return true;
}

// 6browser patch: browser shortcuts the page did not use (Ctrl+F outside
// Google Docs, Ctrl+K outside Slack) run in the host, as in Chrome.
bool WebviewHandler::OnKeyEvent(CefRefPtr<CefBrowser> browser,
                                const CefKeyEvent& event,
                                CefEventHandle os_event) {
    if (event.type == KEYEVENT_RAWKEYDOWN && onUnhandledKeyEvent) {
        onUnhandledKeyEvent(browser->GetIdentifier(), event.windows_key_code,
                            static_cast<int>(event.modifiers));
    }
    return false;
}

bool WebviewHandler::OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                                      CefRefPtr<CefFrame> frame,
                                      const CefString& target_url,
                                      CefRequestHandler::WindowOpenDisposition target_disposition,
                                      bool user_gesture) {
    switch (target_disposition) {
        case CEF_WOD_NEW_FOREGROUND_TAB:
        case CEF_WOD_NEW_BACKGROUND_TAB:
        case CEF_WOD_NEW_POPUP:
        case CEF_WOD_NEW_WINDOW:
            openInNewTab(browser, target_url, target_disposition, user_gesture);
            return true;
        default:
            return false;
    }
}

namespace {
// Schemes Chromium loads itself. Any other scheme belongs to an app on the
// computer (mailto:, tg:, zoommtg:...), which Chromium cannot open.
bool IsExternalLink(const std::string& url) {
    static const char* const kWebSchemes[] = {
        "http", "https", "file", "data", "blob", "filesystem", "about",
        "javascript", "ws", "wss", "chrome", "chrome-extension",
        "chrome-untrusted", "chrome-error", "chrome-search", "devtools",
        "view-source", "isolated-app",
    };
    const size_t colon = url.find(':');
    if (colon == 0 || colon == std::string::npos) return false;
    std::string scheme = url.substr(0, colon);
    for (char& c : scheme) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
        const bool valid = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
                           c == '+' || c == '-' || c == '.';
        if (!valid) return false;
    }
    for (const char* web : kWebSchemes) {
        if (scheme == web) return false;
    }
    return true;
}
}  // namespace

bool WebviewHandler::OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                                    CefRefPtr<CefFrame> frame,
                                    CefRefPtr<CefRequest> request,
                                    bool user_gesture,
                                    bool is_redirect) {
    const std::string url = request->GetURL().ToString();
    if (!IsExternalLink(url)) return false;
    // Cancelling keeps the page as it is, as in Chrome. A typed (or
    // bookmarked) link was not asked for by the page on screen.
    const bool typed = (request->GetTransitionType() & TT_SOURCE_MASK) == TT_EXPLICIT;
    offerExternalLink(browser, url, typed ? "" : frame->GetURL().ToString());
    return true;
}

// Like Chrome, a page gets one external link until the user next clicks or
// types, so a script cannot keep launching apps or prompts.
void WebviewHandler::offerExternalLink(CefRefPtr<CefBrowser> browser, const std::string& url,
                                       const std::string& source) {
    auto it = browser_map_.find(browser->GetIdentifier());
    if (it == browser_map_.end() || !it->second.external_link_allowed) return;
    it->second.external_link_allowed = false;
    if (onExternalLinkEvent) onExternalLinkEvent(browser->GetIdentifier(), url, source);
}

void WebviewHandler::openInNewTab(CefRefPtr<CefBrowser> browser, const CefString& url,
                                  int disposition, bool user_gesture) {
    const std::string target = url.ToString();
    if (!user_gesture || target.empty()) return;
    // target=_blank links to apps would leave an empty tab behind.
    if (IsExternalLink(target)) {
        auto main = browser->GetMainFrame();
        offerExternalLink(browser, target, main ? main->GetURL().ToString() : "");
        return;
    }
    if (onNewWindowEvent) {
        onNewWindowEvent(browser->GetIdentifier(), target, disposition);
    } else {
        loadUrl(browser->GetIdentifier(), target);
    }
}

void WebviewHandler::OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                               TerminationStatus status,
                                               int error_code,
                                               const CefString& error_string) {
    CEF_REQUIRE_UI_THREAD();
    auto it = browser_map_.find(browser->GetIdentifier());
    if (it == browser_map_.end()) return;
    // A crashed renderer leaves a frozen frame. Reload once; if the page
    // crashes again soon, show an error page instead of looping.
    const auto now = std::chrono::steady_clock::now();
    const bool recent = it->second.last_crash.time_since_epoch().count() != 0 &&
                        now - it->second.last_crash < std::chrono::seconds(30);
    it->second.last_crash = now;
    if (!recent) {
        browser->Reload();
        return;
    }
    const std::string html =
        "<!doctype html><meta charset=utf-8><title>Page crashed</title>"
        "<style>body{font:15px system-ui,sans-serif;color:#1d1d1f;display:grid;"
        "place-items:center;height:100vh;margin:0}div{text-align:center}"
        "h1{font-size:22px;font-weight:600;margin:0 0 8px}p{color:#6e6e73;margin:0}"
        "@media(prefers-color-scheme:dark){body{background:#1c1c1e;color:#f5f5f7}"
        "p{color:#a1a1a6}}</style><div><h1>This page crashed</h1>"
        "<p>Go back, or try the page again later.</p></div>";
    browser->GetMainFrame()->LoadURL("data:text/html;charset=utf-8," +
                                     CefURIEncode(html, false).ToString());
}

void WebviewHandler::OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next)
{
    executeJavaScript(browser->GetIdentifier(), "document.activeElement.blur()");
}

bool WebviewHandler::OnSetFocus(CefRefPtr<CefBrowser> browser, FocusSource source)
{
    return false;
}

void WebviewHandler::OnGotFocus(CefRefPtr<CefBrowser> browser)
{
}

void WebviewHandler::OnLoadError(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                ErrorCode errorCode,
                                const CefString& errorText,
                                const CefString& failedUrl) {
    CEF_REQUIRE_UI_THREAD();

    // 6browser patch: upstream replaced the failed frame with its own data:
    // URI page here. Chromium already commits its own error page (with Reload
    // and the failed URL kept in history and the address bar), and loading a
    // new URL over it could also cancel a navigation that was about to
    // recover, such as the HTTPS-Upgrades fallback to http://.
}

void WebviewHandler::OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                 CefLoadHandler::TransitionType transition_type) {
}

// 6browser patch: the host's load start/end follow the whole tab, as the
// spinner in Chrome does: from the moment a navigation starts (before the
// server answers, so Stop works) until every frame is done. OnLoadStart and
// OnLoadEnd fire per frame and only after commit, which made the spinner
// flicker with iframes and ads.
void WebviewHandler::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                          bool isLoading,
                                          bool canGoBack,
                                          bool canGoForward) {
    const std::string url = browser->GetMainFrame() ? browser->GetMainFrame()->GetURL().ToString() : "";
    if (isLoading) {
        if (onLoadStart) onLoadStart(browser->GetIdentifier(), url);
    } else {
        if (onLoadEnd) onLoadEnd(browser->GetIdentifier(), url);
    }
}

void WebviewHandler::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                               int httpStatusCode) {
    // 6browser patch: this (Alloy, off-screen) engine has no extension support
    // and Chrome's Web Store install API crashes the browser process inside
    // libcef. The API is added by Chrome's bindings after the page context is
    // created, so remove it once the Web Store page has loaded.
    if (frame->IsMain()) reportZoom(browser);
    const std::string loaded = frame->GetURL().ToString();
    if (loaded.rfind("https://chromewebstore.google.com/", 0) == 0 ||
        loaded.rfind("https://chrome.google.com/webstore", 0) == 0) {
        frame->ExecuteJavaScript(
            "try{if(window.chrome){delete chrome.webstorePrivate;}}catch(e){}",
            frame->GetURL(), 0);
    }
}

void WebviewHandler::CloseAllBrowsers(bool force_close) {
    if (browser_map_.empty()){
        return;
    }
    
    for (auto& it : browser_map_){
        it.second.browser->GetHost()->CloseBrowser(force_close);
        it.second.browser = nullptr;
    }
    browser_map_.clear();
}

void WebviewHandler::closeBrowser(int browserId)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::closeBrowser, this, browserId));
        return;
    }
    if (focused_browser_id_ == browserId) focused_browser_id_ = 0;
    auto it = browser_map_.find(browserId);
    if(it != browser_map_.end()){
        it->second.browser->GetHost()->CloseBrowser(true);
        it->second.browser = nullptr;
        browser_map_.erase(it);
    }
    // 6browser patch: drop the incognito session once its last browser is gone.
    m_incognitoBrowsers.erase(browserId);
    if (m_incognitoBrowsers.empty()) m_incognitoContext = nullptr;
}

void WebviewHandler::createBrowser(std::string url, std::function<void(int)> callback, bool incognito)
{
#ifndef OS_MAC
    if(!CefCurrentlyOn(TID_UI)) {
		CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::createBrowser, this, url, callback, incognito));
		return;
	}
#endif
    CefBrowserSettings browser_settings ;
    // Capped at 60 by CEF; ignored entirely when external begin frame drives the
    // frames (GPU path below). Kept for the software fallback path.
    browser_settings.windowless_frame_rate = 60;
    CefWindowInfo window_info;
    window_info.SetAsWindowless(0);
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    // Enable GPU shared-texture rendering: CEF delivers frames via
    // OnAcceleratedPaint (a D3D11 shared texture on Windows, an IOSurface on
    // macOS) instead of the software OnPaint CPU buffer. Requires the GPU to be
    // left enabled (see WebviewApp).
    window_info.shared_texture_enabled = true;
    // Drive frame production ourselves so the rate can follow the display's
    // refresh (>60 Hz) instead of being capped at windowless_frame_rate. The
    // platform layer ticks SendExternalBeginFrame on each vblank — Windows from
    // an IDXGIOutput vblank wait, macOS from a CVDisplayLink.
    window_info.external_begin_frame_enabled = true;
#endif
    CefRefPtr<CefRequestContext> request_context;  // null = the default (persistent) profile
    if (incognito) {
        if (!m_incognitoContext) {
            // Empty cache_path = in-memory context: nothing is written to disk.
            m_incognitoContext = CefRequestContext::CreateContext(CefRequestContextSettings(), nullptr);
        }
        request_context = m_incognitoContext;
    }
    auto created = CefBrowserHost::CreateBrowserSync(window_info, this, url, browser_settings, nullptr, request_context);
    if (incognito) {
        m_incognitoBrowsers.insert(created->GetIdentifier());
        m_privateIds.insert(created->GetIdentifier());
    }
    callback(created->GetIdentifier());
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    // The GPU shared-texture path is the only render path on this build (no
    // OnPaint fallback). If no accelerated frame arrives shortly, the GPU
    // compositor likely can't export a shared texture — warn so a black webview
    // isn't silent.
    CefPostDelayedTask(TID_UI, base::BindOnce(&WebviewHandler::warnIfNoAcceleratedFrame, this), 5000);
#endif
}

void WebviewHandler::warnIfNoAcceleratedFrame() {
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    if (!received_accelerated_frame_ && !gpu_warning_logged_) {
        gpu_warning_logged_ = true;
        fprintf(stderr,
                "[webview_cef] WARNING: no GPU accelerated-paint frame after 5s. "
                "This build renders the webview only via the GPU shared-texture "
                "path; if it appears black, the GPU compositor may be unavailable "
                "(headless, VM, software GL, or a crashed GPU process).\n");
        fflush(stderr);
    }
#endif
}

void WebviewHandler::sendExternalBeginFrame() {
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sendExternalBeginFrame, this));
        return;
    }
    for (auto& kv : browser_map_) {
        if (kv.second.browser && kv.second.browser->GetHost()) {
            kv.second.browser->GetHost()->SendExternalBeginFrame();
        }
    }
#endif
}

// 6browser patch: |deltaX|/|deltaY| are the distance to scroll in view
// coordinates (DIP), positive scrolls right/down. Fractions are kept per
// browser so slow trackpad and smooth-wheel input is not rounded away.
void WebviewHandler::sendScrollEvent(int browserId, int x, int y, double deltaX, double deltaY, int modifiers) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sendScrollEvent, this, browserId, x, y, deltaX, deltaY, modifiers));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end() || !it->second.browser) return;
    auto& info = it->second;
    info.scroll_rest_x += deltaX;
    info.scroll_rest_y += deltaY;

    // Chromium scrolls content up/left for positive deltas.
    int sendX, sendY;
#ifdef _WIN32
    // CEF reads Windows deltas as wheel units (WHEEL_DELTA a notch) and turns
    // them into pixels with the system's lines/chars per notch, truncating;
    // invert that so the page moves by exactly the requested distance.
    UINT lines = 3, chars = 1;
    SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
    SystemParametersInfo(SPI_GETWHEELSCROLLCHARS, 0, &chars, 0);
    if (lines == 0 || lines == WHEEL_PAGESCROLL) lines = 3;
    if (chars == 0) chars = 1;
    const double pxPerUnitY = lines * (100.0 / 3.0) / WHEEL_DELTA;
    const double pxPerUnitX = chars * (100.0 / 3.0) / WHEEL_DELTA;
    sendX = static_cast<int>(std::lround(-info.scroll_rest_x / pxPerUnitX));
    sendY = static_cast<int>(std::lround(-info.scroll_rest_y / pxPerUnitY));
    // What CEF will actually scroll for these units (same float math as
    // CefBrowserPlatformDelegateNativeWin::GetUiWheelEventOffset).
    const int movedX = static_cast<int>(float(sendX) / WHEEL_DELTA * static_cast<float>(chars) * (100.0f / 3.0f));
    const int movedY = static_cast<int>(float(sendY) / WHEEL_DELTA * static_cast<float>(lines) * (100.0f / 3.0f));
    info.scroll_rest_x += movedX;
    info.scroll_rest_y += movedY;
    if (movedX == 0) sendX = 0;
    if (movedY == 0) sendY = 0;
#else
    sendX = static_cast<int>(-info.scroll_rest_x);
    sendY = static_cast<int>(-info.scroll_rest_y);
    info.scroll_rest_x += sendX;
    info.scroll_rest_y += sendY;
#endif
    if (sendX == 0 && sendY == 0) return;

    CefMouseEvent ev;
    ev.x = x;
    ev.y = y;
    ev.modifiers = static_cast<uint32_t>(modifiers);
    info.browser->GetHost()->SendMouseWheelEvent(ev, sendX, sendY);
    // Ctrl+wheel zooms the page (unless the page handles it); the zoom
    // indicator only learns about it from here.
    if (modifiers & EVENTFLAG_CONTROL_DOWN) {
        CefPostDelayedTask(TID_UI, base::BindOnce(&WebviewHandler::reportZoomFor, this, browserId), 120);
    }
}

void WebviewHandler::setVisible(int browserId, bool visible) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::setVisible, this, browserId, visible));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end() || !it->second.browser) return;
    auto host = it->second.browser->GetHost();
    host->WasHidden(!visible);
    if (visible) host->Invalidate(PET_VIEW);
}

void WebviewHandler::reportZoomFor(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser) reportZoom(it->second.browser);
}

void WebviewHandler::changeSize(int browserId, float a_dpi, int w, int h)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::changeSize, this, browserId, a_dpi, w, h));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser) {
        const bool scaleChanged = it->second.dpi != a_dpi;
        it->second.dpi = a_dpi;
        it->second.width = w;
        it->second.height = h;
        // 6browser patch: moving to a monitor with another scale keeps the
        // logical size, so only this makes the page re-render sharply.
        if (scaleChanged) it->second.browser->GetHost()->NotifyScreenInfoChanged();
        it->second.browser->GetHost()->WasResized();
    }
}

// 6browser patch: input runs on the CEF UI thread (browser_map_ belongs to
// it), carries the modifier keys (Ctrl+click opens a new tab, Shift+click
// extends a selection) and the click count (double-click selects a word).
void WebviewHandler::cursorClick(int browserId, int x, int y, bool up, int button, int clickCount, int modifiers)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::cursorClick, this, browserId, x, y, up, button, clickCount, modifiers));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end() || !it->second.browser) return;
    auto host = it->second.browser->GetHost();
    if (!up) it->second.external_link_allowed = true;
    CefMouseEvent ev;
    ev.x = x;
    ev.y = y;
    clickCount = clickCount < 1 ? 1 : clickCount;
    if (button == MBT_RIGHT || button == MBT_MIDDLE) {
        ev.modifiers = modifiers | (button == MBT_RIGHT ? EVENTFLAG_RIGHT_MOUSE_BUTTON : EVENTFLAG_MIDDLE_MOUSE_BUTTON);
        host->SendMouseClickEvent(ev, static_cast<CefBrowserHost::MouseButtonType>(button), up, clickCount);
        return;
    }
    ev.modifiers = modifiers | EVENTFLAG_LEFT_MOUSE_BUTTON;
    it->second.left_button_down = !up;
    if (up && it->second.is_dragging) {
        host->DragTargetDrop(ev);
        host->DragSourceEndedAt(x, y, DRAG_OPERATION_MOVE);
        host->DragSourceSystemDragEnded();
        it->second.is_dragging = false;
    } else {
        host->SendMouseClickEvent(ev, CefBrowserHost::MouseButtonType::MBT_LEFT, up, clickCount);
    }
}

void WebviewHandler::cursorMove(int browserId, int x , int y, bool dragging, int modifiers)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::cursorMove, this, browserId, x, y, dragging, modifiers));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end() || !it->second.browser) return;
    CefMouseEvent ev;
    ev.x = x;
    ev.y = y;
    ev.modifiers = modifiers | (dragging ? EVENTFLAG_LEFT_MOUSE_BUTTON : 0);
    if(it->second.is_dragging && dragging) {
        it->second.browser->GetHost()->DragTargetDragOver(ev, DRAG_OPERATION_EVERY);
    } else {
        it->second.browser->GetHost()->SendMouseMoveEvent(ev, false);
    }
}

// The pointer left the view: hover effects and tooltips end, as in Chrome.
void WebviewHandler::cursorLeave(int browserId, int x, int y)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::cursorLeave, this, browserId, x, y));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end() || !it->second.browser || it->second.is_dragging) return;
    CefMouseEvent ev;
    ev.x = x;
    ev.y = y;
    it->second.browser->GetHost()->SendMouseMoveEvent(ev, true);
}

// A press the host lost (Flutter cancelled the pointer): end it without
// dropping anything.
void WebviewHandler::cursorCancel(int browserId, int x, int y, int button)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::cursorCancel, this, browserId, x, y, button));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end() || !it->second.browser) return;
    auto host = it->second.browser->GetHost();
    if (it->second.is_dragging) {
        host->DragTargetDragLeave();
        host->DragSourceEndedAt(x, y, DRAG_OPERATION_NONE);
        host->DragSourceSystemDragEnded();
        it->second.is_dragging = false;
        return;
    }
    cursorClick(browserId, x, y, true, button, 1, 0);
}

bool WebviewHandler::StartDragging(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefDragData> drag_data,
                                  DragOperationsMask allowed_ops,
                                  int x,
                                  int y){
    auto it = browser_map_.find(browser->GetIdentifier());
    // 6browser patch: a quick flick can be released before the renderer asks
    // to start the drag; starting it then left the page stuck in a drag.
    if (it == browser_map_.end() || !it->second.browser || !it->second.browser->IsSame(browser) ||
        !it->second.left_button_down) {
        return false;
    }
    {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        ev.modifiers = EVENTFLAG_LEFT_MOUSE_BUTTON;
        it->second.browser->GetHost()->DragTargetDragEnter(drag_data, ev, DRAG_OPERATION_EVERY);
        it->second.is_dragging = true;
    }
    return true;
}

void WebviewHandler::OnImeCompositionRangeChanged(CefRefPtr<CefBrowser> browser, const CefRange &selection_range, const CefRenderHandler::RectList &character_bounds)
{
    CEF_REQUIRE_UI_THREAD();
    auto it = browser_map_.find(browser->GetIdentifier());
    if(it == browser_map_.end() || !it->second.browser.get() || browser->IsPopup()) {
        return;
    }
    if (!character_bounds.empty()) {
        if (it->second.is_ime_commit) {
            auto lastCharacter = character_bounds.back();
            it->second.prev_ime_position = lastCharacter;
            onImeCompositionRangeChangedMessage(browser->GetIdentifier(), lastCharacter.x + lastCharacter.width, lastCharacter.y + lastCharacter.height, lastCharacter.height);
            it->second.is_ime_commit = false;
        }
        else
        {
            auto firstCharacter = character_bounds.front();
            if (firstCharacter != it->second.prev_ime_position) {
                it->second.prev_ime_position = firstCharacter;
                onImeCompositionRangeChangedMessage(browser->GetIdentifier(), firstCharacter.x, firstCharacter.y + firstCharacter.height, firstCharacter.height);
            }
        }
    }
}

void WebviewHandler::sendKeyEvent(CefKeyEvent& ev)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefKeyEvent copy = ev;
        CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<WebviewHandler> self, CefKeyEvent e) {
            self->sendKeyEvent(e);
        }, CefRefPtr<WebviewHandler>(this), copy));
        return;
    }
    auto browser = getFocusedBrowser();
    if (!browser.get()) {
        return;
    }
    if (ev.type == KEYEVENT_RAWKEYDOWN || ev.type == KEYEVENT_KEYDOWN) {
        auto it = browser_map_.find(browser->GetIdentifier());
        if (it != browser_map_.end()) it->second.external_link_allowed = true;
    }
    browser->GetHost()->SendKeyEvent(ev);
}

void WebviewHandler::loadUrl(int browserId, std::string url)
{
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->LoadURL(url);
    }
}

void WebviewHandler::goForward(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->GoForward();
    }
}

void WebviewHandler::goBack(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->GoBack();
    }
}

void WebviewHandler::reload(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->Reload();
    }
}

void WebviewHandler::openDevTools(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefWindowInfo windowInfo;
#ifdef OS_WIN
        windowInfo.SetAsPopup(nullptr, "DevTools");
#endif
        it->second.browser->GetHost()->ShowDevTools(windowInfo, this, CefBrowserSettings(), CefPoint());
    }
}

void WebviewHandler::inspectElementAt(int browserId, int x, int y) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefWindowInfo windowInfo;
#ifdef OS_WIN
        windowInfo.SetAsPopup(nullptr, "DevTools");
#endif
        it->second.browser->GetHost()->ShowDevTools(windowInfo, this, CefBrowserSettings(), CefPoint(x, y));
    }
}

void WebviewHandler::editCommand(int browserId, const std::string& command) {
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end()) return;
    CefRefPtr<CefFrame> frame = it->second.browser->GetFocusedFrame();
    if (!frame) frame = it->second.browser->GetMainFrame();
    if (command == "undo") frame->Undo();
    else if (command == "redo") frame->Redo();
    else if (command == "cut") frame->Cut();
    else if (command == "copy") frame->Copy();
    else if (command == "paste") frame->Paste();
    else if (command == "delete") frame->Delete();
    else if (command == "selectAll") frame->SelectAll();
}

void WebviewHandler::stopLoad(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) it->second.browser->StopLoad();
}

void WebviewHandler::reloadIgnoreCache(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) it->second.browser->ReloadIgnoreCache();
}

void WebviewHandler::zoom(int browserId, int command) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::zoom, this, browserId, command));
        return;
    }
    auto it = browser_map_.find(browserId);
    if (it == browser_map_.end()) return;
    auto host = it->second.browser->GetHost();
    host->Zoom(command < 0 ? CEF_ZOOM_COMMAND_OUT
               : command > 0 ? CEF_ZOOM_COMMAND_IN
                             : CEF_ZOOM_COMMAND_RESET);
    reportZoom(it->second.browser);
}

// Chromium keeps zoom per site, so the level can also change on navigation.
void WebviewHandler::reportZoom(CefRefPtr<CefBrowser> browser) {
    if (onZoomChangedEvent) {
        onZoomChangedEvent(browser->GetIdentifier(), browser->GetHost()->GetZoomLevel());
    }
}

void WebviewHandler::find(int browserId, const std::string& text, bool forward, bool matchCase, bool findNext) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) it->second.browser->GetHost()->Find(text, forward, matchCase, findNext);
}

void WebviewHandler::stopFinding(int browserId, bool clearSelection) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) it->second.browser->GetHost()->StopFinding(clearSelection);
}

void WebviewHandler::print(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) it->second.browser->GetHost()->Print();
}

void WebviewHandler::OnFindResult(CefRefPtr<CefBrowser> browser, int identifier, int count,
                                  const CefRect& selectionRect, int activeMatchOrdinal, bool finalUpdate) {
    if (onFindResultEvent) onFindResultEvent(browser->GetIdentifier(), count, activeMatchOrdinal, finalUpdate);
}

void WebviewHandler::startDownload(int browserId, const std::string& url) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetHost()->StartDownload(url);
    }
}

void WebviewHandler::OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                                         CefRefPtr<CefFrame> frame,
                                         CefRefPtr<CefContextMenuParams> params,
                                         CefRefPtr<CefMenuModel> model) {
    // DevTools windows share this client; leave their native menu alone.
    if (browser_map_.find(browser->GetIdentifier()) == browser_map_.end()) return;
    // Off-screen rendering cannot show the native menu, so hand the details
    // to the host and show nothing here.
    model->Clear();
    if (!onContextMenuEvent) return;
    context_menu_info info;
    info.x = params->GetXCoord();
    info.y = params->GetYCoord();
    info.typeFlags = static_cast<int>(params->GetTypeFlags());
    info.mediaType = static_cast<int>(params->GetMediaType());
    info.editFlags = static_cast<int>(params->GetEditStateFlags());
    info.linkUrl = params->GetLinkUrl().ToString();
    info.srcUrl = params->GetSourceUrl().ToString();
    info.pageUrl = params->GetPageUrl().ToString();
    info.selectionText = params->GetSelectionText().ToString();
    info.canGoBack = browser->CanGoBack();
    info.canGoForward = browser->CanGoForward();
    onContextMenuEvent(browser->GetIdentifier(), info);
}

void WebviewHandler::imeSetComposition(int browserId, std::string text)
{
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }

    CefString cTextStr = CefString(text);

    std::vector<CefCompositionUnderline> underlines;
    cef_composition_underline_t underline = {};
    underline.range.from = 0;
    underline.range.to = static_cast<int>(0 + cTextStr.length());
    underline.color = ColorUNDERLINE;
    underline.background_color = ColorBKCOLOR;
    underline.thick = 0;
    underline.style = CEF_CUS_DOT;
    underlines.push_back(underline);

    // Keeps the caret at the end of the composition
    auto selection_range_end = static_cast<int>(0 + cTextStr.length());
    // Keep the caret at the end of the composition (matches cefclient).
    CefRange selection_range = CefRange(selection_range_end, selection_range_end);
    it->second.browser->GetHost()->ImeSetComposition(cTextStr, underlines, CefRange(UINT32_MAX, UINT32_MAX), selection_range);
}

void WebviewHandler::imeCommitText(int browserId, std::string text)
{
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }

    CefString cTextStr = CefString(text);
    it->second.is_ime_commit = true;

    std::vector<CefCompositionUnderline> underlines;
    auto selection_range_end = static_cast<int>(0 + cTextStr.length());
    CefRange selection_range = CefRange(selection_range_end, selection_range_end);
    // Establish the composition on all platforms before committing so the commit
    // has a live composition to replace (previously skipped on Windows).
    it->second.browser->GetHost()->ImeSetComposition(cTextStr, underlines, CefRange(UINT32_MAX, UINT32_MAX), selection_range);
    it->second.browser->GetHost()->ImeCommitText(cTextStr, CefRange(UINT32_MAX, UINT32_MAX), 0);

}

void WebviewHandler::setClientFocus(int browserId, bool focus)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::setClientFocus, this, browserId, focus));
        return;
    }
    if (focus) {
        focused_browser_id_ = browserId;
    } else if (focused_browser_id_ == browserId) {
        focused_browser_id_ = 0;
    }
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }
    it->second.wants_focus = focus;
    if (focus) {
        // Re-arm the first-frame re-assert (handles a SetFocus that lands before
        // the browser is render/input-ready under external_begin_frame).
        it->second.focus_reasserted = false;
    }
    it->second.browser->GetHost()->SetFocus(focus);
}

CefRefPtr<CefBrowser> WebviewHandler::getFocusedBrowser()
{
    auto it = browser_map_.find(focused_browser_id_);
    return it == browser_map_.end() ? nullptr : it->second.browser;
}

void WebviewHandler::imeSetCompositionNative(const std::wstring& text, int cursor)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeSetCompositionNative, this, text, cursor));
        return;
    }
    auto browser = getFocusedBrowser();
    if (!browser.get()) {
        return;
    }
    CefString cTextStr;
    cTextStr.FromWString(text);

    std::vector<CefCompositionUnderline> underlines;
    cef_composition_underline_t underline = {};
    underline.range.from = 0;
    underline.range.to = static_cast<int>(cTextStr.length());
    underline.color = ColorUNDERLINE;
    underline.background_color = ColorBKCOLOR;
    underline.thick = 0;
    underline.style = CEF_CUS_DOT;
    underlines.push_back(underline);

    const int len = static_cast<int>(cTextStr.length());
    const int caret = (cursor < 0 || cursor > len) ? len : cursor;
    CefRange selection_range(caret, caret);
    browser->GetHost()->ImeSetComposition(cTextStr, underlines,
        CefRange(UINT32_MAX, UINT32_MAX), selection_range);
}

void WebviewHandler::imeCommitTextNative(const std::wstring& text)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeCommitTextNative, this, text));
        return;
    }
    auto browser = getFocusedBrowser();
    if (!browser.get()) {
        return;
    }
    CefString cTextStr;
    cTextStr.FromWString(text);
    browser->GetHost()->ImeCommitText(cTextStr, CefRange(UINT32_MAX, UINT32_MAX), 0);
}

void WebviewHandler::imeFinishComposition()
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeFinishComposition, this));
        return;
    }
    auto browser = getFocusedBrowser();
    if (!browser.get()) {
        return;
    }
    browser->GetHost()->ImeFinishComposingText(false);
}

void WebviewHandler::imeCancelComposition()
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeCancelComposition, this));
        return;
    }
    auto browser = getFocusedBrowser();
    if (browser.get()) browser->GetHost()->ImeCancelComposition();
}

void WebviewHandler::setCookie(const std::string& domain, const std::string& key, const std::string& value){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if(manager){
        CefCookie cookie;
		CefString(&cookie.path).FromASCII("/");
		CefString(&cookie.name).FromString(key.c_str());
		CefString(&cookie.value).FromString(value.c_str());

		if (!domain.empty()) {
			CefString(&cookie.domain).FromString(domain.c_str());
		}

		cookie.httponly = true;
		cookie.secure = false;
		std::string httpDomain = "https://" + domain + "/cookiestorage";
		manager->SetCookie(httpDomain, cookie, nullptr);
    }
}

void WebviewHandler::deleteCookie(const std::string& domain, const std::string& key)
{
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (manager) {
        std::string httpDomain = "https://" + domain + "/cookiestorage";
        manager->DeleteCookies(httpDomain, key, nullptr);
    }
}

void WebviewHandler::visitAllCookies(std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (!manager)
	{
		return;
	}

    CefRefPtr<WebviewCookieVisitor> cookieVisitor = new WebviewCookieVisitor();
    cookieVisitor->setOnVisitComplete(callback);

    manager->VisitAllCookies(cookieVisitor);
}

void WebviewHandler::visitUrlCookies(const std::string& domain, const bool& isHttpOnly, std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (!manager)
	{
		return;
	}

    CefRefPtr<WebviewCookieVisitor> cookieVisitor = new WebviewCookieVisitor();
    cookieVisitor->setOnVisitComplete(callback);

    std::string httpDomain = "https://" + domain + "/cookiestorage";

    manager->VisitUrlCookies(httpDomain, isHttpOnly, cookieVisitor);
}

void WebviewHandler::setJavaScriptChannels(int browserId, const std::vector<std::string> channels)
{
    std::string extensionCode = "try{";
    for(auto& channel : channels)
    {
        extensionCode += channel;
        extensionCode += " = (e,r) => {external.JavaScriptChannel('";
        extensionCode += channel;
        extensionCode += "',e,r)};";
    }
    extensionCode += "}catch(e){console.log(e);}";
    executeJavaScript(browserId, extensionCode);
}

void WebviewHandler::sendJavaScriptChannelCallBack(const bool error, const std::string result, const std::string callbackId, const int browserId, const std::string frameId)
{
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kExecuteJsCallbackMessage);
    CefRefPtr<CefListValue> args = message->GetArgumentList();
    args->SetInt(0, atoi(callbackId.c_str()));
    args->SetBool(1, error);
    args->SetString(2, result);
    auto bit = browser_map_.find(browserId);
    if(bit != browser_map_.end()){
        int64_t frameIdInt = atoll(frameId.c_str());

        CefRefPtr<CefFrame> frame = bit->second.browser->GetMainFrame();

        // CefFrame::GetIdentifier() returns a string identifier in current CEF
        // (since CEF 122) on every platform.
        bool identifierMatch = std::stoll(frame->GetIdentifier().ToString()) == frameIdInt;
        if (identifierMatch)
        {
            frame->SendProcessMessage(PID_RENDERER, message);
        }
    }
}

static std::string GetCallbackId()
{
    auto time = std::chrono::time_point_cast<std::chrono::nanoseconds>(std::chrono::system_clock::now());
	time_t timestamp = time.time_since_epoch().count();
    return std::to_string(timestamp);
} 

void WebviewHandler::executeJavaScript(int browserId, const std::string code, std::function<void(CefRefPtr<CefValue>)> callback)
{
    if(!code.empty())
    {
        auto bit = browser_map_.find(browserId);
        if(bit != browser_map_.end() && bit->second.browser.get()){
            CefRefPtr<CefFrame> frame = bit->second.browser->GetMainFrame();
            if (frame)
            {
                std::string finalCode = code;
                if(callback != nullptr){
                    std::string callbackId = GetCallbackId();

                    finalCode = "external.EvaluateCallback('";
                    finalCode += callbackId;
                    finalCode += "',(function(){return ";
                    finalCode += code;
                    finalCode += "})());";
                    js_callbacks_[callbackId] = callback;
                }
			    frame->ExecuteJavaScript(finalCode, frame->GetURL(), 0);
            }
        }
    }
}

void WebviewHandler::GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) {
    CEF_REQUIRE_UI_THREAD();
    rect.x = rect.y = 0;
    rect.width = rect.height = 1;  // CEF requires a non-empty rectangle
    auto it = browser_map_.find(browser->GetIdentifier());
    if(it == browser_map_.end() || !it->second.browser.get() || browser->IsPopup()) {
        return;
    }
    
    if (it->second.width < 1) {
        rect.width = 1;
    } else {
        rect.width = it->second.width;
    }
    
    if (it->second.height < 1) {
        rect.height = 1;
    } else {
        rect.height = it->second.height;
    }
}

bool WebviewHandler::GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& screen_info) {
    //todo: hi dpi support
    auto it = browser_map_.find(browser->GetIdentifier());
    screen_info.device_scale_factor = it == browser_map_.end() ? 1.0f : it->second.dpi;
    return false;
}

void WebviewHandler::OnPopupShow(CefRefPtr<CefBrowser> browser, bool show) {
    auto it = browser_map_.find(browser->GetIdentifier());
    if (it == browser_map_.end()) return;
    it->second.popup_visible = show;
    if (!show) {
        it->second.popup_rect = CefRect();
        if (onPopupHiddenCallback) onPopupHiddenCallback(browser->GetIdentifier());
    }
}

void WebviewHandler::OnPopupSize(CefRefPtr<CefBrowser> browser, const CefRect& rect) {
    auto it = browser_map_.find(browser->GetIdentifier());
    if (it != browser_map_.end()) it->second.popup_rect = rect;
}

void WebviewHandler::OnPaint(CefRefPtr<CefBrowser> browser, CefRenderHandler::PaintElementType type,
                            const CefRenderHandler::RectList &dirtyRects, const void *buffer, int w, int h) {
    // 6browser patch: popup widgets are only drawn on the GPU path; never let
    // one replace the page.
    if (type != PET_VIEW) return;
    if (!browser->IsPopup() && onPaintCallback != nullptr) {
        onPaintCallback(browser->GetIdentifier(), buffer, w, h);
    }
}

void WebviewHandler::OnAcceleratedPaint(CefRefPtr<CefBrowser> browser, CefRenderHandler::PaintElementType type,
                            const CefRenderHandler::RectList &dirtyRects, const CefAcceleratedPaintInfo &info) {
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    if (type == PET_POPUP) {
        // 6browser patch: drawn over the page by the renderer.
        auto it = browser_map_.find(browser->GetIdentifier());
        if (it == browser_map_.end() || !it->second.popup_visible || !onAcceleratedPopupCallback) return;
#ifdef __APPLE__
        const void* popupTexture = reinterpret_cast<const void*>(info.shared_texture_io_surface);
#else
        const void* popupTexture = reinterpret_cast<const void*>(info.shared_texture_handle);
#endif
        const float dpi = it->second.dpi;
        onAcceleratedPopupCallback(browser->GetIdentifier(), popupTexture,
                                   static_cast<int32_t>(std::lround(it->second.popup_rect.x * dpi)),
                                   static_cast<int32_t>(std::lround(it->second.popup_rect.y * dpi)));
        return;
    }
    if (!browser->IsPopup() && onAcceleratedPaintCallback != nullptr) {
        received_accelerated_frame_ = true;
        int w = 0, h = 0;
        auto it = browser_map_.find(browser->GetIdentifier());
        if (it != browser_map_.end()) {
            w = it->second.width;
            h = it->second.height;
            // A produced frame means the browser is render/input-ready. With
            // external_begin_frame a SetFocus issued right after creation can be
            // dropped (the browser wasn't ready yet), which left the webview
            // unable to receive keyboard input until the window was re-focused.
            // Re-apply the requested focus once, now that frames are flowing.
            if (it->second.wants_focus && !it->second.focus_reasserted) {
                it->second.focus_reasserted = true;
                it->second.browser->GetHost()->SetFocus(true);
            }
        }
        // The shared texture is pool-owned and only valid for the duration of
        // this callback. On Windows it is a HANDLE (open with
        // ID3D11Device1::OpenSharedResource1); on macOS it is an IOSurfaceRef.
        // The platform renderer wraps/copies it before returning.
#ifdef __APPLE__
        const void* sharedTexture = reinterpret_cast<const void*>(info.shared_texture_io_surface);
#else
        const void* sharedTexture = reinterpret_cast<const void*>(info.shared_texture_handle);
#endif
        onAcceleratedPaintCallback(browser->GetIdentifier(), sharedTexture,
                                   w, h, static_cast<int>(info.format));
    }
#endif
}
