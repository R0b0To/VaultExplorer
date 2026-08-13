import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

/// Cooperative cancellation for [HashVerifierService.computeHashes]. For a
/// vault source the hashing loop lives entirely in Dart, so [isCancelled]
/// is polled directly between chunks (mirrors
/// `DuplicateFinderService.CancellationToken`). For an external source the
/// hashing loop runs natively across a single awaited platform-channel
/// call, so [bindNativeOp] arms a callback that fires
/// [VaultExplorerApi.cancelHashCompute] for that op the moment [cancel] is
/// called, letting native's read loop notice and unwind instead of the
/// Dart side just abandoning the (still-running) Future.
class HashCancellationToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void bindNativeOp(int opId) {
    _onCancel = () => vaultExplorerApi.cancelHashCompute(opId);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Thrown by [HashVerifierService.computeHashes] when a
/// [HashCancellationToken] was cancelled mid-hash.
class HashOperationCancelledException implements Exception {
  const HashOperationCancelledException();
  @override
  String toString() => 'Hash computation cancelled.';
}

/// Core service for the Tools tab's File Checksum & Hash Verifier
/// ([HashVerifierSheet] on the Dart side).
///
/// Hashing a vault-resident file streams through [readFileChunk] +
/// `package:crypto`'s chunked [pkg_crypto.Hash] conversion -- exactly
/// [DuplicateFinderService._computeFullHash]'s shape, generalized to run
/// several algorithms over the same read pass. Hashing an external
/// (on-device/SAF) file has to cross the platform channel instead, since
/// `content://` Uris can't be read directly from Dart -- see
/// [VaultExplorerApi.computeExternalFileHash] and HashVerifierHandlers.kt.
class HashVerifierService {
  static const int _chunkSize = 256 * 1024; // matches DuplicateFinderService
  static const int _maxWalkDepth = 10;

  int _opIdCounter = 0;
  int _nextOpId() => ++_opIdCounter;

  Map<HashAlgorithm, pkg_crypto.Hash> get _dartHashFor => {
        HashAlgorithm.md5: pkg_crypto.md5,
        HashAlgorithm.sha1: pkg_crypto.sha1,
        HashAlgorithm.sha256: pkg_crypto.sha256,
        HashAlgorithm.sha512: pkg_crypto.sha512,
      };

  /// Computes every algorithm in [algorithms] over [source] in a single
  /// streaming read pass, reporting byte progress via [onProgress].
  /// Returns lowercase hex digests keyed by algorithm; an algorithm is
  /// simply absent from the result if the native side didn't return it
  /// (should not happen in practice, but callers shouldn't assume every
  /// key is present). Throws [HashOperationCancelledException] if
  /// [cancelToken] is cancelled before the read finishes.
  Future<Map<HashAlgorithm, String>> computeHashes({
    required CryptoSourceItem source,
    required Set<HashAlgorithm> algorithms,
    HashCancellationToken? cancelToken,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) async {
    if (algorithms.isEmpty) return {};
    if (cancelToken?.isCancelled ?? false) throw const HashOperationCancelledException();

    if (!source.isFromVault) {
      final opId = _nextOpId();
      cancelToken?.bindNativeOp(opId);
      if (cancelToken?.isCancelled ?? false) {
        // Cancelled in the window between the check above and binding --
        // fire the native cancel proactively rather than starting a call
        // we already know we don't want to wait out.
        unawaited(vaultExplorerApi.cancelHashCompute(opId));
        throw const HashOperationCancelledException();
      }
      void listener(HashProgress progress) {
        if (progress.opId == opId) onProgress?.call(progress.bytesDone, progress.bytesTotal);
      }
      if (onProgress != null) VaultExplorerApi.addHashProgressListener(listener);
      Map<String, String> result;
      try {
        result = await vaultExplorerApi.computeExternalFileHash(
          uri: source.externalUri!,
          algorithms: algorithms.map((a) => a.wireName).toList(),
          opId: opId,
        );
      } on PlatformException catch (e) {
        if (e.code == 'CANCELLED') throw const HashOperationCancelledException();
        rethrow;
      } finally {
        if (onProgress != null) VaultExplorerApi.removeHashProgressListener(listener);
      }
      return {
        for (final algo in algorithms)
          if (result[algo.wireName] != null) algo: result[algo.wireName]!.toLowerCase(),
      };
    }

    final container = source.container!;
    final path = source.relativePath!;
    final size = await vaultExplorerApi.getFileSize(container, path);

    final sinks = <HashAlgorithm, AccumulatorSink<pkg_crypto.Digest>>{};
    final inputs = <HashAlgorithm, ByteConversionSink>{};
    final dartHashFor = _dartHashFor;
    for (final algo in algorithms) {
      final acc = AccumulatorSink<pkg_crypto.Digest>();
      sinks[algo] = acc;
      inputs[algo] = dartHashFor[algo]!.startChunkedConversion(acc);
    }

    int offset = 0;
    while (offset < size) {
      if (cancelToken?.isCancelled ?? false) throw const HashOperationCancelledException();
      final length = (size - offset) < _chunkSize ? (size - offset) : _chunkSize;
      final chunk = await vaultExplorerApi.readFileChunk(container, path, offset, length);
      if (chunk == null) {
        throw Exception('Failed to read "$path" at offset $offset');
      }
      for (final input in inputs.values) {
        input.add(chunk);
      }
      offset += length;
      onProgress?.call(offset, size);
    }
    for (final input in inputs.values) {
      input.close();
    }

    return {
      for (final algo in algorithms) algo: sinks[algo]!.events.single.toString(),
    };
  }

  /// Reads the full text content of a (small) manifest file, from either a
  /// vault or external source.
  Future<String> readManifestText(CryptoSourceItem source) async {
    Uint8List? bytes;
    if (source.isFromVault) {
      final size = await vaultExplorerApi.getFileSize(source.container!, source.relativePath!);
      bytes = await vaultExplorerApi.readFileChunk(source.container!, source.relativePath!, 0, size);
    } else {
      bytes = await vaultExplorerApi.readExternalFileBytes(source.externalUri!);
    }
    if (bytes == null) throw Exception('Failed to read manifest file');
    return utf8.decode(bytes, allowMalformed: true);
  }

  static final RegExp _bsdLine = RegExp(
    r'^(MD5|SHA1|SHA256|SHA512)\s*\(([^)]+)\)\s*=\s*([0-9a-fA-F]+)\s*$',
    caseSensitive: false,
  );
  static final RegExp _gnuLine = RegExp(r'^([0-9a-fA-F]{32,128})[ \t]([ *])(.+?)\s*$');

  /// Parses a checksum manifest's text content into entries. Supports the
  /// two formats every common checksum tool produces:
  ///  - GNU coreutils (`sha256sum`/`md5sum`/`sha1sum`/`sha512sum`):
  ///    `"<hex>  name"` (text mode) or `"<hex> *name"` (binary mode).
  ///  - BSD-tagged: `"SHA256 (name) = <hex>"`.
  /// The algorithm comes from the BSD tag when present, otherwise it's
  /// inferred from the hex digest's length. Blank lines, `#`-comments, and
  /// lines that don't match either shape are silently skipped -- manifests
  /// occasionally carry a header comment or a blank trailing line.
  List<ManifestEntry> parseManifest(String content) {
    final entries = <ManifestEntry>[];
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final bsd = _bsdLine.firstMatch(line);
      if (bsd != null) {
        final algo = HashAlgorithm.fromBsdTag(bsd.group(1)!);
        if (algo != null) {
          entries.add(ManifestEntry(
            fileName: _normalizeName(bsd.group(2)!),
            expectedHex: bsd.group(3)!.toLowerCase(),
            algorithm: algo,
          ));
        }
        continue;
      }

      final gnu = _gnuLine.firstMatch(line);
      if (gnu != null) {
        final hex = gnu.group(1)!.toLowerCase();
        final algo = HashAlgorithm.fromHexLength(hex.length);
        if (algo != null) {
          entries.add(ManifestEntry(
            fileName: _normalizeName(gnu.group(3)!),
            expectedHex: hex,
            algorithm: algo,
          ));
        }
      }
    }
    return entries;
  }

  String _normalizeName(String name) {
    var n = name.replaceAll('\\', '/').trim();
    if (n.startsWith('./')) n = n.substring(2);
    return n;
  }

  /// Recursively collects every file under the vault folder containing
  /// [manifestSource] (excluding the manifest itself), for the "add all
  /// files from this folder" convenience on the Verify tab. Returned items
  /// carry a [CryptoSourceItem.relativePath] relative to the vault root,
  /// same as any other vault source.
  Future<List<CryptoSourceItem>> collectVaultManifestSiblings(
    CryptoSourceItem manifestSource,
  ) async {
    if (!manifestSource.isFromVault) return const [];
    final container = manifestSource.container!;
    final manifestPath = manifestSource.relativePath!;
    final lastSlash = manifestPath.lastIndexOf('/');
    final folderPath = lastSlash < 0 ? '' : manifestPath.substring(0, lastSlash);

    final results = <CryptoSourceItem>[];

    Future<void> walk(String dirPath, int depth) async {
      if (depth > _maxWalkDepth) return;
      List<String>? raw;
      try {
        raw = await vaultExplorerApi.listDirectory(container, dirPath);
      } catch (_) {
        return;
      }
      if (raw == null) return;

      for (final entry in RawEntry.parseAll(raw)) {
        final fullPath = dirPath.isEmpty ? entry.name : '$dirPath/${entry.name}';
        if (fullPath == manifestPath) continue;
        if (entry.isDir) {
          await walk(fullPath, depth + 1);
        } else {
          results.add(CryptoSourceItem.vault(
            displayName: entry.name,
            container: container,
            relativePath: fullPath,
          ));
        }
      }
    }

    await walk(folderPath, 0);
    return results;
  }

  /// [item]'s path relative to the folder containing [manifestSource]
  /// (forward-slash separated, no leading slash) -- used to match a
  /// manifest entry's `fileName` (which may include a subfolder prefix)
  /// against a vault sibling collected by [collectVaultManifestSiblings].
  /// `null` if [item] isn't a vault source in the same container as
  /// [manifestSource], or doesn't actually live under its folder.
  String? relativeToManifestFolder(CryptoSourceItem item, CryptoSourceItem manifestSource) {
    if (!item.isFromVault || !manifestSource.isFromVault) return null;
    if (item.container!.volId != manifestSource.container!.volId) return null;
    final manifestPath = manifestSource.relativePath!;
    final lastSlash = manifestPath.lastIndexOf('/');
    final folderPath = lastSlash < 0 ? '' : manifestPath.substring(0, lastSlash);
    final itemPath = item.relativePath!;
    if (folderPath.isEmpty) return itemPath;
    if (!itemPath.startsWith('$folderPath/')) return null;
    return itemPath.substring(folderPath.length + 1);
  }

  /// Builds `"<hex>  <name>"` manifest text (GNU coreutils text-mode
  /// format) for every [results] entry that has a digest for [algorithm].
  String buildManifestText(List<HashComputeResult> results, HashAlgorithm algorithm) {
    final buf = StringBuffer();
    for (final r in results) {
      final hex = r.digests[algorithm];
      if (hex != null) {
        buf.write('$hex  ${r.source.displayName}\n');
      }
    }
    return buf.toString();
  }
}
