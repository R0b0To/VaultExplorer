import 'dart:typed_data';

import 'android_resource_chunk_reader.dart';

/// `ResTable_entry.flags` bit indicating a "complex" (bag/style) entry
/// rather than a plain `Res_value` -- not expected for a file resource
/// like a launcher icon, but checked so such an entry is skipped rather
/// than misread as one.
const _flagComplex = 0x0001;

/// Sentinel entry-offset value meaning "no entry for this configuration"
/// in a `ResTable_type`'s offsets array.
const _noEntry = 0xFFFFFFFF;

/// Density qualifiers, highest-resolution first, used to prefer a
/// higher-density raster icon when a resource has more than one raster
/// candidate (the common case -- aapt bundles one PNG per density bucket
/// for a legacy/fallback launcher icon).
const _densityPreference = [
  'xxxhdpi',
  'xxhdpi',
  'xhdpi',
  'hdpi',
  'mdpi',
  'ldpi',
];

/// Resolves [resourceId] (as found by [findApplicationIconResourceId] in
/// the compiled manifest) against a `resources.arsc` resource table,
/// returning the path of the best available *raster* icon file inside the
/// APK (e.g. `"res/mipmap-xxhdpi-v4/ic_launcher.png"`), or `null`.
///
/// A single logical resource like `@mipmap/ic_launcher` is stored as one
/// entry per device configuration it was compiled for -- typically one
/// `Res_value` per density bucket (each a `TYPE_STRING` pointing at a
/// density-specific PNG/WebP path in the table's value string pool), plus,
/// on apps targeting API 26+, one `mipmap-anydpi-v26` entry whose value is
/// instead the path of a *compiled XML* adaptive-icon definition
/// (`<adaptive-icon>`, layering separate foreground/background
/// drawables). This function collects every configuration's value for
/// [resourceId] and deliberately prefers a raster candidate over an XML
/// one: composing an adaptive icon's layers (which can themselves be
/// vector drawables) is real rendering work this app doesn't attempt, so
/// an app that ships *only* an adaptive icon with no legacy raster
/// fallback resolves to `null` here rather than a half-rendered result.
///
/// Only the classic (`ResTable_entry.size == 8`, non-`FLAG_COMPLEX`)
/// entry format is handled. A resource table built with newer/experimental
/// entry-compaction is treated the same as "no entry for this
/// configuration" -- i.e. that configuration is skipped, not the whole
/// resource.
///
/// Returns `null` -- never throws -- for a malformed/truncated table, a
/// package id that isn't present, or a resource id with no raster
/// candidate in any configuration.
String? resolveIconResourcePath(Uint8List arscBytes, int resourceId) {
  try {
    final packageId = (resourceId >> 24) & 0xFF;
    final typeId = (resourceId >> 16) & 0xFF;
    final entryId = resourceId & 0xFFFF;

    final reader = AndroidChunkReader(arscBytes);
    final top = reader.readChunkHeader(0);
    if (top.type != AndroidChunkType.resTable) return null;

    var pos = top.headerSize;
    final end = top.size < reader.length ? top.size : reader.length;

    List<String> valueStrings = const [];
    final candidatePaths = <String>[];

    while (pos + 8 <= end) {
      final chunk = reader.readChunkHeader(pos);
      if (chunk.size <= 0) break;

      if (chunk.type == AndroidChunkType.resStringPool && valueStrings.isEmpty) {
        // The table's one global string pool, holding every TYPE_STRING
        // value in the whole table (file paths among them) -- distinct
        // from the per-package type-name/key-name pools below, which
        // this function never needs to read.
        valueStrings = reader.parseStringPool(pos);
      } else if (chunk.type == AndroidChunkType.resTablePackage) {
        candidatePaths.addAll(
          _collectCandidatesInPackage(
            reader,
            pos,
            chunk,
            packageId,
            typeId,
            entryId,
            valueStrings,
          ),
        );
      }

      pos += chunk.size;
    }

    return _pickBestRasterPath(candidatePaths);
  } catch (_) {
    return null;
  }
}

/// Scans one `RES_TABLE_PACKAGE_TYPE` chunk for `RES_TABLE_TYPE_TYPE`
/// (per-configuration) chunks matching [typeId], and for each, the value
/// stored for [entryId] if present -- one string per configuration that
/// actually defines this resource.
List<String> _collectCandidatesInPackage(
  AndroidChunkReader reader,
  int packageStart,
  AndroidChunkHeader packageChunk,
  int packageId,
  int typeId,
  int entryId,
  List<String> valueStrings,
) {
  final thisPackageId = reader.readU32(packageStart + 8);
  if (thisPackageId != packageId) return const [];

  // `typeIdOffset`: only present in the newer/longer ResTable_package
  // header (added for split resource tables, e.g. dynamic feature
  // modules) -- see ResTable_package's doc comment in ResourceTypes.h.
  // Disk-stored type ids in this package are relative to it: the logical
  // type id a resource id encodes equals the on-disk id plus this offset.
  final typeIdOffset =
      packageChunk.headerSize >= 288 ? reader.readU32(packageStart + 284) : 0;

  final results = <String>[];
  var pos = packageStart + packageChunk.headerSize;
  final packageEnd = packageStart + packageChunk.size;

  while (pos + 8 <= packageEnd) {
    final chunk = reader.readChunkHeader(pos);
    if (chunk.size <= 0) break;

    if (chunk.type == AndroidChunkType.resTableType) {
      final onDiskTypeId = reader.readU8(pos + 8);
      if (onDiskTypeId + typeIdOffset == typeId) {
        final path = _readEntryValueString(
          reader,
          pos,
          chunk,
          entryId,
          valueStrings,
        );
        if (path != null) results.add(path);
      }
    }

    pos += chunk.size;
  }
  return results;
}

/// Reads one `RES_TABLE_TYPE_TYPE` chunk's value for [entryId], if this
/// configuration defines it as a plain (non-complex) `TYPE_STRING` entry.
String? _readEntryValueString(
  AndroidChunkReader reader,
  int typeChunkStart,
  AndroidChunkHeader typeChunk,
  int entryId,
  List<String> valueStrings,
) {
  // ResTable_type: {id u8; res0 u8; res1 u16; entryCount u32;
  // entriesStart u32; config ResTable_config} (variable length, skipped --
  // this function only needs entriesStart/entryCount, both fixed-offset).
  final entryCount = reader.readU32(typeChunkStart + 12);
  final entriesStart = reader.readU32(typeChunkStart + 16);
  if (entryId >= entryCount) return null;

  // Offsets array immediately follows the chunk header (whatever
  // typeChunk.headerSize is, once the variable-length config struct is
  // accounted for) -- one u32 per entry, `_noEntry` where a configuration
  // doesn't define that particular entry at all.
  final offsetSlot = typeChunkStart + typeChunk.headerSize + 4 * entryId;
  final entryOffset = reader.readU32(offsetSlot);
  if (entryOffset == _noEntry) return null;

  final entryPos = typeChunkStart + entriesStart + entryOffset;
  final entrySize = reader.readU16(entryPos);
  final entryFlags = reader.readU16(entryPos + 2);
  if ((entryFlags & _flagComplex) != 0 || entrySize < 8) return null;

  // Res_value immediately follows the ResTable_entry header:
  // {size u16; res0 u8; dataType u8; data u32;}
  final valuePos = entryPos + entrySize;
  final dataType = reader.readU8(valuePos + 3);
  final data = reader.readU32(valuePos + 4);
  if (dataType != AndroidResValueType.typeString) return null;
  if (data >= valueStrings.length) return null;
  return valueStrings[data];
}

bool _isRasterIconPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg');
}

/// Picks the best candidate among every configuration's resolved value
/// for one resource: any raster (PNG/WebP/JPEG) path, preferring higher
/// density per [_densityPreference] -- never an XML path (adaptive-icon
/// definition or vector drawable), which this feature doesn't render.
String? _pickBestRasterPath(List<String> candidates) {
  final raster = candidates.where(_isRasterIconPath).toList();
  if (raster.isEmpty) return null;

  for (final density in _densityPreference) {
    for (final path in raster) {
      if (path.contains('-$density')) return path;
    }
  }
  return raster.first;
}
