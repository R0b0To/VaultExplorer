import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_vlc_controller.dart';

class VideoPlaybackManager {
  final Map<String, NativeVlcController> _controllers = {};
  final Map<String, bool> _subtitlesAvailableMap = {};

  final Map<String, VoidCallback> _evictionCallbacks = {};

  // Files with a prewarm currently in flight, so a rapid double-swipe past
  // the same neighbor doesn't kick off a second concurrent initialize().
  final Set<String> _prewarmingActive = {};

  final ValueNotifier<NativeVlcController?> activeControllerNotifier =
      ValueNotifier<NativeVlcController?>(null);

  NativeVlcController? get activeController => activeControllerNotifier.value;

  NativeVlcController? getController(String fileName) => _controllers[fileName];

  /// True if [fileName] already has a controller (warm or active) — lets
  /// [MediaPlayerWidget] check whether to adopt an existing controller
  /// instead of constructing + initializing a new one.
  bool hasController(String fileName) => _controllers.containsKey(fileName);

  /// Begins constructing and initializing a [NativeVlcController] for
  /// [fileName] ahead of the user actually swiping to it, so the expensive
  /// libVLC open/decode-start work is already done (or in flight) by the
  /// time [MediaPlayerWidget] builds for real.
  ///
  /// [NativeVlcController.initialize] creates its native player + Flutter
  /// texture immediately (it isn't tied to a widget mounting the way
  /// `flutter_vlc_player`'s controller is), so this genuinely hides that
  /// latency behind however long the user spends on the previous item —
  /// the same as the original `video_player`-based prewarm did.
  ///
  /// No-ops if a controller already exists for [fileName] (warm, active, or
  /// otherwise) or a prewarm for it is already in flight. The controller is
  /// left paused/muted at position zero — [MediaPlayerWidget] takes over
  /// playback state once it adopts the warmed controller.
  Future<void> prewarm({
    required String fileName,
    required String contentUriString,
    required List<String> playlist,
    required int currentIndex,
  }) async {
    if (_controllers.containsKey(fileName)) return;
    if (_prewarmingActive.contains(fileName)) return;

    _prewarmingActive.add(fileName);
    final controller = NativeVlcController(
      contentUriString: contentUriString,
      autoPlay: false,
    );
    try {
      await controller.initialize();
      // The user may have swiped elsewhere while this was initializing —
      // re-check before publishing, and discard rather than leak the
      // controller if it's no longer wanted.
      if (_controllers.containsKey(fileName)) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.pause();

      _evictDistantControllers(playlist, currentIndex, keep: fileName);
      _controllers[fileName] = controller;
    } catch (_) {
      try {
        await controller.dispose();
      } catch (_) {}
    } finally {
      _prewarmingActive.remove(fileName);
    }
  }

  bool isSubtitleAvailable(String fileName) => _subtitlesAvailableMap[fileName] ?? false;

  void registerController({
    required String fileName,
    required NativeVlcController controller,
    required bool currentFocus,
    required List<String> playlist,
    required int currentIndex,
    VoidCallback? onEvicted,
  }) {
    _evictDistantControllers(playlist, currentIndex, keep: fileName);

    final existing = _controllers[fileName];
    if (existing != null && existing != controller) {
      _disposeControllerSafely(existing);
    }

    _controllers[fileName] = controller;
    if (onEvicted != null) {
      _evictionCallbacks[fileName] = onEvicted;
    } else {
      _evictionCallbacks.remove(fileName);
    }

    if (currentFocus) {
      activeControllerNotifier.value = controller;
    }
  }

  void updateSubtitleStatus(String fileName, bool available) {
    _subtitlesAvailableMap[fileName] = available;
  }

  void handlePageChange(String fileName) {
    activeControllerNotifier.value = _controllers[fileName];
  }

  void pauseAllExcept(NativeVlcController keepActive) {
    for (final ctrl in _controllers.values) {
      if (ctrl != keepActive) {
        try {
          ctrl.pause();
        } catch (_) {}
      }
    }
  }

  void handleDisposed(String fileName) {
    final removed = _controllers.remove(fileName);
    _subtitlesAvailableMap.remove(fileName);
    _evictionCallbacks.remove(fileName);
    if (removed != null && activeControllerNotifier.value == removed) {
      activeControllerNotifier.value = null;
    }
  }

  void _disposeControllerSafely(NativeVlcController ctrl) {
    try {
      ctrl.pause();
      Future.delayed(const Duration(milliseconds: 150), () async {
        try {
          await ctrl.dispose();
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _evictDistantControllers(
    List<String> playlist,
    int currentIndex, {
    String? keep,
  }) {
    while (_controllers.length >= MediaViewerConstants.maxLiveVideoControllers) {
      String? furthestFile;
      int maxDistance = -1;

      for (final fileName in _controllers.keys) {
        if (fileName == keep) continue;
        final pos = playlist.indexOf(fileName);
        final dist = pos == -1 ? (1 << 30) : (pos - currentIndex).abs();
        if (dist > maxDistance) {
          maxDistance = dist;
          furthestFile = fileName;
        }
      }

      if (furthestFile == null) break;
      final evicted = _controllers.remove(furthestFile);
      _subtitlesAvailableMap.remove(furthestFile);

      final onEvicted = _evictionCallbacks.remove(furthestFile);
      onEvicted?.call();

      if (evicted != null) {
        if (activeControllerNotifier.value == evicted) {
          activeControllerNotifier.value = null;
        }
        _disposeControllerSafely(evicted);
      }
    }
  }

  void dispose() {
    activeControllerNotifier.dispose();
    for (final ctrl in _controllers.values) {
      _disposeControllerSafely(ctrl);
    }
    _controllers.clear();
    _subtitlesAvailableMap.clear();
    _evictionCallbacks.clear();
  }
}
