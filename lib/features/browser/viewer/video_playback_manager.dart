import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

class VideoPlaybackManager {
  final Map<String, NativeVideoController> _controllers = {};
  
  final ValueNotifier<String?> currentFileNotifier = ValueNotifier<String?>(null);
  String? get currentFileName => currentFileNotifier.value;

  final ValueNotifier<NativeVideoController?> activeControllerNotifier =
      ValueNotifier<NativeVideoController?>(null);
  NativeVideoController? get activeController => activeControllerNotifier.value;

  final Map<String, bool> _subtitlesAvailableMap = {};
  bool isSubtitleAvailable(String fileName) => _subtitlesAvailableMap[fileName] ?? false;

  void updateSubtitleStatus(String fileName, bool available) {
    _subtitlesAvailableMap[fileName] = available;
  }

  NativeVideoController? getControllerFor(String fileName) {
    return _controllers[fileName];
  }

  Future<void> activate({
    required String fileName,
    required String contentUriString,
    required bool autoPlay,
    required double playbackSpeed,
  }) async {
    if (currentFileNotifier.value == fileName && _controllers.containsKey(fileName)) {
      final ctrl = _controllers[fileName]!;
      await ctrl.setPlaybackSpeed(playbackSpeed);
      if (autoPlay) await ctrl.play();
      return;
    }

    final previousFile = currentFileNotifier.value;
    if (previousFile != null && previousFile != fileName) {
      final prevCtrl = _controllers.remove(previousFile);
      if (prevCtrl != null) {
        prevCtrl.pause();
        // Mobile SoCs typically expose only a single active hardware video
        // decoding pipeline (e.g. one 4K-capable c2.qti.vp9.decoder
        // instance). The previous controller must be fully torn down
        // *before* the next one is created below -- deferring this via a
        // timer let two decoders be briefly alive at once, which exceeded
        // hardware buffer limits and threw NO_MEMORY on 4K playback.
        await prevCtrl.dispose();
      }
    }

    NativeVideoController controller;
    if (_controllers.containsKey(fileName)) {
      controller = _controllers[fileName]!;
      await controller.setPlaybackSpeed(playbackSpeed);
      if (autoPlay) await controller.play();
    } else {
      controller = NativeVideoController(
        contentUriString: contentUriString,
        autoPlay: autoPlay,
        initialSpeed: playbackSpeed,
      );
      _controllers[fileName] = controller;
      unawaited(controller.initialize());
    }

    // Assign the resolved controller *before* currentFileNotifier fires --
    // listeners on currentFileNotifier (e.g. the screen's per-navigation
    // resync) read activeController synchronously as soon as
    // currentFileNotifier notifies, so activeControllerNotifier must already
    // point at this (correct, just-resolved) controller by then. Doing this
    // in the other order was what made a file-change handler apply settings
    // like playback speed to the *previous* file's controller instead of the
    // new one -- previousFile's controller was still "active" at the moment
    // that listener ran.
    activeControllerNotifier.value = controller;
    currentFileNotifier.value = fileName;

    // The previous controller is already disposed and removed above, so
    // only the newly-active controller needs to be kept alive here.
    _cleanupOldControllers(keepFiles: {fileName});
  }

  void _cleanupOldControllers({required Set<String> keepFiles}) {
    final keysToRemove = _controllers.keys.where((k) => !keepFiles.contains(k)).toList();
    for (final key in keysToRemove) {
      final ctrl = _controllers.remove(key);
      ctrl?.dispose();
    }
  }

  void pauseActive() => activeController?.pause();

  void dispose() {
    currentFileNotifier.dispose();
    activeControllerNotifier.dispose();
    _subtitlesAvailableMap.clear();
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _controllers.clear();
  }
}