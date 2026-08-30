import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';

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

  /// Returns the saved file path, or null on failure (nothing to save, or
  /// the underlying write failed) -- the widget shows the corresponding
  /// snackbar either way.
  Future<String?> saveLog(List<String> filteredLines) async {
    if (state.saving) return null;
    state = _copy(saving: true);
    try {
      final content = filteredLines.isNotEmpty
          ? filteredLines.join('\n')
          : (await ref.read(logcatServiceProvider).captureLogSnapshot() ??
                '');
      if (content.isEmpty) return null;
      return await ref.read(logcatServiceProvider).saveLogToFile(content);
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