#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "desktop_media_session.h"
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

  // The system media controls (media keys, the media overlay). Created by the
  // first "update" of the "desktop_media" channel, on the window of the view it
  // names; null until something plays.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      media_channel_;
  std::unique_ptr<DesktopMediaSession> media_session_;

  // Passes the buttons pressed in the system media controls on to Dart.
  void DispatchMediaCommands();

  // Looks up views other than the main one (secondary windows).
  FlutterDesktopPluginRegistrarRef window_registrar_ = nullptr;

  // Set (by "implicitWindowUnused") when the app draws all of its windows as
  // views of their own and nothing in this one. The next-frame callback that
  // shows this window is registered on the engine, not on this window's view,
  // so this runner cannot rely on it staying quiet for other windows' frames.
  // An empty window showing here would be wrong, and closing it would end the
  // app (WM_DESTROY posts the quit message).
  bool implicit_window_unused_ = false;

  // The top-level window a "vaultexplorer/window" call is about: the one that
  // hosts the Flutter view named by a "viewId" argument, or this window when
  // there is none. Null when the view is gone.
  HWND TargetWindow(const flutter::EncodableValue* arguments);

  // The top-level window that shows the view [view_id], or null.
  HWND WindowForView(int64_t view_id);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
