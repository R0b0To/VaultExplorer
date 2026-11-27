#include "desktop_media_session.h"

// C++/WinRT headers are noisy at the runner's warning level.
#pragma warning(push, 0)
#include <systemmediatransportcontrolsinterop.h>
#include <unknwn.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/base.h>
#pragma warning(pop)

#include <chrono>
#include <cstdlib>
#include <mutex>
#include <utility>

namespace {

using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;

winrt::hstring ToHstring(const std::string& utf8) {
  if (utf8.empty()) return winrt::hstring();
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return winrt::hstring();
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), length);
  return winrt::hstring(wide);
}

winrt::Windows::Foundation::TimeSpan Millis(int64_t ms) {
  return std::chrono::duration_cast<winrt::Windows::Foundation::TimeSpan>(
      std::chrono::milliseconds(ms < 0 ? 0 : ms));
}

}  // namespace

class DesktopMediaSession::Impl {
 public:
  Impl(HWND controls_window, HWND message_window)
      : controls_window_(controls_window), message_window_(message_window) {}

  ~Impl() { Teardown(); }

  void Update(const DesktopMediaUpdate& u) {
    if (failed_) return;
    try {
      Apply(u);
    } catch (const winrt::hresult_error&) {
      // No media controls for this window (or the API is missing): leave the
      // app's own controls to do the work, and do not try again.
      failed_ = true;
      Teardown();
    }
  }

  std::deque<DesktopMediaCommand> TakeCommands() {
    std::lock_guard<std::mutex> lock(mutex_);
    std::deque<DesktopMediaCommand> out;
    out.swap(commands_);
    return out;
  }

 private:
  bool EnsureControls() {
    if (controls_) return true;
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    SystemMediaTransportControls controls{nullptr};
    winrt::check_hresult(interop->GetForWindow(
        controls_window_,
        winrt::guid_of<winrt::Windows::Media::ISystemMediaTransportControls>(),
        winrt::put_abi(controls)));
    controls_ = controls;
    button_token_ = controls_.ButtonPressed(
        [this](SystemMediaTransportControls const&,
               SystemMediaTransportControlsButtonPressedEventArgs const& args) {
          switch (args.Button()) {
            case SystemMediaTransportControlsButton::Play:
              Post("play", -1);
              break;
            case SystemMediaTransportControlsButton::Pause:
              Post("pause", -1);
              break;
            case SystemMediaTransportControlsButton::Stop:
              Post("stop", -1);
              break;
            case SystemMediaTransportControlsButton::Next:
              Post("next", -1);
              break;
            case SystemMediaTransportControlsButton::Previous:
              Post("previous", -1);
              break;
            default:
              break;
          }
        });
    position_token_ = controls_.PlaybackPositionChangeRequested(
        [this](SystemMediaTransportControls const&,
               PlaybackPositionChangeRequestedEventArgs const& args) {
          const auto ticks = args.RequestedPlaybackPosition();
          Post("seekTo",
               std::chrono::duration_cast<std::chrono::milliseconds>(ticks)
                   .count());
        });
    // Only what the app can do; the rest stays off.
    controls_.IsPlayEnabled(true);
    controls_.IsPauseEnabled(true);
    controls_.IsStopEnabled(true);
    controls_.IsNextEnabled(false);
    controls_.IsPreviousEnabled(false);
    return true;
  }

  // Runs on a thread-pool thread: hand the command to the platform thread.
  void Post(const char* name, int64_t position_ms) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const int64_t now_ms =
          std::chrono::duration_cast<std::chrono::milliseconds>(
              std::chrono::system_clock::now().time_since_epoch())
              .count();
      commands_.push_back(DesktopMediaCommand{name, position_ms, now_ms});
    }
    PostMessageW(message_window_, kDesktopMediaCommandMessage, 0, 0);
  }

  void Apply(const DesktopMediaUpdate& u) {
    if (!u.active) {
      if (controls_ && shown_) {
        controls_.DisplayUpdater().ClearAll();
        controls_.PlaybackStatus(MediaPlaybackStatus::Closed);
        controls_.IsEnabled(false);
      }
      shown_ = false;
      return;
    }
    if (!EnsureControls()) return;

    if (!shown_) {
      controls_.IsEnabled(true);
      shown_ = true;
      // Everything below is sent again for a newly shown session.
      has_text_ = false;
      has_status_ = false;
      has_timeline_ = false;
      next_ = previous_ = false;
      controls_.IsNextEnabled(false);
      controls_.IsPreviousEnabled(false);
    }

    if (next_ != u.can_next) {
      next_ = u.can_next;
      controls_.IsNextEnabled(next_);
    }
    if (previous_ != u.can_previous) {
      previous_ = u.can_previous;
      controls_.IsPreviousEnabled(previous_);
    }

    if (!has_text_ || title_ != u.title || artist_ != u.artist ||
        album_ != u.album) {
      has_text_ = true;
      title_ = u.title;
      artist_ = u.artist;
      album_ = u.album;
      auto updater = controls_.DisplayUpdater();
      updater.Type(MediaPlaybackType::Music);
      auto music = updater.MusicProperties();
      music.Title(ToHstring(title_));
      music.Artist(ToHstring(artist_));
      music.AlbumTitle(ToHstring(album_));
      updater.Update();
    }

    if (!has_status_ || playing_ != u.playing) {
      has_status_ = true;
      playing_ = u.playing;
      controls_.PlaybackStatus(playing_ ? MediaPlaybackStatus::Playing
                                        : MediaPlaybackStatus::Paused);
    }

    // The system extrapolates the position while playing: refresh it when the
    // state changed or it drifted (a seek), not on every report.
    const auto now = std::chrono::steady_clock::now();
    bool timeline = !has_timeline_ || duration_ms_ != u.duration_ms ||
                    seek_ != u.can_seek || timeline_playing_ != u.playing;
    if (!timeline) {
      int64_t expected = reported_position_ms_;
      if (timeline_playing_) {
        expected += std::chrono::duration_cast<std::chrono::milliseconds>(
                        now - reported_at_)
                        .count();
      }
      timeline = std::llabs(expected - u.position_ms) > 2000;
    }
    if (timeline) {
      has_timeline_ = true;
      duration_ms_ = u.duration_ms;
      seek_ = u.can_seek;
      timeline_playing_ = u.playing;
      reported_position_ms_ = u.position_ms;
      reported_at_ = now;
      SystemMediaTransportControlsTimelineProperties props;
      props.StartTime(Millis(0));
      props.MinSeekTime(Millis(0));
      props.Position(Millis(u.position_ms));
      props.MaxSeekTime(Millis(u.can_seek ? u.duration_ms : 0));
      props.EndTime(Millis(u.duration_ms));
      // Seeking is offered when the timeline has a range to seek in.
      controls_.UpdateTimelineProperties(props);
    }
  }

  void Teardown() {
    if (!controls_) return;
    try {
      controls_.ButtonPressed(button_token_);
      controls_.PlaybackPositionChangeRequested(position_token_);
      if (shown_) {
        controls_.DisplayUpdater().ClearAll();
        controls_.PlaybackStatus(MediaPlaybackStatus::Closed);
        controls_.IsEnabled(false);
      }
    } catch (const winrt::hresult_error&) {
      // Going away anyway.
    }
    controls_ = nullptr;
    shown_ = false;
  }

  const HWND controls_window_;
  const HWND message_window_;

  SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
  winrt::event_token position_token_{};
  bool failed_ = false;
  bool shown_ = false;

  // What was last sent, to skip unchanged work.
  bool has_text_ = false;
  std::string title_, artist_, album_;
  bool has_status_ = false;
  bool playing_ = false;
  bool next_ = false;
  bool previous_ = false;
  bool has_timeline_ = false;
  bool seek_ = false;
  bool timeline_playing_ = false;
  int64_t duration_ms_ = 0;
  int64_t reported_position_ms_ = 0;
  std::chrono::steady_clock::time_point reported_at_;

  std::mutex mutex_;
  std::deque<DesktopMediaCommand> commands_;
};

DesktopMediaSession::DesktopMediaSession(HWND controls_window,
                                         HWND message_window)
    : impl_(std::make_unique<Impl>(controls_window, message_window)) {}

DesktopMediaSession::~DesktopMediaSession() = default;

void DesktopMediaSession::Update(const DesktopMediaUpdate& update) {
  impl_->Update(update);
}

std::deque<DesktopMediaCommand> DesktopMediaSession::TakeCommands() {
  return impl_->TakeCommands();
}
