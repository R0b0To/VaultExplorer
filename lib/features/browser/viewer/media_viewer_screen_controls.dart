part of 'media_viewer_screen.dart';

/// Playback helpers behind the keyboard shortcuts and controls.
///
/// Moved out of [_MediaViewerScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _MediaViewerControls on _MediaViewerScreenState {
  NativeVideoController? _keyboardPlayer() {
    final controller = _playbackManager.activeController;
    if (controller == null ||
        controller.isDisposed ||
        !controller.value.isInitialized) {
      return null;
    }
    return controller;
  }

  void _showKeyToast(String message) => _showAbLoopToast(message);

  void _seekBy(Duration delta) {
    final controller = _keyboardPlayer();
    if (controller == null) return;
    VeLog.d('MediaViewerKey', '_seekBy delta=${delta.inSeconds}s');
    _startHideTimer();
    final duration = controller.value.duration;
    var target = controller.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    unawaited(controller.seekTo(target));
    _showKeyToast(
      '${formatClockDuration(target)} / ${formatClockDuration(duration)}',
    );
  }

  void _seekToFraction(double fraction) {
    final controller = _keyboardPlayer();
    if (controller == null) return;
    _startHideTimer();
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final target = Duration(
      milliseconds: (duration.inMilliseconds * fraction).round(),
    );
    unawaited(controller.seekTo(target));
    _showKeyToast(
      '${formatClockDuration(target)} / ${formatClockDuration(duration)}',
    );
  }

  void _changeVolume(int delta) {
    final controller = _keyboardPlayer();
    if (controller == null) return;
    VeLog.d(
      'MediaViewerKey',
      '_changeVolume delta=$delta next=$_volumeLevel->${(_volumeLevel + delta).clamp(0, 100)}',
    );
    _startHideTimer();
    final wasMuted = _isMuted;
    _volumeLevel = (_volumeLevel + delta).clamp(0, 100);
    if (wasMuted && delta > 0) {
      // Turning the volume up while muted is an unmute, the same as in
      // every other player.
      _sessionController.setIsMuted(false);
      ref.read(appSettingsServiceProvider).loadSettings().then((s) {
        ref
            .read(appSettingsServiceProvider)
            .saveSettings(s.copyWith(videoMuted: false));
      });
    }
    unawaited(controller.setVolume(_effectiveVolume));
    _showKeyToast('${_effectiveVolume}%');
  }

  /// The volume slider (or the wheel over it) set the volume to [level].
  /// Raising it while muted unmutes, as the keyboard does.
  void _setVolumeWithPointer(int level) {
    final controller = _playbackManager.activeController;
    _volumeLevel = level.clamp(0, 100);
    if (_isMuted && level > 0) {
      _sessionController.setIsMuted(false);
      ref.read(appSettingsServiceProvider).loadSettings().then((s) {
        ref
            .read(appSettingsServiceProvider)
            .saveSettings(s.copyWith(videoMuted: false));
      });
    }
    if (controller != null) unawaited(controller.setVolume(_effectiveVolume));
  }

  void _stepPlaybackSpeed(int direction) {
    const speeds = MediaViewerConstants.playbackSpeeds;
    var index = speeds.indexWhere((s) => (s - _playbackSpeed).abs() < 0.001);
    if (index < 0) {
      index = speeds.indexWhere((s) => s >= _playbackSpeed);
      if (index < 0) index = speeds.length - 1;
    }
    final next = (index + direction).clamp(0, speeds.length - 1);
    _startHideTimer();
    _sessionController.setPlaybackSpeed(speeds[next]);
    _showKeyToast('${speeds[next]}x');
  }

  Future<void> _copyCurrentImageToClipboard() async {
    final fileName = _playlistController.currentFile;
    if (fileName.isEmpty || !MediaViewerConstants.isImage(fileName)) return;
    final ok = await DesktopTransferService.instance.copyImageToOsClipboard(
      container: widget.container,
      vaultPath: fileName,
      fileIoApi: ref.read(vaultFileIoApiProvider),
      sensitiveOverride: widget.isArchivePreview ? true : null,
    );
    if (!mounted) return;
    final label = p.posix.basename(fileName);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? context.l10n.copiedSuffix(label)
                : context.l10n.bookmarkTargetMissing,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
