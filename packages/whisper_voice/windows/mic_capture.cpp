#include "mic_capture.h"

#include <cmath>

namespace whisper_voice {
namespace {

// A REG_SZ value, or empty when it is missing.
std::wstring ReadRegistryString(HKEY root, const std::wstring& key,
                                const wchar_t* name) {
  wchar_t buffer[64] = {};
  DWORD size = sizeof(buffer);
  if (RegGetValueW(root, key.c_str(), name, RRF_RT_REG_SZ, nullptr, buffer,
                   &size) != ERROR_SUCCESS) {
    return L"";
  }
  return buffer;
}

// Windows' privacy switches: "Microphone access" (device and user) and "Let
// desktop apps access your microphone", which also covers the MSIX build (a
// full-trust desktop app that declares no microphone capability).
bool MicrophoneBlocked() {
  const std::wstring store =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager"
      L"\\ConsentStore\\microphone";
  return ReadRegistryString(HKEY_LOCAL_MACHINE, store, L"Value") == L"Deny" ||
         ReadRegistryString(HKEY_CURRENT_USER, store, L"Value") == L"Deny" ||
         ReadRegistryString(HKEY_CURRENT_USER, store + L"\\NonPackaged",
                            L"Value") == L"Deny";
}

}  // namespace

MicCapture::~MicCapture() { Stop(); }

bool MicCapture::Start(LevelCallback on_level, std::string* code,
                       std::string* message) {
  Stop();
  Take();
  if (MicrophoneBlocked()) {
    *code = "mic_blocked";
    *message = "Microphone access is turned off in Windows settings";
    return false;
  }
  if (waveInGetNumDevs() == 0) {
    *code = "no_microphone";
    *message = "No microphone was found";
    return false;
  }

  event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (event_ == nullptr) {
    *code = "mic_error";
    *message = "CreateEvent failed";
    return false;
  }
  WAVEFORMATEX format = {};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = kSampleRate;
  format.wBitsPerSample = 16;
  format.nBlockAlign = sizeof(int16_t);
  format.nAvgBytesPerSec = kSampleRate * sizeof(int16_t);
  const MMRESULT opened =
      waveInOpen(&wave_, WAVE_MAPPER, &format,
                 reinterpret_cast<DWORD_PTR>(event_), 0, CALLBACK_EVENT);
  if (opened != MMSYSERR_NOERROR) {
    wave_ = nullptr;
    CloseHandle(event_);
    event_ = nullptr;
    *code = opened == MMSYSERR_ALLOCATED ? "mic_busy"
            : opened == MMSYSERR_BADDEVICEID || opened == MMSYSERR_NODRIVER
                ? "no_microphone"
                : "mic_error";
    *message = "waveInOpen failed (" + std::to_string(opened) + ")";
    return false;
  }

  stopping_ = false;
  on_level_ = std::move(on_level);
  for (int i = 0; i < kBuffers; i++) {
    data_[i].assign(kBufferSamples, 0);
    headers_[i] = {};
    headers_[i].lpData = reinterpret_cast<LPSTR>(data_[i].data());
    headers_[i].dwBufferLength = kBufferSamples * sizeof(int16_t);
    waveInPrepareHeader(wave_, &headers_[i], sizeof(WAVEHDR));
    in_flight_[i] =
        waveInAddBuffer(wave_, &headers_[i], sizeof(WAVEHDR)) ==
        MMSYSERR_NOERROR;
  }
  thread_ = std::thread(&MicCapture::Run, this);
  if (waveInStart(wave_) != MMSYSERR_NOERROR) {
    Stop();
    Take();
    *code = "mic_error";
    *message = "waveInStart failed";
    return false;
  }
  return true;
}

void MicCapture::Run() {
  int queued = 0;
  for (bool flying : in_flight_) queued += flying ? 1 : 0;
  // Buffers come back in the order they were queued.
  int next = 0;
  while (queued > 0) {
    WaitForSingleObject(event_, 100);
    for (int k = 0; k < kBuffers && queued > 0; k++) {
      if (!in_flight_[next]) {
        next = (next + 1) % kBuffers;
        continue;
      }
      WAVEHDR& header = headers_[next];
      if ((header.dwFlags & WHDR_DONE) == 0) break;

      const size_t count = header.dwBytesRecorded / sizeof(int16_t);
      double sum = 0;
      {
        std::lock_guard<std::mutex> lock(samples_mutex_);
        for (size_t i = 0; i < count; i++) {
          const float sample = data_[next][i] / 32768.0f;
          sum += static_cast<double>(sample) * sample;
          if (samples_.size() < kMaxSamples) samples_.push_back(sample);
        }
      }
      if (count > 0 && on_level_) {
        on_level_(static_cast<float>(std::sqrt(sum / count)));
      }

      {
        std::lock_guard<std::mutex> lock(wave_mutex_);
        header.dwBytesRecorded = 0;
        header.dwFlags &= ~WHDR_DONE;
        if (stopping_ || waveInAddBuffer(wave_, &header, sizeof(WAVEHDR)) !=
                             MMSYSERR_NOERROR) {
          in_flight_[next] = false;
          queued--;
        }
      }
      next = (next + 1) % kBuffers;
    }
  }
}

int64_t MicCapture::Stop() {
  if (wave_ != nullptr) {
    {
      // waveInReset hands every queued buffer back as done; the capture
      // thread then stops re-queuing them and exits.
      std::lock_guard<std::mutex> lock(wave_mutex_);
      stopping_ = true;
      waveInReset(wave_);
    }
    SetEvent(event_);
    if (thread_.joinable()) thread_.join();
    for (WAVEHDR& header : headers_) {
      waveInUnprepareHeader(wave_, &header, sizeof(WAVEHDR));
    }
    waveInClose(wave_);
    wave_ = nullptr;
    CloseHandle(event_);
    event_ = nullptr;
    on_level_ = nullptr;
  }
  std::lock_guard<std::mutex> lock(samples_mutex_);
  return static_cast<int64_t>(samples_.size()) * 1000 / kSampleRate;
}

std::vector<float> MicCapture::Take() {
  std::lock_guard<std::mutex> lock(samples_mutex_);
  std::vector<float> samples;
  samples.swap(samples_);
  return samples;
}

}  // namespace whisper_voice
