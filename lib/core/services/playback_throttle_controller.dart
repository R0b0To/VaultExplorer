import 'package:flutter/foundation.dart';

class PlaybackThrottleController {
  PlaybackThrottleController._();

  static final ValueNotifier<bool> isPlaybackActive = ValueNotifier<bool>(false);

  static void setActive(bool active) {
    if (isPlaybackActive.value != active) {
      isPlaybackActive.value = active;
    }
  }
}
