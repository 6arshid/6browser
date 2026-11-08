#include "whisper_voice_plugin.h"

#include <flutter/standard_method_codec.h>

#include <string>
#include <utility>
#include <vector>

// The module (this DLL) the task window class belongs to.
extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace whisper_voice {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr UINT kRunTask = WM_APP + 0x31;
constexpr wchar_t kWindowClass[] = L"WhisperVoiceTaskWindow";

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                       static_cast<int>(text.size()), nullptr,
                                       0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), size);
  return out;
}

const EncodableValue* Argument(const flutter::MethodCall<EncodableValue>& call,
                               const char* name) {
  const auto* map = std::get_if<EncodableMap>(call.arguments());
  if (map == nullptr) return nullptr;
  const auto found = map->find(EncodableValue(name));
  return found == map->end() ? nullptr : &found->second;
}

std::string StringArgument(const flutter::MethodCall<EncodableValue>& call,
                           const char* name) {
  const EncodableValue* value = Argument(call, name);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? std::string() : *text;
}

std::string MessageFor(const std::string& code) {
  if (code == "no_backend") return "The speech recognition libraries are missing";
  if (code == "no_model") return "The speech model is not loaded";
  if (code == "bad_model") return "The speech model file is damaged";
  if (code == "no_speech") return "No speech was heard";
  if (code == "aborted") return "Cancelled";
  return "Speech recognition failed";
}

}  // namespace

// static
void WhisperVoicePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<WhisperVoicePlugin>(registrar));
}

WhisperVoicePlugin::WhisperVoicePlugin(
    flutter::PluginRegistrarWindows* registrar) {
  const HINSTANCE module = reinterpret_cast<HINSTANCE>(&__ImageBase);
  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = module;
  window_class.lpszClassName = kWindowClass;
  RegisterClassW(&window_class);  // already registered by an earlier engine
  window_ = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                            nullptr, module, nullptr);

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "whisper_voice",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

WhisperVoicePlugin::~WhisperVoicePlugin() {
  channel_->SetMethodCallHandler(nullptr);
  // Stop both threads before the window goes: they post to it.
  mic_.Stop();
  engine_.Shutdown();
  MSG message;
  while (PeekMessageW(&message, window_, kRunTask, kRunTask, PM_REMOVE)) {
    delete reinterpret_cast<std::function<void()>*>(message.lParam);
  }
  DestroyWindow(window_);
}

void WhisperVoicePlugin::RunOnPlatformThread(std::function<void()> task) {
  auto* posted = new std::function<void()>(std::move(task));
  if (window_ == nullptr ||
      !PostMessageW(window_, kRunTask, 0, reinterpret_cast<LPARAM>(posted))) {
    delete posted;
  }
}

// static
LRESULT CALLBACK WhisperVoicePlugin::WindowProc(HWND window, UINT message,
                                                WPARAM wparam, LPARAM lparam) {
  if (message == kRunTask) {
    std::unique_ptr<std::function<void()>> task(
        reinterpret_cast<std::function<void()>*>(lparam));
    (*task)();
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void WhisperVoicePlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "start") {
    std::string code;
    std::string message;
    const bool started = mic_.Start(
        [this](float level) {
          RunOnPlatformThread([this, level] {
            channel_->InvokeMethod(
                "level",
                std::make_unique<EncodableValue>(static_cast<double>(level)));
          });
        },
        &code, &message);
    if (started) {
      result->Success();
    } else {
      result->Error(code, message);
    }
    return;
  }

  if (method == "stop") {
    result->Success(EncodableValue(mic_.Stop()));
    return;
  }

  if (method == "cancel") {
    mic_.Stop();
    mic_.Take();
    engine_.Abort();
    result->Success();
    return;
  }

  if (method == "loadModel") {
    const std::wstring path = Utf8ToWide(StringArgument(call, "path"));
    Result shared(std::move(result));
    engine_.Post([this, path, shared] {
      std::string code;
      const bool loaded = engine_.Load(path, &code);
      RunOnPlatformThread([shared, loaded, code] {
        if (loaded) {
          shared->Success();
        } else {
          shared->Error(code, MessageFor(code));
        }
      });
      if (loaded) engine_.Prime();
    });
    return;
  }

  if (method == "unloadModel") {
    Result shared(std::move(result));
    engine_.Post([this, shared] {
      engine_.Unload();
      RunOnPlatformThread([shared] { shared->Success(); });
    });
    return;
  }

  if (method == "transcribe") {
    std::vector<float> samples;
    const EncodableValue* given = Argument(call, "samples");
    const auto* list =
        given == nullptr ? nullptr : std::get_if<std::vector<float>>(given);
    if (list != nullptr) {
      samples = *list;
    } else {
      mic_.Stop();
      samples = mic_.Take();
    }
    std::string language = StringArgument(call, "language");
    std::vector<std::string> candidates;
    const EncodableValue* names = Argument(call, "candidates");
    if (const auto* items =
            names == nullptr ? nullptr : std::get_if<EncodableList>(names)) {
      for (const EncodableValue& item : *items) {
        if (const auto* name = std::get_if<std::string>(&item)) {
          candidates.push_back(*name);
        }
      }
    }
    const EncodableValue* context = Argument(call, "audioContext");
    const auto* context_steps =
        context == nullptr ? nullptr : std::get_if<int32_t>(context);
    const int audio_context = context_steps == nullptr ? 512 : *context_steps;
    const uint64_t generation = engine_.generation();
    Result shared(std::move(result));
    engine_.Post([this, samples = std::move(samples),
                  language = std::move(language),
                  candidates = std::move(candidates), audio_context,
                  generation, shared]() mutable {
      Transcript transcript;
      std::string code;
      const bool done = engine_.Transcribe(std::move(samples), language,
                                           candidates, audio_context,
                                           generation, &transcript, &code);
      RunOnPlatformThread([shared, done, transcript, code] {
        if (done) {
          shared->Success(EncodableValue(EncodableMap{
              {EncodableValue("text"), EncodableValue(transcript.text)},
              {EncodableValue("language"), EncodableValue(transcript.language)},
          }));
        } else {
          shared->Error(code, MessageFor(code));
        }
      });
      if (language.empty() || language == "auto") engine_.Prime();
    });
    return;
  }

  result->NotImplemented();
}

}  // namespace whisper_voice
