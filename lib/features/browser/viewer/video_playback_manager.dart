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
    int? volId,
    String? filePath,
    String? contentUriString,
    required bool autoPlay,
    required double playbackSpeed,
    bool looping = false,
  }) async {
    final token = ++_activationToken;
    final previousFuture = _currentActivationFuture;
    final completer = Completer<void>();
    _currentActivationFuture = completer.future;
    if (previousFuture != null) {
      try {
        await previousFuture;
      } catch (_) {}
    }
    if (token != _activationToken) {
      completer.complete();
      return;
    }
    try {
      if (currentFileNotifier.value == fileName && _controllers.containsKey(fileName)) {
        final ctrl = _controllers[fileName]!;
        if (!ctrl.isDisposed && !ctrl.value.hasError) {
          await ctrl.setPlaybackSpeed(playbackSpeed);
          await ctrl.setLooping(looping);
          if (autoPlay) await ctrl.play();
          return;
        }
      }

      final previousFile = currentFileNotifier.value;
      if (previousFile != null && previousFile != fileName) {
        _controllers.remove(previousFile);
      }

      if (token != _activationToken) return;

      NativeVideoController controller;
      NativeVideoController createController() {
        if (volId != null && filePath != null) {
          return NativeVideoController(
            volId: volId,
            filePath: filePath,
            autoPlay: autoPlay,
            initialSpeed: playbackSpeed,
          );
        } else if (contentUriString != null) {
          return NativeVideoController.fromUri(
            contentUriString: contentUriString,
            autoPlay: autoPlay,
            initialSpeed: playbackSpeed,
          );
        } else {
          throw ArgumentError('Either (volId, filePath) or contentUriString must be provided');
        }
      }

      if (_controllers.containsKey(fileName)) {
        controller = _controllers[fileName]!;
        if (controller.isDisposed || controller.value.hasError) {
          _controllers.remove(fileName);
          controller = createController();
          _controllers[fileName] = controller;
          unawaited(controller.initialize().then((_) {
            if (token == _activationToken && !controller.isDisposed) {
              controller.setLooping(looping);
            }
          }));
        } else {
          await controller.setPlaybackSpeed(playbackSpeed);
          await controller.setLooping(looping);
          if (autoPlay) await controller.play();
        }
      } else {
        controller = createController();
        _controllers[fileName] = controller;
        unawaited(controller.initialize().then((_) {
          if (token == _activationToken && !controller.isDisposed) {
            controller.setLooping(looping);
          }
        }));
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
      _controllers.remove(key);
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