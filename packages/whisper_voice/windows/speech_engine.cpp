#include "speech_engine.h"

// clang-format off
#include <windows.h>
// clang-format on

#include <algorithm>
#include <cmath>
#include <cstdio>

#include "ggml-backend.h"
#include "mic_capture.h"
#include "whisper.h"

namespace whisper_voice {
namespace {

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) return std::string();
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                       static_cast<int>(text.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), size, nullptr, nullptr);
  return out;
}

std::string ExecutableDirectory() {
  wchar_t path[2048] = {};
  const DWORD length = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  std::wstring dir(path, length);
  return WideToUtf8(dir.substr(0, dir.find_last_of(L"\\/")));
}

void LogToDebugger(ggml_log_level, const char* text, void*) {
  OutputDebugStringA(text);
}

// Up to 8 threads: more do not help whisper, and the browser keeps running.
int ThreadCount() {
  const int cores = static_cast<int>(std::thread::hardware_concurrency());
  if (cores <= 4) return std::max(cores, 1);
  return std::clamp(cores / 2, 4, 8);
}

// Cuts the silence before and after the speech, keeping a little of it.
// False when nothing louder than the background noise was recorded.
bool TrimSilence(std::vector<float>* samples) {
  constexpr size_t kFrame = kSampleRate / 50;  // 20 ms
  const size_t frames = samples->size() / kFrame;
  if (frames == 0) return false;
  std::vector<float> rms(frames);
  for (size_t f = 0; f < frames; f++) {
    double sum = 0;
    for (size_t i = f * kFrame; i < (f + 1) * kFrame; i++) {
      sum += static_cast<double>((*samples)[i]) * (*samples)[i];
    }
    rms[f] = static_cast<float>(std::sqrt(sum / kFrame));
  }
  std::vector<float> sorted = rms;
  const auto quiet = sorted.begin() + sorted.size() / 10;
  std::nth_element(sorted.begin(), quiet, sorted.end());
  const float threshold = std::max(0.005f, *quiet * 3.0f);

  size_t first = frames;
  size_t last = 0;
  size_t loud = 0;
  for (size_t f = 0; f < frames; f++) {
    if (rms[f] <= threshold) continue;
    if (first == frames) first = f;
    last = f;
    loud++;
  }
  if (loud < 5) return false;  // under 100 ms of sound
  const size_t begin = first > 15 ? (first - 15) * kFrame : 0;  // 300 ms
  const size_t end = std::min(samples->size(), (last + 21) * kFrame);
  *samples = std::vector<float>(samples->begin() + begin,
                                samples->begin() + end);
  return true;
}

// Brings quiet recordings up to a normal level (at most 10 times louder).
void Normalize(std::vector<float>* samples) {
  float peak = 0;
  for (float s : *samples) peak = std::max(peak, std::fabs(s));
  if (peak <= 0) return;
  const float gain = std::min(0.9f / peak, 10.0f);
  if (gain <= 1) return;
  for (float& s : *samples) s *= gain;
}

struct AbortState {
  const std::atomic<uint64_t>* current;
  uint64_t posted;
};

bool ShouldAbort(void* data) {
  const auto* state = static_cast<AbortState*>(data);
  return state->current->load() != state->posted;
}

}  // namespace

SpeechEngine::SpeechEngine() { thread_ = std::thread(&SpeechEngine::Run, this); }

SpeechEngine::~SpeechEngine() {
  Shutdown();
  Unload();
}

void SpeechEngine::Shutdown() {
  Abort();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    quit_ = true;
    jobs_.clear();
  }
  wake_.notify_one();
  if (thread_.joinable()) thread_.join();
}

void SpeechEngine::Post(std::function<void()> job) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (quit_) return;
    jobs_.push_back(std::move(job));
  }
  wake_.notify_one();
}

void SpeechEngine::Run() {
  while (true) {
    std::function<void()> job;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      wake_.wait(lock, [this] { return quit_ || !jobs_.empty(); });
      if (quit_) return;
      job = std::move(jobs_.front());
      jobs_.pop_front();
    }
    job();
  }
}

bool SpeechEngine::Load(const std::wstring& path, std::string* code) {
  if (context_ != nullptr && path == loaded_path_) return true;
  Unload();

  static bool backends_loaded = false;
  if (!backends_loaded) {
    backends_loaded = true;
    whisper_log_set(LogToDebugger, nullptr);
    // Only from the app's folder: never a DLL from the current directory.
    ggml_backend_load_all_from_path(ExecutableDirectory().c_str());
  }
  if (ggml_backend_dev_count() == 0) {
    *code = "no_backend";
    return false;
  }

  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || file == nullptr) {
    *code = "no_model";
    return false;
  }
  whisper_model_loader loader = {};
  loader.context = file;
  loader.read = [](void* context, void* output, size_t size) {
    return fread(output, 1, size, static_cast<FILE*>(context));
  };
  loader.eof = [](void* context) {
    return feof(static_cast<FILE*>(context)) != 0;
  };
  loader.close = [](void* context) { fclose(static_cast<FILE*>(context)); };

  whisper_context_params params = whisper_context_default_params();
  params.use_gpu = false;
  // Closes the file whether or not it loads.
  context_ = whisper_init_with_params(&loader, params);
  if (context_ == nullptr) {
    *code = "bad_model";
    return false;
  }
  loaded_path_ = path;
  return true;
}

void SpeechEngine::Unload() {
  if (context_ != nullptr) whisper_free(context_);
  context_ = nullptr;
  loaded_path_.clear();
}

bool SpeechEngine::Transcribe(std::vector<float> samples,
                              const std::string& language,
                              const std::vector<std::string>& candidates,
                              int audio_context, uint64_t generation,
                              Transcript* out, std::string* code) {
  AbortState abort = {&generation_, generation};
  if (ShouldAbort(&abort)) {
    *code = "aborted";
    return false;
  }
  if (context_ == nullptr) {
    *code = "no_model";
    return false;
  }
  if (!TrimSilence(&samples)) {
    *code = "no_speech";
    return false;
  }
  Normalize(&samples);
  // A moment of silence before the speech, and at least 1.2 s in all.
  samples.insert(samples.begin(), kSampleRate / 5, 0.0f);
  samples.resize(std::max<size_t>(samples.size() + kSampleRate / 5,
                                  kSampleRate * 6 / 5),
                 0.0f);
  const int count = static_cast<int>(samples.size());
  const int threads = ThreadCount();

  std::string lang = language;
  if (lang.empty() || lang == "auto") {
    // Whisper's own detection picks among ~100 languages and short commands
    // are easily taken for a neighbour (Persian for Arabic or Urdu), so only
    // the expected ones compete. Detection runs the encoder at the context
    // size Prime() left (see there).
    if (whisper_pcm_to_mel(context_, samples.data(), count, threads) != 0) {
      *code = "failed";
      return false;
    }
    std::vector<float> probabilities(whisper_lang_max_id() + 1, 0.0f);
    if (whisper_lang_auto_detect(context_, 0, threads, probabilities.data()) <
        0) {
      *code = "failed";
      return false;
    }
    float best = -1;
    for (const std::string& candidate : candidates) {
      const int id = whisper_lang_id(candidate.c_str());
      if (id >= 0 && probabilities[id] > best) {
        best = probabilities[id];
        lang = candidate;
      }
    }
    if (best < 0) lang = "en";
    if (ShouldAbort(&abort)) {
      *code = "aborted";
      return false;
    }
  }

  whisper_full_params params =
      whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH);
  params.beam_search.beam_size = 5;
  params.n_threads = threads;
  // The encoder only looks at as much audio as was recorded instead of
  // whisper's 30 s window: several times faster for short commands. Each
  // context step is 20 ms; [audio_context] is the smallest the model stays
  // accurate with (larger models need more).
  const int needed = (count / (kSampleRate / 50) + 63) / 64 * 64;
  params.audio_ctx = std::clamp(std::max(needed, audio_context), 64, 1500);
  params.language = lang.c_str();
  params.detect_language = false;
  params.translate = false;
  params.no_context = true;
  params.no_timestamps = true;
  params.single_segment = true;
  params.suppress_nst = true;
  params.print_special = false;
  params.print_progress = false;
  params.print_realtime = false;
  params.print_timestamps = false;
  params.abort_callback = ShouldAbort;
  params.abort_callback_user_data = &abort;
  const int result = whisper_full(context_, params, samples.data(), count);
  if (ShouldAbort(&abort)) {
    *code = "aborted";
    return false;
  }
  if (result != 0) {
    *code = "failed";
    return false;
  }

  std::string text;
  const int segments = whisper_full_n_segments(context_);
  for (int i = 0; i < segments; i++) {
    text += whisper_full_get_segment_text(context_, i);
  }
  const size_t start = text.find_first_not_of(" \t\r\n");
  const size_t end = text.find_last_not_of(" \t\r\n");
  out->text = start == std::string::npos ? "" : text.substr(start, end - start + 1);
  out->language = lang;
  return true;
}

void SpeechEngine::Prime() {
  if (context_ == nullptr) return;
  // whisper_lang_auto_detect encodes at the context size of the last
  // whisper_full call (the full 30 s before the first one). A run on a
  // moment of silence at a small size makes the next detection several
  // times cheaper; 5 s of audio is plenty to tell the language.
  std::vector<float> silence(kSampleRate, 0.0f);
  whisper_full_params params =
      whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.n_threads = ThreadCount();
  params.audio_ctx = 256;
  params.language = "en";
  params.max_tokens = 1;
  params.no_context = true;
  params.no_timestamps = true;
  params.single_segment = true;
  params.print_special = false;
  params.print_progress = false;
  params.print_realtime = false;
  params.print_timestamps = false;
  whisper_full(context_, params, silence.data(),
               static_cast<int>(silence.size()));
}

}  // namespace whisper_voice
