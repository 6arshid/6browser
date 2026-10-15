"""Adds a --child-host mode to the spike copy of cefsimple (E:\\6b_spike\\cef_src)."""
P = r"E:\6b_spike\cef_src\tests\cefsimple\simple_app.cc"
s = open(P, "rb").read().decode("utf-8")
s = s.replace("\r\n", "\n")  # work in LF, write back as CRLF

OLD = """#if defined(OS_WIN)
    // On Windows we need to specify certain flags that will be passed to
    // CreateWindowEx().
    window_info.SetAsPopup(nullptr, "cefsimple");
#endif"""
NEW = """#if defined(OS_WIN)
    if (command_line->HasSwitch("child-host")) {
      // SPIKE: host the browser as a child of our own parent window, the way
      // 6browser would host it inside the Flutter window. The top 64px stand
      // in for the Flutter toolbar.
      HWND parent = CreateSpikeParentWindow();
      RECT rc;
      GetClientRect(parent, &rc);
      window_info.SetAsChild(parent, CefRect(0, 64, rc.right, rc.bottom - 64));
    } else {
      // On Windows we need to specify certain flags that will be passed to
      // CreateWindowEx().
      window_info.SetAsPopup(nullptr, "cefsimple");
    }
#endif"""
assert OLD in s, "anchor not found"
s = s.replace(OLD, NEW, 1)

HELPER = """#if defined(OS_WIN)
#include <windows.h>
namespace {
LRESULT CALLBACK SpikeParentProc(HWND h, UINT m, WPARAM w, LPARAM l) {
  if (m == WM_PAINT) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(h, &ps);
    RECT bar = {0, 0, 4000, 64};
    HBRUSH brush = CreateSolidBrush(RGB(63, 81, 181));  // stands in for Flutter
    FillRect(dc, &bar, brush);
    DeleteObject(brush);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    const wchar_t kLabel[] = L"6browser spike: Flutter area (parent window)";
    TextOutW(dc, 16, 22, kLabel, static_cast<int>(wcslen(kLabel)));
    EndPaint(h, &ps);
    return 0;
  }
  if (m == WM_DESTROY) {
    CefQuitMessageLoop();
    return 0;
  }
  return DefWindowProcW(h, m, w, l);
}

HWND CreateSpikeParentWindow() {
  WNDCLASSW wc = {};
  wc.lpfnWndProc = SpikeParentProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"SpikeParent";
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  return CreateWindowExW(0, L"SpikeParent", L"6browser child-host spike",
                         WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_VISIBLE,
                         100, 100, 1200, 800, nullptr, nullptr, wc.hInstance,
                         nullptr);
}
}  // namespace
#endif

"""
anchor = "namespace {"
i = s.index(anchor)
s = s[:i] + HELPER + s[i:]
open(P, "wb").write(s.replace("\n", "\r\n").encode("utf-8"))
print("patched")
