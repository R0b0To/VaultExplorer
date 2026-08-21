import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

class FileInfoSheet extends StatefulWidget {
  final MountedContainer container;
  final RawEntry entry;
  final String currentDirPath;

  const FileInfoSheet({
    super.key,
    required this.container,
    required this.entry,
    required this.currentDirPath,
  });

  static Future<void> show(
    BuildContext context, {
    required MountedContainer container,
    required RawEntry entry,
    required String currentDirPath,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true, // <-- Restores the drag handle at the top of the sheet
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => FileInfoSheet(
        container: container,
        entry: entry,
        currentDirPath: currentDirPath,
      ),
    );
  }

  @override
  State<FileInfoSheet> createState() => _FileInfoSheetState();
}

class _FileInfoSheetState extends State<FileInfoSheet> {
  bool _loading = true;
  _ParsedMetadata? _metadata;
  String? _sha256;
  bool _calculatingSha256 = false;

  String get _fullPath => widget.currentDirPath.isEmpty
      ? widget.entry.name
      : '${widget.currentDirPath}/${widget.entry.name}';

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    setState(() => _loading = true);
    try {
      final isImg = MediaViewerConstants.isImage(widget.entry.name);
      final isVid = MediaViewerConstants.isVideo(widget.entry.name);

      Uint8List? headerBytes;
      if (!widget.entry.isDir && (isImg || isVid)) {
        final readLen = min(widget.entry.sizeBytes, 256 * 1024);
        if (readLen > 0) {
          headerBytes = await vaultExplorerApi.readFileChunk(
            widget.container,
            _fullPath,
            0,
            readLen,
          );
        }
      }

      final cachedRatio = MediaAspectRatioCache.get(widget.container, _fullPath);
      final parsed = _MetadataParser.parse(
        fileName: widget.entry.name,
        isDir: widget.entry.isDir,
        headerBytes: headerBytes,
        cachedAspectRatio: cachedRatio,
      );

      if (mounted) {
        setState(() {
          _metadata = parsed;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _computeSha256() async {
    if (_calculatingSha256 || _sha256 != null) return;
    setState(() => _calculatingSha256 = true);
    try {
      final size = widget.entry.sizeBytes;
      final opId = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      await vaultExplorerApi.beginHashSession(opId, ['SHA-256']);

      int offset = 0;
      const chunkSize = 256 * 1024;
      while (offset < size) {
        if (!mounted) break;
        final len = min(size - offset, chunkSize);
        final chunk = await vaultExplorerApi.readFileChunk(
          widget.container,
          _fullPath,
          offset,
          len,
        );
        if (chunk == null) break;
        await vaultExplorerApi.updateHashSession(opId, chunk);
        offset += len;
      }

      final results = await vaultExplorerApi.finishHashSession(opId);
      if (mounted) {
        setState(() {
          _sha256 = results['SHA-256']?.toLowerCase();
          _calculatingSha256 = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _calculatingSha256 = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final double sheetHeight = mediaQuery.size.height * (isLandscape ? 0.88 : 0.72);
    final ext = widget.entry.name.contains('.') ? widget.entry.name.split('.').last : '';

    return AppBottomSheet(
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (widget.entry.isDir ? cs.secondary : colorForFile(widget.entry.name))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.entry.isDir ? Icons.folder_rounded : iconForFile(widget.entry.name),
                    size: 24,
                    color: widget.entry.isDir ? cs.secondary : colorForFile(widget.entry.name),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.name,
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.entry.isDir
                            ? context.l10n.nounFolderCapitalized
                            : ext.isNotEmpty ? ext.toUpperCase() : context.l10n.nounFileCapitalized,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionTitle(context, 'FILE PROPERTIES'),
                          AppCard.rows(
                            dividerIndent: 16,
                            children: [
                              _buildInfoTile(context, 'Full Path', _fullPath),
                              if (!widget.entry.isDir)
                                _buildInfoTile(
                                  context,
                                  'Size',
                                  '${formatBytes(widget.entry.sizeBytes)} (${widget.entry.sizeBytes} B)',
                                ),
                              if (widget.entry.modifiedSecs > 0)
                                _buildInfoTile(
                                  context,
                                  'Modified',
                                  DateFormat('yyyy-MM-dd HH:mm:ss').format(
                                    DateTime.fromMillisecondsSinceEpoch(widget.entry.modifiedSecs * 1000),
                                  ),
                                ),
                              _buildInfoTile(context, 'Vault', widget.container.displayName),
                            ],
                          ),
                          if (_metadata?.hasMediaInfo == true) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(context, 'MEDIA & DIMENSIONS'),
                            AppCard.rows(
                              dividerIndent: 16,
                              children: [
                                if (_metadata?.width != null && _metadata?.height != null)
                                  _buildInfoTile(
                                    context,
                                    'Resolution',
                                    '${_metadata!.width} × ${_metadata!.height}${_metadata!.megapixels != null ? ' (${_metadata!.megapixels} MP)' : ''}',
                                  ),
                                if (_metadata?.aspectRatioString != null)
                                  _buildInfoTile(context, 'Aspect Ratio', _metadata!.aspectRatioString!),
                                if (_metadata?.mimeType != null)
                                  _buildInfoTile(context, 'Format', _metadata!.mimeType!),
                              ],
                            ),
                          ],
                          if (_metadata?.hasExifData == true) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(context, 'EXIF & CAMERA DATA'),
                            AppCard.rows(
                              dividerIndent: 16,
                              children: [
                                if (_metadata?.cameraModel != null)
                                  _buildInfoTile(context, 'Camera', _metadata!.cameraModel!),
                                if (_metadata?.lensModel != null)
                                  _buildInfoTile(context, 'Lens', _metadata!.lensModel!),
                                if (_metadata?.dateTaken != null)
                                  _buildInfoTile(context, 'Date Taken', _metadata!.dateTaken!),
                                if (_metadata?.exposureTime != null)
                                  _buildInfoTile(context, 'Shutter Speed', _metadata!.exposureTime!),
                                if (_metadata?.fNumber != null)
                                  _buildInfoTile(context, 'Aperture', 'f/${_metadata!.fNumber}'),
                                if (_metadata?.iso != null)
                                  _buildInfoTile(context, 'ISO', 'ISO ${_metadata!.iso}'),
                                if (_metadata?.focalLength != null)
                                  _buildInfoTile(context, 'Focal Length', _metadata!.focalLength!),
                                if (_metadata?.flash != null)
                                  _buildInfoTile(context, 'Flash', _metadata!.flash!),
                                if (_metadata?.software != null)
                                  _buildInfoTile(context, 'Software', _metadata!.software!),
                                if (_metadata?.gpsCoordinates != null)
                                  _buildInfoTile(context, 'GPS Location', _metadata!.gpsCoordinates!),
                              ],
                            ),
                          ],
                          if (!widget.entry.isDir) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(context, 'INTEGRITY & CHECKSUM'),
                            AppCard(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SHA-256',
                                            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                          ),
                                          const SizedBox(height: 4),
                                          if (_sha256 != null)
                                            Text(
                                              _sha256!,
                                              style: textTheme.bodySmall?.copyWith(
                                                fontFamily: 'monospace',
                                                fontSize: 11.5,
                                              ),
                                            )
                                          else
                                            Text(
                                              _calculatingSha256 ? 'Computing hash…' : 'Tap Calculate to verify',
                                              style: textTheme.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (_sha256 == null) ...[
                                      const SizedBox(width: 8),
                                      FilledButton.tonal(
                                        onPressed: _calculatingSha256 ? null : _computeSha256,
                                        style: FilledButton.styleFrom(
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        ),
                                        child: _calculatingSha256
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Text('Calculate'),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.1,
            ),
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ── In-Memory Metadata & EXIF Parser ──────────────────────────────────────────

class _ParsedMetadata {
  final int? width;
  final int? height;
  final String? mimeType;
  final String? cameraModel;
  final String? lensModel;
  final String? dateTaken;
  final String? exposureTime;
  final String? fNumber;
  final String? iso;
  final String? focalLength;
  final String? flash;
  final String? software;
  final String? gpsCoordinates;

  const _ParsedMetadata({
    this.width,
    this.height,
    this.mimeType,
    this.cameraModel,
    this.lensModel,
    this.dateTaken,
    this.exposureTime,
    this.fNumber,
    this.iso,
    this.focalLength,
    this.flash,
    this.software,
    this.gpsCoordinates,
  });

  bool get hasMediaInfo => width != null || height != null || mimeType != null;
  bool get hasExifData =>
      cameraModel != null ||
      lensModel != null ||
      dateTaken != null ||
      exposureTime != null ||
      fNumber != null ||
      iso != null ||
      focalLength != null ||
      flash != null ||
      gpsCoordinates != null;

  String? get megapixels {
    if (width == null || height == null || width! <= 0 || height! <= 0) return null;
    final mp = (width! * height!) / 1000000.0;
    return mp >= 1.0 ? mp.toStringAsFixed(1) : mp.toStringAsFixed(2);
  }

  String? get aspectRatioString {
    if (width == null || height == null || width! <= 0 || height! <= 0) return null;
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final divisor = gcd(width!, height!);
    final rw = width! ~/ divisor;
    final rh = height! ~/ divisor;
    if (rw <= 21 && rh <= 21) return '$rw:$rh';
    return (width! / height!).toStringAsFixed(2);
  }
}

class _MetadataParser {
  static _ParsedMetadata parse({
    required String fileName,
    required bool isDir,
    Uint8List? headerBytes,
    double? cachedAspectRatio,
  }) {
    if (isDir || headerBytes == null || headerBytes.isEmpty) {
      return const _ParsedMetadata();
    }

    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return _parseJpeg(headerBytes);
    } else if (lower.endsWith('.png')) {
      return _parsePng(headerBytes);
    } else if (lower.endsWith('.gif')) {
      return _parseGif(headerBytes);
    } else if (lower.endsWith('.webp')) {
      return _parseWebp(headerBytes);
    }

    return const _ParsedMetadata();
  }

  static _ParsedMetadata _parseJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return const _ParsedMetadata();
    }

    int? width;
    int? height;
    String? make;
    String? model;
    String? lensModel;
    String? dateTaken;
    String? exposureTime;
    String? fNumber;
    String? iso;
    String? focalLength;
    String? flash;
    String? software;
    String? gpsCoordinates;

    int offset = 2;
    while (offset < bytes.length - 4) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
        offset += 2;
        continue;
      }

      if (offset + 4 > bytes.length) break;
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (length < 2 || offset + 2 + length > bytes.length) break;

      // SOF markers for resolution (SOF0, SOF1, SOF2)
      if ((marker >= 0xC0 && marker <= 0xC3) || (marker >= 0xC5 && marker <= 0xC7)) {
        if (offset + 9 <= bytes.length) {
          height = (bytes[offset + 5] << 8) | bytes[offset + 6];
          width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        }
      }

      // APP1: Exif segment
      if (marker == 0xE1 && length >= 14) {
        final segmentBytes = bytes.sublist(offset + 4, offset + 2 + length);
        if (segmentBytes.length >= 6 &&
            segmentBytes[0] == 0x45 && // E
            segmentBytes[1] == 0x78 && // x
            segmentBytes[2] == 0x69 && // i
            segmentBytes[3] == 0x66 && // f
            segmentBytes[4] == 0x00 &&
            segmentBytes[5] == 0x00) {
          final tiffData = segmentBytes.sublist(6);
          final exif = _parseTiffExif(tiffData);
          make = exif['make'];
          model = exif['model'];
          lensModel = exif['lensModel'];
          dateTaken = exif['dateTaken'];
          exposureTime = exif['exposureTime'];
          fNumber = exif['fNumber'];
          iso = exif['iso'];
          focalLength = exif['focalLength'];
          flash = exif['flash'];
          software = exif['software'];
          gpsCoordinates = exif['gps'];
        }
      }

      offset += 2 + length;
    }

    String? fullCamera;
    if (make != null && model != null) {
      fullCamera = model.toLowerCase().contains(make.toLowerCase()) ? model : '$make $model';
    } else {
      fullCamera = model ?? make;
    }

    return _ParsedMetadata(
      width: width,
      height: height,
      mimeType: 'JPEG Image',
      cameraModel: fullCamera,
      lensModel: lensModel,
      dateTaken: dateTaken,
      exposureTime: exposureTime,
      fNumber: fNumber,
      iso: iso,
      focalLength: focalLength,
      flash: flash,
      software: software,
      gpsCoordinates: gpsCoordinates,
    );
  }

  static Map<String, String> _parseTiffExif(Uint8List tiff) {
    final result = <String, String>{};
    if (tiff.length < 8) return result;

    final isLe = tiff[0] == 0x49 && tiff[1] == 0x49; // 'II' vs 'MM'
    int readU16(int o) {
      if (o < 0 || o + 2 > tiff.length) return 0;
      return isLe ? (tiff[o] | (tiff[o + 1] << 8)) : ((tiff[o] << 8) | tiff[o + 1]);
    }
    int readU32(int o) {
      if (o < 0 || o + 4 > tiff.length) return 0;
      return isLe
          ? (tiff[o] | (tiff[o + 1] << 8) | (tiff[o + 2] << 16) | (tiff[o + 3] << 24))
          : ((tiff[o] << 24) | (tiff[o + 1] << 16) | (tiff[o + 2] << 8) | tiff[o + 3]);
    }

    final ifd0Offset = readU32(4);
    if (ifd0Offset >= tiff.length || ifd0Offset <= 0) return result;

    void readIfd(int offset, bool isSubIfd, bool isGps, [int depth = 0]) {
      if (depth > 3 || offset < 0 || offset + 2 > tiff.length) return;
      final entryCount = readU16(offset);
      int p = offset + 2;

      for (int i = 0; i < entryCount; i++) {
        if (p + 12 > tiff.length) break;
        final tag = readU16(p);
        final count = readU32(p + 4);
        final valOffset = readU32(p + 8);

        String readAscii() {
          final start = count <= 4 ? p + 8 : valOffset;
          if (start < 0 || start >= tiff.length) return '';
          final end = min(tiff.length, start + count);
          if (end <= start) return '';
          final sub = tiff.sublist(start, end);
          final nullIdx = sub.indexOf(0);
          final clean = nullIdx != -1 ? sub.sublist(0, nullIdx) : sub;
          return utf8.decode(clean, allowMalformed: true).trim();
        }

        double? readRational(int rOffset) {
          if (rOffset < 0 || rOffset + 8 > tiff.length) return null;
          final num = readU32(rOffset);
          final den = readU32(rOffset + 4);
          if (den == 0) return null;
          return num / den;
        }

        if (tag == 0x010F) result['make'] = readAscii();
        if (tag == 0x0110) result['model'] = readAscii();
        if (tag == 0x0131) result['software'] = readAscii();
        if (tag == 0x8769) readIfd(valOffset, true, false, depth + 1);
        if (tag == 0x8825) readIfd(valOffset, false, true, depth + 1);

        if (isSubIfd) {
          if (tag == 0x9003 || tag == 0x9004) result['dateTaken'] = readAscii();
          if (tag == 0xA434) result['lensModel'] = readAscii();
          if (tag == 0x8827) result['iso'] = '$valOffset';
          if (tag == 0x829D) {
            final f = readRational(valOffset);
            if (f != null) result['fNumber'] = f.toStringAsFixed(1);
          }
          if (tag == 0x829A) {
            if (valOffset + 8 <= tiff.length) {
              final num = readU32(valOffset);
              final den = readU32(valOffset + 4);
              if (den > 0) {
                result['exposureTime'] = num < den ? '1/${(den / num).round()}s' : '${num / den}s';
              }
            }
          }
          if (tag == 0x920A) {
            final fl = readRational(valOffset);
            if (fl != null) result['focalLength'] = '${fl.toStringAsFixed(1)} mm';
          }
        }

        p += 12;
      }
    }

    readIfd(ifd0Offset, false, false, 0);
    return result;
  }

  static _ParsedMetadata _parsePng(Uint8List bytes) {
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return _ParsedMetadata(width: w, height: h, mimeType: 'PNG Image');
    }
    return const _ParsedMetadata();
  }

  static _ParsedMetadata _parseGif(Uint8List bytes) {
    if (bytes.length >= 10 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      final w = bytes[6] | (bytes[7] << 8);
      final h = bytes[8] | (bytes[9] << 8);
      return _ParsedMetadata(width: w, height: h, mimeType: 'GIF Image');
    }
    return const _ParsedMetadata();
  }

  static _ParsedMetadata _parseWebp(Uint8List bytes) {
    if (bytes.length >= 30 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x20) {
        final w = ((bytes[27] & 0x3F) << 8) | bytes[26];
        final h = ((bytes[29] & 0x3F) << 8) | bytes[28];
        return _ParsedMetadata(width: w, height: h, mimeType: 'WebP Image');
      }
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x58) {
        final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
        final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
        return _ParsedMetadata(width: w, height: h, mimeType: 'WebP Image');
      }
    }
    return const _ParsedMetadata();
  }
}