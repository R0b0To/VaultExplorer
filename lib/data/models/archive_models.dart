/// Data models for native archive operations (via libarchive engine).
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
  tarZstd;

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
  final String errorMessage;

  const ArchiveIndexResult({
    required this.status,
    required this.entries,
    required this.isSolid,
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
      errorMessage: map['errorMessage'] as String? ?? '',
    );
  }
}

/// Result of native bulk extraction.
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
