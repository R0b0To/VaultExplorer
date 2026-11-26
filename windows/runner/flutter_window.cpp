#include "flutter_window.h"

#include <commctrl.h>

#include <optional>
#include <string>
#include <utility>

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

const flutter::EncodableValue* FindArgument(const flutter::EncodableMap& map,
                                            const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string StringArgument(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindArgument(map, key);
  if (value != nullptr) {
    if (const auto* text = std::get_if<std::string>(value)) return *text;
  }
  return std::string();
}

bool BoolArgument(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindArgument(map, key);
  if (value != nullptr) {
    if (const auto* flag = std::get_if<bool>(value)) return *flag;
  }
  return false;
}

int64_t IntArgument(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindArgument(map, key);
  if (value != nullptr) {
    if (const auto* small = std::get_if<int32_t>(value)) return *small;
    if (const auto* large = std::get_if<int64_t>(value)) return *large;
  }
  return 0;
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

  media_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.aeidolon.vaultexplorer/desktop_media",
      &flutter::StandardMethodCodec::GetInstance());
  media_channel_->SetMethodCallHandler(
      [this](const auto& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "update") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            call.arguments() == nullptr
                ? nullptr
                : std::get_if<flutter::EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("bad_arguments", "A map was expected.");
          return;
        }
        if (!media_session_) {
          // Attached to the window of the view that asked (the one the user
          // sees; this runner's own window is never shown), with the commands
          // delivered to this window.
          const HWND target = TargetWindow(call.arguments());
          if (!target) {
            result->Error("window_unavailable", "The window is unavailable.");
            return;
          }
          media_session_ =
              std::make_unique<DesktopMediaSession>(target, GetHandle());
        }
        DesktopMediaUpdate update;
        update.active = BoolArgument(*args, "active");
        update.title = StringArgument(*args, "title");
        update.artist = StringArgument(*args, "artist");
        update.album = StringArgument(*args, "album");
        update.playing = BoolArgument(*args, "playing");
        update.position_ms = IntArgument(*args, "positionMs");
        update.duration_ms = IntArgument(*args, "durationMs");
        update.can_next = BoolArgument(*args, "canNext");
        update.can_previous = BoolArgument(*args, "canPrevious");
        update.can_seek = BoolArgument(*args, "canSeek");
        media_session_->Update(update);
        result->Success(flutter::EncodableValue());
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

void FlutterWindow::DispatchMediaCommands() {
  if (!media_session_ || !media_channel_) return;
  for (const DesktopMediaCommand& command : media_session_->TakeCommands()) {
    flutter::EncodableMap arguments;
    arguments[flutter::EncodableValue("command")] =
        flutter::EncodableValue(command.name);
    if (command.position_ms >= 0) {
      arguments[flutter::EncodableValue("positionMs")] =
          flutter::EncodableValue(command.position_ms);
    }
    media_channel_->InvokeMethod(
        "command",
        std::make_unique<flutter::EncodableValue>(std::move(arguments)));
  }
}

void FlutterWindow::OnDestroy() {
  if (media_channel_) {
    media_channel_->SetMethodCallHandler(nullptr);
  }
  media_session_.reset();
  media_channel_.reset();
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
    case kDesktopMediaCommandMessage:
      DispatchMediaCommands();
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
