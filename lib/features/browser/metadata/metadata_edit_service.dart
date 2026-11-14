import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

import 'image_metadata_editor.dart';
import 'metadata_source.dart';

/// How an attempt to edit a file's metadata ended.
enum MetadataEditStatus {
  /// The file was rewritten.
  changed,

  /// Nothing would have changed, so the file was left alone.
  unchanged,

  /// Not a JPEG, PNG or WebP: its embedded metadata cannot be edited here.
  unsupported,

  /// The vault is read-only.
  readOnly,

  /// The file is damaged or its metadata could not be edited safely.
  failed,
}

class MetadataEditOutcome {
  const MetadataEditOutcome(this.status, [this.failure]);
  final MetadataEditStatus status;
  final MetadataEditFailure? failure;

  bool get ok => status == MetadataEditStatus.changed || status == MetadataEditStatus.unchanged;
}

/// Reads a file of a vault, phone storage or SAF location through
/// [VaultFileIoApi], for the metadata reader and editor.
class VaultMetadataSource implements MetadataSource {
  VaultMetadataSource(this._api, this._container, this._path, this.length);

  final VaultFileIoApi _api;
  final MountedContainer _container;
  final String _path;

  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || offset >= length || count <= 0) return Uint8List(0);
    final want = count < length - offset ? count : length - offset;
    final bytes = await _api.readFileChunk(_container, _path, offset, want);
    if (bytes == null) throw StateError('Could not read $_path at $offset');
    return bytes;
  }
}

/// Applies [MetadataEdit]s to files in a container.
///
/// The file is never decrypted to disk and never held whole in memory: the
/// edit is planned from its header, then the new file is streamed into a
/// sibling temp file and renamed over the original (see
/// [VaultFileIoApi.replaceFileFromChunks]).
class MetadataEditService {
  MetadataEditService(this._api);

  final VaultFileIoApi _api;

  /// A source for reading metadata of [path], or null when it cannot be sized.
  Future<VaultMetadataSource?> openSource(MountedContainer container, String path) async {
    final size = await _api.getFileSize(container, path);
    if (size < 0) return null;
    return VaultMetadataSource(_api, container, path, size);
  }

  /// Applies [edit] to [path].
  ///
  /// The file's modified time is put back to [keepModifiedSecs] afterwards
  /// (the edit itself must not make a photo look newly changed), unless
  /// [newModifiedSecs] is given, which is set instead.
  Future<MetadataEditOutcome> apply(
    MountedContainer container,
    String path,
    MetadataEdit edit, {
    int? keepModifiedSecs,
    int? newModifiedSecs,
  }) async {
    if (container.readOnly) return const MetadataEditOutcome(MetadataEditStatus.readOnly);
    if (!ImageMetadataEditor.canEdit(path)) {
      return const MetadataEditOutcome(MetadataEditStatus.unsupported);
    }
    final source = await openSource(container, path);
    if (source == null) return const MetadataEditOutcome(MetadataEditStatus.failed);
    try {
      final plan = await ImageMetadataEditor.plan(source, edit);
      if (plan == null) return const MetadataEditOutcome(MetadataEditStatus.unchanged);
      final ok = await _api.replaceFileFromChunks(container, path, plan.stream(source));
      if (!ok) return const MetadataEditOutcome(MetadataEditStatus.failed);
    } on MetadataEditException catch (e) {
      return MetadataEditOutcome(
        e.reason == MetadataEditFailure.unsupportedFormat
            ? MetadataEditStatus.unsupported
            : MetadataEditStatus.failed,
        e.reason,
      );
    } on StateError {
      return const MetadataEditOutcome(MetadataEditStatus.failed);
    }
    final stamp = newModifiedSecs ?? keepModifiedSecs;
    if (stamp != null) await _api.setLastModifiedTime(container, path, stamp);
    return const MetadataEditOutcome(MetadataEditStatus.changed);
  }

  /// Sets only the modified time, for files whose embedded dates cannot be
  /// edited (videos, HEIC, GIF).
  Future<bool> setModifiedTime(MountedContainer container, String path, int epochSecs) {
    if (container.readOnly) return Future.value(false);
    return _api.setLastModifiedTime(container, path, epochSecs);
  }
}
