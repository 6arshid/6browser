#ifndef WHISPER_VOICE_MIC_CAPTURE_H_
#define WHISPER_VOICE_MIC_CAPTURE_H_

// clang-format off
#include <windows.h>
#include <mmsystem.h>
// clang-format on

#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace whisper_voice {

// Whisper's input: 16 kHz mono.
constexpr int kSampleRate = 16000;

// Records the default microphone as 16 kHz mono samples (Windows converts
// from the device format). Levels are reported from the capture thread.
class MicCapture {
 public:
  // RMS level (0..1) of each 50 ms block, called on the capture thread.
  using LevelCallback = std::function<void(float)>;

  MicCapture() = default;
  ~MicCapture();
  MicCapture(const MicCapture&) = delete;
  MicCapture& operator=(const MicCapture&) = delete;

  // Starts recording (a recording in progress is dropped). On failure fills
  // [code]: "mic_blocked" (Windows privacy settings), "no_microphone",
  // "mic_busy" or "mic_error".
  bool Start(LevelCallback on_level, std::string* code, std::string* message);

  // Stops recording and keeps what was recorded. Returns its length in ms.
  int64_t Stop();

  // Hands over the recorded samples (empty afterwards).
  std::vector<float> Take();

  bool recording() const { return wave_ != nullptr; }

 private:
  static constexpr int kBuffers = 8;
  static constexpr int kBufferSamples = kSampleRate / 20;  // 50 ms
  static constexpr size_t kMaxSamples = kSampleRate * 30;  // whisper's window

  void Run();

  HWAVEIN wave_ = nullptr;
  HANDLE event_ = nullptr;
  std::thread thread_;
  WAVEHDR headers_[kBuffers] = {};
  std::vector<int16_t> data_[kBuffers];
  // Queued with the driver; only the capture thread changes these after
  // Start.
  bool in_flight_[kBuffers] = {};
  LevelCallback on_level_;

  // Guards [stopping_] against waveInAddBuffer, so no buffer is queued after
  // waveInReset.
  std::mutex wave_mutex_;
  bool stopping_ = false;

  std::mutex samples_mutex_;
  std::vector<float> samples_;
};

}  // namespace whisper_voice

#endif  // WHISPER_VOICE_MIC_CAPTURE_H_
