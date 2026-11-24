#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // Looks up views other than the main one (secondary windows).
  FlutterDesktopPluginRegistrarRef window_registrar_ = nullptr;

  // Whether closing this window hides it instead of destroying it.
  //
  // This window owns the Flutter engine and the widget tree that every
  // secondary window is drawn into, so it cannot go while one of them is open.
  // While the Dart side has a window that must outlive this one it sets this
  // ("setHideOnClose"), and a close request then only hides the window. The
  // Dart side ends the app (see "quitIfMainHidden") when the last such window
  // has closed.
  bool hide_on_close_ = false;

  // The top-level window a "vaultexplorer/window" call is about: the one that
  // hosts the Flutter view named by a "viewId" argument, or this window when
  // there is none. Null when the view is gone.
  HWND TargetWindow(const flutter::EncodableValue* arguments);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
