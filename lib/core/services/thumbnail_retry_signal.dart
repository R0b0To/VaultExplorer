import 'package:flutter/widgets.dart';

/// Bumped once every time the app comes back to the foreground, so a
/// thumbnail that never resolved gets another chance instead of sitting
/// on a spinner until the user navigates away and back.
///
/// `AsyncThumbnailLoader` arms its fetch exactly once per provider
/// instance, which is the right default -- a tile should not re-fetch on
/// every rebuild. The cost of that is having no way back from a load that
/// ends in neither bytes nor an error: the provider stays in its initial
/// `isLoading` state with nothing in flight, and nothing on the widget
/// side knows to restart it. That can happen for reasons this app doesn't
/// fully control (a native call that never calls back, a queue slot that
/// never frees), and returning to the app is both the moment the user
/// notices the stuck tile and a natural, cheap point to retry.
///
/// This deliberately does *not* invalidate tiles that already have bytes
/// -- see `AsyncThumbnailLoader._onRetrySignal`, which ignores the bump
/// for anything already showing an image. It is a recovery path, not a
/// refresh.
///
/// Modelled on [PlaybackThrottleController.isPlaybackActive], which the
/// same loader already listens to for the same kind of "conditions
/// changed, try again" nudge.
class ThumbnailRetrySignal with WidgetsBindingObserver {
  /// Listened to by every live thumbnail loader. The value itself carries
  /// no meaning beyond "it changed".
  static final ValueNotifier<int> generation = ValueNotifier<int>(0);

  static ThumbnailRetrySignal? _instance;

  ThumbnailRetrySignal._();

  /// Registers the singleton observer with [WidgetsBinding.instance].
  static void register() {
    if (_instance != null) return;
    _instance = ThumbnailRetrySignal._();
    WidgetsBinding.instance.addObserver(_instance!);
  }

  /// Unregisters the observer if active.
  static void unregister() {
    if (_instance == null) return;
    WidgetsBinding.instance.removeObserver(_instance!);
    _instance = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only a real return to the foreground. `inactive` alone fires for
    // things like the notification shade sliding down, which is exactly
    // when a stuck tile tends to be noticed -- but the app hasn't been
    // anywhere, so the trip back up is the moment worth acting on.
    if (state != AppLifecycleState.resumed) return;
    generation.value++;
  }
}
