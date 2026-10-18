import 'package:flutter/foundation.dart';

/// Status returned by native archive open/extract/create operations.
enum ArchiveOpenStatus {
  ok,
  unsupportedFormat,
  passphraseRequired,
  wrongPassphrase,
  ioError;

  static ArchiveOpenStatus fromInt(int value) {
    switch (value) {
      case 0:
        return ArchiveOpenStatus.ok;
      case 1:
        return ArchiveOpenStatus.unsupportedFormat;
      case 2:
        return ArchiveOpenStatus.passphraseRequired;
      case 3:
        return ArchiveOpenStatus.wrongPassphrase;
      default:
        return ArchiveOpenStatus.ioError;
    }
  }
}

/// Archive format types supported for creation by the native engine.
enum ArchiveFormatType {
  zip,
  sevenZip,
  tar,
  tarGz,
  tarBz2,
  tarXz,
  tarZstd,
  tarLzma,
  iso,     
  cpio;

  int get code {
    switch (this) {
      case ArchiveFormatType.zip:
        return 0;
      case ArchiveFormatType.sevenZip:
        return 1;
      case ArchiveFormatType.tar:
        return 2;
      case ArchiveFormatType.tarGz:
        return 3;
      case ArchiveFormatType.tarBz2:
        return 4;
      case ArchiveFormatType.tarXz:
        return 5;
      case ArchiveFormatType.tarZstd:
        return 6;
        case ArchiveFormatType.tarLzma:
        return 7;
      case ArchiveFormatType.iso:
        return 8;
      case ArchiveFormatType.cpio:
        return 9;
    }
  }

  String get fileExtension {
    switch (this) {
      case ArchiveFormatType.zip:
        return 'zip';
      case ArchiveFormatType.sevenZip:
        return '7z';
      case ArchiveFormatType.tar:
        return 'tar';
      case ArchiveFormatType.tarGz:
        return 'tar.gz';
      case ArchiveFormatType.tarBz2:
        return 'tar.bz2';
      case ArchiveFormatType.tarXz:
        return 'tar.xz';
      case ArchiveFormatType.tarZstd:
        return 'tar.zst';
      case ArchiveFormatType.tarLzma:
        return 'tar.lzma';
      case ArchiveFormatType.iso:
        return 'iso';
      case ArchiveFormatType.cpio:
        return 'cpio';
    }
  }

  /// Short technical format name for UI display (not localized, same as
  /// e.g. FilesystemType's "FAT32"/"NTFS" labels).
  String get displayLabel {
    switch (this) {
      case ArchiveFormatType.zip:
        return 'ZIP';
      case ArchiveFormatType.sevenZip:
        return '7-Zip';
      case ArchiveFormatType.tar:
        return 'TAR';
      case ArchiveFormatType.tarGz:
        return 'TAR.GZ';
      case ArchiveFormatType.tarBz2:
        return 'TAR.BZ2';
      case ArchiveFormatType.tarXz:
        return 'TAR.XZ';
      case ArchiveFormatType.tarZstd:
        return 'TAR.ZST';
      case ArchiveFormatType.tarLzma:
        return 'TAR.LZMA';
      case ArchiveFormatType.iso:
        return 'ISO';
      case ArchiveFormatType.cpio:
        return 'CPIO';
    }
  }

  /// Whether the native engine supports AES-256 password protection when
  /// creating an archive in this format.
  bool get supportsPassword =>
      this == ArchiveFormatType.zip || this == ArchiveFormatType.sevenZip;

  /// Whether, together with a password, the file names can be encrypted too
  /// (the 7z header). ZIP can't: its file names are always stored in the clear.
  bool get supportsFilenameEncryption => this == ArchiveFormatType.sevenZip;

  /// Whether the format compresses its contents and so honors a compression
  /// level. Plain TAR, ISO and CPIO only package files; the native engine
  /// ignores the level for them, so the UI should not offer it.
  ///
  /// Exhaustive on purpose: adding a format forces a decision here.
  bool get supportsCompressionLevel => switch (this) {
        ArchiveFormatType.zip ||
        ArchiveFormatType.sevenZip ||
        ArchiveFormatType.tarGz ||
        ArchiveFormatType.tarBz2 ||
        ArchiveFormatType.tarXz ||
        ArchiveFormatType.tarZstd ||
        ArchiveFormatType.tarLzma =>
          true,
        ArchiveFormatType.tar ||
        ArchiveFormatType.iso ||
        ArchiveFormatType.cpio =>
          false,
      };

  /// The compression methods the user can choose between for this format.
  /// Only 7z has a real choice; every other format is tied to one codec (see
  /// [fixedCompressionLabel]). Mirrors `archiveCompressionMethodSupported` in
  /// the native engine, which refuses anything outside this list.
  ///
  /// The first entry is the preselected one.
  List<ArchiveCompressionMethod> get selectableCompressionMethods =>
      switch (this) {
        ArchiveFormatType.sevenZip => const [
            ArchiveCompressionMethod.lzma2,
            ArchiveCompressionMethod.lzma,
            ArchiveCompressionMethod.deflate,
          ],
        ArchiveFormatType.zip ||
        ArchiveFormatType.tar ||
        ArchiveFormatType.tarGz ||
        ArchiveFormatType.tarBz2 ||
        ArchiveFormatType.tarXz ||
        ArchiveFormatType.tarZstd ||
        ArchiveFormatType.tarLzma ||
        ArchiveFormatType.iso ||
        ArchiveFormatType.cpio =>
          const [],
      };

  /// Short technical name of the one codec a compressing format always uses,
  /// or null when the user picks it ([selectableCompressionMethods]) or when
  /// the format doesn't compress at all. Not localized, like [displayLabel].
  String? get fixedCompressionLabel => switch (this) {
        ArchiveFormatType.zip || ArchiveFormatType.tarGz => 'Deflate',
        ArchiveFormatType.tarBz2 => 'BZip2',
        ArchiveFormatType.tarXz => 'LZMA2',
        ArchiveFormatType.tarZstd => 'Zstandard',
        ArchiveFormatType.tarLzma => 'LZMA',
        ArchiveFormatType.sevenZip ||
        ArchiveFormatType.tar ||
        ArchiveFormatType.iso ||
        ArchiveFormatType.cpio =>
          null,
      };
}

/// The codec an archive's data is compressed with, for formats that let the
/// user choose (see [ArchiveFormatType.selectableCompressionMethods]).
///
/// [code] is shared with the native engine (`ArchiveCompressionMethod` in
/// archive_engine.h) and the Kotlin handler; don't renumber it.
enum ArchiveCompressionMethod {
  /// No explicit choice: the format uses its own codec.
  auto,
  deflate,
  lzma,
  lzma2;

  int get code => switch (this) {
        ArchiveCompressionMethod.auto => 0,
        ArchiveCompressionMethod.deflate => 1,
        ArchiveCompressionMethod.lzma => 2,
        ArchiveCompressionMethod.lzma2 => 3,
      };

  /// Short technical name for UI display (not localized).
  String get displayLabel => switch (this) {
        ArchiveCompressionMethod.auto => '',
        ArchiveCompressionMethod.deflate => 'Deflate',
        ArchiveCompressionMethod.lzma => 'LZMA',
        ArchiveCompressionMethod.lzma2 => 'LZMA2',
      };
}

/// Human-readable presets for compression level.
enum ArchiveCompressionLevel {
  store,
  fast,
  normal,
  ultra;

  int get code {
    switch (this) {
      case ArchiveCompressionLevel.store:
        return 0;
      case ArchiveCompressionLevel.fast:
        return 1;
      case ArchiveCompressionLevel.normal:
        return 5;
      case ArchiveCompressionLevel.ultra:
        return 9;
    }
  }

  int get level => code;

  String get label {
    switch (this) {
      case ArchiveCompressionLevel.store:
        return 'Store (0)';
      case ArchiveCompressionLevel.fast:
        return 'Fast (1–3)';
      case ArchiveCompressionLevel.normal:
        return 'Normal (5)';
      case ArchiveCompressionLevel.ultra:
        return 'Ultra (9)';
    }
  }

  String get title {
    switch (this) {
      case ArchiveCompressionLevel.store:
        return 'Store (0) — No compression';
      case ArchiveCompressionLevel.fast:
        return 'Fast (1–3) — Quick';
      case ArchiveCompressionLevel.normal:
        return 'Normal (5) — Balanced';
      case ArchiveCompressionLevel.ultra:
        return 'Ultra (9) — Smallest size';
    }
  }

  String get description {
    switch (this) {
      case ArchiveCompressionLevel.store:
        return 'Instant packaging, best for videos, music & archives';
      case ArchiveCompressionLevel.fast:
        return 'Quick compression for everyday sharing';
      case ArchiveCompressionLevel.normal:
        return 'Balanced speed and compression (default)';
      case ArchiveCompressionLevel.ultra:
        return 'Maximum compression, slower';
    }
  }
}


/// Metadata describing a single entry inside an archive.
@immutable
class ArchiveEntryInfo {
  final String path;
  final int uncompressedSize;
  final int compressedSize;
  final DateTime modTime;
  final bool isEncrypted;
  final bool isDirectory;
  final int index;

  const ArchiveEntryInfo({
    required this.path,
    required this.uncompressedSize,
    required this.compressedSize,
    required this.modTime,
    required this.isEncrypted,
    required this.isDirectory,
    required this.index,
  });

  factory ArchiveEntryInfo.fromMap(Map<Object?, Object?> map) {
    final rawModTime = map['modTimeEpochSeconds'];
    final epochSeconds = rawModTime is num ? rawModTime.toInt() : 0;
    return ArchiveEntryInfo(
      path: map['path'] as String? ?? '',
      uncompressedSize: (map['uncompressedSize'] as num?)?.toInt() ?? 0,
      compressedSize: (map['compressedSize'] as num?)?.toInt() ?? 0,
      modTime: DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true),
      isEncrypted: map['isEncrypted'] as bool? ?? false,
      isDirectory: map['isDirectory'] as bool? ?? false,
      index: (map['index'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Summary result of scanning an archive's header/metadata.
@immutable
class ArchiveIndexResult {
  final ArchiveOpenStatus status;
  final List<ArchiveEntryInfo> entries;
  final bool isSolid;
  final bool isSevenZip;
  final String errorMessage;

  const ArchiveIndexResult({
    required this.status,
    required this.entries,
    required this.isSolid,
    this.isSevenZip = false,
    required this.errorMessage,
  });

  factory ArchiveIndexResult.fromMap(Map<Object?, Object?> map) {
    final rawStatus = map['status'] as num? ?? 4;
    final rawEntries = map['entries'] as List<Object?>? ?? const [];
    final entries = rawEntries
        .whereType<Map<Object?, Object?>>()
        .map(ArchiveEntryInfo.fromMap)
        .toList();

    return ArchiveIndexResult(
      status: ArchiveOpenStatus.fromInt(rawStatus.toInt()),
      entries: entries,
      isSolid: map['isSolid'] as bool? ?? false,
      isSevenZip: map['isSevenZip'] as bool? ?? false,
      errorMessage: map['errorMessage'] as String? ?? '',
    );
  }
}

/// Result of extracting a single entry from an archive on-demand.
///
/// Carries [status] through from the native engine instead of collapsing
/// "passphrase required", "wrong passphrase", a genuine I/O error, and a
/// successfully-extracted zero-byte file into a single ambiguous null.
@immutable
class ArchiveEntryExtractResult {
  final ArchiveOpenStatus status;
  final Uint8List? data;
  final String errorMessage;

  const ArchiveEntryExtractResult({
    required this.status,
    required this.data,
    required this.errorMessage,
  });

  bool get needsPassphrase =>
      status == ArchiveOpenStatus.passphraseRequired ||
      status == ArchiveOpenStatus.wrongPassphrase;

  factory ArchiveEntryExtractResult.fromMap(Map<Object?, Object?> map) {
    final rawStatus = map['status'] as num? ?? 4;
    final rawData = map['data'];
    return ArchiveEntryExtractResult(
      status: ArchiveOpenStatus.fromInt(rawStatus.toInt()),
      data: rawData is Uint8List
          ? rawData
          : (rawData is List<int> ? Uint8List.fromList(rawData) : null),
      errorMessage: map['errorMessage'] as String? ?? '',
    );
  }

  factory ArchiveEntryExtractResult.ioError(String message) =>
      ArchiveEntryExtractResult(
        status: ArchiveOpenStatus.ioError,
        data: null,
        errorMessage: message,
      );
}

/// Result of streaming an archive entry to a temporary file for preview or
/// extraction. Preserves passphrase failures so the browser can ask for a
/// password and retry without rescanning the archive.
@immutable
class ArchiveEntryStageResult {
  final ArchiveOpenStatus status;
  final String? path;
  final String errorMessage;

  const ArchiveEntryStageResult({
    required this.status,
    required this.path,
    required this.errorMessage,
  });

  bool get needsPassphrase =>
      status == ArchiveOpenStatus.passphraseRequired ||
      status == ArchiveOpenStatus.wrongPassphrase;

  factory ArchiveEntryStageResult.fromMap(Map<Object?, Object?> map) {
    final rawStatus = map['status'] as num? ?? 4;
    return ArchiveEntryStageResult(
      status: ArchiveOpenStatus.fromInt(rawStatus.toInt()),
      path: map['path'] as String?,
      errorMessage: map['errorMessage'] as String? ?? '',
    );
  }

  factory ArchiveEntryStageResult.ioError(String message) =>
      ArchiveEntryStageResult(
        status: ArchiveOpenStatus.ioError,
        path: null,
        errorMessage: message,
      );
}

@immutable
class ArchiveBulkExtractResult {
  final ArchiveOpenStatus status;
  final int extractedCount;
  final String errorMessage;

  const ArchiveBulkExtractResult({
    required this.status,
    required this.extractedCount,
    required this.errorMessage,
  });

  factory ArchiveBulkExtractResult.fromMap(Map<Object?, Object?> map) {
    final rawStatus = map['status'] as num? ?? 4;
    return ArchiveBulkExtractResult(
      status: ArchiveOpenStatus.fromInt(rawStatus.toInt()),
      extractedCount: (map['extractedCount'] as num?)?.toInt() ?? 0,
      errorMessage: map['errorMessage'] as String? ?? '',
    );
  }
}
