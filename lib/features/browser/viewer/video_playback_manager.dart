import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/native_ffmpeg_controller.dart';

class VideoPlaybackManager {
  final Map<String, NativeFFmpegController> _controllers = {};
  
  final ValueNotifier<String?> currentFileNotifier = ValueNotifier<String?>(null);
  String? get currentFileName => currentFileNotifier.value;

  final ValueNotifier<NativeFFmpegController?> activeControllerNotifier =
      ValueNotifier<NativeFFmpegController?>(null);
  NativeFFmpegController? get activeController => activeControllerNotifier.value;

  final Map<String, bool> _subtitlesAvailableMap = {};
  bool isSubtitleAvailable(String fileName) => _subtitlesAvailableMap[fileName] ?? false;

  void updateSubtitleStatus(String fileName, bool available) {
    _subtitlesAvailableMap[fileName] = available;
  }

  NativeFFmpegController? getControllerFor(String fileName) {
    return _controllers[fileName];
  }

  Future<void> activate({
    required String fileName,
    required String contentUriString,
    required bool autoPlay,
  }) async {
    if (currentFileNotifier.value == fileName && _controllers.containsKey(fileName)) {
      final ctrl = _controllers[fileName]!;
      if (autoPlay) await ctrl.play();
      return;
    }

    final previousFile = currentFileNotifier.value;
    if (previousFile != null && previousFile != fileName) {
      final prevCtrl = _controllers[previousFile];
      prevCtrl?.pause();
      _scheduleDisposal(previousFile, prevCtrl);
    }

    currentFileNotifier.value = fileName;

    NativeFFmpegController controller;
    if (_controllers.containsKey(fileName)) {
      controller = _controllers[fileName]!;
      if (autoPlay) await controller.play();
    } else {
      controller = NativeFFmpegController(
        contentUriString: contentUriString,
        autoPlay: autoPlay,
      );
      _controllers[fileName] = controller;
      unawaited(controller.initialize());
    }

    activeControllerNotifier.value = controller;
    _cleanupOldControllers(keepFiles: {fileName, if (previousFile != null) previousFile});
  }

  void _scheduleDisposal(String fileName, NativeFFmpegController? controller) {
    if (controller == null) return;
    Future.delayed(const Duration(milliseconds: 750), () {
      if (currentFileNotifier.value != fileName && _controllers[fileName] == controller) {
        _controllers.remove(fileName);
        controller.dispose();
      }
    });
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