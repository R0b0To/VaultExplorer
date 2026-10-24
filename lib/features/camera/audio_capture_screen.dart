import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_audio_edit_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/audio_editor/audio_edit_providers.dart';
import 'package:vaultexplorer/features/audio_editor/models/audio_waveform.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

import 'active_recording_registry.dart';
import 'audio_waveform_trimmer.dart';
import 'camera_capture_lock_controller.dart';
import 'camera_vault_service.dart';
import 'vault_audio_recorder_controller.dart';

const String _tag = 'AudioCaptureScreen';

/// Anything shorter than this is treated as an accidental tap, same as the
/// camera's video recording.
const int _minRecordingMs = 500;

/// Smallest span the trim handles can be dragged to.
const int _minTrimSpanMs = 500;

const int _levelBarCount = 48;
const Duration _tickInterval = Duration(milliseconds: 80);

enum _Phase {
  preparing,
  needsPermission,
  ready,
  recording,
  paused,
  stopping,
  reviewing,
  saving,
}

/// Audio-only counterpart of `CameraCaptureScreen`: record from the
/// microphone, review (with playback and a trim), then save the file
/// straight into [container] at [targetDirPath].
///
/// Pops with the saved file's name, or `null` if nothing was saved.
///
/// Like the camera flow, the take sits in a plaintext temp file only
/// between "stop" and "save"/"discard" -- the native side wipes it either
/// way, and anything left unsaved when this screen goes away (back, vault
/// lock, process death) is wiped too.
class AudioCaptureScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String targetDirPath;

  const AudioCaptureScreen({
    super.key,
    required this.container,
    required this.targetDirPath,
  });

  @override
  ConsumerState<AudioCaptureScreen> createState() => _AudioCaptureScreenState();
}

class _AudioCaptureScreenState extends ConsumerState<AudioCaptureScreen>
    with WidgetsBindingObserver {
  final VaultAudioRecorderController _recorder = VaultAudioRecorderController();
  late final VaultFileIoApi _fileIo;
  late final VaultEngineEvents _events;
  late final ActiveRecordingRegistry _registry;
  late final SessionLockController _sessionLockController;
  late final VaultDashboardController _dashboardController;
  late final CameraVaultService _vaultService;
  late final VaultAudioEditApi _audioEditApi;

  _Phase _phase = _Phase.preparing;

  /// The quality the current take was started with. The encoder is fixed once
  /// recording begins, so the app bar shows this (read-only) while recording
  /// instead of the picker.
  AudioRecordingQuality? _recordingQuality;

  /// True while an async transition (start/stop/save) is in flight, so a
  /// second tap can't start another one on top of it.
  bool _busy = false;

  /// True while the registry callback, keep-screen-on, the background
  /// service and the timed auto-lock hold are held for an active recording.
  bool _resourcesHeld = false;

  /// True while this screen holds [SessionLockController.pauseVaultAutoLock]
  /// and the container's auto-close pause. Kept separate from
  /// [_resourcesHeld] so the hold is taken and released exactly once.
  bool _autoLockPausedForRecording = false;

  /// Set once the take is safely in the vault.
  bool _saved = false;

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  // --- Recording -----------------------------------------------------------
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  bool _pollInFlight = false;
  final List<double> _levels = List<double>.filled(
    _levelBarCount,
    0.0,
    growable: true,
  );
  final List<double> _recordedLevels = [];
  DateTime? _startedAt;

  // --- Review ----------------------------------------------------------------
  String? _recordedPath;
  int _durationMs = 0;
  int _trimStartMs = 0;
  int _trimEndMs = 0;
  bool _isDraggingTrim = false;
  NativeVideoController? _player;
  String? _playerPath;
  AudioWaveform? _waveform;
  int? _waveOpId;

  @override
  void initState() {
    super.initState();
    _fileIo = ref.read(vaultFileIoApiProvider);
    _events = ref.read(vaultEngineEventsProvider);
    _registry = ref.read(activeRecordingRegistryProvider);
    // Captured here (not read in dispose) so the auto-lock hold can still be
    // released while the element is being torn down, same as the camera screen.
    _sessionLockController = ref.read(sessionLockControllerProvider);
    _dashboardController = ref.read(vaultDashboardControllerProvider.notifier);
    _audioEditApi = ref.read(vaultAudioEditApiProvider);
    _vaultService = CameraVaultService(
      container: widget.container,
      targetDirPath: widget.targetDirPath,
      fileIoApi: _fileIo,
      lifecycleApi: ref.read(vaultLifecycleApiProvider),
    );
    WidgetsBinding.instance.addObserver(this);
    _events.addBackgroundRecordingStopRequestedListener(
      _onBackgroundStopRequested,
    );
    unawaited(_init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _events.removeBackgroundRecordingStopRequestedListener(
      _onBackgroundStopRequested,
    );
    _releaseRecordingResources();
    final waveOp = _waveOpId;
    if (waveOp != null) unawaited(_audioEditApi.cancel(waveOp));
    _waveOpId = null;
    // Whatever is still unsaved gets wiped rather than left in the cache.
    unawaited(_recorder.cancel());
    final leftover = _recordedPath;
    if (leftover != null) unawaited(_recorder.discard(leftover));
    _player?.removeListener(_onPlayerTick);
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.paused) unawaited(_player?.pause());
  }

  // ── Setup ───────────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      // Only one audio screen can exist at a time, so a recording that is
      // still running natively at this point is a leftover from a screen
      // that went away without cleaning up.
      await _recorder.cancel();
      var granted = await _recorder.hasPermission();
      if (!granted) granted = await _recorder.requestPermission();
      if (!mounted) return;
      setState(() => _phase = granted ? _Phase.ready : _Phase.needsPermission);
    } catch (e) {
      VeLog.w(_tag, 'init failed', e);
      if (mounted) setState(() => _phase = _Phase.needsPermission);
    }
  }

  void _acquireRecordingResources() {
    _resourcesHeld = true;
    unawaited(_fileIo.setKeepScreenOn(true));
    // The timed auto-lock must not cut a running recording short.
    _pauseAutoLockForRecording();
    // If the vault is locked mid-recording by anything else (e.g. the user
    // tapping Lock), stop and save what exists so far.
    _registry.register(widget.container.uri, _stopAndSaveForLock);
    unawaited(
      _fileIo.startBackgroundRecording(
        volId: widget.container.volId,
        containerName: widget.container.displayName,
        audioOnly: true,
      ),
    );
  }

  void _releaseRecordingResources() {
    if (!_resourcesHeld) return;
    _resourcesHeld = false;
    _registry.unregister(widget.container.uri);
    unawaited(_fileIo.setKeepScreenOn(false));
    unawaited(_fileIo.stopBackgroundRecording());
    _resumeAutoLockAfterRecording();
  }

  /// Holds off the two inactivity timers for as long as a take is being
  /// recorded (including while it is paused): the global vault auto-lock
  /// ([SessionLockController.pauseVaultAutoLock]) and this container's own
  /// auto-close timer. Both would otherwise lock the vault out from under the
  /// recording and force it to be stopped. Like an app lock, they simply do
  /// not apply while a recording is in progress; the idle timeout starts
  /// fresh once the recording ends. Screen-off is already ignored while this
  /// screen is open (the add-item menu opens it under
  /// `withLockSuppression`), and a manual lock still goes through
  /// [_registry], which saves what was recorded so far.
  void _pauseAutoLockForRecording() {
    if (_autoLockPausedForRecording) return;
    _autoLockPausedForRecording = true;
    _sessionLockController.pauseVaultAutoLock();
    _dashboardController.pauseAutoCloseForActivity(widget.container.volId);
  }

  void _resumeAutoLockAfterRecording() {
    if (!_autoLockPausedForRecording) return;
    _autoLockPausedForRecording = false;
    _dashboardController.resumeAutoCloseAfterActivity(widget.container.volId);
    _sessionLockController.resumeVaultAutoLock();
  }

  // ── Recording ───────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_busy || _phase != _Phase.ready) return;
    _busy = true;
    try {
      // Read at the moment recording starts, so a change made in the app bar
      // or in Settings applies to this take and never to one already running.
      final settingsState = ref.read(appSettingsControllerProvider);
      final settings = settingsState.loading
          ? await ref.read(appSettingsServiceProvider).loadSettings()
          : settingsState.settings;
      final quality = settings.audioRecordingQuality;
      final res = await _recorder.start(quality: quality);
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      if (!res.success) {
        final l10n = context.l10n;
        if (res.error == 'permission_denied') {
          _showError(l10n.audioMicPermissionRequiredMessage);
          setState(() => _phase = _Phase.needsPermission);
        } else {
          _showError(
            l10n.cameraRecordingFailedWithReasonMessage(res.error ?? ''),
          );
        }
        return;
      }
      _startedAt = DateTime.now();
      _clock
        ..reset()
        ..start();
      for (var i = 0; i < _levels.length; i++) {
        _levels[i] = 0.0;
      }
      _recordedLevels.clear();
      final waveOp = _waveOpId;
      if (waveOp != null) unawaited(_audioEditApi.cancel(waveOp));
      _waveOpId = null;
      _waveform = null;
      unawaited(HapticFeedback.mediumImpact());
      _acquireRecordingResources();
      setState(() {
        _phase = _Phase.recording;
        _recordingQuality = quality;
      });
      _startTicker();
    } catch (e) {
      VeLog.w(_tag, 'start failed', e);
      if (mounted) {
        _showError(context.l10n.cameraRecordingFailedWithReasonMessage('$e'));
      }
    } finally {
      _busy = false;
    }
  }

  /// Puts the big timer and the level meter back to their idle look.
  ///
  /// The timer text is rendered straight from [_clock], so anything that
  /// returns the screen to [_Phase.ready] without starting a new take
  /// (discard, a too-short take, a failed stop) has to zero it explicitly --
  /// otherwise the previous take's length stays on screen.
  void _resetRecordingDisplay() {
    _clock
      ..stop()
      ..reset();
    for (var i = 0; i < _levels.length; i++) {
      _levels[i] = 0.0;
    }
    _recordedLevels.clear();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) => unawaited(_onTick()));
  }

  Future<void> _onTick() async {
    if (!mounted || _phase != _Phase.recording) return;
    // No point polling the meter (or repainting) while nobody can see it.
    if (_lifecycle != AppLifecycleState.resumed) return;
    if (_pollInFlight) return;
    _pollInFlight = true;
    final level = await _recorder.level();
    _pollInFlight = false;
    if (!mounted || _phase != _Phase.recording) return;
    _recordedLevels.add(level);
    setState(() {
      _levels.removeAt(0);
      _levels.add(level);
    });
  }

  Future<void> _togglePause() async {
    if (_busy) return;
    if (_phase == _Phase.recording) {
      _busy = true;
      try {
        if (await _recorder.pause()) {
          _clock.stop();
          unawaited(HapticFeedback.lightImpact());
          if (mounted) setState(() => _phase = _Phase.paused);
        }
      } catch (e) {
        VeLog.w(_tag, 'pause failed', e);
      } finally {
        _busy = false;
      }
    } else if (_phase == _Phase.paused) {
      _busy = true;
      try {
        if (await _recorder.resume()) {
          _clock.start();
          unawaited(HapticFeedback.lightImpact());
          if (mounted) setState(() => _phase = _Phase.recording);
        }
      } catch (e) {
        VeLog.w(_tag, 'resume failed', e);
      } finally {
        _busy = false;
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || (_phase != _Phase.recording && _phase != _Phase.paused)) {
      return;
    }
    _busy = true;
    _ticker?.cancel();
    _clock.stop();
    setState(() => _phase = _Phase.stopping);
    String? orphanPath;
    try {
      unawaited(HapticFeedback.mediumImpact());
      final res = await _recorder.stop();
      final path = res.path;
      if (!res.success || path == null) {
        if (mounted) {
          _showError(
            context.l10n.cameraRecordingFailedWithReasonMessage(
              res.error ?? '',
            ),
          );
          _resetRecordingDisplay();
          setState(() => _phase = _Phase.ready);
        }
        return;
      }
      if (!mounted) {
        orphanPath = path;
        return;
      }
      if (res.durationMs < _minRecordingMs) {
        await _recorder.discard(path);
        if (mounted) {
          _showError(context.l10n.cameraRecordingTooShortMessage);
          _resetRecordingDisplay();
          setState(() => _phase = _Phase.ready);
        }
        return;
      }
      _recordedPath = path;
      _durationMs = res.durationMs;
      _trimStartMs = 0;
      _trimEndMs = res.durationMs;
      await _initPlayer(path);
      if (!mounted) return; // dispose() wipes _recordedPath
      setState(() => _phase = _Phase.reviewing);
      unawaited(_loadWaveform(path));
    } catch (e) {
      VeLog.w(_tag, 'stop failed', e);
      if (mounted) {
        _showError(context.l10n.cameraRecordingFailedWithReasonMessage('$e'));
        _resetRecordingDisplay();
        setState(() => _phase = _Phase.ready);
      }
    } finally {
      _releaseRecordingResources();
      _busy = false;
      if (orphanPath != null) unawaited(_recorder.discard(orphanPath));
    }
  }

  Future<void> _loadWaveform(String path) async {
    final opId = DateTime.now().millisecondsSinceEpoch & 0x3fffffff;
    _waveOpId = opId;
    try {
      final res = await _audioEditApi.waveform(
        volId: -1,
        filePath: path,
        isLocalStorage: true,
        opId: opId,
      );
      if (!mounted || _recordedPath != path) return;
      setState(() {
        _waveform = AudioWaveform(
          peaks: res.peaks,
          peaksPerSecond: res.peaksPerSecond,
          complete: res.complete,
        );
      });
    } catch (e) {
      VeLog.w(_tag, 'waveform extraction failed', e);
    }
  }

  /// "Stop & save" on the background-recording notification. Same as
  /// tapping stop: the take lands in review, where it can be trimmed and
  /// saved once the app is back in front.
  void _onBackgroundStopRequested(int volId) {
    if (volId != widget.container.volId) return;
    if (_phase == _Phase.recording || _phase == _Phase.paused) {
      unawaited(_stopRecording());
    }
  }

  /// Called through [ActiveRecordingRegistry] right before the vault locks.
  /// The vault is still mounted for the duration of this call, so the take
  /// is stopped and written out now instead of being lost.
  Future<void> _stopAndSaveForLock() async {
    if (_phase == _Phase.recording || _phase == _Phase.paused) {
      await _stopRecording();
    }
    if (_phase == _Phase.reviewing && _recordedPath != null) {
      await _save(popOnSuccess: false);
    }
  }

  /// The vault is locked: nothing can be saved any more, so wipe whatever
  /// is left unsaved. The build method shows a blank screen meanwhile.
  Future<void> _onContainerLocked() async {
    if (_saved) return;
    await _abandon();
  }

  // ── Review / save / discard ────────────────────────────────────────────────

  Future<void> _initPlayer(String path) async {
    await _disposePlayer();
    final player = NativeVideoController(
      volId: -1,
      filePath: path,
      isLocalStorage: true,
      autoPlay: false,
      initialSpeed: 1.0,
    );
    _player = player;
    _playerPath = path;
    player.addListener(_onPlayerTick);
    try {
      await player.initialize();
      await player.setLooping(false);
    } catch (e) {
      VeLog.w(_tag, 'player init failed', e);
    }
  }

  Future<void> _disposePlayer() async {
    final player = _player;
    _player = null;
    _playerPath = null;
    if (player == null) return;
    player.removeListener(_onPlayerTick);
    try {
      await player.dispose();
    } catch (e) {
      VeLog.w(_tag, 'player dispose failed', e);
    }
  }

  void _onPlayerTick() {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    if (!_isDraggingTrim &&
        player.value.isPlaying &&
        player.value.position.inMilliseconds >= _trimEndMs) {
      unawaited(player.pause());
      unawaited(player.seekTo(Duration(milliseconds: _trimStartMs)));
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    if (player.value.isPlaying) {
      await player.pause();
      return;
    }
    final pos = player.value.position.inMilliseconds;
    if (pos < _trimStartMs || pos >= _trimEndMs - 50) {
      await player.seekTo(Duration(milliseconds: _trimStartMs));
    }
    await player.play();
  }

  bool get _isTrimmed => _trimStartMs > 0 || _trimEndMs < _durationMs;

  Future<void> _save({bool popOnSuccess = true}) async {
    final path = _recordedPath;
    if (_busy || path == null || _phase != _Phase.reviewing) return;
    _busy = true;
    setState(() => _phase = _Phase.saving);
    try {
      await _player?.pause();
      var savePath = path;
      if (_isTrimmed) {
        final trimmed = await _recorder.trim(
          path: path,
          startMs: _trimStartMs,
          endMs: _trimEndMs,
        );
        if (trimmed == null) {
          await _failSave();
          return;
        }
        // The native trim wiped the original. The new file starts at zero.
        savePath = trimmed;
        _recordedPath = trimmed;
        _durationMs = _trimEndMs - _trimStartMs;
        _trimStartMs = 0;
        _trimEndMs = _durationMs;
      }
      final name = await _vaultService.nextAvailableAudioName(at: _startedAt);
      final virtualPath = _vaultService.buildVirtualPath(name);
      final audioBytes = await _vaultService.localFileSize(savePath);
      if (audioBytes != null &&
          !await _vaultService.hasEnoughSpaceFor(audioBytes)) {
        if (mounted) {
          await _failSave(
            message: context.l10n.cameraNotEnoughVaultSpaceMessage,
          );
        }
        return;
      }
      final ok = widget.container.isLocalStorage
          ? await _fileIo.writeFileFromLocalPath(
              widget.container,
              virtualPath,
              savePath,
            )
          : await _recorder.saveToVault(
              path: savePath,
              volId: widget.container.volId,
              virtualPath: virtualPath,
            );
      if (!ok) {
        // Keep the temp recording available for retry and remove any partial
        // destination file.
        await _deletePartialVaultFile(virtualPath);
        await _failSave();
        return;
      }
      if (!await _vaultService.finalizeVaultWrite(virtualPath)) {
        await _deletePartialVaultFile(virtualPath);
        await _failSave();
        return;
      }
      await _recorder.discard(savePath);
      _recordedPath = null; // securely wiped after the destination write succeeds
      _saved = true;
      if (popOnSuccess && mounted) Navigator.pop(context, name);
    } catch (e) {
      VeLog.w(_tag, 'save failed', e);
      await _failSave(error: '$e');
    } finally {
      _busy = false;
    }
  }

  /// Back to review after a failed save, with the player pointing at the
  /// file that actually still exists (a successful trim replaces it).
  Future<void> _failSave({String? error, String? message}) async {
    if (!mounted) return;
    final l10n = context.l10n;
    _showError(
      message ??
          (error == null
              ? l10n.cameraCouldNotSaveRecordingMessage
              : l10n.cameraCouldNotSaveRecordingWithReasonMessage(error)),
    );
    final current = _recordedPath;
    if (current != null && current != _playerPath) {
      await _initPlayer(current);
    }
    if (mounted) setState(() => _phase = _Phase.reviewing);
  }

  Future<void> _deletePartialVaultFile(String virtualPath) async {
    try {
      await _fileIo.deleteFile(widget.container, virtualPath);
    } catch (e) {
      VeLog.w(_tag, 'could not remove partial vault file', e);
    }
  }

  Future<void> _onDiscardPressed() async {
    if (_busy || _phase != _Phase.reviewing) return;
    if (await _confirmDiscard() != true || !mounted) return;
    if (_busy || _phase != _Phase.reviewing) return;
    final waveOp = _waveOpId;
    if (waveOp != null) unawaited(_audioEditApi.cancel(waveOp));
    _waveOpId = null;
    _waveform = null;
    _resetRecordingDisplay();
    await _disposePlayer();
    final path = _recordedPath;
    _recordedPath = null;
    if (path != null) await _recorder.discard(path);
    if (mounted) setState(() => _phase = _Phase.ready);
  }

  /// Stops everything and wipes any unsaved take.
  Future<void> _abandon() async {
    _ticker?.cancel();
    _clock.stop();
    final waveOp = _waveOpId;
    if (waveOp != null) unawaited(_audioEditApi.cancel(waveOp));
    _waveOpId = null;
    _waveform = null;
    _recordedLevels.clear();
    await _disposePlayer();
    await _recorder.cancel();
    final path = _recordedPath;
    _recordedPath = null;
    if (path != null) await _recorder.discard(path);
    _releaseRecordingResources();
  }

  Future<bool?> _confirmDiscard() {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.audioRecordingDiscardTitle),
        content: Text(l10n.audioRecordingDiscardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
        FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
              foregroundColor: ctx.colors.onError,
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
  }

  Future<void> _requestClose() async {
    if (_busy) return;
    switch (_phase) {
      case _Phase.preparing:
      case _Phase.needsPermission:
      case _Phase.ready:
        Navigator.pop(context);
        return;
      case _Phase.recording:
      case _Phase.paused:
      case _Phase.reviewing:
        if (await _confirmDiscard() != true || !mounted) return;
        await _abandon();
        if (mounted) Navigator.pop(context);
        return;
      case _Phase.stopping:
      case _Phase.saving:
        return;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final cs = context.colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: cs.onError)),
        backgroundColor: cs.error,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lockProvider = cameraCaptureLockProvider(widget.container.volId);
    final isLocked = ref.watch(lockProvider);
    ref.listen<bool>(lockProvider, (previous, next) {
      if (next && previous != true) unawaited(_onContainerLocked());
    });
    final selectedQuality = ref.watch(
      appSettingsControllerProvider.select(
        (s) => s.settings.audioRecordingQuality,
      ),
    );
    if (isLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_requestClose());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: CloseButton(onPressed: () => unawaited(_requestClose())),
          title: Text(context.l10n.audioRecorder),
          actions: [?_buildQualityAction(context, selectedQuality)],
        ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  /// Picks the quality the next take is recorded at -- the audio counterpart
  /// of the camera's resolution menu. The choice is saved as the default, so
  /// it is still selected next time (and in Settings).
  void _selectQuality(AudioRecordingQuality quality) {
    if (_phase != _Phase.ready) return;
    unawaited(
      ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((s) => s.copyWith(audioRecordingQuality: quality)),
    );
  }

  /// The quality pill in the app bar: a menu before recording starts, and just
  /// a label for the quality in use while a take is running (the encoder can't
  /// change mid-recording). Null on screens that aren't the recorder.
  Widget? _buildQualityAction(
    BuildContext context,
    AudioRecordingQuality selected,
  ) {
    final ready = _phase == _Phase.ready;
    final recorderShown =
        ready ||
        _phase == _Phase.recording ||
        _phase == _Phase.paused ||
        _phase == _Phase.stopping;
    if (!recorderShown) return null;

    final l10n = context.l10n;
    final cs = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final shown = ready ? selected : (_recordingQuality ?? selected);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ready ? cs.outline : cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shown.getLocalizedLabel(l10n),
            style: textTheme.labelLarge?.copyWith(
              color: ready ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
          if (ready) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 20, color: cs.onSurface),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: ready
          ? PopupMenuButton<AudioRecordingQuality>(
              tooltip: l10n.audioRecordingQualityLabel,
              initialValue: selected,
              onSelected: _selectQuality,
              itemBuilder: (context) => [
                for (final q in AudioRecordingQuality.values)
                  PopupMenuItem<AudioRecordingQuality>(
                    value: q,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: q == selected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: cs.primary,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                q.getLocalizedLabel(l10n),
                                style: textTheme.bodyLarge?.copyWith(
                                  fontWeight: q == selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              Text(
                                q.getLocalizedSubtitle(l10n),
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: pill,
            )
          : pill,
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.preparing:
        return const Center(child: CircularProgressIndicator());
      case _Phase.needsPermission:
        return _buildPermissionPrompt(context);
      case _Phase.ready:
      case _Phase.recording:
      case _Phase.paused:
      case _Phase.stopping:
        return _buildRecorder(context);
      case _Phase.reviewing:
      case _Phase.saving:
        return _buildReview(context);
    }
  }

  /// Centers [child] when there is room and scrolls when there isn't (a
  /// phone in landscape), instead of overflowing.
  Widget _scrollableCentered(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildPermissionPrompt(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    return _scrollableCentered(
      Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_rounded, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              l10n.audioMicPermissionRequiredMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                setState(() => _phase = _Phase.preparing);
                unawaited(_init());
              },
              child: Text(l10n.audioRecordingAllowMicrophone),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecorder(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final isRecording = _phase == _Phase.recording;
    final isPaused = _phase == _Phase.paused;
    final isActive = isRecording || isPaused;
    final isStopping = _phase == _Phase.stopping;

    return _scrollableCentered(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatAudioDuration(_clock.elapsedMilliseconds),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isPaused ? cs.onSurfaceVariant : cs.onSurface,
              ),
            ),
            SizedBox(
              height: 28,
              child: isPaused
                  ? Center(
                      child: Text(
                        l10n.audioRecordingPausedLabel,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: cs.primary),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 96,
              width: double.infinity,
              child: CustomPaint(
                painter: _LevelBarsPainter(
                  levels: List<double>.of(_levels),
                  activeColor: isRecording ? cs.primary : cs.outlineVariant,
                  idleColor: cs.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 72,
                  child: isActive
                      ? IconButton.filledTonal(
                          tooltip: isPaused
                              ? l10n.audioRecordingResumeTooltip
                              : l10n.audioRecordingPauseTooltip,
                          iconSize: 28,
                          icon: Icon(
                            isPaused
                                ? Icons.mic_rounded
                                : Icons.pause_rounded,
                          ),
                          onPressed: () => unawaited(_togglePause()),
                        )
                      : null,
                ),
                const SizedBox(width: 24),
                Tooltip(
                  message: isActive
                      ? l10n.audioRecordingStopTooltip
                      : l10n.audioRecordingStartTooltip,
                  child: GestureDetector(
                    onTap: isStopping
                        ? null
                        : () => unawaited(
                            isActive ? _stopRecording() : _startRecording(),
                          ),
                    child: Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.onSurface, width: 3),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: isActive ? 30 : 60,
                        height: isActive ? 30 : 60,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(
                            isActive ? 8 : 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                const SizedBox(width: 72),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final saving = _phase == _Phase.saving;
    final playerValue = _player?.value;
    final playerReady = playerValue?.isInitialized ?? false;
    final isPlaying = playerValue?.isPlaying ?? false;
    final selectedMs = _trimEndMs - _trimStartMs;
    final positionMs =
        ((playerValue?.position.inMilliseconds ?? 0) - _trimStartMs).clamp(
          0,
          selectedMs,
        );
    final totalPlayerMs = playerValue?.position.inMilliseconds ?? 0;

    return _scrollableCentered(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded, size: 64, color: cs.primary),
            const SizedBox(height: 8),
            Text(
              formatAudioDuration(selectedMs),
              style: textTheme.displayMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
           Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  tooltip: l10n.mediaViewerActionPlayPause,
                  iconSize: 32,
                  style: IconButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    disabledBackgroundColor: cs.surfaceContainerHighest,
                    disabledForegroundColor:
                        cs.onSurfaceVariant.withValues(alpha: 0.38),
                    minimumSize: const Size(56, 56),
                  ),
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: (playerReady && !saving)
                        ? cs.onPrimary
                        : cs.onSurfaceVariant.withValues(alpha: 0.38),
                    size: 32,
                  ),
                  onPressed: playerReady && !saving
                      ? () => unawaited(_togglePlay())
                      : null,
                ),
                const SizedBox(width: 16),
                Text(
                  '${formatAudioDuration(positionMs)} / '
                  '${formatAudioDuration(selectedMs)}',
                  style: textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            AudioWaveformTrimmer(
              durationMs: _durationMs,
              trimStartMs: _trimStartMs,
              trimEndMs: _trimEndMs,
              currentPositionMs: totalPlayerMs,
              waveform: _waveform,
              recordedLevels: _recordedLevels,
              minTrimSpanMs: _minTrimSpanMs,
              onTrimChangeStart: saving
                  ? null
                  : () {
                      _isDraggingTrim = true;
                      unawaited(_player?.pause());
                    },
              onTrimChanged: saving ? (start, end) {} : _onTrimChanged,
              onTrimChangeEnd: saving
                  ? null
                  : () {
                      _isDraggingTrim = false;
                      unawaited(
                        _player?.seekTo(Duration(milliseconds: _trimStartMs)),
                      );
                    },
              onSeek: saving
                  ? null
                  : (posMs) {
                      unawaited(_player?.seekTo(Duration(milliseconds: posMs)));
                    },
            ),
            const SizedBox(height: 28),
            if (saving) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                widget.container.isLocalStorage
                    ? l10n.savingLabel
                    : l10n.savingToVault,
                style: textTheme.bodyMedium,
              ),
            ] else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_onDiscardPressed()),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l10n.discard),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => unawaited(_save()),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(l10n.save),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _onTrimChanged(int start, int end) {
    final total = _durationMs;
    final minSpan = math.min(_minTrimSpanMs, total);
    var s = start.clamp(0, total);
    var e = end.clamp(0, total);
    if (e - s < minSpan) {
      if (s + minSpan <= total) {
        e = s + minSpan;
      } else {
        s = (e - minSpan).clamp(0, total);
      }
    }
    setState(() {
      _trimStartMs = s;
      _trimEndMs = e;
    });
  }
}

/// Rolling input-level meter: one bar per recent poll, newest on the right.
class _LevelBarsPainter extends CustomPainter {
  final List<double> levels;
  final Color activeColor;
  final Color idleColor;

  _LevelBarsPainter({
    required this.levels,
    required this.activeColor,
    required this.idleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final slot = size.width / levels.length;
    final barWidth = math.max(2.0, slot * 0.6);
    final midY = size.height / 2;
    const minBarHeight = 4.0;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      final height = math.max(minBarHeight, level * size.height);
      paint.color = level > 0.02 ? activeColor : idleColor;
      final cx = slot * i + slot / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, midY),
            width: barWidth,
            height: height,
          ),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelBarsPainter oldDelegate) =>
      oldDelegate.levels != levels ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.idleColor != idleColor;
}
