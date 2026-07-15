import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'media_viewer_constants.dart';

/// Tracks live [VideoPlayerController]s for the media viewer.
///
/// Controllers are keyed by file path rather than page index. Page index is
/// not a stable identity for a file: enabling/disabling playlist mode,
/// switching folder scope ("This Folder" vs "All"), and shuffling can all
/// reorder or resize the playlist, which changes which index a given file
/// sits at. A controller registered under its old index would then be
/// looked up under a new, unrelated index — so [activeController] would
/// silently go null (or point at the wrong file) even though the
/// underlying VideoPlayerController is still alive and playing. Keying by
/// file path sidesteps that entirely.
class VideoPlaybackManager {
  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, bool> _subtitlesAvailableMap = {};

  // Lets the owning MediaPlayerWidget know if its controller is forced out
  // by _evictDistantControllers while it may still be mounted, so it can
  // reinitialize instead of being left holding a disposed controller.
  final Map<String, VoidCallback> _evictionCallbacks = {};

  final ValueNotifier<VideoPlayerController?> activeControllerNotifier =
      ValueNotifier<VideoPlayerController?>(null);

  VideoPlayerController? get activeController => activeControllerNotifier.value;

  VideoPlayerController? getController(String fileName) => _controllers[fileName];

  bool isSubtitleAvailable(String fileName) => _subtitlesAvailableMap[fileName] ?? false;

  /// Registers the controller for [fileName]. [playlist] and [currentIndex]
  /// describe the current playlist ordering/position and are only used to
  /// decide which *other* live controllers are safe to evict (the ones
  /// furthest from where the user currently is).
  ///
  /// [onEvicted], if provided, is invoked if this controller later gets
  /// forced out by [_evictDistantControllers] to make room for another
  /// page — giving a still-mounted widget the chance to reinitialize
  /// cleanly instead of freezing on a disposed controller.
  void registerController({
    required String fileName,
    required VideoPlayerController controller,
    required bool currentFocus,
    required List<String> playlist,
    required int currentIndex,
    VoidCallback? onEvicted,
  }) {
    _evictDistantControllers(playlist, currentIndex, keep: fileName);
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

  /// Explicitly halts any video stream other than the focus controller to prevent cross-page audio leaks.
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
        // Not found in the current playlist at all (e.g. stale entry from
        // before a rescan) is treated as maximally far away.
        final dist = pos == -1 ? (1 << 30) : (pos - currentIndex).abs();
        if (dist > maxDistance) {
          maxDistance = dist;
          furthestFile = fileName;
        }
      }

      if (furthestFile == null) break;
      final evicted = _controllers.remove(furthestFile);
      _subtitlesAvailableMap.remove(furthestFile);

      // Notify the owning widget (if it registered a callback) *before* we
      // pause/dispose below, so a page that's still mounted — e.g. one that
      // was mid-initialize during a fast swipe — can drop its reference and
      // reinitialize instead of being left holding a disposed controller
      // (frozen video, dead controls, until the user navigates away and
      // back).
      final onEvicted = _evictionCallbacks.remove(furthestFile);
      onEvicted?.call();

      if (evicted != null) {
        if (activeControllerNotifier.value == evicted) {
          activeControllerNotifier.value = null;
        }
        Future.microtask(() async {
          try {
            // Workaround for fvp/libmdk crash (wang-bin/fvp#362)
            // Disposing the player while its AAudio stream is in STARTING state
            // results in a Scudo memory allocation error and fatal crash.
            // Pausing and waiting briefly gives the audio engine time to settle.
            await evicted.pause();
            await Future.delayed(const Duration(milliseconds: 150));
            await evicted.dispose();
          } catch (e) {
            debugPrint('Failed evicting video controller safely: $e');
          }
        });
      }
    }
  }

  void dispose() {
    activeControllerNotifier.dispose();
    for (final ctrl in _controllers.values) {
      try {
        // Apply the same dispose workaround to prevent AAudio crashes during UI exit
        ctrl.pause();
        Future.delayed(const Duration(milliseconds: 150), () async {
          try {
            await ctrl.dispose();
          } catch (_) {}
        });
      } catch (_) {}
    }
    _controllers.clear();
    _subtitlesAvailableMap.clear();
    _evictionCallbacks.clear();
  }
}