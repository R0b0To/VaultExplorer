import 'dart:async';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_video_edit_api.dart';
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

import 'models/edit_segment.dart';
import 'models/video_edit_math.dart';
import 'video_edit_providers.dart';
import 'video_editor_controller.dart';
import 'widgets/video_export_sheet.dart';
import 'widgets/video_segments_sheet.dart';
import 'widgets/video_timeline.dart';

/// A lossless video editor: trim, cut out parts, split, and merge clips
/// without re-encoding (see `LosslessVideoCutter.kt`).
class VideoEditorScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;

  const VideoEditorScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen>
    with WidgetsBindingObserver {
  static int _opCounter = DateTime.now().millisecondsSinceEpoch & 0x3fffffff;
  static const String _tag = 'VideoEditorScreen';

  NativeVideoController? _player;
  VideoEditorController? _editor;
  VideoProbe? _probe;
  String? _loadError;

  /// Filmstrip thumbnails loaded across the timeline.
  List<FilmstripEntry>? _filmstripFrames;

  /// The playhead in microseconds. Follows the player, except while the user
  /// is scrubbing or a seek is still in flight, when it holds the requested
  /// position so the UI doesn't jump back.
  final ValueNotifier<int> _playhead = ValueNotifier<int>(0);
  final GlobalKey<VideoTimelineState> _timelineKey =
      GlobalKey<VideoTimelineState>();

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
  String get _nativePath => _isLocal
      ? p.join(widget.container.uri, widget.filePath)
      : widget.filePath;

  String get _fileName => widget.filePath.split('/').last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shutdownPlayer());
    _disposeFilmstrip();
    _editor?.dispose();
    _playhead.dispose();
    super.dispose();
  }

  void _disposeFilmstrip() {
    if (_filmstripFrames != null) {
      for (final f in _filmstripFrames!) {
        f.image.dispose();
      }
      _filmstripFrames = null;
    }
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
    final api = ref.read(vaultVideoEditApiProvider);
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

      final probe = await api.probe(
        volId: widget.container.volId,
        filePath: _nativePath,
        isLocalStorage: _isLocal,
      );
      if (!mounted) return;
      if (probe.durationUs <= 0) {
        throw const VideoEditException('PROBE_FAILED', 'Unknown video length');
      }

      final editor = VideoEditorController(
        durationUs: probe.durationUs,
        keyframesUs: probe.keyframesUs,
        keyframesComplete: probe.keyframesComplete,
      );
      setState(() {
        _probe = probe;
        _editor = editor;
      });

      // Load filmstrip in background
      unawaited(_loadFilmstrip(probe));
    } on VideoEditException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (e) {
      VeLog.w(_tag, 'Loading the video editor failed', e);
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _loadFilmstrip(VideoProbe probe) async {
    if (probe.durationUs <= 0) return;
    final fileIo = ref.read(vaultFileIoApiProvider);
    const count = 10;
    final stepUs = probe.durationUs ~/ count;
    final targets = <int>[];
    for (var i = 0; i < count; i++) {
      final t = i * stepUs;
      final kf = keyframeAtOrBefore(probe.keyframesUs, t) ?? t;
      if (!targets.contains(kf)) targets.add(kf);
    }

    final loaded = <FilmstripEntry>[];
    for (final t in targets) {
      if (!mounted) break;
      try {
        final bytes = await fileIo.getVideoThumbnail(
          widget.container,
          widget.filePath,
          targetSize: 80,
          quality: 40,
          timeUs: t,
        );
        if (bytes != null && mounted) {
          final codec = await ui.instantiateImageCodec(bytes);
          final fi = await codec.getNextFrame();
          loaded.add((timeUs: t, image: fi.image));
        }
      } catch (_) {
        // Thumbnail load error gracefully ignored
      }
    }
    if (mounted && loaded.isNotEmpty) {
      setState(() => _filmstripFrames = loaded);
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

    // "Preview result" playback: skips over gaps between exported ranges
    if (_previewResult && player.value.isPlaying && !_skippingGap) {
      final ranges = editor.snappedRanges;
      if (ranges.isEmpty) {
        unawaited(player.pause());
        return;
      }

      var inRange = false;
      for (var i = 0; i < ranges.length; i++) {
        final r = ranges[i];
        if (us >= r.startUs && us < r.endUs) {
          inRange = true;
          // Approaching end of this segment
          if (us >= r.endUs - 80000) {
            _skippingGap = true;
            if (i < ranges.length - 1) {
              unawaited(_seekToUs(ranges[i + 1].startUs).then((_) {
                _skippingGap = false;
              }));
            } else {
              // Reached end of last segment: pause and park at start of first segment
              unawaited(player.pause().then((_) {
                return _seekToUs(ranges.first.startUs);
              }).then((_) {
                _skippingGap = false;
              }));
            }
          }
          break;
        }
      }

      if (!inRange) {
        _skippingGap = true;
        final next = ranges.where((r) => r.startUs > us).firstOrNull;
        if (next != null) {
          unawaited(_seekToUs(next.startUs).then((_) {
            _skippingGap = false;
          }));
        } else {
          unawaited(player.pause().then((_) {
            return _seekToUs(ranges.first.startUs);
          }).then((_) {
            _skippingGap = false;
          }));
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
      final ranges = editor.snappedRanges;
      if (ranges.isNotEmpty) {
        final cur = _playhead.value;
        final inside = ranges.any((r) => cur >= r.startUs && cur < r.endUs - 80000);
        if (!inside) {
          final next = ranges.where((r) => r.startUs >= cur).firstOrNull ?? ranges.first;
          await _seekToUs(next.startUs);
        }
      }
    } else if (_playhead.value >= editor.durationUs - 200000) {
      await _seekToUs(0);
    }
    await player.play();
  }

  void _step(int deltaUs) => unawaited(_seekToUs(_playhead.value + deltaUs));

  void _jumpKeyframe({required bool forward}) {
    final editor = _editor;
    if (editor == null) return;
    final from = _playhead.value;
    final target = forward
        ? (editor.nextKeyframe(from) ?? editor.durationUs)
        : (editor.previousKeyframe(from) ?? 0);
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
      _toast(l10n.videoEditorReadOnly, tone: AppBannerTone.error);
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

    final choice = await VideoExportSheet.show(
      context,
      clipCount: editor.plannedRanges.length,
      totalDurationUs: editor.totalSnappedUs,
      defaultBaseName: '${defaultStem}_cut',
      extension: probe.outputExtension,
      isReadOnly: widget.container.readOnly,
      hasSubtitles: probe.hasSubtitles,
    );
    if (choice == null || !mounted) return;

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
    final baseSourceName = choice.customName != null
        ? '${choice.customName}.${probe.outputExtension}'
        : _fileName;

    final names = planOutputNames(
      sourceFileName: baseSourceName,
      extension: probe.outputExtension,
      count: outputCount,
      existingLowercase: {for (final e in existing) e.name.toLowerCase()},
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
    );

    // If replaceOriginal was chosen and export succeeded, replace the original file
    if (choice.replaceOriginal && result != null && relativePaths.isNotEmpty) {
      try {
        final fileIo = ref.read(vaultFileIoApiProvider);
        final cutPath = relativePaths.first;
        await fileIo.deleteFile(container, widget.filePath);
        await fileIo.renameFile(container, cutPath, _fileName);
        _toast(l10n.videoEditorSaved(1), tone: AppBannerTone.success);
      } catch (e) {
        VeLog.w(_tag, 'Failed to replace original file with cut', e);
      }
    }
  }

  Future<VideoExportResult?> _runExport({
    required List<TimeRange> ranges,
    required bool merge,
    required List<String> outputPaths,
    required int outputCount,
  }) async {
    final api = ref.read(vaultVideoEditApiProvider);
    final events = ref.read(vaultEngineEventsProvider);
    final fileIo = ref.read(vaultFileIoApiProvider);
    final lockController = ref.read(sessionLockControllerProvider);
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    final opId = ++_opCounter;

    final progress = ValueNotifier<VideoEditProgress?>(null);
    void onProgress(VideoEditProgress e) {
      if (e.opId == opId) progress.value = e;
    }

    events.addVideoEditProgressListener(onProgress);
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
            onCancel: () => unawaited(api.cancel(opId)),
          ),
        ),
      ),
    );

    VideoExportResult? result;
    VideoEditException? failure;
    await fileIo.setKeepScreenOn(true);
    try {
      await lockController.withLockSuppression(() async {
        result = await api.export(
          volId: widget.container.volId,
          filePath: _nativePath,
          isLocalStorage: _isLocal,
          segmentsUs: ranges,
          merge: merge,
          outputPaths: outputPaths,
          opId: opId,
        );
      });
    } on VideoEditException catch (e) {
      failure = e;
    } catch (e) {
      VeLog.w(_tag, 'Export failed unexpectedly', e);
      failure = VideoEditException('EXPORT_FAILED', e.toString());
    } finally {
      await fileIo.setKeepScreenOn(false);
      events.removeVideoEditProgressListener(onProgress);
    }

    if (navigator.mounted) navigator.pop(); // close progress dialog
    if (!mounted) return result;
    setState(() => _exporting = false);

    if (result != null) {
      final count = result!.outputPaths.length;
      _toast(
        result!.droppedAudioTracks > 0
            ? '${l10n.videoEditorSaved(count)} ${l10n.videoEditorAudioDropped}'
            : l10n.videoEditorSaved(count),
        tone: result!.droppedAudioTracks > 0
            ? AppBannerTone.warning
            : AppBannerTone.success,
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
                        onPressed: editor.canExport && !_exporting
                            ? _onExport
                            : null,
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
                l10n.videoEditorLoadFailed(_loadError!),
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
              l10n.videoEditorAnalyzing,
              style: context.typography.bodyMedium,
            ),
          ],
        ),
      );
    }

    final preview = _buildPreview(player);
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final controls = _buildControls(context, editor, player);
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        if (landscape) {
          return Row(
            children: [
              Expanded(child: preview),
              SizedBox(
                width: 380,
                child: SingleChildScrollView(child: controls),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: preview),
            controls,
          ],
        );
      },
    );
  }

  Widget _buildPreview(NativeVideoController player) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_togglePlay()),
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: ValueListenableBuilder<NativeVideoValue>(
            valueListenable: player,
            builder: (context, v, _) {
              if (v.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    v.errorDescription,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }
              if (!v.isInitialized) return const CircularProgressIndicator();
              return AspectRatio(
                aspectRatio: v.aspectRatio,
                child: NativeVideoPlayerView(controller: player),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    VideoEditorController editor,
    NativeVideoController player,
  ) {
    final l10n = context.l10n;
    final cs = context.colors;
    final text = context.typography;
    final segments = editor.segments;
    final selected = editor.selected;

    final snapNote = _snapNote(context, editor, selected);
    final summaryStyle = text.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Time readout + zoom controls
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

          // Row 2: Timeline with draggable handles & filmstrip
          VideoTimeline(
            key: _timelineKey,
            durationUs: editor.durationUs,
            segments: segments,
            selectedId: editor.selectedId,
            mode: editor.mode,
            keyframes: editor.keyframes,
            snappedExportRanges: editor.snappedRanges,
            filmstripFrames: _filmstripFrames,
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
          const SizedBox(height: 4),

          // Row 3: Selected segment timestamps + segments chip
          Row(
            children: [
              Expanded(
                child: selected != null
                    ? Text(
                        '${formatTimecode(selected.startUs)} – ${formatTimecode(selected.endUs)}'
                        '  (${formatTimecode(selected.lengthUs, millis: false)})'
                        '${snapNote != null ? '  ⤑ $snapNote' : ''}',
                        style: summaryStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        segments.isEmpty
                            ? l10n.videoEditorNoSegments
                            : '${segments.length} ${segments.length == 1 ? 'segment' : 'segments'}',
                        style: summaryStyle,
                        maxLines: 1,
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Row 4: Transport + preview cut + 2× speed
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.videoEditorPrevKeyframe,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: () => _jumpKeyframe(forward: false),
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
                  tooltip: l10n.videoEditorNextKeyframe,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () => _jumpKeyframe(forward: true),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: _previewResult ? cs.primaryContainer : null,
                    foregroundColor: _previewResult ? cs.onPrimaryContainer : null,
                  ),
                  tooltip: l10n.videoEditorPreviewCut,
                  icon: Icon(
                    _previewResult
                        ? Icons.content_cut_rounded
                        : Icons.content_cut_outlined,
                  ),
                  onPressed: () {
                    setState(() => _previewResult = !_previewResult);
                  },
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: _playbackSpeed > 1.0 ? cs.primaryContainer : null,
                    foregroundColor: _playbackSpeed > 1.0 ? cs.onPrimaryContainer : null,
                  ),
                  tooltip: _playbackSpeed > 1.0 ? '1×' : '2×',
                  icon: Text(
                    _playbackSpeed > 1.0 ? '2×' : '1×',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _playbackSpeed > 1.0 ? cs.onPrimaryContainer : cs.onSurfaceVariant,
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

          // Row 5: Tools (icon-only, normal size)
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

  /// Only shown in keep mode when the selected clip's real export range differs from what's drawn.
  String? _snapNote(
    BuildContext context,
    VideoEditorController editor,
    EditSegment? selected,
  ) {
    if (editor.keyframes.isEmpty || editor.mode != VideoEditMode.keep || selected == null) {
      return null;
    }
    final snapped = editor.snappedFor(selected);
    if (snapped.startUs == selected.startUs && snapped.endUs == selected.endUs) {
      return null;
    }
    return context.l10n.videoEditorSnapNote(
      formatTimecode(snapped.startUs),
      formatTimecode(snapped.endUs),
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
  final ValueListenable<VideoEditProgress?> progress;
  final int outputCount;
  final VoidCallback onCancel;

  const _ExportProgressDialog({
    required this.progress,
    required this.outputCount,
    required this.onCancel,
  });

  static double? _overall(VideoEditProgress? e) {
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
      title: Text(l10n.videoEditorExporting),
      content: ValueListenableBuilder<VideoEditProgress?>(
        valueListenable: progress,
        builder: (context, e, _) {
          final String label;
          if (e != null && e.phase == 'saving') {
            label = l10n.videoEditorSaving;
          } else if (outputCount > 1) {
            label = l10n.videoEditorCutting(
              (e?.outputIndex ?? 0) + 1,
              outputCount,
            );
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
