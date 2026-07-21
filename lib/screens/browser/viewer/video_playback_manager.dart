import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'media_viewer_constants.dart';

class VideoPlaybackManager {
  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, bool> _subtitlesAvailableMap = {};

  final Map<String, VoidCallback> _evictionCallbacks = {};

  final ValueNotifier<VideoPlayerController?> activeControllerNotifier =
      ValueNotifier<VideoPlayerController?>(null);

  VideoPlayerController? get activeController => activeControllerNotifier.value;

  VideoPlayerController? getController(String fileName) => _controllers[fileName];

  bool isSubtitleAvailable(String fileName) => _subtitlesAvailableMap[fileName] ?? false;

  void registerController({
    required String fileName,
    required VideoPlayerController controller,
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

  void pauseAllExcept(VideoPlayerController keepActive) {
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

  void _disposeControllerSafely(VideoPlayerController ctrl) {
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