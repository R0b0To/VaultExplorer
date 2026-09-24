import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/domain/endpoints/sync_endpoint.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';

/// The one concrete [SyncEndpoint] the app needs: a folder ([rootPath]) in
/// a [MountedContainer].
///
/// A real vault, a device-storage folder and an SAF tree are all
/// `MountedContainer`s to [VaultFileIoApi], which already dispatches on the
/// container kind for every call used here. So the plan's separate
/// "vault endpoint" and "host/SAF endpoint" collapse into this one adapter
/// instead of duplicating that dispatch.
class ContainerSyncEndpoint implements SyncEndpoint {
  static const int _chunkSize = 2 * 1024 * 1024;
  static const int _hashChunkSize = 4 * 1024 * 1024;
  static const int _maxDepth = 32;

  /// Hash-session ids live in their own range so they can't collide with
  /// the ones `HashVerifierService` hands out (it counts up from 1).
  static int _hashOpSeq = 1600000000;

  final VaultFileIoApi _io;
  final VaultHashApi _hashApi;
  final MountedContainer container;

  /// Sync root inside [container], normalized (no slashes at either end).
  final String rootPath;

  @override
  final String label;

  /// Container-relative paths of folders known to exist (from the last
  /// scan, or created by [ensureDirectory]). Avoids `createDirectory` on
  /// existing folders -- some SAF providers answer that by silently
  /// creating "name (1)".
  final Set<String> _knownDirs = {};

  ContainerSyncEndpoint({
    required VaultFileIoApi io,
    required VaultHashApi hashApi,
    required this.container,
    String rootPath = '',
    String? label,
  }) : _io = io,
       _hashApi = hashApi,
       rootPath = normalizeSyncPath(rootPath),
       label = label ?? container.displayName;

  @override
  bool get isEncrypted => !container.isLocalStorage;

  String _abs(String rel) {
    if (rootPath.isEmpty) return rel;
    if (rel.isEmpty) return rootPath;
    return '$rootPath/$rel';
  }

  static String _parentOf(String rel) {
    final i = rel.lastIndexOf('/');
    return i < 0 ? '' : rel.substring(0, i);
  }

  static String _baseName(String rel) {
    final i = rel.lastIndexOf('/');
    return i < 0 ? rel : rel.substring(i + 1);
  }

  // ── scan ─────────────────────────────────────────────────────────────

  @override
  Future<SyncSnapshot> scan({
    required SyncIgnoreMatcher ignore,
    required SyncCancellationToken token,
  }) async {
    final files = <String, SyncSideState>{};
    final dirs = <String>{};
    final unreadable = <String>{};
    final truncated = <String>{};
    final leftovers = <String>[];
    var rootReadable = true;

    final stack = <({String rel, int depth})>[(rel: '', depth: 0)];
    while (stack.isNotEmpty) {
      if (token.isCancelled) throw const SyncCancelledException();
      final cur = stack.removeLast();

      List<RawEntry>? entries;
      var wasTruncated = false;
      try {
        final raw = await _io.listDirectory(
          container,
          _abs(cur.rel),
          // Raw file-system listings are cached briefly and native SAF
          // copies bypass that cache, so always read fresh.
          refresh: true,
        );
        if (raw != null) {
          wasTruncated = raw.any((r) => r.startsWith('System:TRUNCATED'));
          entries = RawEntry.parseAll(raw);
        }
      } catch (_) {
        entries = null;
      }

      if (entries == null) {
        if (cur.rel.isEmpty) {
          rootReadable = false;
        } else {
          unreadable.add(cur.rel);
        }
        continue;
      }
      if (wasTruncated) truncated.add(cur.rel);

      for (final e in entries) {
        if (e.isPlaceholder) continue;
        final rel = cur.rel.isEmpty ? e.name : '${cur.rel}/${e.name}';
        if (e.isDir) {
          if (ignore.isIgnored(rel)) continue;
          dirs.add(rel);
          if (cur.depth + 1 > _maxDepth) {
            unreadable.add(rel);
          } else {
            stack.add((rel: rel, depth: cur.depth + 1));
          }
        } else {
          if (isSyncArtifact(rel)) {
            leftovers.add(rel);
          } else if (!ignore.isIgnored(rel)) {
            files[rel] = SyncSideState(
              size: e.sizeBytes,
              mtimeSecs: e.modifiedSecs,
            );
          }
        }
      }
    }

    _knownDirs
      ..clear()
      ..add(rootPath)
      ..addAll(dirs.map(_abs));

    return SyncSnapshot(
      files: files,
      dirs: dirs,
      unreadableDirs: unreadable,
      truncatedDirs: truncated,
      rootReadable: rootReadable,
      leftovers: leftovers,
    );
  }

  @override
  Future<Map<String, SyncSideState>> stat(Iterable<String> relPaths) async {
    final byDir = <String, List<String>>{};
    for (final rel in relPaths) {
      byDir.putIfAbsent(_parentOf(rel), () => []).add(rel);
    }
    final out = <String, SyncSideState>{};
    for (final group in byDir.entries) {
      try {
        final raw = await _io.listDirectory(
          container,
          _abs(group.key),
          refresh: true,
        );
        if (raw == null) continue;
        final byName = <String, RawEntry>{
          for (final e in RawEntry.parseAll(raw))
            if (!e.isDir) e.name: e,
        };
        for (final rel in group.value) {
          final e = byName[_baseName(rel)];
          if (e != null) {
            out[rel] = SyncSideState(size: e.sizeBytes, mtimeSecs: e.modifiedSecs);
          }
        }
      } catch (_) {
        // Unlisted -> reported as missing; callers treat that as "unknown".
      }
    }
    return out;
  }

  // ── hashing ──────────────────────────────────────────────────────────

  @override
  Future<String?> hash(String relPath, SyncCancellationToken token) async {
    final abs = _abs(relPath);
    final opId = ++_hashOpSeq;
    final algorithm = HashAlgorithm.sha256.wireName;
    var sessionOpen = false;
    try {
      final size = await _io.getFileSize(container, abs);
      if (size < 0) return null;
      await _hashApi.beginHashSession(opId, [algorithm]);
      sessionOpen = true;

      var offset = 0;
      while (offset < size) {
        if (token.isCancelled) throw const SyncCancelledException();
        final len = math.min(_hashChunkSize, size - offset);
        final chunk = await _io.readFileChunk(container, abs, offset, len);
        if (chunk == null || chunk.isEmpty) return null;
        await _hashApi.updateHashSession(opId, chunk);
        offset += chunk.length;
      }

      final digests = await _hashApi.finishHashSession(opId);
      sessionOpen = false;
      final hex = digests[algorithm];
      return (hex == null || hex.isEmpty) ? null : hex.toLowerCase();
    } on SyncCancelledException {
      rethrow;
    } catch (_) {
      return null;
    } finally {
      if (sessionOpen) await _hashApi.discardHashSession(opId);
    }
  }

  // ── mutations ────────────────────────────────────────────────────────

  @override
  Future<bool> ensureDirectory(String relDir) async {
    final segments = normalizeSyncPath(relDir).split('/').where((s) => s.isNotEmpty);
    var current = rootPath;
    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      if (_knownDirs.contains(current)) continue;

      var ok = false;
      try {
        ok = await _io.createDirectory(container, current);
      } catch (_) {
        ok = false;
      }
      if (!ok) {
        // "Already exists" also reports failure; confirm before giving up.
        try {
          ok = await _io.listDirectory(container, current) != null;
        } catch (_) {
          ok = false;
        }
      }
      if (!ok) return false;
      _knownDirs.add(current);
    }
    return true;
  }

  @override
  Future<bool> copyFrom(
    SyncEndpoint source,
    String sourceRel,
    String destRel, {
    required int opId,
    required SyncCancellationToken token,
  }) async {
    if (source is! ContainerSyncEndpoint) {
      throw ArgumentError.value(
        source,
        'source',
        'ContainerSyncEndpoint can only copy from a ContainerSyncEndpoint',
      );
    }
    final src = source;
    final srcAbs = src._abs(sourceRel);
    final dstAbs = _abs(destRel);

    // A variable (not a local function) so the very same object is handed
    // to bindOnCancel and unbind.
    // ignore: prefer_function_declarations_over_variables
    final void Function() cancelNative = () => unawaited(_io.cancelCopy(opId));
    token.bindOnCancel(cancelNative);
    try {
      if (token.isCancelled) throw const SyncCancelledException();

      final size = await _io.getFileSize(src.container, srcAbs);
      if (size < 0) return false;

      // Same first step as the app's own copy engine: never write into a
      // file that's already there.
      await _io.deleteFile(container, dstAbs);

      if (size == 0) {
        final ok = await _io.writeFileChunk(container, dstAbs, 0, Uint8List(0));
        if (!ok) return false;
        return _io.finishWrite(container, dstAbs);
      }

      // Fast path: one native call (vault<->vault, vault<->device storage,
      // and device/SAF pairs). Returns false for pairings it can't do.
      final direct = await _io.copyFile(
        src.container,
        srcAbs,
        container,
        dstAbs,
        opId: opId,
      );
      if (token.isCancelled) throw const SyncCancelledException();
      if (direct) return true;

      // Fallback (e.g. SAF <-> vault): short read/write hops, checking for
      // cancellation between each.
      await _io.deleteFile(container, dstAbs);
      var offset = 0;
      while (offset < size) {
        if (token.isCancelled) throw const SyncCancelledException();
        final len = math.min(_chunkSize, size - offset);
        final chunk = await _io.readFileChunk(src.container, srcAbs, offset, len);
        if (chunk == null || chunk.isEmpty) return false;
        final ok = await _io.writeFileChunk(container, dstAbs, offset, chunk);
        if (!ok) return false;
        offset += chunk.length;
      }
      return _io.finishWrite(container, dstAbs);
    } finally {
      token.unbind(cancelNative);
      await _io.clearCopyState(opId);
    }
  }

  @override
  Future<bool> rename(String fromRel, String toRel) async {
    try {
      return await _io.renameFile(container, _abs(fromRel), _abs(toRel));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String relPath) async {
    try {
      final abs = _abs(relPath);
      final ok = await _io.deleteFile(container, abs);
      if (ok) {
        _knownDirs.remove(abs);
        _knownDirs.removeWhere((d) => d.startsWith('$abs/'));
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setModified(String relPath, int mtimeSecs) async {
    // The SAF path of setLastModifiedTime isn't implemented natively.
    if (container.isSafStorage || mtimeSecs <= 0) return false;
    try {
      return await _io.setLastModifiedTime(container, _abs(relPath), mtimeSecs);
    } catch (_) {
      return false;
    }
  }
}
