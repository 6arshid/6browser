// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "webview_app.h"

#include <string>
#include <unordered_map>
#include <vector>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_helpers.h"

namespace {

// See WebviewApp::OnContextCreated.
const char kVideoPictureInPictureShim[] = R"JS((() => {
  // documentPictureInPicture is added a task after the page's context is
  // created (secure-context API), so set up once it exists.
  const setUp = () => {
  const pip = window.documentPictureInPicture;
  if (!pip || window !== top || !window.HTMLVideoElement) return false;
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
  return true;
  };
  if (!setUp() && window === top) setTimeout(setUp, 0);
})();)JS";

// 6browser patch: getDisplayMedia. Alloy has no source picker (it shares
// the whole desktop) and its system audio echoes the call back to the other
// people. The page's getDisplayMedia is replaced: the host's picker runs
// first (native.pick), then exactly the chosen screen or window is captured
// through the legacy desktop constraints, and system audio without this
// browser's own sound is fed in from the browser process (native.audio).
// Evaluates to a function that receives |native|; the page never sees it.
// Runs before the page's own scripts, so the originals are kept here.
const char kScreenShareShim[] = R"JS((function (native) {
  'use strict';
  const apply = Reflect.apply;
  const define = Object.defineProperty;
  const getPrototypeOf = Object.getPrototypeOf;
  const getVideoTracks = MediaStream.prototype.getVideoTracks;
  const getAudioTracks = MediaStream.prototype.getAudioTracks;
  const addTrack = MediaStream.prototype.addTrack;
  const trackStop = MediaStreamTrack.prototype.stop;
  const getSettings = MediaStreamTrack.prototype.getSettings;
  const listen = EventTarget.prototype.addEventListener;
  const AudioContextClass = window.AudioContext;
  const PromiseClass = Promise;
  const DOMExceptionClass = DOMException;
  const TypeErrorClass = TypeError;
  const Int16 = Int16Array;
  const controllers = new WeakSet();
  const isOurs = WeakSet.prototype.has;
  const markOurs = WeakSet.prototype.add;
  let picking = false;

  const notAllowed = (message) => new DOMExceptionClass(message || 'Permission denied', 'NotAllowedError');
  const numberOf = (c) => {
    if (typeof c === 'number') return c;
    if (!c || typeof c !== 'object') return undefined;
    for (const key of ['max', 'exact', 'ideal']) {
      if (typeof c[key] === 'number') return c[key];
    }
    return undefined;
  };

  // System audio arrives as 48 kHz stereo 16-bit chunks and is played into a
  // MediaStream track, a little ahead of time so a busy page does not cut it.
  const attachAudio = (stream, video) => {
    let context;
    try {
      context = new AudioContextClass({sampleRate: 48000, latencyHint: 'playback'});
    } catch (e) {
      return;
    }
    const destination = context.createMediaStreamDestination();
    destination.channelCount = 2;
    const track = apply(getAudioTracks, destination.stream, [])[0];
    if (!track) {
      context.close();
      return;
    }
    const lead = 0.15;
    let next = 0;
    let stopped = false;
    native.audio(true, (buffer) => {
      if (stopped) return;
      const pcm = new Int16(buffer);
      const frames = pcm.length >> 1;
      if (!frames) return;
      const chunk = context.createBuffer(2, frames, 48000);
      const left = chunk.getChannelData(0);
      const right = chunk.getChannelData(1);
      for (let i = 0, j = 0; i < frames; i++, j += 2) {
        left[i] = pcm[j] / 32768;
        right[i] = pcm[j + 1] / 32768;
      }
      const source = context.createBufferSource();
      source.buffer = chunk;
      source.connect(destination);
      const now = context.currentTime;
      if (next < now + 0.02 || next > now + 1) next = now + lead;
      source.start(next);
      next += chunk.duration;
    });
    const end = () => {
      if (stopped) return;
      stopped = true;
      native.audio(false);
      context.close().catch(() => {});
    };
    define(track, 'stop', {configurable: true, writable: true, value: function stop() {
      end();
      return apply(trackStop, this, []);
    }});
    // The shared window closed or the share ended.
    apply(listen, video, ['ended', () => {
      end();
      apply(trackStop, track, []);
    }]);
    apply(addTrack, stream, [track]);
  };

  // Blink adds secure-context APIs only after this runs: navigator.mediaDevices
  // right away, the MediaDevices and CaptureController interface objects a
  // task later. Each part is installed as soon as it exists, long before a
  // user action can start a share.
  const installGetDisplayMedia = () => {
    if (!window.isSecureContext) return true;
    const devices = navigator.mediaDevices;
    const proto = devices ? getPrototypeOf(devices)
                          : window.MediaDevices && window.MediaDevices.prototype;
    if (!proto || typeof proto.getUserMedia !== 'function') return false;
    const getUserMedia = proto.getUserMedia;
    define(proto, 'getDisplayMedia', {configurable: true, enumerable: true, writable: true,
      value: function getDisplayMedia(options) {
        const target = this;
        return new PromiseClass((resolve, reject) => {
          if (options === undefined) options = {};
          if (options === null || typeof options !== 'object') {
            return reject(new TypeErrorClass("Failed to execute 'getDisplayMedia' on 'MediaDevices': The provided value is not of type 'DisplayMediaStreamOptions'."));
          }
          const video = options.video === undefined ? true : options.video;
          if (video === false) {
            return reject(new TypeErrorClass("Failed to execute 'getDisplayMedia' on 'MediaDevices': video must be requested"));
          }
          const policy = document.permissionsPolicy || document.featurePolicy;
          if (policy && typeof policy.allowsFeature === 'function' &&
              !apply(policy.allowsFeature, policy, ['display-capture'])) {
            return reject(notAllowed('Access to the feature "display-capture" is disallowed by permissions policy.'));
          }
          if (picking) {
            return reject(new DOMExceptionClass('Another screen share request is open.', 'InvalidStateError'));
          }
          const Controller = window.CaptureController;
          if (typeof Controller === 'function' && options.controller instanceof Controller) {
            apply(markOurs, controllers, [options.controller]);
          }
          picking = true;
          native.pick(options.audio !== undefined && options.audio !== false, (choice) => {
            picking = false;
            if (!choice || !choice.id) return reject(notAllowed());
            const wanted = typeof video === 'object' ? video : {};
            const mandatory = {chromeMediaSource: 'desktop', chromeMediaSourceId: choice.id};
            const width = numberOf(wanted.width);
            const height = numberOf(wanted.height);
            const rate = numberOf(wanted.frameRate);
            if (width) mandatory.maxWidth = width;
            if (height) mandatory.maxHeight = height;
            if (rate) mandatory.maxFrameRate = rate;
            apply(getUserMedia, target, [{audio: false, video: {mandatory}}]).then((stream) => {
              const track = apply(getVideoTracks, stream, [])[0];
              if (track) {
                const surface = choice.surface;
                define(track, 'getSettings', {configurable: true, writable: true, value: function getSettings_() {
                  const settings = apply(getSettings, this, []);
                  if (surface && !settings.displaySurface) settings.displaySurface = surface;
                  return settings;
                }});
                if (choice.audio) attachAudio(stream, track);
              }
              resolve(stream);
            }, reject);
          });
        });
      },
    });
    return true;
  };

  // A CaptureController given to getDisplayMedia is not tied to this capture;
  // asking it not to focus the shared window is fine (focus never moves).
  const installCaptureController = () => {
    if (!window.isSecureContext) return true;
    const Controller = window.CaptureController;
    if (typeof Controller !== 'function') return false;
    const setFocusBehavior = Controller.prototype.setFocusBehavior;
    if (typeof setFocusBehavior !== 'function') return true;
    define(Controller.prototype, 'setFocusBehavior', {configurable: true, enumerable: true, writable: true,
      value: function setFocusBehavior_(behavior) {
        if (apply(isOurs, controllers, [this])) return undefined;
        return apply(setFocusBehavior, this, [behavior]);
      },
    });
    return true;
  };

  for (const install of [installGetDisplayMedia, installCaptureController]) {
    if (install()) continue;
    queueMicrotask(() => {
      if (!install()) setTimeout(install, 0);
    });
  }
}))JS";

// Renderer-side state of the screen share shim. Renderer main thread only.
struct PendingPick {
    CefRefPtr<CefV8Context> context;
    CefRefPtr<CefV8Value> callback;
};
std::unordered_map<int, PendingPick> g_capture_picks;
int g_next_capture_pick = 1;
// Frame identifier -> where its system audio chunks go.
std::unordered_map<std::string, PendingPick> g_audio_sinks;

// The |native| object handed to kScreenShareShim.
class CaptureBridge : public CefV8Handler {
public:
    bool Execute(const CefString& name, CefRefPtr<CefV8Value> object,
                 const CefV8ValueList& arguments, CefRefPtr<CefV8Value>& retval,
                 CefString& exception) override {
        CefRefPtr<CefV8Context> context = CefV8Context::GetCurrentContext();
        CefRefPtr<CefFrame> frame = context ? context->GetFrame() : nullptr;
        if (!frame) return true;
        if (name == "pick") {
            if (arguments.size() < 2 || !arguments[1]->IsFunction()) return true;
            const int id = g_next_capture_pick++;
            g_capture_picks[id] = {context, arguments[1]};
            CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kCapturePickMessage);
            message->GetArgumentList()->SetInt(0, id);
            message->GetArgumentList()->SetBool(1, arguments[0]->IsBool() && arguments[0]->GetBoolValue());
            frame->SendProcessMessage(PID_BROWSER, message);
            return true;
        }
        if (name == "audio") {
            const bool start = !arguments.empty() && arguments[0]->IsBool() && arguments[0]->GetBoolValue();
            const std::string frameId = frame->GetIdentifier().ToString();
            if (start) {
                if (arguments.size() < 2 || !arguments[1]->IsFunction()) return true;
                g_audio_sinks[frameId] = {context, arguments[1]};
            } else {
                g_audio_sinks.erase(frameId);
            }
            CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kCaptureAudioMessage);
            message->GetArgumentList()->SetBool(0, start);
            frame->SendProcessMessage(PID_BROWSER, message);
            return true;
        }
        return false;
    }

private:
    IMPLEMENT_REFCOUNTING(CaptureBridge);
};

void InstallScreenShareShim(CefRefPtr<CefV8Context> context) {
    if (!context->Enter()) return;
    CefRefPtr<CefV8Value> factory;
    CefRefPtr<CefV8Exception> exception;
    if (context->Eval(kScreenShareShim, "", 0, factory, exception) && factory &&
        factory->IsFunction()) {
        CefRefPtr<CaptureBridge> bridge = new CaptureBridge();
        CefRefPtr<CefV8Value> native = CefV8Value::CreateObject(nullptr, nullptr);
        native->SetValue("pick", CefV8Value::CreateFunction("pick", bridge),
                         V8_PROPERTY_ATTRIBUTE_READONLY);
        native->SetValue("audio", CefV8Value::CreateFunction("audio", bridge),
                         V8_PROPERTY_ATTRIBUTE_READONLY);
        factory->ExecuteFunction(nullptr, {native});
    }
    context->Exit();
}

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

            // Chromium treats --remote-debugging-pipe as automation and makes
            // navigator.webdriver true in every page. The pipe is only ours,
            // pages are never automated, so report it the way Chrome does
            // (false). Google sign-in refuses a "webdriver" browser.
            std::string blink = command_line->GetSwitchValue("disable-blink-features");
            if (blink.find("AutomationControlled") == size_t(-1))
            {
                blink += blink.empty() ? "AutomationControlled" : ",AutomationControlled";
            }
            command_line->AppendSwitchWithValue("disable-blink-features", blink);
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
    // 6browser patch: screen sharing with a source picker; every frame, as
    // iframes may share with allow="display-capture".
    InstallScreenShareShim(context);
}

void WebviewApp::OnContextReleased(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context)
{
    if (m_render_js_bridge.get())
    {
        m_render_js_bridge->RemoveCallbackFuncWithFrame(frame);
    }
    // 6browser patch: the page is gone; so are its screen share requests and
    // its system audio.
    for (auto it = g_capture_picks.begin(); it != g_capture_picks.end();) {
        if (it->second.context->IsSame(context)) it = g_capture_picks.erase(it);
        else ++it;
    }
    auto sink = g_audio_sinks.find(frame->GetIdentifier().ToString());
    if (sink != g_audio_sinks.end() && sink->second.context->IsSame(context)) {
        g_audio_sinks.erase(sink);
        CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kCaptureAudioMessage);
        message->GetArgumentList()->SetBool(0, false);
        frame->SendProcessMessage(PID_BROWSER, message);
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
    else if (message_name == kCapturePickedMessage)
    {
        // 6browser patch: the user chose a screen or window (or cancelled).
        auto args = message->GetArgumentList();
        auto it = g_capture_picks.find(args->GetInt(0));
        if (it == g_capture_picks.end()) return true;
        const PendingPick pick = it->second;
        g_capture_picks.erase(it);
        if (!pick.context->IsValid() || !pick.context->Enter()) return true;
        CefRefPtr<CefV8Value> choice = CefV8Value::CreateObject(nullptr, nullptr);
        choice->SetValue("id", CefV8Value::CreateString(args->GetString(1)), V8_PROPERTY_ATTRIBUTE_NONE);
        choice->SetValue("audio", CefV8Value::CreateBool(args->GetBool(2)), V8_PROPERTY_ATTRIBUTE_NONE);
        choice->SetValue("surface", CefV8Value::CreateString(args->GetString(3)), V8_PROPERTY_ATTRIBUTE_NONE);
        pick.callback->ExecuteFunction(nullptr, {choice});
        pick.context->Exit();
        return true;
    }
    else if (message_name == kCaptureChunkMessage)
    {
        // 6browser patch: system audio for the frame's screen share.
        auto sink = g_audio_sinks.find(frame->GetIdentifier().ToString());
        if (sink == g_audio_sinks.end()) return true;
        const PendingPick target = sink->second;
        if (!target.context->IsValid()) {
            g_audio_sinks.erase(sink);
            return true;
        }
        CefRefPtr<CefBinaryValue> binary = message->GetArgumentList()->GetBinary(0);
        const size_t size = binary ? binary->GetSize() : 0;
        if (!size || !target.context->Enter()) return true;
        std::vector<uint8_t> data(size);
        binary->GetData(data.data(), size, 0);
        CefRefPtr<CefV8Value> buffer = CefV8Value::CreateArrayBufferWithCopy(data.data(), size);
        target.callback->ExecuteFunction(nullptr, {buffer});
        target.context->Exit();
        return true;
    }

    return false;
}
