#ifndef WHISPER_VOICE_SPEECH_ENGINE_H_
#define WHISPER_VOICE_SPEECH_ENGINE_H_

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct whisper_context;

namespace whisper_voice {

struct Transcript {
  std::string text;
  // The language it was recognized in ("fa", "en"...).
  std::string language;
};

// whisper.cpp on one worker thread: jobs run one at a time, in the order
// they were posted. Load, Unload and Transcribe are for jobs only.
class SpeechEngine {
 public:
  SpeechEngine();
  ~SpeechEngine();
  SpeechEngine(const SpeechEngine&) = delete;
  SpeechEngine& operator=(const SpeechEngine&) = delete;

  void Post(std::function<void()> job);

  // Aborts the running job, drops queued ones and waits for the worker to
  // end. Later posts are dropped.
  void Shutdown();

  // Loads the model file at [path] unless it is the one loaded. On failure
  // fills [code]: "no_backend" (the ggml CPU libraries are missing),
  // "no_model" (cannot open the file) or "bad_model".
  bool Load(const std::wstring& path, std::string* code);
  void Unload();

  // Recognizes 16 kHz mono [samples] in [language] ("fa", "en"...), or in
  // whichever of [candidates] whisper finds most likely when [language] is
  // "auto". The encoder looks at no less than [audio_context] steps of
  // 20 ms. [generation] is generation() when the job was posted: Abort()
  // since then stops it. On failure fills [code]: "no_model", "no_speech"
  // (only background noise), "aborted" or "failed".
  bool Transcribe(std::vector<float> samples, const std::string& language,
                  const std::vector<std::string>& candidates,
                  int audio_context, uint64_t generation, Transcript* out,
                  std::string* code);

  // Makes the next language detection fast; run when idle (after loading
  // and after each transcription).
  void Prime();

  // Any thread.
  uint64_t generation() const { return generation_.load(); }
  void Abort() { generation_++; }

 private:
  void Run();

  std::thread thread_;
  std::mutex mutex_;
  std::condition_variable wake_;
  std::deque<std::function<void()>> jobs_;
  bool quit_ = false;

  whisper_context* context_ = nullptr;
  std::wstring loaded_path_;
  std::atomic<uint64_t> generation_{0};
};

}  // namespace whisper_voice

#endif  // WHISPER_VOICE_SPEECH_ENGINE_H_
