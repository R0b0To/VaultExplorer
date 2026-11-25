import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/utils/secure_temp_file.dart';

/// Callback that checks whether any external process still holds an open handle
/// to a file inside [dirPath].
typedef StagingInUseProbe = Future<bool> Function(String dirPath);

/// Callback that applies OS-specific directory hardening (owner-only DACL,
/// disable search indexing) to [dirPath].
typedef StagingHardener = Future<void> Function(String dirPath);

/// Callback that cancels in-flight native staging work for [batchId].
typedef StagingBatchCanceller = Future<void> Function(String batchId);

/// Callback that clears the OS clipboard if it still points to [batchId].
typedef StagingClipboardReleaser = Future<void> Function(String batchId);

/// Metadata for a single lazy desktop drag/clipboard staging batch.
class StagingBatch {
  StagingBatch({
    required this.batchId,
    required this.volId,
    required this.directory,
    required this.isClipboard,
    this.autoClearTimeout,
    RandomAccessFile? lockFile,
  }) : _lockFile = lockFile;

  final String batchId;
  final int? volId;
  final Directory directory;
  final bool isClipboard;
  final Duration? autoClearTimeout;

  RandomAccessFile? _lockFile;
  bool realized = false;
  bool disposed = false;
  DateTime? realizedAt;
  Timer? drainTimer;
  Timer? autoClearTimer;

  String get dirPath => directory.path;

  Future<void> releaseLock() async {
    final raf = _lockFile;
    _lockFile = null;
    if (raf == null) return;
    try {
      await raf.unlock();
    } catch (_) {
      // Lock is released on close regardless.
    }
    try {
      await raf.close();
    } catch (_) {
      // Best-effort close.
    }
  }
}

/// Manages private plaintext staging directories for desktop drag-and-drop and
/// OS file clipboard transfers.
///
/// Guarantees:
/// * Nothing is written to disk at drag-start or Ctrl+C; directories are only
///   populated when a drop/paste commits ([markRealized]).
/// * Staging lives in `$XDG_RUNTIME_DIR` (memory-backed tmpfs on Linux) when
///   available, or `%LOCALAPPDATA%\VaultExplorer\staging` / system temp.
/// * Every active batch holds an exclusive lock on `batch.lock`, so concurrent
///   VaultExplorer processes (`G_APPLICATION_NON_UNIQUE`) never wipe an active
///   sibling's scratch directory while still purging crashed runs on startup.
/// * All cleanup calls [SecureTempFile.wipeAndDeleteDir] (zero-fill + delete).
class DesktopStagingManager {
  DesktopStagingManager({
    Directory? baseDirOverride,
    StagingInUseProbe? isBatchInUse,
    StagingHardener? hardenDir,
    StagingBatchCanceller? cancelNativeBatch,
    StagingClipboardReleaser? releaseClipboardBatch,
    this.defaultGracePeriod = const Duration(seconds: 20),
    this.drainPollInterval = const Duration(seconds: 3),
    this.defaultClipboardTimeout = const Duration(minutes: 10),
    int? pidOverride,
  })  : _baseDirOverride = baseDirOverride,
        _isBatchInUse = isBatchInUse,
        _hardenDir = hardenDir,
        _cancelNativeBatch = cancelNativeBatch,
        _releaseClipboardBatch = releaseClipboardBatch,
        _pid = pidOverride ?? pid;

  static const String batchDirPrefix = 'vaultexplorer-xfer-';
  static const String lockFileName = 'batch.lock';

  final Directory? _baseDirOverride;
  StagingInUseProbe? _isBatchInUse;
  StagingHardener? _hardenDir;
  StagingBatchCanceller? _cancelNativeBatch;
  StagingClipboardReleaser? _releaseClipboardBatch;

  final Duration defaultGracePeriod;
  final Duration drainPollInterval;
  final Duration defaultClipboardTimeout;
  final int _pid;

  final Map<String, StagingBatch> _batches = {};
  int _serial = 0;
  bool _purgedStale = false;

  /// Attaches native platform callbacks after the desktop transfer plugin is
  /// initialized.
  void configurePlatformHooks({
    StagingInUseProbe? isBatchInUse,
    StagingHardener? hardenDir,
    StagingBatchCanceller? cancelNativeBatch,
    StagingClipboardReleaser? releaseClipboardBatch,
  }) {
    _isBatchInUse = isBatchInUse ?? _isBatchInUse;
    _hardenDir = hardenDir ?? _hardenDir;
    _cancelNativeBatch = cancelNativeBatch ?? _cancelNativeBatch;
    _releaseClipboardBatch = releaseClipboardBatch ?? _releaseClipboardBatch;
  }

  /// Active batches tracked by this manager (exposed for testing/inspection).
  List<StagingBatch> get activeBatches => List.unmodifiable(_batches.values);

  StagingBatch? batchOf(String batchId) => _batches[batchId];

  /// Resolves the private parent directory where transfer batches live.
  Directory resolveStagingRoot() {
    final override = _baseDirOverride;
    if (override != null) return override;

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory(p.join(localAppData, 'VaultExplorer', 'staging'));
      }
      return Directory.systemTemp;
    }

    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime != null && runtime.isNotEmpty && Directory(runtime).existsSync()) {
      return Directory(runtime);
    }
    return Directory.systemTemp;
  }

  /// All directories that could ever contain stale `vaultexplorer-xfer-*`
  /// folders from previous runs.
  Set<Directory> _candidateRoots() {
    final override = _baseDirOverride;
    if (override != null) return {override};

    final roots = <Directory>{Directory.systemTemp, resolveStagingRoot()};
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime != null && runtime.isNotEmpty) {
      roots.add(Directory(runtime));
    }
    return roots;
  }

  /// Purges orphaned staging directories left behind by crashed runs.
  ///
  /// Safe across multiple concurrent VaultExplorer processes: any folder whose
  /// `batch.lock` file still has an active exclusive OS lock is skipped.
  Future<int> purgeStaleAtStartup() async {
    _purgedStale = true;
    var purged = 0;
    for (final root in _candidateRoots()) {
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final name = p.basename(entity.path);
          if (!name.startsWith(batchDirPrefix)) continue;
          if (_batches.values.any((b) => p.equals(b.dirPath, entity.path))) {
            continue;
          }
          if (await _tryPurgeOrphanDir(entity)) {
            purged++;
          }
        }
      } on FileSystemException {
        // Root unreadable or vanished concurrently.
      }
    }
    return purged;
  }

  Future<bool> _tryPurgeOrphanDir(Directory dir) async {
    final lockFile = File(p.join(dir.path, lockFileName));
    RandomAccessFile? raf;
    if (await lockFile.exists()) {
      try {
        raf = await lockFile.open(mode: FileMode.write);
        await raf.lock(FileLock.exclusive);
      } on FileSystemException {
        try {
          await raf?.close();
        } catch (_) {}
        return false; // Held by another running VaultExplorer instance.
      }
    }
    try {
      await raf?.unlock();
    } catch (_) {}
    try {
      await raf?.close();
    } catch (_) {}
    await SecureTempFile.wipeAndDeleteDir(dir);
    return !await dir.exists();
  }

  /// Reserves a fresh, hardened, lockfile-protected staging directory for a
  /// drag or clipboard transfer belonging to [volId] (`null` for LocalStorage).
  Future<StagingBatch> createBatch({
    required int? volId,
    required bool isClipboard,
    Duration? clipboardTimeout,
  }) async {
    if (!_purgedStale) {
      await purgeStaleAtStartup();
    }
    final root = resolveStagingRoot();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final serial = ++_serial;
    final batchId = '${_pid}_$serial';
    final dir = await root.createTemp('$batchDirPrefix$batchId-');

    try {
      await _hardenDir?.call(dir.path);
    } catch (e) {
      debugPrint('[desktop-staging] directory hardening failed: $e');
    }

    RandomAccessFile? lockRaf;
    try {
      final lockFile = File(p.join(dir.path, lockFileName));
      lockRaf = await lockFile.open(mode: FileMode.write);
      await lockRaf.writeString('$_pid\n');
      await lockRaf.flush();
      await lockRaf.lock(FileLock.exclusive);
    } on FileSystemException catch (e) {
      debugPrint('[desktop-staging] could not acquire batch.lock: $e');
      try {
        await lockRaf?.close();
      } catch (_) {}
      lockRaf = null;
    }

    final timeout = isClipboard ? (clipboardTimeout ?? defaultClipboardTimeout) : null;
    final batch = StagingBatch(
      batchId: batchId,
      volId: volId,
      directory: dir,
      isClipboard: isClipboard,
      autoClearTimeout: timeout,
      lockFile: lockRaf,
    );
    _batches[batchId] = batch;

    if (timeout != null && timeout > Duration.zero) {
      batch.autoClearTimer = Timer(timeout, () {
        unawaited(_expireClipboardBatch(batchId));
      });
    }
    return batch;
  }

  /// Marks [batchId] as having materialized plaintext files on disk.
  void markRealized(String batchId, {bool isDrag = false}) {
    final batch = _batches[batchId];
    if (batch == null || batch.disposed) return;
    batch.realized = true;
    batch.realizedAt = DateTime.now();
    // Clipboard batches wait until overwritten or timed out; drag batches wait
    // until transfer completion (or fallback grace sweep).
    if (isDrag) {
      _scheduleDrainCheck(batch, delay: defaultGracePeriod);
    }
  }

  /// Called when an OS drag-and-drop transfer ends (`EndOperation` on Windows
  /// or `drag-end` / `drag-failed` on Linux).
  Future<void> onDragTransferFinished(
    String batchId, {
    required bool immediateIfUnused,
  }) async {
    final batch = _batches[batchId];
    if (batch == null || batch.disposed) return;
    if (!batch.realized) {
      // Cancelled drag or virtual IStream drag: zero plaintext files were
      // created, so wipe the empty batch folder immediately.
      await cleanupBatch(batchId);
      return;
    }
    if (immediateIfUnused) {
      if (!await _checkInUse(batch.dirPath)) {
        await cleanupBatch(batchId);
        return;
      }
    }
    _scheduleDrainCheck(batch, delay: defaultGracePeriod);
  }

  /// Called when the OS clipboard was overwritten by another application or
  /// cleared externally.
  Future<void> onClipboardOwnershipLost(String batchId) async {
    final batch = _batches[batchId];
    if (batch == null || batch.disposed) return;
    batch.autoClearTimer?.cancel();
    batch.autoClearTimer = null;
    if (!batch.realized) {
      await cleanupBatch(batchId);
      return;
    }
    // Give an OS file manager that triggered a paste just before losing focus
    // time to open/finish copying, guarded by the reader-drain probe.
    _scheduleDrainCheck(batch, delay: defaultGracePeriod);
  }

  Future<void> _expireClipboardBatch(String batchId) async {
    final batch = _batches[batchId];
    if (batch == null || batch.disposed) return;
    try {
      await _releaseClipboardBatch?.call(batchId);
    } catch (_) {}
    if (!batch.realized) {
      await cleanupBatch(batchId);
      return;
    }
    if (!await _checkInUse(batch.dirPath)) {
      await cleanupBatch(batchId);
    } else {
      _scheduleDrainCheck(batch, delay: drainPollInterval);
    }
  }

  void _scheduleDrainCheck(StagingBatch batch, {required Duration delay}) {
    batch.drainTimer?.cancel();
    batch.drainTimer = Timer(delay, () {
      unawaited(_attemptDrainCleanup(batch.batchId));
    });
  }

  Future<void> _attemptDrainCleanup(String batchId) async {
    final batch = _batches[batchId];
    if (batch == null || batch.disposed) return;
    if (await _checkInUse(batch.dirPath)) {
      _scheduleDrainCheck(batch, delay: drainPollInterval);
      return;
    }
    await cleanupBatch(batchId);
  }

  Future<bool> _checkInUse(String dirPath) async {
    final probe = _isBatchInUse;
    if (probe == null) return false;
    try {
      return await probe(dirPath);
    } catch (_) {
      return false;
    }
  }

  /// Cancels native work (if running), releases the batch lock, and zero-wipes
  /// + deletes [batchId]'s directory.
  Future<void> cleanupBatch(String batchId) async {
    final batch = _batches.remove(batchId);
    if (batch == null || batch.disposed) return;
    batch.disposed = true;
    batch.drainTimer?.cancel();
    batch.drainTimer = null;
    batch.autoClearTimer?.cancel();
    batch.autoClearTimer = null;

    try {
      await _cancelNativeBatch?.call(batchId);
    } catch (_) {}
    try {
      await _releaseClipboardBatch?.call(batchId);
    } catch (_) {}

    await batch.releaseLock();
    await SecureTempFile.wipeAndDeleteDir(batch.directory);
  }

  /// Immediately wipes all staged batches belonging to [volId] (called on vault
  /// lock). Unconditionally terminates grace windows for security.
  Future<void> cleanupVolume(int volId) async {
    final matching = [
      for (final b in _batches.values)
        if (b.volId == volId) b.batchId,
    ];
    for (final id in matching) {
      await cleanupBatch(id);
    }
  }

  /// Immediately wipes every staged batch across all volumes (called on app
  /// shutdown).
  Future<void> cleanupAll() async {
    final ids = _batches.keys.toList();
    for (final id in ids) {
      await cleanupBatch(id);
    }
  }
}
