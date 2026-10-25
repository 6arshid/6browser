// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "webview_app.h"

#include <string>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_helpers.h"

namespace {

// See WebviewApp::OnContextCreated.
const char kVideoPictureInPictureShim[] = R"JS((() => {
  const pip = window.documentPictureInPicture;
  if (!pip || window !== top || !window.HTMLVideoElement) return;
  const define = (target, name, value) => Object.defineProperty(target, name,
      {configurable: true, writable: true, value});
  let active = null;

  const pipWindowFor = (win) => {
    const target = new EventTarget();
    target.onresize = null;
    Object.defineProperties(target, {
      width: {get: () => win.innerWidth},
      height: {get: () => win.innerHeight},
    });
    win.addEventListener('resize', () => {
      const event = new Event('resize');
      target.dispatchEvent(event);
      if (typeof target.onresize === 'function') target.onresize(event);
    });
    return target;
  };
  const fire = (video, type, pictureInPictureWindow) => {
    const event = new Event(type, {bubbles: true});
    Object.defineProperty(event, 'pictureInPictureWindow', {value: pictureInPictureWindow});
    video.dispatchEvent(event);
  };
  // Puts the video back in the page; runs when the PiP window closes.
  const restore = (entry) => {
    if (active !== entry) return;
    active = null;
    const {video, placeholder} = entry;
    const playing = !video.paused;
    if (placeholder.isConnected) placeholder.replaceWith(video);
    else { video.pause(); video.remove(); }
    video.controls = entry.controls;
    if (playing && video.paused && video.isConnected) video.play().catch(() => {});
    fire(video, 'leavepictureinpicture', entry.pipWindow);
  };

  define(HTMLVideoElement.prototype, 'requestPictureInPicture', async function () {
    if (this.disablePictureInPicture) {
      throw new DOMException('Picture-in-Picture is disabled for this video', 'InvalidStateError');
    }
    if (this.readyState === 0 || !this.isConnected) {
      throw new DOMException('The video is not ready', 'InvalidStateError');
    }
    if (active && active.video === this) return active.pipWindow;
    const ratio = this.videoWidth && this.videoHeight ? this.videoWidth / this.videoHeight : 16 / 9;
    const width = 480;
    const win = await pip.requestWindow({width, height: Math.round(width / ratio)});
    if (active) restore(active);

    const doc = win.document;
    const style = doc.createElement('style');
    style.textContent = 'html,body{margin:0;height:100%;background:#000;overflow:hidden}' +
      'video{position:fixed!important;inset:0!important;width:100%!important;' +
      'height:100%!important;max-width:none!important;max-height:none!important;' +
      'margin:0!important;transform:none!important;object-fit:contain!important}';
    doc.head.append(style);
    doc.title = document.title;

    // Keep the page layout while the video is away.
    const rect = this.getBoundingClientRect();
    const placeholder = document.createElement('div');
    placeholder.style.cssText = this.style.cssText;
    placeholder.style.width = rect.width + 'px';
    placeholder.style.height = rect.height + 'px';
    placeholder.style.background = '#000';

    const playing = !this.paused;
    const entry = {video: this, placeholder, win, controls: this.controls, pipWindow: pipWindowFor(win)};
    active = entry;
    this.replaceWith(placeholder);
    doc.body.append(this);
    this.controls = true;
    if (playing && this.paused) this.play().catch(() => {});
    win.addEventListener('pagehide', () => restore(entry), {once: true});
    addEventListener('pagehide', () => win.close(), {once: true});
    fire(this, 'enterpictureinpicture', entry.pipWindow);
    return entry.pipWindow;
  });

  define(Document.prototype, 'exitPictureInPicture', async function () {
    if (this !== document || !active) {
      throw new DOMException('There is no Picture-in-Picture element', 'InvalidStateError');
    }
    const entry = active;
    restore(entry);
    entry.win.close();
  });
  Object.defineProperty(Document.prototype, 'pictureInPictureElement', {
    configurable: true,
    get() { return this === document && active ? active.video : null; },
  });
})();)JS";

// When using the Views framework this object provides the delegate
// implementation for the CefWindow that hosts the Views-based browser.
class SimpleWindowDelegate : public CefWindowDelegate {
public:
    explicit SimpleWindowDelegate(CefRefPtr<CefBrowserView> browser_view)
    : browser_view_(browser_view) {}
    
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        // Add the browser view and show the window.
        window->AddChildView(browser_view_);
        window->Show();
        
        // Give keyboard focus to the browser view.
        browser_view_->RequestFocus();
    }
    
    void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
        browser_view_ = nullptr;
    }
    
    bool CanClose(CefRefPtr<CefWindow> window) override {
        // Allow the window to close if the browser says it's OK.
        CefRefPtr<CefBrowser> browser = browser_view_->GetBrowser();
        if (browser)
            return browser->GetHost()->TryCloseBrowser();
        return true;
    }
    
    CefSize GetPreferredSize(CefRefPtr<CefView> view) override {
        return CefSize(1280, 720);
    }
    
private:
    CefRefPtr<CefBrowserView> browser_view_;
    
    IMPLEMENT_REFCOUNTING(SimpleWindowDelegate);
    DISALLOW_COPY_AND_ASSIGN(SimpleWindowDelegate);
};

class SimpleBrowserViewDelegate : public CefBrowserViewDelegate {
public:
    SimpleBrowserViewDelegate() {}
    
    bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView> browser_view,
                                   CefRefPtr<CefBrowserView> popup_browser_view,
                                   bool is_devtools) override {
        // Create a new top-level Window for the popup. It will show itself after
        // creation.
        CefWindow::CreateTopLevelWindow(
                                        new SimpleWindowDelegate(popup_browser_view));
        
        // We created the Window.
        return true;
    }
    
private:
    IMPLEMENT_REFCOUNTING(SimpleBrowserViewDelegate);
    DISALLOW_COPY_AND_ASSIGN(SimpleBrowserViewDelegate);
};

}  // namespace

WebviewApp::WebviewApp(CefRefPtr<WebviewHandler> handler) {
    m_handler = handler;
}

WebviewApp::ProcessType WebviewApp::GetProcessType(CefRefPtr<CefCommandLine> command_line)
{
    // The command-line flag won't be specified for the browser process.
	if (!command_line->HasSwitch("type"))
    {
        return BrowserProcess;
    }

	const std::string& process_type = command_line->GetSwitchValue("type");
	if (process_type == "renderer")
		return RendererProcess;
#if defined(OS_LINUX)
	else if (process_type == "zygote")
		return ZygoteProcess;
#endif
	return OtherProcess;
}

void WebviewApp::OnBeforeCommandLineProcessing(const CefString &process_type, CefRefPtr<CefCommandLine> command_line)
{
    // Pass additional command-line flags to the browser process.
	if (process_type.empty())
	{
#ifndef WEBVIEW_CEF_GPU_TEXTURE
		// The GPU shared-texture path (OnAcceleratedPaint) requires the GPU
		// compositor; only allow disabling the GPU when it is not compiled in.
		if (!m_bEnableGPU)
		{
			command_line->AppendSwitch("disable-gpu");
			command_line->AppendSwitch("disable-gpu-compositing");
		}
#endif

		// 6browser patch: upstream unconditionally added "disable-web-security"
		// and "allow-running-insecure-content" here. Both are unsafe for a
		// general-purpose browser, so they are no longer set.
		// Don't create a "GPUCache" directory when cache-path is unspecified.
		command_line->AppendSwitch("disable-gpu-shader-disk-cache");                            //disable gpu shader disk cache
        command_line->AppendSwitch("no-sandbox");

		//http://www.chromium.org/developers/design-documents/process-models
		if (m_uMode == 1)
		{
			command_line->AppendSwitch("process-per-site");                                     //each site in its own process
			command_line->AppendSwitchWithValue("renderer-process-limit", "8");              //limit renderer process count to decrease memory usage
		}
		else if (m_uMode == 2)
		{
			command_line->AppendSwitch("process-per-tab");                                      //each tab in its own process
		}
		else if (m_uMode == 3)
		{
			command_line->AppendSwitch("single-process");                                     //all in one process
		}
		command_line->AppendSwitchWithValue("autoplay-policy", "no-user-gesture-required");     //autoplay policy for media

        // 6browser patch: upstream also disabled SameSiteByDefaultCookies and
        // CookiesWithoutSameSiteMustBeSecure here; cookie protections stay on.
        std::string values = command_line->GetSwitchValue("disable-features");
        if (values.find("CalculateNativeWinOcclusion") == size_t(-1))
        {
            values += values.empty() ? "CalculateNativeWinOcclusion" : ",CalculateNativeWinOcclusion";
        }
        // 6browser patch: extensions run in this engine, so extensions that
        // other programs register for Chrome (Windows registry, e.g. antivirus
        // add-ons) must not be picked up. 6browser loads only its own.
        if (values.find("ExternalExtensions") == size_t(-1))
        {
            values += ",ExternalExtensions";
        }

        command_line->AppendSwitchWithValue("disable-features", values);

        // 6browser patch: a DevTools connection to the browser target, used to
        // load and remove extensions at runtime. It is an anonymous pipe owned
        // by this process (see startCEF), never a network port, so no other
        // program can connect to it.
        if (!m_devToolsPipes.empty())
        {
            command_line->AppendSwitch("remote-debugging-pipe");
            command_line->AppendSwitchWithValue("remote-debugging-io-pipes", m_devToolsPipes);
        }
        // 6browser patch: upstream's "ignore-certificate-errors" for a filter
        // domain is removed; TLS errors must never be silently ignored.
    }

#ifdef __APPLE__
    command_line->AppendSwitch("use-mock-keychain");
    // macOS now runs multi-process via bundled CEF helper apps (see the
    // example Runner's "Embed CEF Helpers" phase). The process model is
    // selected by m_uMode above, like the other platforms.
#endif
#ifdef __linux__
                                           
#endif
}

void WebviewApp::OnContextInitialized()
{
    CEF_REQUIRE_UI_THREAD();
//    CefBrowserSettings browser_settings;
//    browser_settings.windowless_frame_rate = 60;
//                
//    CefWindowInfo window_info;
//    window_info.SetAsWindowless(0);
//
//    // create browser
//    CefBrowserHost::CreateBrowser(window_info, m_handler, "", browser_settings, nullptr, nullptr);
    
}

// CefRefPtr<CefClient> WebviewApp::GetDefaultClient() {
//     // Called when a new browser window is created via the Chrome runtime UI.
//     return WebviewHandler::GetInstance();
// }

void WebviewApp::SetUnSafelyTreatInsecureOriginAsSecure(const CefString &strFilterDomain)
{
    m_strFilterDomain = strFilterDomain;
}

void WebviewApp::OnWebKitInitialized()
{
    //inject js function for jssdk
    std::string extensionCode = R"(
			var external = {};
			var clientSdk = {};
			(() => {
				clientSdk.jsCmd = (functionName, arg1, arg2, arg3) => {
					if (typeof arg1 === 'function') {
						native function jsCmd(functionName, arg1);
						return jsCmd(functionName, arg1);
					} 
					else if	 (typeof arg2 === 'function') {
                        jsonString = arg1;
                        if	(typeof arg1 !== 'string'){
						    jsonString = JSON.stringify(arg1);
                        }
						native function jsCmd(functionName, jsonString, arg2);
						return jsCmd(functionName, jsonString, arg2);
					}
					else if	 (typeof arg3 === 'function') {
                        jsonString = arg1;
                        if	(typeof arg1 !== 'string'){
						    jsonString = JSON.stringify(arg1);
                        }
						native function jsCmd(functionName, jsonString, arg2, arg3);
						return jsCmd(functionName, jsonString, arg2, arg3);
					}else {

					}
				};

                external.JavaScriptChannel = (n,e,r) => {
                    var a; 
                    null == r ? a = '' : (a = '_' + new Date + (1e3 + Math.floor(8999 * Math.random())), window[a] = function (n, e) { 
                        return function () { 
                            try {
                                e && e.call && e.call(null, arguments[1]) 
                            } finally {
                                delete window[n]
                            } 
                        } 
                    }(a, r)); 
                    try {
                        external.StartRequest(external.GetNextReqID(), n, a, JSON.stringify(e || {}), '') 
                    } catch (l) {
                        console.log('messeage send')
                    }
                }

                external.EvaluateCallback = (nReqID, result) => {
                    native function EvaluateCallback();
                    EvaluateCallback(nReqID, result);
                }

				external.StartRequest  = (nReqID, strCmd, strCallBack, strArgs, strLog) => {
					native function StartRequest();
					StartRequest(nReqID, strCmd, strCallBack, strArgs, strLog);
				};
				external.GetNextReqID  = () => {
				  native function GetNextReqID();
				  return GetNextReqID();
				};
			})();
		 )";

    CefRefPtr<CefJSHandler> handler = new CefJSHandler();

    if (!m_render_js_bridge.get())
        m_render_js_bridge.reset(new CefJSBridge);
    handler->AttachJSBridge(m_render_js_bridge);

    CefRegisterExtension("v8/extern", extensionCode, handler);
}

void WebviewApp::OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> extra_info)
{
    if (!m_render_js_bridge.get()) {
        m_render_js_bridge.reset(new CefJSBridge);
    }
}

void WebviewApp::SetProcessMode(uint32_t uMode)
{
    m_uMode = uMode;
}

void WebviewApp::SetEnableGPU(bool bEnable)
{
    m_bEnableGPU = bEnable;
}

void WebviewApp::OnBeforeChildProcessLaunch(CefRefPtr<CefCommandLine> command_line)
{
}

void WebviewApp::OnBrowserDestroyed(CefRefPtr<CefBrowser> browser)
{
}

void WebviewApp::OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context)
{
    // 6browser patch: off-screen browsers have no native video
    // Picture-in-Picture (Alloy returns NotSupportedError), so <video> PiP is
    // emulated by moving the video into a Document Picture-in-Picture window.
    // Runs before the page's own scripts; Document PiP is top-level only.
    const std::string url = frame->GetURL().ToString();
    if (frame->IsMain() &&
        (url.rfind("https://", 0) == 0 || url.rfind("http://", 0) == 0)) {
        CefRefPtr<CefV8Value> result;
        CefRefPtr<CefV8Exception> exception;
        context->Eval(kVideoPictureInPictureShim, url, 0, result, exception);
    }
}

void WebviewApp::OnContextReleased(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context)
{
    if (m_render_js_bridge.get())
    {
        m_render_js_bridge->RemoveCallbackFuncWithFrame(frame);
    }
}

void WebviewApp::OnUncaughtException(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context, CefRefPtr<CefV8Exception> exception, CefRefPtr<CefV8StackTrace> stackTrace)
{
}

void WebviewApp::OnFocusedNodeChanged(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefDOMNode> node)
 {    
    //Get node attribute
    bool is_editable = (node.get() && node->IsEditable());
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kFocusedNodeChangedMessage);
    message->GetArgumentList()->SetBool(0, is_editable);
    if (is_editable)
    {
        CefRect rect = node->GetElementBounds();
        message->GetArgumentList()->SetInt(1, rect.x);
        message->GetArgumentList()->SetInt(2, rect.y + rect.height);
        message->GetArgumentList()->SetInt(3, rect.height);
    }
    frame->SendProcessMessage(PID_BROWSER, message);
}

bool WebviewApp::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefProcessId source_process, CefRefPtr<CefProcessMessage> message)
{
    const CefString& message_name = message->GetName();
    if (message_name == kExecuteJsCallbackMessage)
    {
        int			callbackId = message->GetArgumentList()->GetInt(0);
        bool		error = message->GetArgumentList()->GetBool(1);
        CefString	result = message->GetArgumentList()->GetString(2);
        if (m_render_js_bridge.get())
        {
            m_render_js_bridge->ExecuteJSCallbackFunc(callbackId, error, result);
        }
    }

    return false;
}
