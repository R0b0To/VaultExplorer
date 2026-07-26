// File: lib/features/browser/viewer/widgets/media_diagnostics_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../native_ffmpeg_controller.dart';

/// Debug/"stats for nerds" overlay for the video player: shows live playback
/// state plus codec-level info read from the container by the native side.
/// Opened via a long-press on the advanced settings button.
class MediaDiagnosticsSheet extends StatefulWidget {
  final String fileName;
  final NativeFFmpegController controller;
  final double playbackSpeed;

  const MediaDiagnosticsSheet({
    super.key,
    required this.fileName,
    required this.controller,
    required this.playbackSpeed,
  });

  @override
  State<MediaDiagnosticsSheet> createState() => _MediaDiagnosticsSheetState();
}

class _MediaDiagnosticsSheetState extends State<MediaDiagnosticsSheet> {
  late final Future<Map<String, dynamic>> _diagnosticsFuture;

  @override
  void initState() {
    super.initState();
    _diagnosticsFuture = widget.controller.getDiagnostics();
  }

  Future<void> _copyDiagnostics() async {
    final diag = await _diagnosticsFuture;
    final value = widget.controller.value;
    final lines = <String>[
      'File: ${widget.fileName}',
      'Resolution: ${_formatResolution(value.size.width, value.size.height)}',
      'Duration: ${_formatDuration(value.duration)}',
      'Playback Speed: ${widget.playbackSpeed.toStringAsFixed(2)}x',
      if (diag['videoCodec'] != null) 'Video Codec: ${_codecLabel(diag['videoCodec'] as String?)}',
      if (diag['frameRate'] != null) 'Frame Rate: ${_formatFrameRate(diag['frameRate'])}',
      if (diag['measuredFps'] != null) 'Measured FPS: ${_formatFrameRate(diag['measuredFps'])}',
      if (diag['videoBitrate'] != null || diag['containerBitrate'] != null)
        'Video Bitrate: ${_formatBitrate(diag['videoBitrate'] ?? diag['containerBitrate'])}',
      if (diag['rotationDegrees'] != null) 'Rotation: ${diag['rotationDegrees']}°',
      if (diag['audioCodec'] != null) 'Audio Codec: ${_codecLabel(diag['audioCodec'] as String?)}',
      if (diag['audioSampleRate'] != null) 'Sample Rate: ${diag['audioSampleRate']} Hz',
      if (diag['audioChannels'] != null) 'Channels: ${_formatChannels(diag['audioChannels'])}',
      if (diag['audioBitrate'] != null) 'Audio Bitrate: ${_formatBitrate(diag['audioBitrate'])}',
      if (diag['containerFormat'] != null || diag['containerMimeType'] != null)
        'Container: ${diag['containerFormat'] ?? diag['containerMimeType']}',
      if (diag['framesDecoded'] != null) 'Frames Decoded: ${diag['framesDecoded']}',
      if (diag['framesRendered'] != null) 'Frames Rendered: ${diag['framesRendered']}',
      'Engine: FFmpeg (native)',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 12, top: 4, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(cs, textTheme),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionLabel(cs, 'Playback'),
                        ValueListenableBuilder<NativeFFmpegValue>(
                          valueListenable: widget.controller,
                          builder: (context, value, _) {
                            return Column(
                              children: [
                                _buildStatRow(
                                  cs,
                                  'State',
                                  value.hasError
                                      ? 'Error'
                                      : value.isPlaying
                                          ? 'Playing'
                                          : 'Paused',
                                ),
                                _buildStatRow(cs, 'Resolution', _formatResolution(value.size.width, value.size.height)),
                                _buildStatRow(
                                  cs,
                                  'Aspect Ratio',
                                  value.size.width > 0 ? value.aspectRatio.toStringAsFixed(3) : 'Unknown',
                                ),
                                _buildStatRow(cs, 'Position', _formatDuration(value.position)),
                                _buildStatRow(cs, 'Duration', _formatDuration(value.duration)),
                                _buildStatRow(cs, 'Playback Speed', '${widget.playbackSpeed.toStringAsFixed(2)}x'),
                                if (value.hasError)
                                  _buildStatRow(cs, 'Error', value.errorDescription),
                              ],
                            );
                          },
                        ),
                        FutureBuilder<Map<String, dynamic>>(
                          future: _diagnosticsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState != ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            final diag = snapshot.data ?? const {};
                            final hasVideoTrack = diag['videoCodec'] != null;
                            final hasAudioTrack = diag['audioCodec'] != null;
                            final hasContainerInfo =
                                diag['containerFormat'] != null || diag['containerMimeType'] != null;
                            if (!hasVideoTrack && !hasAudioTrack && !hasContainerInfo) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Track details unavailable for this file.',
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                                ),
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasVideoTrack) ...[
                                  _buildSectionLabel(cs, 'Video Track'),
                                  _buildStatRow(cs, 'Codec', _codecLabel(diag['videoCodec'] as String?)),
                                  _buildStatRow(cs, 'Frame Rate', _formatFrameRate(diag['frameRate'])),
                                  // Measured against the container's declared
                                  // rate above -- this is the actual render
                                  // rate coming off the native decode/paint
                                  // pipeline right now, so a gap between the
                                  // two is real dropped-frame/pacing
                                  // behavior, not measurement noise.
                                  if (diag['measuredFps'] != null)
                                    _buildStatRow(cs, 'Measured FPS', _formatFrameRate(diag['measuredFps'])),
                                  _buildStatRow(
                                    cs,
                                    'Bitrate',
                                    _formatBitrate(diag['videoBitrate'] ?? diag['containerBitrate']),
                                  ),
                                  if (diag['rotationDegrees'] != null)
                                    _buildStatRow(cs, 'Rotation', '${diag['rotationDegrees']}°'),
                                  if (diag['framesDecoded'] != null)
                                    _buildStatRow(cs, 'Frames Decoded', '${diag['framesDecoded']}'),
                                  if (diag['framesRendered'] != null)
                                    _buildStatRow(cs, 'Frames Rendered', '${diag['framesRendered']}'),
                                ],
                                if (hasAudioTrack) ...[
                                  _buildSectionLabel(cs, 'Audio Track'),
                                  _buildStatRow(cs, 'Codec', _codecLabel(diag['audioCodec'] as String?)),
                                  _buildStatRow(
                                    cs,
                                    'Sample Rate',
                                    diag['audioSampleRate'] != null ? '${diag['audioSampleRate']} Hz' : 'Unknown',
                                  ),
                                  _buildStatRow(cs, 'Channels', _formatChannels(diag['audioChannels'])),
                                  _buildStatRow(cs, 'Bitrate', _formatBitrate(diag['audioBitrate'])),
                                ],
                                _buildSectionLabel(cs, 'Container'),
                                _buildStatRow(
                                  cs,
                                  'Format',
                                  (diag['containerFormat'] as String?) ?? (diag['containerMimeType'] as String?) ?? 'Unknown',
                                ),
                                _buildStatRow(cs, 'Engine', 'FFmpeg (native)'),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, TextTheme textTheme) {
    return Row(
      children: [
        const SizedBox(width: 8),
        Icon(Icons.query_stats_rounded, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Diagnostics',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: 'Copy diagnostics',
          icon: Icon(Icons.copy_rounded, size: 20, color: cs.onSurfaceVariant),
          onPressed: _copyDiagnostics,
        ),
        IconButton(
          tooltip: 'Close',
          icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(ColorScheme cs, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: cs.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildStatRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

String _formatResolution(double width, double height) {
  if (width <= 0 || height <= 0) return 'Unknown';
  return '${width.toInt()} × ${height.toInt()}';
}

String _formatDuration(Duration d) {
  if (d.isNegative) return '--:--';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  return '$minutes:$seconds';
}

String _formatFrameRate(dynamic raw) {
  if (raw is! num || raw <= 0) return 'Unknown';
  final fps = raw.toDouble();
  return fps == fps.roundToDouble() ? '${fps.toInt()} fps' : '${fps.toStringAsFixed(2)} fps';
}

String _formatBitrate(dynamic raw) {
  if (raw is! num || raw <= 0) return 'Unknown';
  final bits = raw.toDouble();
  final mbps = bits / 1000000;
  if (mbps >= 1) return '${mbps.toStringAsFixed(2)} Mbps';
  return '${(bits / 1000).toStringAsFixed(0)} kbps';
}

String _formatChannels(dynamic raw) {
  if (raw is! int) return 'Unknown';
  switch (raw) {
    case 1:
      return 'Mono';
    case 2:
      return 'Stereo';
    default:
      return '$raw channels';
  }
}

// Two naming schemes land here: Android's MediaExtractor reports MIME
// strings (video/avc, audio/mp4a-latm...) from the fallback
// collectDiagnostics() pass, while the native FFmpeg diagnostics call
// reports avcodec_get_name()'s short codec names (h264, aac...) --
// both map to the same handful of human-readable labels, so both sets
// of keys live in one table rather than needing two lookup paths.
const Map<String, String> _codecLabels = {
  'video/avc': 'H.264 (AVC)',
  'h264': 'H.264 (AVC)',
  'video/hevc': 'H.265 (HEVC)',
  'hevc': 'H.265 (HEVC)',
  'video/x-vnd.on2.vp8': 'VP8',
  'vp8': 'VP8',
  'video/x-vnd.on2.vp9': 'VP9',
  'vp9': 'VP9',
  'video/av01': 'AV1',
  'av1': 'AV1',
  'video/mp4v-es': 'MPEG-4',
  'mpeg4': 'MPEG-4',
  'video/3gpp': 'H.263',
  'h263': 'H.263',
  'audio/mp4a-latm': 'AAC',
  'aac': 'AAC',
  'audio/mpeg': 'MP3',
  'mp3': 'MP3',
  'mp3float': 'MP3',
  'audio/vorbis': 'Vorbis',
  'vorbis': 'Vorbis',
  'audio/opus': 'Opus',
  'opus': 'Opus',
  'audio/flac': 'FLAC',
  'flac': 'FLAC',
  'audio/raw': 'PCM',
  'pcm_s16le': 'PCM',
  'pcm_s24le': 'PCM',
  'pcm_u8': 'PCM',
  'pcm_f32le': 'PCM',
};

String _codecLabel(String? mime) {
  if (mime == null) return 'Unknown';
  return _codecLabels[mime] ?? mime;
}
