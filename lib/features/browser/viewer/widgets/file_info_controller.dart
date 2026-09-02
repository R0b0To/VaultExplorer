// FileInfoSheet was a StatefulWidget owning metadata-load and SHA-256
// compute state directly as State fields. Family-keyed by (volId, fullPath):
// a fresh sheet instance is pushed per file/folder inspected, same shape as
// VaultItemDetail/TextEditorLoad scoping to "this screen's session". The
// pure in-memory parsers (_ParsedMetadata/_MetadataParser and their EXIF/
// JPEG/PNG/GIF/WebP byte-parsing) stay exactly where they are in
// file_info_sheet.dart -- they're stateless functions, nothing to convert.
import 'dart:math';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart' show ParsedMetadata, MetadataParser;
import 'package:vaultexplorer/core/utils/raw_entry.dart';

part 'file_info_controller.g.dart';

class FileInfoState {
  final bool loading;
  final ParsedMetadata? metadata;
  final String? sha256;
  final bool calculatingSha256;

  const FileInfoState({
    this.loading = true,
    this.metadata,
    this.sha256,
    this.calculatingSha256 = false,
  });

  FileInfoState copyWith({
    bool? loading,
    ParsedMetadata? metadata,
    String? sha256,
    bool? calculatingSha256,
  }) =>
      FileInfoState(
        loading: loading ?? this.loading,
        metadata: metadata ?? this.metadata,
        sha256: sha256 ?? this.sha256,
        calculatingSha256: calculatingSha256 ?? this.calculatingSha256,
      );
}

@riverpod
class FileInfo extends _$FileInfo {
  @override
  FileInfoState build(int volId, String fullPath) {
    return const FileInfoState();
  }

  Future<void> load(MountedContainer container, RawEntry entry) async {
     
     if (!state.loading) {
    state = state.copyWith(loading: true);
    }
    try {
      final isImg = MediaViewerConstants.isImage(entry.name);
      final isVid = MediaViewerConstants.isVideo(entry.name);

      Uint8List? headerBytes;
      if (!entry.isDir && (isImg || isVid)) {
        final readLen = min(entry.sizeBytes, 256 * 1024);
        if (readLen > 0) {
          headerBytes = await ref.read(vaultFileIoApiProvider).readFileChunk(
                container,
                fullPath,
                0,
                readLen,
              );
        }
      }

      final cachedRatio = MediaAspectRatioCache.get(container, fullPath);
      final parsed = MetadataParser.parse(
        fileName: entry.name,
        isDir: entry.isDir,
        headerBytes: headerBytes,
        cachedAspectRatio: cachedRatio,
      );

      if (!ref.mounted) return;
      state = state.copyWith(metadata: parsed, loading: false);
    } catch (_) {
      if (ref.mounted) state = state.copyWith(loading: false);
    }
  }

  Future<void> computeSha256(MountedContainer container, RawEntry entry) async {
    if (state.calculatingSha256 || state.sha256 != null) return;
    state = state.copyWith(calculatingSha256: true);
    try {
      final size = entry.sizeBytes;
      final opId = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      final hashApi = ref.read(vaultHashApiProvider);
      final fileIoApi = ref.read(vaultFileIoApiProvider);
      await hashApi.beginHashSession(opId, ['SHA-256']);

      int offset = 0;
      const chunkSize = 256 * 1024;
      while (offset < size) {
        if (!ref.mounted) break;
        final len = min(size - offset, chunkSize);
        final chunk = await fileIoApi.readFileChunk(container, fullPath, offset, len);
        if (chunk == null) break;
        await hashApi.updateHashSession(opId, chunk);
        offset += len;
      }

      final results = await hashApi.finishHashSession(opId);
      if (ref.mounted) {
        state = state.copyWith(
          sha256: results['SHA-256']?.toLowerCase(),
          calculatingSha256: false,
        );
      }
    } catch (_) {
      if (ref.mounted) state = state.copyWith(calculatingSha256: false);
    }
  }
}
