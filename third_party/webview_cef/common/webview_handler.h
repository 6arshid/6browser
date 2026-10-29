// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_CEFSIMPLE_SIMPLE_HANDLER_H_
#define CEF_TESTS_CEFSIMPLE_SIMPLE_HANDLER_H_

#include <chrono>
#include "include/cef_client.h"

#include <functional>
#include <list>
#include <set>
#include <unordered_map>

#include "webview_cookieVisitor.h"

#define ColorUNDERLINE \
  0xFF000000  // Black SkColor value for underline,
              // same as Blink.
#define ColorBKCOLOR \
  0x00000000  // White SkColor value for background,
              // same as Blink.

struct browser_info{
    CefRefPtr<CefBrowser> browser;
    uint32_t width = 1;
    uint32_t height = 1;
    float dpi = 1.0;
    bool is_dragging = false;
    bool left_button_down = false;
    CefRect prev_ime_position = CefRect();
    bool is_ime_commit = false;
    // Focus the host requested (via setClientFocus) and whether it has been
    // re-asserted after the first rendered frame. With external_begin_frame the
    // browser isn't input/focus-ready until frames flow, so a SetFocus issued
    // right after creation is lost; we re-apply it once the first frame lands.
    bool wants_focus = false;
    bool focus_reasserted = false;
    // 6browser patch: scroll distance (DIP) not yet sent to CEF.
    double scroll_rest_x = 0;
    double scroll_rest_y = 0;
    // 6browser patch: the open popup widget (<select> dropdown), in view
    // coordinates.
    bool popup_visible = false;
    CefRect popup_rect;
    // 6browser patch: when the page's renderer last crashed.
    std::chrono::steady_clock::time_point last_crash;
    // 6browser patch: the page may hand one link to an external app until
    // the user next clicks or types (Chrome's flood guard).
    bool external_link_allowed = true;
};

// 6browser patch: what was under the cursor when a context menu was requested.
// The native menu is suppressed and the host draws its own.
struct context_menu_info {
    int x = 0;
    int y = 0;
    int typeFlags = 0;   // cef_context_menu_type_flags_t
    int mediaType = 0;   // cef_context_menu_media_type_t
    int editFlags = 0;   // cef_context_menu_edit_state_flags_t
    std::string linkUrl;
    std::string srcUrl;
    std::string pageUrl;
    std::string selectionText;
    bool canGoBack = false;
    bool canGoForward = false;
};

class WebviewHandler : public CefClient,
public CefDisplayHandler,
public CefLifeSpanHandler,
public CefFocusHandler,
public CefLoadHandler,
public CefDownloadHandler,
public CefContextMenuHandler,
public CefPermissionHandler,
public CefFindHandler,
public CefRequestHandler,
public CefKeyboardHandler,
public CefRenderHandler{
public:
    //Paint callback (software off-screen rendering)
    std::function<void(int browserId, const void* buffer, int32_t width, int32_t height)> onPaintCallback;
    //Accelerated paint callback (GPU shared texture). On Windows |sharedHandle|
    //is the OnAcceleratedPaint shared-texture HANDLE; |format| is a
    //cef_color_type_t. Only fired when shared textures are enabled.
    std::function<void(int browserId, const void* sharedHandle, int32_t width, int32_t height, int32_t format)> onAcceleratedPaintCallback;
    // 6browser patch: popup widget frames, at (x, y) pixels in the view, and
    // the popup closing.
    std::function<void(int browserId, const void* sharedHandle, int32_t x, int32_t y)> onAcceleratedPopupCallback;
    std::function<void(int browserId)> onPopupHiddenCallback;
    //cef message event
    std::function<void(int browserId, std::string url)> onUrlChangedEvent;
    std::function<void(int browserId, std::string title)> onTitleChangedEvent;
    // 6browser patch: download progress. state: 0 in progress, 1 complete, 2 canceled.
    std::function<void(int id, std::string url, std::string path, int64_t received, int64_t total, int state, bool incognito)> onDownloadEvent;
    std::function<void(int browserId, int type)>onCursorChangedEvent;
    std::function<void(int browserId, std::string text)> onTooltipEvent;
    std::function<void(int browserId, int level, std::string message, std::string source, int line)>onConsoleMessageEvent;
    std::function<void(int browserId, bool editable)> onFocusedNodeChangeMessage;
    std::function<void(int browserId, int32_t x, int32_t y, int32_t height)> onImeCompositionRangeChangedMessage;
    //webpage message
    std::function<void(std::string, std::string, std::string, int browserId, std::string)> onJavaScriptChannelMessage;
    std::function<void(int browserId, std::string url)> onLoadStart;
    std::function<void(int browserId, std::string url)> onLoadEnd;
    // 6browser patch: a page asked for a context menu.
    std::function<void(int browserId, const context_menu_info& info)> onContextMenuEvent;
    std::function<void(int browserId, int count, int activeMatch, bool finalUpdate)> onFindResultEvent;
    std::function<void(int browserId, double level)> onZoomChangedEvent;
    // 6browser patch: a link or script asked for a new tab/window
    // (cef_window_open_disposition_t); the host opens it as a tab.
    std::function<void(int browserId, std::string url, int disposition)> onNewWindowEvent;
    // 6browser patch: the page tried to open a link that belongs to another
    // app (mailto:, tg:...). The navigation is cancelled; the host asks the
    // user and opens it. |source| is the URL of the page that asked, empty
    // when the user typed the link.
    std::function<void(int browserId, std::string url, std::string source)> onExternalLinkEvent;
    // 6browser patch: a key press the page did not handle (Windows virtual
    // key code, CEF modifier flags), for the host's shortcuts.
    std::function<void(int browserId, int keyCode, int modifiers)> onUnhandledKeyEvent;
    
    explicit WebviewHandler();
    ~WebviewHandler();
    
    // CefClient methods:
    virtual CefRefPtr<CefDisplayHandler> GetDisplayHandler() override {
        return this;
    }
    virtual CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override {
        return this;
    }
    virtual CefRefPtr<CefFocusHandler> GetFocusHandler() override {
        return this;
    }
    virtual CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    virtual CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    virtual CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
    // 6browser patch: find-in-page results (Ctrl+F).
    void OnFindResult(CefRefPtr<CefBrowser> browser,
                      int identifier,
                      int count,
                      const CefRect& selectionRect,
                      int activeMatchOrdinal,
                      bool finalUpdate) override;
    bool OnRequestMediaAccessPermission(
        CefRefPtr<CefBrowser> browser,
        CefRefPtr<CefFrame> frame,
        const CefString& requesting_origin,
        uint32_t requested_permissions,
        CefRefPtr<CefMediaAccessCallback> callback) override;
    bool OnShowPermissionPrompt(
        CefRefPtr<CefBrowser> browser,
        uint64_t prompt_id,
        const CefString& requesting_origin,
        uint32_t requested_permissions,
        CefRefPtr<CefPermissionPromptCallback> callback) override;

    // CefContextMenuHandler methods (6browser patch):
    void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             CefRefPtr<CefContextMenuParams> params,
                             CefRefPtr<CefMenuModel> model) override;

    // CefDownloadHandler methods (6browser patch):
    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefDownloadItem> download_item,
                          const CefString& suggested_name,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override;
    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefDownloadItem> download_item,
                           CefRefPtr<CefDownloadItemCallback> callback) override;
    virtual CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }

    // 6browser patch: Ctrl/Shift/middle clicks on links open new tabs; a
    // crashed renderer shows an error page instead of a frozen frame.
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
    bool OnKeyEvent(CefRefPtr<CefBrowser> browser,
                    const CefKeyEvent& event,
                    CefEventHandle os_event) override;
    bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefFrame> frame,
                          const CefString& target_url,
                          CefRequestHandler::WindowOpenDisposition target_disposition,
                          bool user_gesture) override;
    // 6browser patch: links to other apps go to the host instead of ending
    // on an ERR_UNKNOWN_URL_SCHEME page.
    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefRequest> request,
                        bool user_gesture,
                        bool is_redirect) override;
    void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                   TerminationStatus status,
                                   int error_code,
                                   const CefString& error_string) override;

	bool OnProcessMessageReceived(
        CefRefPtr<CefBrowser> browser,
		CefRefPtr<CefFrame> frame,
		CefProcessId source_process,
		CefRefPtr<CefProcessMessage> message) override;

    
    // CefDisplayHandler methods:
    virtual void OnTitleChange(CefRefPtr<CefBrowser> browser,
                               const CefString& title) override;
    virtual void OnAddressChange(CefRefPtr<CefBrowser> browser,
                                 CefRefPtr<CefFrame> frame,
                                 const CefString& url) override;
    virtual bool OnCursorChange(CefRefPtr<CefBrowser> browser,
                                CefCursorHandle cursor,
                                cef_cursor_type_t type,
                                const CefCursorInfo& custom_cursor_info) override;
    virtual bool OnTooltip(CefRefPtr<CefBrowser> browser, CefString& text) override;
    virtual bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                  cef_log_severity_t level,
                                  const CefString& message,
                                  const CefString& source,
                                  int line) override;
    
    // CefLifeSpanHandler methods:
    virtual void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
    virtual bool DoClose(CefRefPtr<CefBrowser> browser) override;
    virtual void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;
    virtual bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
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
                               bool* no_javascript_access) override;
    
    virtual void OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next) override;
    virtual bool OnSetFocus(CefRefPtr<CefBrowser> browser, FocusSource source) override;
    virtual void OnGotFocus(CefRefPtr<CefBrowser> browser) override;

    // CefLoadHandler methods:
    virtual void OnLoadError(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             ErrorCode errorCode,
                             const CefString& errorText,
                             const CefString& failedUrl) override;
    virtual void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           int httpStatusCode) override;
    virtual void OnLoadStart(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             CefLoadHandler::TransitionType transition_type) override;
    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                              bool isLoading,
                              bool canGoBack,
                              bool canGoForward) override;
    
    // CefRenderHandler methods:
    virtual void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect& rect) override;
    virtual void OnPaint(CefRefPtr<CefBrowser> browser, PaintElementType type, const RectList& dirtyRects, const void* buffer, int width, int height) override;
    virtual void OnAcceleratedPaint(CefRefPtr<CefBrowser> browser, PaintElementType type, const RectList& dirtyRects, const CefAcceleratedPaintInfo& info) override;
    virtual bool GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& screen_info) override;
    void OnPopupShow(CefRefPtr<CefBrowser> browser, bool show) override;
    void OnPopupSize(CefRefPtr<CefBrowser> browser, const CefRect& rect) override;
    virtual bool StartDragging(CefRefPtr<CefBrowser> browser,
                               CefRefPtr<CefDragData> drag_data,
                               DragOperationsMask allowed_ops,
                               int x,
                               int y) override;
    virtual void OnImeCompositionRangeChanged(CefRefPtr<CefBrowser> browser,const CefRange& selection_range,const CefRenderHandler::RectList& character_bounds) override;

    // Request that all existing browser windows close.
    void CloseAllBrowsers(bool force_close);

    void closeBrowser(int browserId);
    // 6browser patch: |incognito| browsers share one in-memory request context
    // (no cookies/cache/localStorage touch the disk) that is discarded when the
    // last incognito browser closes.
    void createBrowser(std::string url, std::function<void(int)> callback, bool incognito = false);
    bool isIncognito(int browserId) const { return m_privateIds.count(browserId) > 0; }

    // Drives one external BeginFrame for every live browser (GPU path only).
    // Marshals to the CEF UI thread; safe to call from any thread.
    void sendExternalBeginFrame();

    // Diagnostic (GPU path): warn once if no accelerated-paint frame has arrived
    // shortly after a browser is created — the symptom of an unavailable GPU
    // shared texture, which would otherwise be a silent black webview.
    void warnIfNoAcceleratedFrame();

    void sendScrollEvent(int browserId, int x, int y, double deltaX, double deltaY, int modifiers);
    void reportZoomFor(int browserId);
    // 6browser patch: background tabs stop rendering, as in Chrome.
    void setVisible(int browserId, bool visible);
    void openInNewTab(CefRefPtr<CefBrowser> browser, const CefString& url,
                      int disposition, bool user_gesture);
    void offerExternalLink(CefRefPtr<CefBrowser> browser, const std::string& url,
                           const std::string& source);
    void changeSize(int browserId, float a_dpi, int width, int height);
    // |button|: 0 left, 1 middle, 2 right (cef_mouse_button_type_t).
    void cursorClick(int browserId, int x, int y, bool up, int button = 0, int clickCount = 1, int modifiers = 0);
    void cursorMove(int browserId, int x, int y, bool dragging, int modifiers = 0);
    void cursorLeave(int browserId, int x, int y);
    void cursorCancel(int browserId, int x, int y, int button);
    void sendKeyEvent(CefKeyEvent& ev);
    void loadUrl(int browserId, std::string url);
    void goForward(int browserId);
    void goBack(int browserId);
    void reload(int browserId);
    void openDevTools(int browserId);
    // 6browser patch: context menu actions.
    void inspectElementAt(int browserId, int x, int y);
    // |command|: undo, redo, cut, copy, paste, delete, selectAll.
    void editCommand(int browserId, const std::string& command);
    void startDownload(int browserId, const std::string& url);
    // 6browser patch: browser keyboard shortcuts.
    void stopLoad(int browserId);
    void reloadIgnoreCache(int browserId);
    // |command|: -1 zoom out, 0 reset, 1 zoom in (Chrome's preset steps).
    // The resulting level is reported through onZoomChangedEvent.
    void zoom(int browserId, int command);
    void reportZoom(CefRefPtr<CefBrowser> browser);
    void find(int browserId, const std::string& text, bool forward, bool matchCase, bool findNext);
    void stopFinding(int browserId, bool clearSelection);
    void print(int browserId);

    void imeSetComposition(int browserId, std::string text);
    void imeCommitText(int browserId, std::string text);
    void setClientFocus(int browserId, bool focus);

    // Native IME pipeline (Windows WM_IME_*): operate on the currently focused
    // browser. |text| is UTF-16 read from the IMM composition string.
    CefRefPtr<CefBrowser> getFocusedBrowser();
    void imeCancelComposition();
    // 6browser patch: keys and IME go to the browser the host focused
    // (setClientFocus), never to a background tab or DevTools.
    int focused_browser_id_ = 0;
    void imeSetCompositionNative(const std::wstring& text, int cursor);
    void imeCommitTextNative(const std::wstring& text);
    void imeFinishComposition();

    void setCookie(const std::string& domain, const std::string& key, const std::string& value);
    void deleteCookie(const std::string& domain, const std::string& key);
    void visitAllCookies(std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback);
    void visitUrlCookies(const std::string& domain, const bool& isHttpOnly, std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback);

    void setJavaScriptChannels(int browserId, const std::vector<std::string> channels);
    void sendJavaScriptChannelCallBack(const bool error, const std::string result, const std::string callbackId, const int browserId, const std::string frameId);
    void executeJavaScript(int browserId, const std::string code, std::function<void(CefRefPtr<CefValue>)> callback = nullptr);
    
private:
    // List of existing browser windows. Only accessed on the CEF UI thread.
    std::unordered_map<int, browser_info> browser_map_;
    std::set<int> m_incognitoBrowsers;
    // Every private browser ever opened (its downloads may outlive it).
    std::set<int> m_privateIds;
    CefRefPtr<CefRequestContext> m_incognitoContext;

    std::unordered_map<std::string, std::function<void(CefRefPtr<CefValue>)>> js_callbacks_;

#ifdef WEBVIEW_CEF_GPU_TEXTURE
    // GPU diagnostic state: whether any accelerated-paint frame has arrived, and
    // whether the "no GPU frame" warning was already logged (log it once).
    // Only declared on GPU builds so non-GPU builds don't see unused fields.
    bool received_accelerated_frame_ = false;
    bool gpu_warning_logged_ = false;
#endif

    // Include the default reference counting implementation.
    IMPLEMENT_REFCOUNTING(WebviewHandler);

};

#endif  // CEF_TESTS_CEFSIMPLE_SIMPLE_HANDLER_H_
