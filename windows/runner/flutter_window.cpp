#include "flutter_window.h"

#include <commctrl.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kCustomCaptionSubclassId = 1;

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
      if (wparam != TRUE) break;
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG original_top = params->rgrc[0].top;
      // Let Windows compute the left/right/bottom resize frame first.
      const LRESULT result = DefSubclassProc(hwnd, message, wparam, lparam);
      if (result != 0) return result;
      if (IsZoomed(hwnd)) {
        // A maximized window overhangs the monitor by the sizing-frame
        // thickness, so push the client area back on screen.
        const UINT dpi = GetDpiForWindow(hwnd);
        params->rgrc[0].top = original_top +
            GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
            GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
      } else {
        // Drop the OS caption. Keep 1px so DWM still draws its border and
        // the top edge stays grabbable.
        params->rgrc[0].top = original_top + 1;
      }
      return 0;
    }
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, CustomCaptionProc, subclass_id);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

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
        } else if (method == "setHideOnClose") {
          // Whether closing the main window hides it (see hide_on_close_).
          // These three calls are about the main window, so they carry no
          // "viewId" and TargetWindow() above resolved to it.
          bool enabled = false;
          if (const auto* arguments =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto it = arguments->find(flutter::EncodableValue("enabled"));
            if (it != arguments->end()) {
              if (const auto* value = std::get_if<bool>(&it->second)) {
                enabled = *value;
              }
            }
          }
          hide_on_close_ = enabled;
          result->Success(flutter::EncodableValue());
        } else if (method == "revealMainWindow") {
          // Brings the main window back if it was hidden on close, without
          // taking the focus from the window the person is working in. A
          // window that is merely minimized or behind others is left alone.
          if (!IsWindowVisible(hwnd)) {
            ShowWindow(hwnd, SW_SHOWNOACTIVATE);
          }
          result->Success(flutter::EncodableValue());
        } else if (method == "quitIfMainHidden") {
          // The last window that could stand on its own has closed. A main
          // window that was hidden for its sake has no reason left to exist,
          // so close it for real, which ends the app. A main window that is on
          // screen means the person never closed it: nothing to do.
          if (!IsWindowVisible(hwnd)) {
            hide_on_close_ = false;
            PostMessage(hwnd, WM_CLOSE, 0, 0);
          }
          result->Success(flutter::EncodableValue());
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
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
  // Closing the main window while another window depends on it only hides it
  // (see hide_on_close_). This comes before Flutter's own handling so that the
  // engine never starts its "close the app" sequence for this request; it
  // still hears about the window being hidden through WM_SHOWWINDOW. Every way
  // of closing the window ends up here as WM_CLOSE: the title bar's close
  // button (the "close" call above), Alt+F4 and the taskbar.
  if (message == WM_CLOSE && hide_on_close_ && hwnd == GetHandle()) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

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
