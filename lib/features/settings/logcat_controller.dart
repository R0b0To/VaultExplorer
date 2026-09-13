import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/logcat_service.dart';

part 'logcat_controller.g.dart';

enum LogFilterMode { appOnly, all }

const List<String> _noisyTags = [
  'ImeTracker',
  'InsetsController',
  'ViewRootImpl',
  'BLASTBufferQueue',
  'OpenGLRenderer',
  'DecorView',
  'InputMethodManager',
  'SurfaceView',
  'CompatibilityChangeReporter',
  'WindowOnBackDispatcher',
  'SurfaceSyncGroup',
  'Choreographer',
  'AutofillManager',
  'TextInputPlugin',
  'FlutterView',
  'AccessibilityBridge',
  'ProfileInstaller',
  'DynamicColors',
  'HandwritingMode',
  'RenderThread',
  'GraphicBuffer',
  'BufferQueue',
];

const List<String> _appKeywords = [
  'VaultExplorer',
  'UnlockSheet',
  'SplitFuseCallback',
  'SafSplitResolver',
  'ContainerEngine',
  'Cryptomator',
  'Gocryptfs',
  'Cryfs',
  'VeraCrypt',
  'Luks',
  'BitLocker',
  'VeLog',
  'FAT',
  'NTFS',
  'EXT4',
  'EXFAT',
  'E/',
  'F/',
];

class LogcatState {
  final List<String> lines;
  final LogFilterMode filterMode;
  final String searchQuery;
  final bool streamError;
  final bool saving;
  final bool clearing;

  const LogcatState({
    this.lines = const [],
    this.filterMode = LogFilterMode.appOnly,
    this.searchQuery = '',
    this.streamError = false,
    this.saving = false,
    this.clearing = false,
  });
}

@riverpod
class LogcatController extends _$LogcatController {
  StreamSubscription<String>? _sub;

  @override
  LogcatState build() {
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_startStream);
    return const LogcatState();
  }

  LogcatState _copy({
    List<String>? lines,
    LogFilterMode? filterMode,
    String? searchQuery,
    bool? streamError,
    bool? saving,
    bool? clearing,
  }) => LogcatState(
    lines: lines ?? state.lines,
    filterMode: filterMode ?? state.filterMode,
    searchQuery: searchQuery ?? state.searchQuery,
    streamError: streamError ?? state.streamError,
    saving: saving ?? state.saving,
    clearing: clearing ?? state.clearing,
  );

  /// Re-attaches to the log stream from scratch (also the retry action on
  /// the error screen).
  void restartStream() => _startStream();

  void _startStream() {
    _sub?.cancel();
    if (!ref.mounted) return;
    state = _copy(lines: const [], streamError: false);
    _sub = ref
        .read(logcatServiceProvider)
        .logStream
        .listen(
          (line) {
            if (!ref.mounted) return;
            state = _copy(lines: [...state.lines, line]);
          },
          onError: (_) {
            if (ref.mounted) state = _copy(streamError: true);
          },
        );
  }

  void setFilterMode(LogFilterMode mode) => state = _copy(filterMode: mode);

  void setSearchQuery(String query) =>
      state = _copy(searchQuery: query.trim());

  Future<void> clearLog() async {
    if (state.clearing) return;
    state = _copy(clearing: true);
    try {
      await ref.read(logcatServiceProvider).clearLog();
      if (ref.mounted) state = _copy(lines: const []);
    } finally {
      if (ref.mounted) state = _copy(clearing: false);
    }
  }

  /// Returns:
  /// - `null` if the user cancelled the system "Save As" picker -- silently,
  ///   not treated as an error, since this is a deliberate choice rather
  ///   than a failure.
  /// - `(success: true, displayName: ...)` once the content was written to
  ///   wherever the user chose; [displayName] is a best-effort name for
  ///   that location, for the "Log saved to ..." confirmation.
  /// - `(success: false, displayName: '')` when there was nothing to save,
  ///   or the write itself failed -- the widget shows an error snackbar
  ///   either way.
  Future<({bool success, String displayName})?> saveLog(
    List<String> filteredLines,
  ) async {
    if (state.saving) return null;
    state = _copy(saving: true);
    try {
      final content = filteredLines.isNotEmpty
          ? filteredLines.join('\n')
          : (await ref.read(logcatServiceProvider).captureLogSnapshot() ??
                '');
      if (content.isEmpty) return (success: false, displayName: '');
      try {
        return await ref.read(logcatServiceProvider).saveLogToFile(content);
      } catch (_) {
        // A real write failure (e.g. IO_ERROR from the native side) --
        // distinct from the picker-cancelled case above, which never
        // throws and returns null instead.
        return (success: false, displayName: '');
      }
    } finally {
      if (ref.mounted) state = _copy(saving: false);
    }
  }
}

extension LogcatStateX on LogcatState {
  bool isLineAccepted(String line) {
    if (filterMode == LogFilterMode.appOnly) {
      for (final noise in _noisyTags) {
        if (line.contains(noise)) return false;
      }
      final hasAppKeyword = _appKeywords.any((k) => line.contains(k));
      if (!hasAppKeyword) return false;
    }
    if (searchQuery.isNotEmpty) {
      if (!line.toLowerCase().contains(searchQuery.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  List<String> get filteredLines => lines.where(isLineAccepted).toList();
}