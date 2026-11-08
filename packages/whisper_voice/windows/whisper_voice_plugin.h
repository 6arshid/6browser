#ifndef FLUTTER_PLUGIN_WHISPER_VOICE_PLUGIN_H_
#define FLUTTER_PLUGIN_WHISPER_VOICE_PLUGIN_H_

// clang-format off
#include <windows.h>
// clang-format on

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <functional>
#include <memory>

#include "mic_capture.h"
#include "speech_engine.h"

namespace whisper_voice {

// Channel "whisper_voice":
//   start                 records the microphone; levels come back as
//                         "level" calls (RMS 0..1, every 50 ms)
//   stop -> ms            stops recording, keeps the audio
//   cancel                stops recording and drops the audio, aborts a
//                         transcription in progress
//   loadModel {path}      loads (or keeps) a ggml model file
//   unloadModel           frees the model's memory
//   transcribe {language, candidates, audioContext, samples?}
//                         -> {text, language}
//                         recognizes the recording, or [samples] (16 kHz
//                         mono float) when given
class WhisperVoicePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit WhisperVoicePlugin(flutter::PluginRegistrarWindows* registrar);
  ~WhisperVoicePlugin() override;

  WhisperVoicePlugin(const WhisperVoicePlugin&) = delete;
  WhisperVoicePlugin& operator=(const WhisperVoicePlugin&) = delete;

 private:
  using Result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Runs [task] on the platform thread; callable from any thread.
  void RunOnPlatformThread(std::function<void()> task);
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  // Message-only window that receives tasks for the platform thread.
  HWND window_ = nullptr;
  MicCapture mic_;
  SpeechEngine engine_;
};

}  // namespace whisper_voice

#endif  // FLUTTER_PLUGIN_WHISPER_VOICE_PLUGIN_H_
