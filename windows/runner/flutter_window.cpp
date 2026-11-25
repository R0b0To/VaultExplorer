#include "flutter_window.h"

#include <commctrl.h>

#include <cwchar>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kCustomCaptionSubclassId = 1;

// Class of the windows the Flutter engine creates for every view of the app
// (the main window included).
constexpr wchar_t kEngineHostWindowClass[] = L"FLUTTER_HOST_WINDOW";

// Gives the top of |client| back to the app: drops the OS caption but keeps
// 1px so DWM still draws its border and the top edge stays grabbable.
// |original_top| is the top of the window rect before the default calculation.
void DropCaption(HWND hwnd, RECT* client, LONG original_top) {
  if (IsZoomed(hwnd)) {
    // A maximized window overhangs the monitor by the sizing-frame
    // thickness, so push the client area back on screen.
    const UINT dpi = GetDpiForWindow(hwnd);
    client->top = original_top + GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
                  GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  } else {
    client->top = original_top + 1;
  }
}

// Hides the OS caption of a window the Flutter engine created (a secondary
// window), the way Win32Window does for the main one: the window keeps its
// overlapped style, so Aero Snap, the maximize animation and the DWM shadow
// still work, and WM_NCCALCSIZE gives the caption's room to the client area.
LRESULT CALLBACK CustomCaptionProc(HWND hwnd,
                                   UINT message,
                                   WPARAM wparam,
                                   LPARAM lparam,
                                   UINT_PTR subclass_id,
                                   DWORD_PTR /*ref_data*/) {
  switch (message) {
    case WM_NCCALCSIZE: {
      if (wparam == TRUE) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const LONG original_top = params->rgrc[0].top;
        // Let Windows compute the left/right/bottom resize frame first.
        const LRESULT result = DefSubclassProc(hwnd, message, wparam, lparam);
        if (result != 0) return result;
        DropCaption(hwnd, &params->rgrc[0], original_top);
        return 0;
      }
      // CreateWindowEx sends the very first calculation with wParam FALSE and
      // a plain RECT. Handling it here is what lets a window come into
      // existence without a caption, instead of being shown with one and
      // corrected afterwards (which flashed the OS frame / an unpainted
      // resize before the first themed frame).
      auto* rect = reinterpret_cast<RECT*>(lparam);
      const LONG original_top = rect->top;
      DefSubclassProc(hwnd, message, wparam, lparam);
      DropCaption(hwnd, rect, original_top);
      return 0;
    }
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, CustomCaptionProc, subclass_id);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

// The engine creates its windows hidden and shows them as soon as the first
// frame of their view is ready, so the caption has to be gone before that
// frame is laid out. A call from Dart after the view exists is too late: it
// arrives once the first frame is already on its way, and the window then
// resizes under a frame that was drawn for the old client area.
//
// This hook runs inside CreateWindowEx, before the window procedure sees any
// message, and subclasses each captioned engine window right there. It is
// thread-local: the engine creates its windows on the thread that runs the
// message loop, which is where it is installed.
HHOOK g_caption_hook = nullptr;

LRESULT CALLBACK CaptionCbtProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HCBT_CREATEWND) {
    const HWND hwnd = reinterpret_cast<HWND>(wparam);
    const auto* create = reinterpret_cast<const CBT_CREATEWND*>(lparam);
    // Only captioned windows: popups and tooltips have none to hide.
    if (create != nullptr && create->lpcs != nullptr &&
        (create->lpcs->style & WS_CAPTION) == WS_CAPTION) {
      wchar_t class_name[64] = {};
      if (GetClassNameW(hwnd, class_name, 64) > 0 &&
          wcscmp(class_name, kEngineHostWindowClass) == 0) {
        SetWindowSubclass(hwnd, CustomCaptionProc, kCustomCaptionSubclassId, 0);
      }
    }
  }
  return CallNextHookEx(g_caption_hook, code, wparam, lparam);
}

void InstallCaptionHook() {
  if (g_caption_hook != nullptr) return;
  g_caption_hook = SetWindowsHookExW(WH_CBT, CaptionCbtProc, nullptr,
                                     GetCurrentThreadId());
}

void RemoveCaptionHook() {
  if (g_caption_hook == nullptr) return;
  UnhookWindowsHookEx(g_caption_hook);
  g_caption_hook = nullptr;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Before the engine exists, so no window of it is ever created without it.
  InstallCaptionHook();

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  window_registrar_ =
      flutter_controller_->engine()->GetRegistrarForPlugin("VaultExplorerWindow");

  window_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "vaultexplorer/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        // Calls from a secondary window name their view; everything else is
        // about the main window.
        const HWND hwnd = TargetWindow(call.arguments());
        if (!hwnd) {
          result->Error("window_unavailable", "The window is unavailable.");
          return;
        }
        const auto& method = call.method_name();
        if (method == "useCustomCaption") {
          // The Flutter title bar replaces the OS caption of a secondary
          // window. The main window already runs without one.
          if (hwnd != GetHandle()) {
            // Normally the creation hook has done this already; this is the
            // fallback for a window it did not see.
            DWORD_PTR ref_data = 0;
            if (!GetWindowSubclass(hwnd, CustomCaptionProc,
                                   kCustomCaptionSubclassId, &ref_data)) {
              if (!SetWindowSubclass(hwnd, CustomCaptionProc,
                                     kCustomCaptionSubclassId, 0)) {
                result->Error("subclass_failed",
                              "The window caption could not be replaced.");
                return;
              }
              SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                           SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                               SWP_NOZORDER | SWP_NOACTIVATE);
            }
          }
          result->Success(flutter::EncodableValue());
        } else if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
        } else if (method == "minimize") {
          ShowWindow(hwnd, SW_MINIMIZE);
          result->Success(flutter::EncodableValue());
        } else if (method == "toggleMaximize") {
          ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
        } else if (method == "close") {
          PostMessage(hwnd, WM_CLOSE, 0, 0);
          result->Success(flutter::EncodableValue());
        } else if (method == "startDragging") {
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success(flutter::EncodableValue());
        } else if (method == "implicitWindowUnused") {
          // The app draws its windows (the main one included) as views of
          // their own, so this window shows nothing and must stay hidden. If
          // it was already shown by a first frame that came first, hide it.
          implicit_window_unused_ = true;
          ShowWindow(hwnd, SW_HIDE);
          result->Success(flutter::EncodableValue());
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!implicit_window_unused_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

HWND FlutterWindow::TargetWindow(const flutter::EncodableValue* arguments) {
  if (arguments != nullptr) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
      const auto it = map->find(flutter::EncodableValue("viewId"));
      if (it != map->end()) {
        int64_t view_id = 0;
        if (const auto* id32 = std::get_if<int32_t>(&it->second)) {
          view_id = *id32;
        } else if (const auto* id64 = std::get_if<int64_t>(&it->second)) {
          view_id = *id64;
        } else {
          return nullptr;
        }
        if (window_registrar_ == nullptr) return nullptr;
        FlutterDesktopViewRef view =
            FlutterDesktopPluginRegistrarGetViewById(window_registrar_, view_id);
        if (view == nullptr) return nullptr;
        const HWND content = FlutterDesktopViewGetHWND(view);
        return content != nullptr ? GetAncestor(content, GA_ROOT) : nullptr;
      }
    }
  }
  return GetHandle();
}

void FlutterWindow::OnDestroy() {
  RemoveCaptionHook();
  if (window_channel_) {
    window_channel_->SetMethodCallHandler(nullptr);
  }
  window_channel_.reset();
  window_registrar_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
