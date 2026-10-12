import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_controller.dart';

class FileInfoSheet extends ConsumerStatefulWidget {
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
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => FileInfoSheet(
        container: container,
        entry: entry,
        currentDirPath: currentDirPath,
      ),
    );
  }

  @override
  ConsumerState<FileInfoSheet> createState() => _FileInfoSheetState();
}

class _FileInfoSheetState extends ConsumerState<FileInfoSheet> {
  String get _fullPath => widget.currentDirPath.isEmpty
      ? widget.entry.name
      : '${widget.currentDirPath}/${widget.entry.name}';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(
        fileInfoProvider(widget.container.volId, _fullPath).notifier,
      );
      notifier.load(widget.container, widget.entry);

      // Trigger folder stats scan for directories
      if (widget.entry.isDir) {
        notifier.loadFolderStats(widget.container);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(
      fileInfoProvider(widget.container.volId, _fullPath),
    );
    final metadata = controllerState.metadata;
    final videoMetadata = controllerState.videoMetadata;
    final audioMetadata = controllerState.audioMetadata;
    final audioTags = controllerState.audioTags;
    final sha256 = controllerState.sha256;
    final calculatingSha256 = controllerState.calculatingSha256;
    final loading = controllerState.loading;

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final double sheetHeight =
        mediaQuery.size.height * (isLandscape ? 0.88 : 0.72);
    final ext = widget.entry.name.contains('.')
        ? widget.entry.name.split('.').last
        : '';

    // Some containers (MP3 in particular) report no bitrate; fall back to the
    // file's average (size / duration), flagged as approximate. It includes
    // tags and cover art, so it is only an estimate.
    int? audioBitrate = audioMetadata?.bitrate;
    var audioBitrateApprox = false;
    if ((audioBitrate ?? 0) <= 0 &&
        audioMetadata != null &&
        audioMetadata.durationUs > 0 &&
        widget.entry.sizeBytes > 0) {
      audioBitrate =
          (widget.entry.sizeBytes * 8 * 1000000 / audioMetadata.durationUs)
              .round();
      audioBitrateApprox = true;
    }
    final hasAudioProperties =
        (audioMetadata != null &&
            (audioMetadata.durationUs > 0 ||
                audioMetadata.mime?.isNotEmpty == true ||
                (audioMetadata.sampleRate ?? 0) > 0 ||
                (audioMetadata.channels ?? 0) > 0)) ||
        audioTags?.bitDepth != null;

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
                    color:
                        (widget.entry.isDir
                                ? cs.secondary
                                : colorForFile(widget.entry.name))
                            .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.entry.isDir
                        ? Icons.folder_rounded
                        : iconForFile(widget.entry.name),
                    size: 24,
                    color: widget.entry.isDir
                        ? cs.secondary
                        : colorForFile(widget.entry.name),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.entry.isDir
                            ? context.l10n.nounFolderCapitalized
                            : ext.isNotEmpty
                            ? ext.toUpperCase()
                            : context.l10n.nounFileCapitalized,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
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
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionTitle(
                            context,
                            context.l10n.filePropertiesSectionHeader,
                          ),
                          AppCard.rows(
                            dividerIndent: 16,
                            children: [
                              _buildInfoTile(
                                context,
                                context.l10n.fullPathLabel,
                                _fullPath,
                                copyable: true,
                              ),
                              if (!widget.entry.isDir)
                                _buildInfoTile(
                                  context,
                                  context.l10n.sizeLabel,
                                  '${formatBytes(widget.entry.sizeBytes)} (${widget.entry.sizeBytes} B)',
                                ),
                              if (widget.entry.isDir)
                                _buildInfoTile(
                                  context,
                                  context.l10n.contentsLabel,
                                  controllerState.folderItemCount != null
                                      ? context.l10n.folderItemCount(
                                          controllerState.folderItemCount!,
                                        )
                                      : context.l10n.calculatingFolderStats,
                                ),
                              if (widget.entry.isDir)
                                _buildInfoTile(
                                  context,
                                  context.l10n.totalSizeLabel,
                                  controllerState.folderTotalBytes != null
                                      ? '${formatBytes(controllerState.folderTotalBytes!)} (${controllerState.folderTotalBytes!} B)'
                                      : context.l10n.calculatingFolderStats,
                                ),
                              if (widget.entry.modifiedSecs > 0)
                                _buildInfoTile(
                                  context,
                                  context.l10n.modifiedLabel,
                                  DateFormat('yyyy-MM-dd HH:mm:ss').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      widget.entry.modifiedSecs * 1000,
                                    ),
                                  ),
                                ),
                              _buildInfoTile(
                                context,
                                context.l10n.vaultLabel,
                                widget.container.displayName,
                              ),
                            ],
                          ),
                          if (metadata?.hasMediaInfo == true) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(
                              context,
                              context.l10n.mediaDimensionsSectionHeader,
                            ),
                            AppCard.rows(
                              dividerIndent: 16,
                              children: [
                                if (metadata?.width != null &&
                                    metadata?.height != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.resolutionLabel,
                                    '${metadata!.width} × ${metadata.height}${metadata.megapixels != null ? ' (${metadata.megapixels} MP)' : ''}',
                                  ),
                                if (metadata?.aspectRatioString != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.aspectRatioLabel,
                                    metadata!.aspectRatioString!,
                                  ),
                                if (metadata?.mimeType != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.formatLabel,
                                    metadata!.mimeType!,
                                  ),
                                if (metadata?.colorMode != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.colorModeLabel,
                                    metadata!.colorMode!,
                                  ),
                                if (metadata?.bitDepth != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.bitDepthLabel,
                                    metadata!.bitDepth!,
                                  ),
                                if (metadata?.hasAlpha != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.transparencyLabel,
                                    metadata!.hasAlpha!
                                        ? context.l10n.vaultInfoYesValue
                                        : context.l10n.vaultInfoNoValue,
                                  ),
                                if (metadata?.isAnimated != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.animationLabel,
                                    metadata!.isAnimated!
                                        ? context.l10n.vaultInfoYesValue
                                        : context.l10n.vaultInfoNoValue,
                                  ),
                                if (metadata?.orientation != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.orientationLabel,
                                    metadata!.orientation!,
                                  ),
                                if (metadata?.density != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.densityLabel,
                                    metadata!.density!,
                                  ),
                                if (metadata?.encoding != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.encodingLabel,
                                    metadata!.encoding!,
                                  ),
                              ],
                            ),
                          ],
                          if (videoMetadata != null &&
                              (videoMetadata.hasVideo ||
                                  videoMetadata.hasAudio)) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(
                              context,
                              context.l10n.videoFilePropertiesSectionHeader,
                            ),
                            AppCard.rows(
                              dividerIndent: 16,
                              children: [
                                if (videoMetadata.durationUs > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.durationLabel,
                                    formatClockDuration(
                                      Duration(
                                        microseconds: videoMetadata.durationUs,
                                      ),
                                    ),
                                  ),
                                if (videoMetadata.hasVideo &&
                                    videoMetadata.width > 0 &&
                                    videoMetadata.height > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.resolutionLabel,
                                    '${videoMetadata.width} × ${videoMetadata.height}',
                                  ),
                                if (videoMetadata.hasVideo &&
                                    videoMetadata.width > 0 &&
                                    videoMetadata.height > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.aspectRatioLabel,
                                    (videoMetadata.width / videoMetadata.height)
                                        .toStringAsFixed(2),
                                  ),
                                if (videoMetadata.rotationDegrees != 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.rotationLabel,
                                    context.l10n.rotationDegreesValue(
                                      videoMetadata.rotationDegrees,
                                    ),
                                  ),
                                if (videoMetadata.videoMime?.isNotEmpty == true)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.videoCodecLabel,
                                    _prettyCodec(videoMetadata.videoMime!),
                                  ),
                                if ((videoMetadata.videoBitrate ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.videoBitrateLabel,
                                    _formatBitrate(videoMetadata.videoBitrate!),
                                  ),
                                if ((videoMetadata.frameRate ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.framerateLabel,
                                    '${videoMetadata.frameRate!.toStringAsFixed(2)} fps',
                                  ),
                                if (videoMetadata.audioMime?.isNotEmpty == true)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.audioCodecLabel,
                                    _prettyCodec(videoMetadata.audioMime!),
                                  ),
                                if ((videoMetadata.audioBitrate ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.audioBitrateLabel,
                                    _formatBitrate(videoMetadata.audioBitrate!),
                                  ),
                                if ((videoMetadata.audioSampleRate ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.sampleRateLabel,
                                    '${videoMetadata.audioSampleRate} Hz',
                                  ),
                                if ((videoMetadata.audioChannels ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.audioChannelsLabel,
                                    videoMetadata.audioChannels.toString(),
                                  ),
                                if (videoMetadata.subtitleTracks > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.subtitleTracksLabel,
                                    videoMetadata.subtitleTracks.toString(),
                                  ),
                              ],
                            ),
                          ],
                          if (audioTags?.hasTags == true) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(
                              context,
                              context.l10n.audioTagsSectionHeader,
                            ),
                            AppCard.rows(
                              dividerIndent: 16,
                              children: [
                                if (audioTags?.title != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.titleSectionLabel,
                                    audioTags!.title!,
                                  ),
                                if (audioTags?.artist != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.artistLabel,
                                    audioTags!.artist!,
                                  ),
                                if (audioTags?.album != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.albumLabel,
                                    audioTags!.album!,
                                  ),
                                if (audioTags?.trackNumber != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.audioTrackLabel,
                                    audioTags!.trackNumber!,
                                  ),
                                if (audioTags?.year != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.yearLabel,
                                    audioTags!.year!,
                                  ),
                                if (audioTags?.genre != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.genreLabel,
                                    audioTags!.genre!,
                                  ),
                              ],
                            ),
                          ],
                          if (hasAudioProperties) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(
                              context,
                              context.l10n.audioFilePropertiesSectionHeader,
                            ),
                            AppCard.rows(
                              dividerIndent: 16,
                              children: [
                                if ((audioMetadata?.durationUs ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.durationLabel,
                                    formatClockDuration(
                                      Duration(
                                        microseconds: audioMetadata!.durationUs,
                                      ),
                                    ),
                                  ),
                                if (audioMetadata?.mime?.isNotEmpty == true)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.audioCodecLabel,
                                    _prettyCodec(audioMetadata!.mime!),
                                  ),
                                if ((audioBitrate ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.audioBitrateLabel,
                                    '${audioBitrateApprox ? '~' : ''}${_formatBitrate(audioBitrate!)}',
                                  ),
                                if ((audioMetadata?.sampleRate ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.sampleRateLabel,
                                    '${audioMetadata!.sampleRate} Hz',
                                  ),
                                if (audioTags?.bitDepth != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.bitDepthLabel,
                                    '${audioTags!.bitDepth}-bit',
                                  ),
                                if ((audioMetadata?.channels ?? 0) > 0)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.audioChannelsLabel,
                                    audioMetadata!.channels.toString(),
                                  ),
                              ],
                            ),
                          ],
                          if (metadata?.hasExifData == true) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(
                              context,
                              context.l10n.exifCameraDataSectionHeader,
                            ),
                            AppCard.rows(
                              dividerIndent: 16,
                              children: [
                                if (metadata?.cameraModel != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.cameraLabel,
                                    metadata!.cameraModel!,
                                  ),
                                if (metadata?.lensModel != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.lensLabel,
                                    metadata!.lensModel!,
                                  ),
                                if (metadata?.dateTaken != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.dateTakenLabel,
                                    metadata!.dateTaken!,
                                  ),
                                if (metadata?.exposureTime != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.shutterSpeedLabel,
                                    metadata!.exposureTime!,
                                  ),
                                if (metadata?.fNumber != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.apertureLabel,
                                    'f/${metadata!.fNumber}',
                                  ),
                                if (metadata?.iso != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.isoLabel,
                                    'ISO ${metadata!.iso}',
                                  ),
                                if (metadata?.focalLength != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.focalLengthLabel,
                                    metadata!.focalLength!,
                                  ),
                                if (metadata?.flash != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.flashLabel,
                                    metadata!.flash!,
                                  ),
                                if (metadata?.software != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.softwareLabel,
                                    metadata!.software!,
                                  ),
                                if (metadata?.gpsCoordinates != null)
                                  _buildInfoTile(
                                    context,
                                    context.l10n.gpsLocationLabel,
                                    metadata!.gpsCoordinates!,
                                  ),
                              ],
                            ),
                          ],
                          if (!widget.entry.isDir) ...[
                            const SizedBox(height: 16),
                            _buildSectionTitle(
                              context,
                              context.l10n.integrityChecksumSectionHeader,
                            ),
                            AppCard(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SHA-256',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (sha256 != null)
                                      Text(
                                        sha256,
                                        style: textTheme.bodySmall?.copyWith(
                                          fontFamily: 'monospace',
                                          fontSize: 11.5,
                                        ),
                                      )
                                    else if (calculatingSha256)
                                      Row(
                                        children: [
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            context.l10n.computingHashMessage,
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant
                                                      .withValues(alpha: 0.8),
                                                ),
                                          ),
                                        ],
                                      )
                                    else
                                      Text(
                                        '—',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
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

  String _formatBitrate(int bitsPerSecond) {
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(1)} Mbps';
    }
    if (bitsPerSecond >= 1000) {
      return '${(bitsPerSecond / 1000).round()} kbps';
    }
    return '$bitsPerSecond bps';
  }

  String _prettyCodec(String mime) => switch (mime.toLowerCase()) {
    'video/avc' => 'H.264 / AVC',
    'video/hevc' => 'H.265 / HEVC',
    'video/av01' => 'AV1',
    'video/x-vnd.on2.vp8' => 'VP8',
    'video/x-vnd.on2.vp9' => 'VP9',
    'video/mp4v-es' => 'MPEG-4 Part 2',
    'audio/mp4a-latm' => 'AAC',
    'audio/opus' => 'Opus',
    'audio/vorbis' => 'Vorbis',
    'audio/ac3' => 'Dolby Digital (AC-3)',
    'audio/eac3' => 'Dolby Digital Plus (E-AC-3)',
    'audio/mpeg' => 'MP3',
    'audio/flac' => 'FLAC',
    'audio/raw' => 'PCM (WAV)',
    'audio/alac' => 'ALAC',
    'audio/3gpp' => 'AMR-NB',
    'audio/amr-wb' => 'AMR-WB',
    'audio/vnd.dts' => 'DTS',
    'audio/vnd.dts.hd' => 'DTS-HD',
    'audio/g711-alaw' => 'G.711 A-law',
    'audio/g711-mlaw' => 'G.711 mu-law',
    _ => mime,
  };

  Future<void> _copyValue(
    BuildContext context,
    String label,
    String value,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.copiedSuffix(label),
      tone: AppBannerTone.success,
    );
  }

  Widget _buildInfoTile(
    BuildContext context,
    String label,
    String value, {
    bool copyable = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final row = Padding(
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
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 8),
            Icon(Icons.copy_rounded, size: 18, color: cs.onSurfaceVariant),
          ],
        ],
      ),
    );

    if (!copyable) return row;
    return InkWell(
      onTap: () => _copyValue(context, label, value),
      onLongPress: () => _copyValue(context, label, value),
      child: row,
    );
  }
}

// ── In-Memory Metadata & EXIF Parser ──────────────────────────────────────────

class ParsedMetadata {
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

  /// Bits per channel, e.g. `8-bit` (or palette index bits for GIF).
  final String? bitDepth;

  /// Colour model of the stored pixels, e.g. `RGB`, `RGBA`, `Grayscale`.
  final String? colorMode;

  /// Whether the image has an alpha/transparency channel; null when unknown.
  final bool? hasAlpha;

  /// Whether the image holds more than one frame; null when unknown.
  final bool? isAnimated;

  /// EXIF orientation, e.g. `Rotated 90° CW`.
  final String? orientation;

  /// Print density, e.g. `300 dpi`.
  final String? density;

  /// How the pixel data is stored, e.g. `Progressive`, `Lossless`.
  final String? encoding;

  const ParsedMetadata({
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
    this.bitDepth,
    this.colorMode,
    this.hasAlpha,
    this.isAnimated,
    this.orientation,
    this.density,
    this.encoding,
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
    if (width == null || height == null || width! <= 0 || height! <= 0)
      return null;
    final mp = (width! * height!) / 1000000.0;
    return mp >= 1.0 ? mp.toStringAsFixed(1) : mp.toStringAsFixed(2);
  }

  String? get aspectRatioString {
    if (width == null || height == null || width! <= 0 || height! <= 0)
      return null;
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final divisor = gcd(width!, height!);
    final rw = width! ~/ divisor;
    final rh = height! ~/ divisor;
    if (rw <= 21 && rh <= 21) return '$rw:$rh';
    return (width! / height!).toStringAsFixed(2);
  }
}

class MetadataParser {
  static ParsedMetadata parse({
    required String fileName,
    required bool isDir,
    Uint8List? headerBytes,
    double? cachedAspectRatio,
  }) {
    if (isDir || headerBytes == null || headerBytes.isEmpty) {
      return const ParsedMetadata();
    }

    // Trust the bytes over the extension: a JPEG saved as `.png` (common with
    // downloaded wallpapers) would otherwise be fed to the wrong parser and
    // show nothing. The extension is only a fallback for unrecognised headers.
    final kind = _sniffKind(headerBytes) ?? _kindFromName(fileName);
    switch (kind) {
      case 'jpeg':
        return _parseJpeg(headerBytes);
      case 'png':
        return _parsePng(headerBytes);
      case 'gif':
        return _parseGif(headerBytes);
      case 'webp':
        return _parseWebp(headerBytes);
      case 'bmff':
        return _parseIsoBmff(headerBytes);
    }

    return const ParsedMetadata();
  }

  static String? _sniffKind(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpeg';
    }
    if (b.length >= 4 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'png';
    }
    if (b.length >= 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return 'gif';
    }
    if (b.length >= 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    if (b.length >= 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') {
      return 'bmff';
    }
    return null;
  }

  static String? _kindFromName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpeg';
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.avif') || lower.endsWith('.heic')) return 'bmff';
    return null;
  }

  static ParsedMetadata _parseJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return const ParsedMetadata();
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
    int? precision;
    int? components;
    bool progressive = false;
    String? orientationRaw;
    String? xResolution;
    String? resolutionUnit;

    int offset = 2;
    while (offset < bytes.length - 4) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xD8 ||
          marker == 0xD9 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        offset += 2;
        continue;
      }

      if (offset + 4 > bytes.length) break;
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (length < 2 || offset + 2 + length > bytes.length) break;

      // SOF markers for resolution (SOF0, SOF1, SOF2)
      if ((marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7)) {
        if (offset + 9 <= bytes.length) {
          height = (bytes[offset + 5] << 8) | bytes[offset + 6];
          width = (bytes[offset + 7] << 8) | bytes[offset + 8];
          precision = bytes[offset + 4];
          if (offset + 10 <= bytes.length) components = bytes[offset + 9];
          progressive = marker == 0xC2 || marker == 0xC6;
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
          orientationRaw = exif['orientation'];
          xResolution = exif['xResolution'];
          resolutionUnit = exif['resolutionUnit'];
        }
      }

      offset += 2 + length;
    }

    String? fullCamera;
    if (make != null && model != null) {
      fullCamera = model.toLowerCase().contains(make.toLowerCase())
          ? model
          : '$make $model';
    } else {
      fullCamera = model ?? make;
    }

    return ParsedMetadata(
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
      bitDepth: precision != null && precision > 0 ? '$precision-bit' : null,
      colorMode: switch (components) {
        1 => 'Grayscale',
        3 => 'YCbCr',
        4 => 'CMYK',
        _ => null,
      },
      isAnimated: false,
      orientation: _orientationName(int.tryParse(orientationRaw ?? '')),
      density: _densityString(xResolution, resolutionUnit),
      encoding: width != null ? (progressive ? 'Progressive' : 'Baseline') : null,
    );
  }

  static String? _orientationName(int? value) => switch (value) {
    1 => 'Normal',
    2 => 'Flipped horizontally',
    3 => 'Rotated 180°',
    4 => 'Flipped vertically',
    5 => 'Transposed',
    6 => 'Rotated 90° CW',
    7 => 'Transverse',
    8 => 'Rotated 90° CCW',
    _ => null,
  };

  /// EXIF ResolutionUnit: 2 = inch (the default when absent), 3 = centimetre,
  /// 1 = no absolute unit (then the number means nothing, so nothing is shown).
  static String? _densityString(String? xRes, String? unit) {
    final value = double.tryParse(xRes ?? '');
    if (value == null || value <= 0) return null;
    final u = int.tryParse(unit ?? '') ?? 2;
    if (u == 1) return null;
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return u == 3 ? '$text dpcm' : '$text dpi';
  }

  static Map<String, String> _parseTiffExif(Uint8List tiff) {
    final result = <String, String>{};
    if (tiff.length < 8) return result;

    final isLe = tiff[0] == 0x49 && tiff[1] == 0x49; // 'II' vs 'MM'
    int readU16(int o) {
      if (o < 0 || o + 2 > tiff.length) return 0;
      return isLe
          ? (tiff[o] | (tiff[o + 1] << 8))
          : ((tiff[o] << 8) | tiff[o + 1]);
    }

    int readU32(int o) {
      if (o < 0 || o + 4 > tiff.length) return 0;
      return isLe
          ? (tiff[o] |
                (tiff[o + 1] << 8) |
                (tiff[o + 2] << 16) |
                (tiff[o + 3] << 24))
          : ((tiff[o] << 24) |
                (tiff[o + 1] << 16) |
                (tiff[o + 2] << 8) |
                tiff[o + 3]);
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

        // IFD0-only tags. SHORT values sit in the first two bytes of the
        // value field, so read them as U16 (a U32 read is wrong when the
        // data is big-endian).
        if (!isSubIfd && !isGps) {
          if (tag == 0x0112) result['orientation'] = '${readU16(p + 8)}';
          if (tag == 0x011A) {
            final xr = readRational(valOffset);
            if (xr != null) result['xResolution'] = '$xr';
          }
          if (tag == 0x0128) result['resolutionUnit'] = '${readU16(p + 8)}';
        }

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
                result['exposureTime'] = num < den
                    ? '1/${(den / num).round()}s'
                    : '${num / den}s';
              }
            }
          }
          if (tag == 0x920A) {
            final fl = readRational(valOffset);
            if (fl != null)
              result['focalLength'] = '${fl.toStringAsFixed(1)} mm';
          }
        }

        p += 12;
      }
    }

    readIfd(ifd0Offset, false, false, 0);
    return result;
  }

  static ParsedMetadata _parsePng(Uint8List bytes) {
    if (bytes.length < 24 ||
        bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47) {
      return const ParsedMetadata();
    }
    int u32(int o) =>
        (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];

    final w = u32(16);
    final h = u32(20);

    String? bitDepth;
    String? colorMode;
    bool? hasAlpha;
    String? encoding;
    if (bytes.length >= 29) {
      bitDepth = '${bytes[24]}-bit';
      final (String? mode, bool? alpha) = switch (bytes[25]) {
        0 => ('Grayscale', false),
        2 => ('RGB', false),
        3 => ('Indexed', false),
        4 => ('Grayscale + Alpha', true),
        6 => ('RGBA', true),
        _ => (null, null),
      };
      colorMode = mode;
      hasAlpha = alpha;
      encoding = bytes[28] == 1 ? 'Interlaced (Adam7)' : 'Non-interlaced';
    }

    // Walk the chunks that precede the pixel data: tRNS adds transparency to
    // any colour type, and acTL marks an animated PNG (APNG).
    var animated = false;
    var off = 8;
    while (off + 8 <= bytes.length) {
      final len = u32(off);
      final type = String.fromCharCodes(bytes.sublist(off + 4, off + 8));
      if (type == 'IDAT' || type == 'IEND') break;
      if (type == 'tRNS') hasAlpha = true;
      if (type == 'acTL') animated = true;
      if (off + 12 + len > bytes.length) break;
      off += 12 + len;
    }

    return ParsedMetadata(
      width: w,
      height: h,
      mimeType: 'PNG Image',
      bitDepth: bitDepth,
      colorMode: colorMode,
      hasAlpha: hasAlpha,
      isAnimated: animated,
      encoding: encoding,
    );
  }

  static ParsedMetadata _parseGif(Uint8List bytes) {
    if (bytes.length < 13 ||
        bytes[0] != 0x47 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46) {
      return const ParsedMetadata();
    }
    final w = bytes[6] | (bytes[7] << 8);
    final h = bytes[8] | (bytes[9] << 8);
    final version = String.fromCharCodes(bytes.sublist(0, 6));

    final packed = bytes[10];
    final hasPalette = (packed & 0x80) != 0;
    final paletteBits = (packed & 0x07) + 1;
    final paletteBytes = hasPalette ? 3 * (1 << paletteBits) : 0;

    // Walk the blocks to count frames and spot a transparent colour. Only the
    // start of the file is available, so a long animation may be cut short.
    int skipSubBlocks(int p) {
      while (p < bytes.length) {
        final n = bytes[p];
        p += 1 + n;
        if (n == 0) return p;
      }
      return bytes.length + 1;
    }

    var pos = 13 + paletteBytes;
    var frames = 0;
    var transparent = false;
    var complete = false;
    while (pos < bytes.length) {
      final block = bytes[pos];
      if (block == 0x3B) {
        complete = true;
        break;
      }
      if (block == 0x21) {
        if (pos + 2 > bytes.length) break;
        // Graphic Control Extension: bit 0 of the packed byte = transparency.
        if (bytes[pos + 1] == 0xF9 &&
            pos + 4 <= bytes.length &&
            (bytes[pos + 3] & 0x01) != 0) {
          transparent = true;
        }
        pos = skipSubBlocks(pos + 2);
      } else if (block == 0x2C) {
        if (pos + 10 > bytes.length) break;
        frames++;
        final imagePacked = bytes[pos + 9];
        final localPalette = (imagePacked & 0x80) != 0
            ? 3 * (1 << ((imagePacked & 0x07) + 1))
            : 0;
        pos += 10 + localPalette + 1; // +1: LZW minimum code size
        if (pos >= bytes.length) break;
        pos = skipSubBlocks(pos);
      } else {
        break;
      }
    }

    return ParsedMetadata(
      width: w,
      height: h,
      mimeType: 'GIF Image',
      bitDepth: hasPalette ? '$paletteBits-bit' : null,
      colorMode: hasPalette ? 'Indexed' : null,
      hasAlpha: transparent ? true : (complete ? false : null),
      isAnimated: frames > 1 ? true : (complete ? false : null),
      encoding: version,
    );
  }

  static ParsedMetadata _parseWebp(Uint8List bytes) {
    if (bytes.length < 30 ||
        bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46 ||
        bytes[8] != 0x57 ||
        bytes[9] != 0x45 ||
        bytes[10] != 0x42 ||
        bytes[11] != 0x50) {
      return const ParsedMetadata();
    }
    int u32le(int o) =>
        bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16) | (bytes[o + 3] << 24);

    final fourcc = String.fromCharCodes(bytes.sublist(12, 16));
    int? w;
    int? h;
    bool? alpha;
    bool? animated;
    String? encoding;

    if (fourcc == 'VP8 ') {
      w = ((bytes[27] & 0x3F) << 8) | bytes[26];
      h = ((bytes[29] & 0x3F) << 8) | bytes[28];
      alpha = false;
      animated = false;
      encoding = 'Lossy';
    } else if (fourcc == 'VP8L') {
      // Lossless: signature 0x2F, then 14+14 bits of (size - 1) and an alpha
      // flag. This variant had no dimensions before.
      if (bytes[20] == 0x2F) {
        final bits = u32le(21);
        w = (bits & 0x3FFF) + 1;
        h = ((bits >> 14) & 0x3FFF) + 1;
        alpha = ((bits >> 28) & 1) == 1;
      }
      animated = false;
      encoding = 'Lossless';
    } else if (fourcc == 'VP8X') {
      final flags = bytes[20];
      alpha = (flags & 0x10) != 0;
      animated = (flags & 0x02) != 0;
      w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
      if (!animated) {
        var off = 30;
        while (off + 8 <= bytes.length) {
          final id = String.fromCharCodes(bytes.sublist(off, off + 4));
          final size = u32le(off + 4);
          if (id == 'VP8 ') {
            encoding = 'Lossy';
            break;
          }
          if (id == 'VP8L') {
            encoding = 'Lossless';
            break;
          }
          off += 8 + size + (size & 1);
        }
      }
    } else {
      return const ParsedMetadata();
    }

    return ParsedMetadata(
      width: w,
      height: h,
      mimeType: 'WebP Image',
      bitDepth: '8-bit',
      colorMode: alpha == null ? null : (alpha ? 'RGBA' : 'RGB'),
      hasAlpha: alpha,
      isAnimated: animated,
      encoding: encoding,
    );
  }

  /// AVIF and HEIC are ISO-BMFF files: the pixel size sits in `ispe` boxes and
  /// the channel bit depth in `pixi`. A HEIC image is often a grid of tiles,
  /// each with its own `ispe`, so the largest one is the full picture.
  static ParsedMetadata _parseIsoBmff(Uint8List bytes) {
    if (bytes.length < 16 ||
        String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
      return const ParsedMetadata();
    }
    int u32(int o) =>
        (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];

    final ftypEnd = min(bytes.length, max(16, u32(0)));
    final brands = String.fromCharCodes(bytes.sublist(8, ftypEnd));
    final isAvif = brands.contains('avif') || brands.contains('avis');

    var bestW = 0;
    var bestH = 0;
    var from = 0;
    while (true) {
      final idx = _indexOfBytes(bytes, const [0x69, 0x73, 0x70, 0x65], from);
      if (idx < 0 || idx + 16 > bytes.length) break;
      final w = u32(idx + 8);
      final h = u32(idx + 12);
      if (w * h > bestW * bestH) {
        bestW = w;
        bestH = h;
      }
      from = idx + 4;
    }

    String? bitDepth;
    String? colorMode;
    final pixi = _indexOfBytes(bytes, const [0x70, 0x69, 0x78, 0x69], 0);
    if (pixi >= 0 && pixi + 10 <= bytes.length) {
      final channels = bytes[pixi + 8];
      final bits = bytes[pixi + 9];
      if (bits >= 1 && bits <= 16) bitDepth = '$bits-bit';
      if (channels == 1) colorMode = 'Grayscale';
      if (channels >= 3) colorMode = 'RGB';
    }

    return ParsedMetadata(
      width: bestW > 0 ? bestW : null,
      height: bestH > 0 ? bestH : null,
      mimeType: isAvif ? 'AVIF Image' : 'HEIC Image',
      bitDepth: bitDepth,
      colorMode: colorMode,
    );
  }

  static int _indexOfBytes(Uint8List b, List<int> pattern, int from) {
    for (var i = from; i + pattern.length <= b.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (b[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
