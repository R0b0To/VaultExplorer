#ifndef RUNNER_DESKTOP_MEDIA_SESSION_H_
#define RUNNER_DESKTOP_MEDIA_SESSION_H_

#include <windows.h>

#include <cstdint>
#include <deque>
#include <memory>
#include <string>

// Posted to the message window when the system media controls have something
// for the app (their events arrive on a thread-pool thread).
constexpr UINT kDesktopMediaCommandMessage = WM_APP + 0x4D;

// A button pressed in the system media controls (media keys, the media overlay,
// the lock screen): "play", "pause", "stop", "next", "previous", or "seekTo"
// with the requested position.
struct DesktopMediaCommand {
  std::string name;
  int64_t position_ms = -1;
};

// What the system media controls should show.
struct DesktopMediaUpdate {
  bool active = false;
  std::string title;   // UTF-8
  std::string artist;  // UTF-8
  std::string album;   // UTF-8
  bool playing = false;
  int64_t position_ms = 0;
  int64_t duration_ms = 0;
  bool can_next = false;
  bool can_previous = false;
  bool can_seek = false;
};

// The System Media Transport Controls of Windows for one window. All WinRT is
// kept inside the .cpp, so the rest of the runner does not see its headers.
class DesktopMediaSession {
 public:
  // |controls_window| is the window the controls are attached to;
  // |message_window| receives kDesktopMediaCommandMessage and must belong to
  // the thread that calls Update() and TakeCommands().
  DesktopMediaSession(HWND controls_window, HWND message_window);
  ~DesktopMediaSession();

  DesktopMediaSession(const DesktopMediaSession&) = delete;
  DesktopMediaSession& operator=(const DesktopMediaSession&) = delete;

  // Shows |update|. Cheap to call often: unchanged parts are not re-sent.
  void Update(const DesktopMediaUpdate& update);

  // The commands received since the last call.
  std::deque<DesktopMediaCommand> TakeCommands();

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_DESKTOP_MEDIA_SESSION_H_
