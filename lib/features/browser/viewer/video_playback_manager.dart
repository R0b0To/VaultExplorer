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

  // Track activation queue to prevent concurrent decoder allocations
  int _activationToken = 0;
  Future<void>? _currentActivationFuture;

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
    final token = ++_activationToken;

    // Chain activations sequentially so previous decoders are fully disposed first
    final previousFuture = _currentActivationFuture;
    final completer = Completer<void>();
    _currentActivationFuture = completer.future;

    if (previousFuture != null) {
      try {
        await previousFuture;
      } catch (_) {}
    }

    // Cancel if a newer activation request came in while waiting in queue
    if (token != _activationToken) {
      completer.complete();
      return;
    }

    try {
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
          // Fully teardown hardware pipeline before instantiating next controller
          await prevCtrl.dispose();
        }
      }

      // Check token again after async teardown
      if (token != _activationToken) return;

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

      activeControllerNotifier.value = controller;
      currentFileNotifier.value = fileName;

      _cleanupOldControllers(keepFiles: {fileName});
    } finally {
      completer.complete();
    }
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
    _activationToken++;
    currentFileNotifier.dispose();
    activeControllerNotifier.dispose();
    _subtitlesAvailableMap.clear();
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _controllers.clear();
  }
}