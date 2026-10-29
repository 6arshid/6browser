#include "webview_cef_gpu_texture.h"

#include <flutter_windows.h>

#include <algorithm>
#include <iostream>

namespace webview_cef {

    using Microsoft::WRL::ComPtr;

    namespace {
        // Maps CEF/D3D BGRA or RGBA to the matching Flutter pixel format.
        FlutterDesktopPixelFormat ToFlutterFormat(DXGI_FORMAT format) {
            switch (format) {
                case DXGI_FORMAT_R8G8B8A8_UNORM:
                case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
                    return kFlutterDesktopPixelFormatRGBA8888;
                default:
                    return kFlutterDesktopPixelFormatBGRA8888;
            }
        }

        // Holds a reference to the bridge texture for the lifetime of one Flutter
        // "obtain descriptor" call so the shared handle stays valid until Flutter
        // has opened it. The engine invokes release_callback when it is done.
        struct DescriptorHolder {
            ComPtr<ID3D11Texture2D> texture;
            FlutterDesktopGpuSurfaceDescriptor descriptor = {};
        };
    }  // namespace

    WebviewGpuTextureRenderer::WebviewGpuTextureRenderer(FlutterDesktopTextureRegistrarRef registrar)
        : registrar_(registrar) {
        // Create our own hardware D3D11 device. BGRA support is required so the
        // bridge texture format matches CEF's output and Flutter/ANGLE.
        const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
        ComPtr<ID3D11Device> device;
        ComPtr<ID3D11DeviceContext> context;
        HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
                                       levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                                       &device, nullptr, &context);
        if (FAILED(hr)) {
            // Fall back to the WARP software renderer (still GPU-surface based).
            hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
                                   levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                                   &device, nullptr, &context);
        }
        if (FAILED(hr)) {
            std::cerr << "webview_cef: D3D11CreateDevice failed (0x" << std::hex << hr
                      << "); GPU texture path unavailable." << std::endl;
            return;
        }
        // OpenSharedResource1 (for CEF's NT shared handle) needs ID3D11Device1.
        if (FAILED(device.As(&device_))) {
            device_.Reset();
            return;
        }
        context_ = context;

        FlutterDesktopTextureInfo info = {};
        info.type = kFlutterDesktopGpuSurfaceTexture;
        info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
        info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
        info.gpu_surface_config.user_data = this;
        info.gpu_surface_config.callback =
            [](size_t width, size_t height, void* user_data) -> const FlutterDesktopGpuSurfaceDescriptor* {
                return static_cast<WebviewGpuTextureRenderer*>(user_data)->ObtainDescriptor(width, height);
            };
        textureId = FlutterDesktopTextureRegistrarRegisterExternalTexture(registrar_, &info);
    }

    WebviewGpuTextureRenderer::~WebviewGpuTextureRenderer() {
        if (registrar_ && textureId) {
            // 6browser patch: Flutter's raster thread may still be drawing this
            // texture (ObtainDescriptor gets |this|); wait until it lets go
            // before freeing. Not under |mutex_|, which that call takes.
            HANDLE done = CreateEventW(nullptr, TRUE, FALSE, nullptr);
            void (*signal)(void*) = [](void* event) { SetEvent(static_cast<HANDLE>(event)); };
            FlutterDesktopTextureRegistrarUnregisterExternalTexture(
                registrar_, textureId, done ? signal : nullptr, done);
            // On a timeout the callback may still come later: keep the event.
            if (done && WaitForSingleObject(done, 1000) == WAIT_OBJECT_0) {
                CloseHandle(done);
            }
        }
    }

    bool WebviewGpuTextureRenderer::EnsureBridgeTexture(UINT width, UINT height, DXGI_FORMAT format) {
        if (bridge_tex_ && tex_width_ == width && tex_height_ == height && tex_format_ == format) {
            return true;
        }
        bridge_tex_.Reset();
        shared_handle_ = nullptr;

        D3D11_TEXTURE2D_DESC desc = {};
        desc.Width = width;
        desc.Height = height;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = format;
        desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
        // Legacy shared so ANGLE can open the texture on its own device through a
        // share handle (EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE).
        desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
        if (FAILED(device_->CreateTexture2D(&desc, nullptr, &bridge_tex_))) {
            return false;
        }
        ComPtr<IDXGIResource> dxgi_resource;
        if (FAILED(bridge_tex_.As(&dxgi_resource)) ||
            FAILED(dxgi_resource->GetSharedHandle(&shared_handle_)) || !shared_handle_) {
            bridge_tex_.Reset();
            shared_handle_ = nullptr;
            return false;
        }
        tex_width_ = width;
        tex_height_ = height;
        tex_format_ = format;
        flutter_format_ = ToFlutterFormat(format);
        return true;
    }

    ComPtr<ID3D11Texture2D> WebviewGpuTextureRenderer::OpenCefTexture(const void* sharedHandle) {
        // CEF's shared texture is pool-owned and only valid during this call, so
        // reopen it on our device every frame (NT handle -> OpenSharedResource1).
        ComPtr<ID3D11Texture2D> tex;
        if (!device_ || sharedHandle == nullptr) return tex;
        if (FAILED(device_->OpenSharedResource1(
                reinterpret_cast<HANDLE>(const_cast<void*>(sharedHandle)), IID_PPV_ARGS(&tex)))) {
            tex.Reset();
        }
        return tex;
    }

    bool WebviewGpuTextureRenderer::EnsureCopy(ID3D11Device* device, ComPtr<ID3D11Texture2D>& tex,
                                               const D3D11_TEXTURE2D_DESC& like) {
        if (tex) {
            D3D11_TEXTURE2D_DESC have = {};
            tex->GetDesc(&have);
            if (have.Width == like.Width && have.Height == like.Height && have.Format == like.Format) {
                return true;
            }
            tex.Reset();
        }
        D3D11_TEXTURE2D_DESC desc = {};
        desc.Width = like.Width;
        desc.Height = like.Height;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = like.Format;
        desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
        return SUCCEEDED(device->CreateTexture2D(&desc, nullptr, &tex));
    }

    void WebviewGpuTextureRenderer::onAcceleratedFrame(const void* sharedHandle, int width, int height, int format) {
        std::lock_guard<std::mutex> lock(mutex_);
        ComPtr<ID3D11Texture2D> cef_tex = OpenCefTexture(sharedHandle);
        if (!cef_tex) {
            return;
        }

        D3D11_TEXTURE2D_DESC src_desc = {};
        cef_tex->GetDesc(&src_desc);
        if (!EnsureBridgeTexture(src_desc.Width, src_desc.Height, src_desc.Format)) {
            return;
        }

        context_->CopyResource(bridge_tex_.Get(), cef_tex.Get());
        if (popup_shown_) {
            // Keep the bare page so the popup can be redrawn or removed later.
            page_saved_ = EnsureCopy(device_.Get(), page_tex_, src_desc);
            if (page_saved_) context_->CopyResource(page_tex_.Get(), cef_tex.Get());
            CompositePopup();
        }
        FrameAvailable();
    }

    // 6browser patch: CEF paints popup widgets (<select> dropdowns, date
    // pickers) separately; they used to replace the whole page texture.
    void WebviewGpuTextureRenderer::onAcceleratedPopup(const void* sharedHandle, int x, int y) {
        std::lock_guard<std::mutex> lock(mutex_);
        ComPtr<ID3D11Texture2D> cef_tex = OpenCefTexture(sharedHandle);
        if (!cef_tex || !bridge_tex_) {
            return;
        }
        D3D11_TEXTURE2D_DESC desc = {};
        cef_tex->GetDesc(&desc);
        if (desc.Format != tex_format_ || !EnsureCopy(device_.Get(), popup_tex_, desc)) {
            return;
        }
        context_->CopyResource(popup_tex_.Get(), cef_tex.Get());
        if (!page_saved_) {
            // The bridge still holds the bare page: keep it before drawing over.
            D3D11_TEXTURE2D_DESC page = {};
            bridge_tex_->GetDesc(&page);
            page_saved_ = EnsureCopy(device_.Get(), page_tex_, page);
            if (!page_saved_) return;
            context_->CopyResource(page_tex_.Get(), bridge_tex_.Get());
        } else {
            context_->CopyResource(bridge_tex_.Get(), page_tex_.Get());
        }
        popup_shown_ = true;
        popup_x_ = x;
        popup_y_ = y;
        CompositePopup();
        FrameAvailable();
    }

    void WebviewGpuTextureRenderer::hidePopup() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (popup_shown_ && page_saved_ && bridge_tex_) {
            context_->CopyResource(bridge_tex_.Get(), page_tex_.Get());
            FrameAvailable();
        }
        popup_shown_ = false;
        page_saved_ = false;
        popup_tex_.Reset();
        page_tex_.Reset();
    }

    void WebviewGpuTextureRenderer::CompositePopup() {
        if (!popup_tex_ || !bridge_tex_) return;
        D3D11_TEXTURE2D_DESC desc = {};
        popup_tex_->GetDesc(&desc);
        // Clip to the page.
        const int left = (std::max)(popup_x_, 0);
        const int top = (std::max)(popup_y_, 0);
        const int right = (std::min)(popup_x_ + static_cast<int>(desc.Width), static_cast<int>(tex_width_));
        const int bottom = (std::min)(popup_y_ + static_cast<int>(desc.Height), static_cast<int>(tex_height_));
        if (right <= left || bottom <= top) return;
        D3D11_BOX box = {};
        box.left = static_cast<UINT>(left - popup_x_);
        box.top = static_cast<UINT>(top - popup_y_);
        box.right = static_cast<UINT>(right - popup_x_);
        box.bottom = static_cast<UINT>(bottom - popup_y_);
        box.front = 0;
        box.back = 1;
        context_->CopySubresourceRegion(bridge_tex_.Get(), 0, left, top, 0, popup_tex_.Get(), 0, &box);
    }

    void WebviewGpuTextureRenderer::FrameAvailable() {
        context_->Flush();
        if (registrar_ && textureId) {
            FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(registrar_, textureId);
        }
    }

    const FlutterDesktopGpuSurfaceDescriptor* WebviewGpuTextureRenderer::ObtainDescriptor(size_t width, size_t height) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!bridge_tex_ || !shared_handle_) {
            return nullptr;
        }
        auto* holder = new DescriptorHolder();
        holder->texture = bridge_tex_;  // keep alive until Flutter opens the handle
        holder->descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
        holder->descriptor.handle = shared_handle_;
        holder->descriptor.width = holder->descriptor.visible_width = tex_width_;
        holder->descriptor.height = holder->descriptor.visible_height = tex_height_;
        holder->descriptor.format = flutter_format_;
        holder->descriptor.release_callback = [](void* release_context) {
            delete static_cast<DescriptorHolder*>(release_context);
        };
        holder->descriptor.release_context = holder;
        return &holder->descriptor;
    }
}  // namespace webview_cef
