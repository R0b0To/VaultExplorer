import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_audio_edit_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/editor_swipe_to_seek_area.dart';
import 'package:vaultexplorer/features/video_editor/models/edit_segment.dart';
import 'package:vaultexplorer/features/video_editor/models/video_edit_math.dart';
import 'package:vaultexplorer/features/video_editor/widgets/video_segments_sheet.dart';

import 'audio_edit_providers.dart';
import 'audio_editor_controller.dart';
import 'models/audio_compression.dart';
import 'models/audio_waveform.dart';
import 'widgets/audio_export_sheet.dart';
import 'widgets/audio_timeline.dart';

/// An audio editor: trim, cut out parts, split and merge clips. Formats that can
/// be stream-copied (AAC, MP3, WAV, Opus, Vorbis) are cut without re-encoding;
/// anything else (FLAC, WMA, AMR, ...) is re-encoded to AAC, which is cheap for
/// audio (see `LosslessAudioCutter.kt` and `AudioReencoder.kt`). The audio
/// sibling of the video editor -- same segment model, keep / cut-out modes,
/// undo and export flow -- with a waveform timeline in place of the filmstrip.
class AudioEditorScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;

  const AudioEditorScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  ConsumerState<AudioEditorScreen> createState() => _AudioEditorScreenState();
}

class _AudioEditorScreenState extends ConsumerState<AudioEditorScreen>
    with WidgetsBindingObserver {
  static int _opCounter = DateTime.now().millisecondsSinceEpoch & 0x3fffffff;
  static const String _tag = 'AudioEditorScreen';

  /// Within this of a segment edge counts as "on" it for the cut-point buttons.
  static const int _cutPointSlackUs = 50000;

  late final VaultAudioEditApi _api;
  late final VaultEngineEvents _events;

  NativeVideoController? _player;
  AudioEditorController? _editor;
  AudioProbe? _probe;
  String? _loadError;

  AudioWaveform? _waveform;

  /// 0..1 while the waveform is being decoded, null otherwise.
  final ValueNotifier<double?> _waveProgress = ValueNotifier<double?>(null);
  int? _waveOpId;

  /// The playhead in microseconds. Follows the player, except while the user
  /// is scrubbing or a seek is still in flight, when it holds the requested
  /// position so the UI doesn't jump back.
  final ValueNotifier<int> _playhead = ValueNotifier<int>(0);
  final GlobalKey<AudioTimelineState> _timelineKey =
      GlobalKey<AudioTimelineState>();

  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  bool _exporting = false;
  bool _previewResult = false;
  bool _skippingGap = false;
  double _playbackSpeed = 1.0;

  // Seek pump: only the latest requested position is ever sent, one at a time.
  int? _pendingSeekUs;
  bool _seeking = false;
  Completer<void>? _seekIdle;

  bool get _isLocal => widget.container.isLocalStorage;

  /// Path the native side reads from: real and absolute for local storage,
  /// container-relative for a vault (same rule the media viewer follows).
  String get _nativePath =>
      _isLocal ? p.join(widget.container.uri, widget.filePath) : widget.filePath;

  String get _fileName => widget.filePath.split('/').last;

  /// The file's extension in capitals (`FLAC`), as named in the format banners.
  String get _formatLabel =>
      p.extension(_fileName).replaceFirst('.', '').toUpperCase();

  @override
  void initState() {
    super.initState();
    _api = ref.read(vaultAudioEditApiProvider);
    _events = ref.read(vaultEngineEventsProvider);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final waveOp = _waveOpId;
    if (waveOp != null) unawaited(_api.cancel(waveOp)); // stop decoding for nobody
    unawaited(_shutdownPlayer());
    _editor?.dispose();
    _playhead.dispose();
    _waveProgress.dispose();
    super.dispose();
  }

  /// Releases the native player and clears the playback-active flag.
  Future<void> _shutdownPlayer() async {
    final player = _player;
    if (player == null) return;
    _player = null;
    player.removeListener(_onPlayerChanged);
    await player.dispose();
    await PlaybackThrottleController.setActive(false);
  }

  Future<void> _onPopRequested(bool didPop, Object? result) async {
    if (didPop || _exporting) return;
    final editor = _editor;
    if (editor != null && editor.hasUnsavedChanges) {
      final l10n = context.l10n;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.videoEditorDiscardTitle),
          content: Text(l10n.videoEditorDiscardMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ctx.colors.error,
                foregroundColor: ctx.colors.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.videoEditorDiscardAction),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    await _shutdownPlayer();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_player?.pause());
  }

  // ── Loading ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      await PlaybackThrottleController.setActive(true);
      if (!mounted) return;

      final player = NativeVideoController(
        volId: widget.container.volId,
        filePath: _nativePath,
        autoPlay: false,
        isLocalStorage: _isLocal,
      );
      _player = player;
      player.addListener(_onPlayerChanged);
      unawaited(
        player.initialize().catchError((Object e) {
          VeLog.w(_tag, 'Player initialization failed', e);
        }),
      );

      final probe = await _api.probe(
        volId: widget.container.volId,
        filePath: _nativePath,
        isLocalStorage: _isLocal,
      );
      if (!mounted) return;
      if (probe.durationUs <= 0) {
        throw const AudioEditException('PROBE_FAILED', 'Unknown audio length');
      }

      final editor = AudioEditorController(durationUs: probe.durationUs);
      setState(() {
        _probe = probe;
        _editor = editor;
      });

      // The editor is usable while the waveform decodes in the background.
      unawaited(_loadWaveform());
    } on AudioEditException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (e) {
      VeLog.w(_tag, 'Loading the audio editor failed', e);
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _loadWaveform() async {
    final opId = ++_opCounter;
    _waveOpId = opId;
    _waveProgress.value = 0;
    void onProgress(AudioEditProgress e) {
      if (e.opId == opId && e.phase == 'waveform') {
        _waveProgress.value = e.fraction;
      }
    }

    _events.addAudioEditProgressListener(onProgress);
    try {
      final result = await _api.waveform(
        volId: widget.container.volId,
        filePath: _nativePath,
        isLocalStorage: _isLocal,
        opId: opId,
      );
      if (!mounted) return;
      setState(() {
        _waveform = AudioWaveform(
          peaks: result.peaks,
          peaksPerSecond: result.peaksPerSecond,
          complete: result.complete,
        );
      });
    } on AudioEditException catch (e) {
      // Editing still works without the waveform; the track just stays flat.
      if (!e.cancelled) VeLog.w(_tag, 'Waveform failed: ${e.message}');
    } finally {
      _events.removeAudioEditProgressListener(onProgress);
      if (_waveOpId == opId) _waveOpId = null;
      if (mounted) _waveProgress.value = null;
    }
  }

  void _onPlayerChanged() {
    if (_scrubbing || _seeking) return;
    final player = _player;
    final editor = _editor;
    if (player == null || editor == null) return;
    var us = player.value.position.inMicroseconds;
    if (us > editor.durationUs) us = editor.durationUs;
    if (us != _playhead.value) _playhead.value = us;

    // "Preview cut" playback: skips over the gaps between exported ranges.
    if (_previewResult && player.value.isPlaying && !_skippingGap) {
      final ranges = editor.plannedRanges;
      if (ranges.isEmpty) {
        unawaited(player.pause());
        return;
      }

      var inRange = false;
      for (var i = 0; i < ranges.length; i++) {
        final r = ranges[i];
        if (us >= r.startUs && us < r.endUs) {
          inRange = true;
          // Approaching the end of this range.
          if (us >= r.endUs - 80000) {
            _skippingGap = true;
            if (i < ranges.length - 1) {
              unawaited(
                _seekToUs(ranges[i + 1].startUs).then((_) {
                  _skippingGap = false;
                }),
              );
            } else {
              // End of the last range: pause and park at the start of the first.
              unawaited(
                player
                    .pause()
                    .then((_) => _seekToUs(ranges.first.startUs))
                    .then((_) {
                      _skippingGap = false;
                    }),
              );
            }
          }
          break;
        }
      }

      if (!inRange) {
        _skippingGap = true;
        final later = ranges.where((r) => r.startUs > us);
        if (later.isNotEmpty) {
          unawaited(
            _seekToUs(later.first.startUs).then((_) {
              _skippingGap = false;
            }),
          );
        } else {
          unawaited(
            player
                .pause()
                .then((_) => _seekToUs(ranges.first.startUs))
                .then((_) {
                  _skippingGap = false;
                }),
          );
        }
      }
    }
  }

  // ── Seeking / transport ────────────────────────────────────────────────

  Future<void> _seekToUs(int us) {
    final editor = _editor;
    final t = editor == null ? us : us.clamp(0, editor.durationUs).toInt();
    _playhead.value = t;
    return _requestSeek(t);
  }

  Future<void> _requestSeek(int us) {
    _pendingSeekUs = us;
    if (_seeking) return _seekIdle!.future;
    _seeking = true;
    _seekIdle = Completer<void>();
    unawaited(_runSeekLoop());
    return _seekIdle!.future;
  }

  Future<void> _runSeekLoop() async {
    try {
      while (_pendingSeekUs != null) {
        final us = _pendingSeekUs!;
        _pendingSeekUs = null;
        final player = _player;
        if (player == null || player.isDisposed) break;
        await player.seekTo(Duration(milliseconds: (us + 999) ~/ 1000));
      }
    } catch (e) {
      VeLog.w(_tag, 'Seek failed', e);
    } finally {
      _seeking = false;
      _seekIdle!.complete();
    }
  }

  void _onScrubStart() {
    _scrubbing = true;
    _resumeAfterScrub = _player?.value.isPlaying ?? false;
    if (_resumeAfterScrub) unawaited(_player?.pause());
  }

  void _onScrub(int us) => unawaited(_seekToUs(us));

  void _onScrubEnd() {
    _scrubbing = false;
    if (_resumeAfterScrub) unawaited(_player?.play());
    _resumeAfterScrub = false;
  }

  void _onTimelineTap(int us) {
    _editor?.selectAt(us);
    unawaited(_seekToUs(us));
  }

  Future<void> _togglePlay() async {
    final player = _player;
    final editor = _editor;
    if (player == null || editor == null) return;
    if (player.value.isPlaying) {
      await player.pause();
      return;
    }

    if (_previewResult) {
      final ranges = editor.plannedRanges;
      if (ranges.isNotEmpty) {
        final cur = _playhead.value;
        final inside = ranges.any(
          (r) => cur >= r.startUs && cur < r.endUs - 80000,
        );
        if (!inside) {
          final later = ranges.where((r) => r.startUs >= cur);
          await _seekToUs(later.isNotEmpty ? later.first.startUs : ranges.first.startUs);
        }
      }
    } else if (_playhead.value >= editor.durationUs - 200000) {
      await _seekToUs(0);
    }
    await player.play();
  }

  void _step(int deltaUs) => unawaited(_seekToUs(_playhead.value + deltaUs));

  /// Jumps to the previous / next segment edge (or the start / end of the file).
  void _jumpCutPoint({required bool forward}) {
    final editor = _editor;
    if (editor == null) return;
    final points = <int>{0, editor.durationUs};
    for (final s in editor.segments) {
      points
        ..add(s.startUs)
        ..add(s.endUs);
    }
    final sorted = points.toList()..sort();
    final from = _playhead.value;
    final int target;
    if (forward) {
      target = sorted.firstWhere(
        (t) => t > from + _cutPointSlackUs,
        orElse: () => editor.durationUs,
      );
    } else {
      target = sorted.lastWhere(
        (t) => t < from - _cutPointSlackUs,
        orElse: () => 0,
      );
    }
    unawaited(_seekToUs(target));
  }

  // ── Segment edits ──────────────────────────────────────────────────────

  void _toast(String message, {AppBannerTone tone = AppBannerTone.info}) {
    if (!mounted) return;
    showAppSnackBar(context, message: message, tone: tone);
  }

  void _setStart() {
    if (!_editor!.setSelectedStart(_playhead.value)) {
      _toast(context.l10n.videoEditorBoundaryInvalid);
    }
  }

  void _setEnd() {
    if (!_editor!.setSelectedEnd(_playhead.value)) {
      _toast(context.l10n.videoEditorBoundaryInvalid);
    }
  }

  void _addSegment() {
    if (!_editor!.addSegmentAt(_playhead.value)) {
      _toast(context.l10n.videoEditorNoRoom);
    }
  }

  void _splitSegment() {
    if (!_editor!.splitAt(_playhead.value)) {
      _toast(context.l10n.videoEditorNoRoom);
    }
  }

  // ── Export ─────────────────────────────────────────────────────────────

  Future<void> _onExport() async {
    final editor = _editor;
    final probe = _probe;
    if (editor == null || probe == null || _exporting) return;
    final l10n = context.l10n;

    if (widget.container.readOnly) {
      _toast(l10n.audioEditorReadOnly, tone: AppBannerTone.error);
      return;
    }
    if (!editor.canExport) {
      _toast(l10n.videoEditorNothingToExport);
      return;
    }

    await _player?.pause();
    if (!mounted) return;

    final dot = _fileName.lastIndexOf('.');
    final defaultStem = dot > 0 ? _fileName.substring(0, dot) : _fileName;

    final choice = await AudioExportSheet.show(
      context,
      clipCount: editor.plannedRanges.length,
      totalDurationUs: editor.totalSnappedUs,
      defaultBaseName: '${defaultStem}_cut',
      extension: probe.outputExtension,
      isReadOnly: widget.container.readOnly,
      reencode: probe.reencode,
      compressionOptions: AudioCompression.optionsFor(probe),
      sourceChannels: probe.channels,
      sourceBitrate: probe.bitrate,
    );
    if (choice == null || !mounted) return;

    // A compressed export is always AAC in an .m4a, whatever the source was.
    final outputExtension = choice.compression.isOn
        ? AudioCompression.outputExtension
        : probe.outputExtension;

    final ranges = editor.exportRanges(merge: choice.merge);
    final outputCount = choice.merge ? 1 : ranges.length;

    final container = widget.container;
    final slash = widget.filePath.lastIndexOf('/');
    final dirPath = slash == -1 ? '' : widget.filePath.substring(0, slash);

    var existing = <RawEntry>[];
    try {
      final raw = await ref
          .read(vaultFileIoApiProvider)
          .listDirectory(container, dirPath);
      if (raw != null) existing = RawEntry.parseAll(raw);
    } catch (e) {
      VeLog.w(
        _tag,
        'Directory listing failed at ${VeLog.censorUri(dirPath)} while naming exports',
        e,
      );
    }
    if (!mounted) return;

    final fsType = resolveFilesystemType(container);
    final existingLowercase = {for (final e in existing) e.name.toLowerCase()};
    final baseSourceName = choice.customName != null
        ? '${choice.customName}.$outputExtension'
        : _fileName;

    final names = planOutputNames(
      sourceFileName: baseSourceName,
      extension: outputExtension,
      count: outputCount,
      existingLowercase: existingLowercase,
      unique: FileOperationService.makeUniqueName,
    );

    final relativePaths = <String>[];
    for (final name in names) {
      final built = PathComponents(
        parentSegments: dirPath.isEmpty ? const [] : dirPath.split('/'),
        name: name,
        type: EntryType.file,
        fsType: fsType,
      ).validateAndBuild(l10n);
      switch (built) {
        case PathBuildFailure(:final issues):
          _toast(
            l10n.videoEditorExportFailed(issues.first.message),
            tone: AppBannerTone.error,
          );
          return;
        case PathBuildSuccess(:final path):
          relativePaths.add(path);
      }
    }
    final nativeOutputs = _isLocal
        ? [for (final r in relativePaths) p.join(container.uri, r)]
        : relativePaths;

    final result = await _runExport(
      ranges: ranges,
      merge: choice.merge,
      outputPaths: nativeOutputs,
      outputCount: outputCount,
      compressBitratePerChannel: choice.compression.bitratePerChannel,
    );

    if (choice.replaceOriginal && result != null && relativePaths.isNotEmpty) {
      await _replaceOriginalWith(
        cutPath: relativePaths.first,
        extension: outputExtension,
        existingLowercase: existingLowercase,
      );
    }
  }

  /// Swaps the freshly exported cut in for the original file. The cut keeps
  /// the original's name when the extension is unchanged; when the cut had to
  /// be written in another container (an `.aac` becomes `.m4a`) it gets the
  /// same name with the new extension, so the name never lies about the content.
  Future<void> _replaceOriginalWith({
    required String cutPath,
    required String extension,
    required Set<String> existingLowercase,
  }) async {
    final l10n = context.l10n;
    final container = widget.container;
    final fileIo = ref.read(vaultFileIoApiProvider);

    final dot = _fileName.lastIndexOf('.');
    final stem = dot > 0 ? _fileName.substring(0, dot) : _fileName;
    final currentExt = dot > 0 ? _fileName.substring(dot + 1) : '';
    final String targetName;
    if (currentExt.toLowerCase() == extension.toLowerCase()) {
      targetName = _fileName;
    } else {
      // The original is about to go, so only the other files can clash.
      final others = {...existingLowercase}..remove(_fileName.toLowerCase());
      targetName = FileOperationService.makeUniqueName('$stem.$extension', others);
    }

    try {
      await fileIo.deleteFile(container, widget.filePath);
      await fileIo.renameFile(container, cutPath, targetName);
    } catch (e) {
      VeLog.w(_tag, 'Failed to replace original file with cut', e);
      _toast(
        l10n.videoEditorExportFailed(e.toString()),
        tone: AppBannerTone.error,
      );
    }
  }

  Future<AudioExportResult?> _runExport({
    required List<TimeRange> ranges,
    required bool merge,
    required List<String> outputPaths,
    required int outputCount,
    int? compressBitratePerChannel,
  }) async {
    final fileIo = ref.read(vaultFileIoApiProvider);
    final lockController = ref.read(sessionLockControllerProvider);
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    final opId = ++_opCounter;

    final progress = ValueNotifier<AudioEditProgress?>(null);
    void onProgress(AudioEditProgress e) {
      if (e.opId == opId) progress.value = e;
    }

    _events.addAudioEditProgressListener(onProgress);
    setState(() => _exporting = true);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: _ExportProgressDialog(
            progress: progress,
            outputCount: outputCount,
            onCancel: () => unawaited(_api.cancel(opId)),
          ),
        ),
      ),
    );

    AudioExportResult? result;
    AudioEditException? failure;
    await fileIo.setKeepScreenOn(true);
    try {
      await lockController.withLockSuppression(() async {
        result = await _api.export(
          volId: widget.container.volId,
          filePath: _nativePath,
          isLocalStorage: _isLocal,
          segmentsUs: ranges,
          merge: merge,
          outputPaths: outputPaths,
          opId: opId,
          compressBitratePerChannel: compressBitratePerChannel,
        );
      });
    } on AudioEditException catch (e) {
      failure = e;
    } catch (e) {
      VeLog.w(_tag, 'Export failed unexpectedly', e);
      failure = AudioEditException('EXPORT_FAILED', e.toString());
    } finally {
      await fileIo.setKeepScreenOn(false);
      _events.removeAudioEditProgressListener(onProgress);
    }

    if (navigator.mounted) navigator.pop(); // close the progress dialog
    if (!mounted) return result;
    setState(() => _exporting = false);

    if (result != null) {
      _toast(
        l10n.audioEditorSaved(result!.outputPaths.length),
        tone: AppBannerTone.success,
      );
    } else if (failure != null) {
      if (failure.cancelled) {
        _toast(l10n.videoEditorExportCancelled);
      } else {
        _toast(
          l10n.videoEditorExportFailed(failure.message),
          tone: AppBannerTone.error,
        );
      }
    }
    return result;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  bool get _canExport {
    final editor = _editor;
    final probe = _probe;
    return editor != null &&
        probe != null &&
        probe.cutSupported &&
        editor.canExport &&
        !_exporting;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editor = _editor;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopRequested,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (editor != null)
              ListenableBuilder(
                listenable: editor,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.undoTooltip,
                      icon: const Icon(Icons.undo_rounded),
                      onPressed: editor.canUndo ? editor.undo : null,
                    ),
                    IconButton(
                      tooltip: l10n.redoTooltip,
                      icon: const Icon(Icons.redo_rounded),
                      onPressed: editor.canRedo ? editor.redo : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12, left: 4),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        onPressed: _canExport ? _onExport : null,
                        child: Text(l10n.videoEditorExportAction),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final editor = _editor;
    final player = _player;

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: cs.error),
              const SizedBox(height: 12),
              Text(
                l10n.audioEditorLoadFailed(_loadError!),
                textAlign: TextAlign.center,
                style: context.typography.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.closeTooltip),
              ),
            ],
          ),
        ),
      );
    }
    if (editor == null || player == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n.audioEditorAnalyzing,
              style: context.typography.bodyMedium,
            ),
          ],
        ),
      );
    }

    final panel = _buildInfoPanel(context, player);
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final controls = _buildControls(context, editor, player);
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        if (landscape) {
          return Row(
            children: [
              Expanded(child: panel),
              SizedBox(width: 380, child: SingleChildScrollView(child: controls)),
            ],
          );
        }
        return Column(children: [Expanded(child: panel), controls]);
      },
    );
  }

  /// There's no picture to show, so the preview area is a big time readout and
  /// a summary of the file. Tapping it plays / pauses, like the video preview.
  Widget _buildInfoPanel(BuildContext context, NativeVideoController player) {
    final cs = context.colors;
    final text = context.typography;
    final probe = _probe;
    final details = probe == null ? '' : _describe(probe);
    final editor = _editor;
    final totalDuration = Duration(microseconds: editor?.durationUs ?? 0);
    final canSeek = editor != null &&
        player.value.isInitialized &&
        !_exporting &&
        totalDuration > Duration.zero;

    return EditorSwipeToSeekArea(
      totalDuration: totalDuration,
      currentPosition: () => Duration(microseconds: _playhead.value),
      visibleDuration: () => _timelineKey.currentState?.visibleDuration,
      enabled: canSeek,
      onTap: () => unawaited(_togglePlay()),
      onSeekStart: _onScrubStart,
      onSeekUpdate: (pos) => _onScrub(pos.inMicroseconds),
      onSeekEnd: (_) => _onScrubEnd(),
      onSeekCancel: (pos) {
        unawaited(_seekToUs(pos.inMicroseconds));
        _onScrubEnd();
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<NativeVideoValue>(
                valueListenable: player,
                builder: (context, v, _) => Icon(
                  Icons.graphic_eq_rounded,
                  size: 72,
                  color: v.isPlaying ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<int>(
                valueListenable: _playhead,
                builder: (context, us, _) => Text(
                  formatTimecode(us),
                  style: text.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  details,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// `AAC · 44.1 kHz · 2 ch · 128 kbps` -- whatever the probe knows.
  static String _describe(AudioProbe probe) {
    final parts = <String>[];
    final mime = probe.mime;
    if (mime != null) parts.add(_codecName(mime));
    final rate = probe.sampleRate;
    if (rate != null && rate > 0) {
      parts.add(
        rate % 1000 == 0
            ? '${rate ~/ 1000} kHz'
            : '${(rate / 1000).toStringAsFixed(1)} kHz',
      );
    }
    final channels = probe.channels;
    if (channels != null && channels > 0) parts.add('$channels ch');
    final bitrate = probe.bitrate;
    if (bitrate != null && bitrate > 0) {
      parts.add('${(bitrate / 1000).round()} kbps');
    }
    return parts.join(' · ');
  }

  static String _codecName(String mime) => switch (mime) {
    'audio/mp4a-latm' => 'AAC',
    'audio/mpeg' => 'MP3',
    'audio/opus' => 'Opus',
    'audio/vorbis' => 'Vorbis',
    'audio/raw' => 'PCM',
    'audio/flac' => 'FLAC',
    _ => mime.split('/').last.toUpperCase(),
  };

  Widget _buildControls(
    BuildContext context,
    AudioEditorController editor,
    NativeVideoController player,
  ) {
    final l10n = context.l10n;
    final cs = context.colors;
    final text = context.typography;
    final segments = editor.segments;
    final selected = editor.selected;
    final probe = _probe;
    final summaryStyle = text.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A format that can't be copied is re-encoded to AAC on export; one this
          // device can't decode at all can still be played, just not exported.
          if (probe != null && (!probe.cutSupported || probe.reencode)) ...[
            InlineBanner(
              probe.cutSupported
                  ? l10n.audioEditorReencodeBanner(_formatLabel)
                  : l10n.audioEditorUnsupportedFormat(_formatLabel),
              tone: probe.cutSupported
                  ? AppBannerTone.info
                  : AppBannerTone.warning,
            ),
            const SizedBox(height: 8),
          ],

          // Row 1: time readout + zoom controls
          Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _playhead,
                builder: (context, us, _) => Text(
                  '${formatTimecode(us)} / ${formatTimecode(editor.durationUs)}',
                  style: text.labelLarge,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: l10n.videoEditorZoomOut,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.zoom_out_rounded),
                onPressed: () => _timelineKey.currentState?.zoomBy(0.5),
              ),
              IconButton(
                tooltip: l10n.videoEditorZoomIn,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.zoom_in_rounded),
                onPressed: () => _timelineKey.currentState?.zoomBy(2),
              ),
              IconButton(
                tooltip: l10n.videoEditorZoomFit,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.fit_screen_rounded),
                onPressed: () => _timelineKey.currentState?.resetZoom(),
              ),
            ],
          ),

          // Row 2: waveform timeline with draggable handles
          AudioTimeline(
            key: _timelineKey,
            durationUs: editor.durationUs,
            segments: segments,
            selectedId: editor.selectedId,
            mode: editor.mode,
            waveform: _waveform,
            playheadUs: _playhead,
            onScrubStart: _onScrubStart,
            onScrub: _onScrub,
            onScrubEnd: _onScrubEnd,
            onTapAt: _onTimelineTap,
            onHandleDragStart: editor.beginHandleDrag,
            onHandleDragUpdate: (isStart, us) {
              if (isStart) {
                editor.updateSelectedStart(us);
              } else {
                editor.updateSelectedEnd(us);
              }
            },
            onHandleDragEnd: editor.endHandleDrag,
          ),
          ValueListenableBuilder<double?>(
            valueListenable: _waveProgress,
            builder: (context, v, _) => SizedBox(
              height: 3,
              child: v == null
                  ? null
                  : LinearProgressIndicator(value: v, minHeight: 2),
            ),
          ),
          const SizedBox(height: 2),

          // Row 3: selected segment times + segments chip
          Row(
            children: [
              Expanded(
                child: selected != null
                    ? Text(
                        '${formatTimecode(selected.startUs)} – ${formatTimecode(selected.endUs)}'
                        '  (${formatTimecode(selected.lengthUs, millis: false)})',
                        style: summaryStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        l10n.videoEditorNoSegments,
                        style: summaryStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              ActionChip(
                avatar: const Icon(Icons.layers_rounded, size: 18),
                label: Text('${segments.length}'),
                tooltip: l10n.videoEditorSegments,
                onPressed: () => VideoSegmentsSheet.show(
                  context,
                  editor: editor,
                  onSeekTo: (us) => unawaited(_seekToUs(us)),
                  cutOutModeDescription: l10n.audioEditorCutOutModeDescription,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Row 4: transport + preview cut + 2x speed
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.audioEditorPrevCutPoint,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: () => _jumpCutPoint(forward: false),
                ),
                _StepButton(label: '−1s', onTap: () => _step(-1000000)),
                ValueListenableBuilder<NativeVideoValue>(
                  valueListenable: player,
                  builder: (context, v, _) => IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                    tooltip: l10n.mediaViewerActionPlayPause,
                    icon: Icon(
                      v.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: () => unawaited(_togglePlay()),
                  ),
                ),
                _StepButton(label: '+1s', onTap: () => _step(1000000)),
                IconButton(
                  tooltip: l10n.audioEditorNextCutPoint,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () => _jumpCutPoint(forward: true),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: _previewResult ? cs.primaryContainer : null,
                    foregroundColor: _previewResult
                        ? cs.onPrimaryContainer
                        : null,
                  ),
                  tooltip: l10n.videoEditorPreviewCut,
                  icon: Icon(
                    _previewResult
                        ? Icons.content_cut_rounded
                        : Icons.content_cut_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _previewResult = !_previewResult),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: _playbackSpeed > 1.0
                        ? cs.primaryContainer
                        : null,
                    foregroundColor: _playbackSpeed > 1.0
                        ? cs.onPrimaryContainer
                        : null,
                  ),
                  tooltip: _playbackSpeed > 1.0 ? '1×' : '2×',
                  icon: Text(
                    _playbackSpeed > 1.0 ? '2×' : '1×',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _playbackSpeed > 1.0
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  onPressed: () {
                    final next = _playbackSpeed > 1.0 ? 1.0 : 2.0;
                    _player?.setPlaybackSpeed(next);
                    setState(() => _playbackSpeed = next);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Row 5: tools
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.videoEditorSetStart,
                icon: const Icon(Icons.first_page_rounded),
                onPressed: selected == null ? null : _setStart,
              ),
              IconButton(
                tooltip: l10n.videoEditorSetEnd,
                icon: const Icon(Icons.last_page_rounded),
                onPressed: selected == null ? null : _setEnd,
              ),
              IconButton(
                tooltip: l10n.videoEditorSplit,
                icon: const Icon(Icons.call_split_rounded),
                onPressed: _splitSegment,
              ),
              IconButton(
                tooltip: l10n.videoEditorRemoveSection,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: selected == null ? null : editor.deleteSelected,
              ),
              IconButton(
                tooltip: l10n.videoEditorAddSegment,
                icon: const Icon(Icons.add_rounded),
                onPressed: _addSegment,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      child: Text(label),
    );
  }
}

/// Non-dismissible progress dialog for a running export, with Cancel.
class _ExportProgressDialog extends StatelessWidget {
  final ValueListenable<AudioEditProgress?> progress;
  final int outputCount;
  final VoidCallback onCancel;

  const _ExportProgressDialog({
    required this.progress,
    required this.outputCount,
    required this.onCancel,
  });

  static double? _overall(AudioEditProgress? e) {
    if (e == null) return null;
    final within = e.phase == 'saving'
        ? 0.85 + 0.15 * e.fraction
        : 0.85 * e.fraction;
    return ((e.outputIndex + within) / e.outputCount)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.audioEditorExporting),
      content: ValueListenableBuilder<AudioEditProgress?>(
        valueListenable: progress,
        builder: (context, e, _) {
          final String label;
          if (e != null && e.phase == 'saving') {
            label = l10n.videoEditorSaving;
          } else if (outputCount > 1) {
            label = l10n.videoEditorCutting((e?.outputIndex ?? 0) + 1, outputCount);
          } else {
            label = l10n.videoEditorCuttingOne;
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: _overall(e)),
              const SizedBox(height: 12),
              Text(label),
            ],
          );
        },
      ),
      actions: [TextButton(onPressed: onCancel, child: Text(l10n.cancel))],
    );
  }
}
