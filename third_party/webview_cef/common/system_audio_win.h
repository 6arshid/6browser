// 6browser patch: "Also share system audio" when sharing the screen.
#ifndef WEBVIEW_CEF_SYSTEM_AUDIO_WIN_H_
#define WEBVIEW_CEF_SYSTEM_AUDIO_WIN_H_

#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

// Captures everything the computer plays EXCEPT this browser's own sound
// (its whole process tree, which includes Chromium's audio service). Sharing
// a screen in a call therefore does not send the other people's voices back
// to them. CEF's own desktop audio is a plain "loopback" that includes them.
//
// Uses Windows process loopback (Windows 10 build 20348 / Windows 11 and
// later); IsSupported() is false elsewhere and on other platforms.
class SystemAudioCapture {
public:
    static constexpr int kSampleRate = 48000;
    static constexpr int kChannels = 2;

    // 16-bit interleaved stereo PCM at kSampleRate, about 20 ms per call.
    // Called on the capture thread.
    using Sink = std::function<void(std::vector<int16_t> pcm)>;

    static bool IsSupported();

    explicit SystemAudioCapture(Sink sink);
    ~SystemAudioCapture();  // Stops.

    SystemAudioCapture(const SystemAudioCapture&) = delete;
    SystemAudioCapture& operator=(const SystemAudioCapture&) = delete;

    // False when Windows refused the capture.
    bool Start();
    void Stop();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

#endif  // WEBVIEW_CEF_SYSTEM_AUDIO_WIN_H_
