// 6browser patch: see system_audio_win.h.
#include "system_audio_win.h"

#ifdef _WIN32

#include <windows.h>
#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <atomic>
#include <thread>

using Microsoft::WRL::ComPtr;

namespace {

constexpr UINT32 kChunkFrames = SystemAudioCapture::kSampleRate / 50;  // 20 ms
constexpr REFERENCE_TIME kBufferDuration = 2000000;                    // 200 ms

// Process loopback arrived in Windows 10 build 20348.
constexpr DWORD kFirstSupportedBuild = 20348;

DWORD WindowsBuild() {
    using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    auto get_version = ntdll ? reinterpret_cast<RtlGetVersionFn>(
                                   GetProcAddress(ntdll, "RtlGetVersion"))
                             : nullptr;
    RTL_OSVERSIONINFOW info = {};
    info.dwOSVersionInfoSize = sizeof(info);
    if (!get_version || get_version(&info) != 0) return 0;
    return info.dwBuildNumber;
}

// Loaded at run time: older Windows lacks parts of the process loopback API.
using ActivateFn = HRESULT(WINAPI*)(LPCWSTR, REFIID, PROPVARIANT*,
                                    IActivateAudioInterfaceCompletionHandler*,
                                    IActivateAudioInterfaceAsyncOperation**);

ActivateFn ActivateFunction() {
    static ActivateFn activate = [] {
        HMODULE module = LoadLibraryExW(L"mmdevapi.dll", nullptr,
                                        LOAD_LIBRARY_SEARCH_SYSTEM32);
        return module ? reinterpret_cast<ActivateFn>(
                            GetProcAddress(module, "ActivateAudioInterfaceAsync"))
                      : nullptr;
    }();
    return activate;
}

class ActivationHandler
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          Microsoft::WRL::FtmBase, IActivateAudioInterfaceCompletionHandler> {
public:
    ActivationHandler() { done_ = CreateEventW(nullptr, TRUE, FALSE, nullptr); }
    ~ActivationHandler() override {
        if (done_) CloseHandle(done_);
    }

    STDMETHOD(ActivateCompleted)(IActivateAudioInterfaceAsyncOperation* op) override {
        HRESULT result = E_FAIL;
        ComPtr<IUnknown> unknown;
        if (SUCCEEDED(op->GetActivateResult(&result, &unknown)) && SUCCEEDED(result) && unknown) {
            unknown.As(&client_);
        }
        SetEvent(done_);
        return S_OK;
    }

    HANDLE done() const { return done_; }
    ComPtr<IAudioClient> client() const { return client_; }

private:
    HANDLE done_ = nullptr;
    ComPtr<IAudioClient> client_;
};

}  // namespace

struct SystemAudioCapture::Impl {
    Sink sink;
    std::thread thread;
    HANDLE stop = nullptr;

    void Run(HANDLE started, std::atomic<bool>* ok);
};

void SystemAudioCapture::Impl::Run(HANDLE started, std::atomic<bool>* ok) {
    const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
    ComPtr<IAudioClient> client;
    ComPtr<IAudioCaptureClient> capture;
    HANDLE ready = nullptr;
    bool good = false;
    do {
        ActivateFn activate = ActivateFunction();
        if (!activate) break;
        AUDIOCLIENT_ACTIVATION_PARAMS params = {};
        params.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
        params.ProcessLoopbackParams.TargetProcessId = GetCurrentProcessId();
        params.ProcessLoopbackParams.ProcessLoopbackMode =
            PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE;
        PROPVARIANT property = {};
        property.vt = VT_BLOB;
        property.blob.cbSize = sizeof(params);
        property.blob.pBlobData = reinterpret_cast<BYTE*>(&params);

        auto handler = Microsoft::WRL::Make<ActivationHandler>();
        ComPtr<IActivateAudioInterfaceAsyncOperation> operation;
        if (FAILED(activate(VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
                            &property, handler.Get(), &operation))) {
            break;
        }
        if (WaitForSingleObject(handler->done(), 5000) != WAIT_OBJECT_0) break;
        client = handler->client();
        if (!client) break;

        // Process loopback has no mix format of its own; Windows converts to
        // the format asked for.
        WAVEFORMATEX format = {};
        format.wFormatTag = WAVE_FORMAT_PCM;
        format.nChannels = kChannels;
        format.nSamplesPerSec = kSampleRate;
        format.wBitsPerSample = 16;
        format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
        format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
        if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                      AUDCLNT_STREAMFLAGS_LOOPBACK |
                                          AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                                          AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
                                      kBufferDuration, 0, &format, nullptr))) {
            break;
        }
        ready = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!ready || FAILED(client->SetEventHandle(ready))) break;
        if (FAILED(client->GetService(IID_PPV_ARGS(&capture)))) break;
        if (FAILED(client->Start())) break;
        good = true;
    } while (false);

    ok->store(good);
    SetEvent(started);

    if (good) {
        const size_t chunk_samples = size_t(kChunkFrames) * kChannels;
        std::vector<int16_t> chunk;
        chunk.reserve(chunk_samples * 2);
        HANDLE waits[2] = {stop, ready};
        while (WaitForMultipleObjects(2, waits, FALSE, INFINITE) == WAIT_OBJECT_0 + 1) {
            UINT32 packet = 0;
            while (SUCCEEDED(capture->GetNextPacketSize(&packet)) && packet > 0) {
                BYTE* data = nullptr;
                UINT32 frames = 0;
                DWORD flags = 0;
                if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
                const size_t samples = size_t(frames) * kChannels;
                if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) || !data) {
                    chunk.insert(chunk.end(), samples, 0);
                } else {
                    const auto* pcm = reinterpret_cast<const int16_t*>(data);
                    chunk.insert(chunk.end(), pcm, pcm + samples);
                }
                capture->ReleaseBuffer(frames);
                if (chunk.size() >= chunk_samples) {
                    sink(std::move(chunk));
                    chunk = std::vector<int16_t>();
                    chunk.reserve(chunk_samples * 2);
                }
            }
        }
        client->Stop();
    }
    capture.Reset();
    client.Reset();
    if (ready) CloseHandle(ready);
    if (SUCCEEDED(com)) CoUninitialize();
}

bool SystemAudioCapture::IsSupported() {
    static const bool supported =
        WindowsBuild() >= kFirstSupportedBuild && ActivateFunction() != nullptr;
    return supported;
}

SystemAudioCapture::SystemAudioCapture(Sink sink) : impl_(std::make_unique<Impl>()) {
    impl_->sink = std::move(sink);
}

SystemAudioCapture::~SystemAudioCapture() { Stop(); }

bool SystemAudioCapture::Start() {
    if (impl_->thread.joinable() || !IsSupported()) return false;
    impl_->stop = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE started = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!impl_->stop || !started) {
        if (started) CloseHandle(started);
        return false;
    }
    std::atomic<bool> ok{false};
    impl_->thread = std::thread(&Impl::Run, impl_.get(), started, &ok);
    WaitForSingleObject(started, INFINITE);
    CloseHandle(started);
    if (!ok.load()) {
        Stop();
        return false;
    }
    return true;
}

void SystemAudioCapture::Stop() {
    if (impl_->stop) SetEvent(impl_->stop);
    if (impl_->thread.joinable()) impl_->thread.join();
    if (impl_->stop) {
        CloseHandle(impl_->stop);
        impl_->stop = nullptr;
    }
}

#else  // !_WIN32

struct SystemAudioCapture::Impl {};

bool SystemAudioCapture::IsSupported() { return false; }
SystemAudioCapture::SystemAudioCapture(Sink) : impl_(std::make_unique<Impl>()) {}
SystemAudioCapture::~SystemAudioCapture() = default;
bool SystemAudioCapture::Start() { return false; }
void SystemAudioCapture::Stop() {}

#endif  // _WIN32
