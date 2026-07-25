import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/native_vlc_controller.dart';


class VideoPlaybackManager {
  NativeVlcController? _controller;


  final ValueNotifier<String?> currentFileNotifier = ValueNotifier<String?>(null);
  String? get currentFileName => currentFileNotifier.value;

  final ValueNotifier<NativeVlcController?> activeControllerNotifier =
      ValueNotifier<NativeVlcController?>(null);
  NativeVlcController? get activeController => activeControllerNotifier.value;

  final Map<String, bool> _subtitlesAvailableMap = {};
  bool isSubtitleAvailable(String fileName) => _subtitlesAvailableMap[fileName] ?? false;
  void updateSubtitleStatus(String fileName, bool available) {
    _subtitlesAvailableMap[fileName] = available;
  }


  Future<void> activate({
    required String fileName,
    required String contentUriString,
    required bool autoPlay,
  }) async {
    if (currentFileNotifier.value == fileName && _controller != null) {
      if (autoPlay) await _controller!.play();
      return;
    }

    currentFileNotifier.value = fileName;

    final existing = _controller;
    if (existing == null) {
      final controller = NativeVlcController(
        contentUriString: contentUriString,
        autoPlay: autoPlay,
      );
      _controller = controller;
      activeControllerNotifier.value = controller;
      await controller.initialize();
    } else {

      await existing.switchTo(contentUriString, autoPlay: autoPlay);
    }
  }


  void pauseActive() {
    _controller?.pause();
  }

  void dispose() {
    currentFileNotifier.dispose();
    activeControllerNotifier.dispose();
    _subtitlesAvailableMap.clear();
    _controller?.dispose();
    _controller = null;
  }
}