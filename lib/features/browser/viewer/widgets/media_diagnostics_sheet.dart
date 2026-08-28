import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import '../native_video_controller.dart';

/// Transparent glassmorphic dialog displaying real-time video diagnostics,
/// hardware vs software decoder status, framerate, dropped frames, buffer health,
/// and pipeline failure indicators.
class MediaDiagnosticsDialog extends StatelessWidget {
  final String fileName;
  final NativeVideoController controller;
  final double playbackSpeed;

  const MediaDiagnosticsDialog({
    super.key,
    required this.fileName,
    required this.controller,
    required this.playbackSpeed,
  });

  Future<void> _copyDiagnostics(
    BuildContext context,
    NativeVideoValue val,
    MediaDiagnosticsInfo diag,
  ) async {
    final text = '''
=== VAULTEXPLORER MEDIA DIAGNOSTICS ===
File: $fileName
Volume ID: ${diag.volId}
Path: ${diag.filePath}

-- VIDEO DECODER --
Decoder Name: ${diag.videoDecoderName}
Hardware Accelerated: ${diag.isVideoHardwareAccelerated ? "YES (HW)" : "NO (SW Software Fallback)"}
Resolution: ${val.size.width.toInt()}x${val.size.height.toInt()}
Aspect Ratio: ${val.size.width > 0 ? val.aspectRatio.toStringAsFixed(3) : "Unknown"}
Framerate: ${diag.frameRate > 0 ? "${diag.frameRate.toStringAsFixed(2)} fps" : "Unknown"}
Video MIME: ${diag.videoMimeType.isNotEmpty ? diag.videoMimeType : "Unknown"}
Color Format: ${diag.colorInfo}
Decoder Init Time: ${diag.decoderInitTimeMs} ms
Dropped Frames: ${diag.droppedFrames}

-- AUDIO DECODER --
Audio Decoder: ${diag.audioDecoderName}
Audio HW Accel: ${diag.isAudioHardwareAccelerated ? "YES" : "NO"}
Audio MIME: ${diag.audioMimeType.isNotEmpty ? diag.audioMimeType : "Unknown"}

-- PIPELINE & BUFFER --
State: ${_stateLabel(context, val)}
Position: ${_formatDuration(val.position)}
Duration: ${_formatDuration(val.duration)}
Buffered: ${(diag.bufferedMs / 1000.0).toStringAsFixed(1)} s
Playback Speed: ${playbackSpeed.toStringAsFixed(2)}x
Error: ${val.hasError ? val.errorDescription : "None"}
Engine: Media3 ExoPlayer (Direct JNI C++ Stream)
=======================================
''';

    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.diagnosticsCopiedToClipboard),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _stateLabel(BuildContext context, NativeVideoValue value) {
    if (value.hasError) return context.l10n.diagnosticsErrorLabel;
    if (value.isBuffering) return context.l10n.diagnosticsStateBuffering;
    return value.isPlaying
        ? context.l10n.diagnosticsStatePlaying
        : context.l10n.diagnosticsStatePaused;
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '0:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final ms = d.inMilliseconds % 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${(ms / 100).floor()}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: ValueListenableBuilder<NativeVideoValue>(
              valueListenable: controller,
              builder: (context, videoVal, _) {
                return ValueListenableBuilder<MediaDiagnosticsInfo>(
                  valueListenable: controller.diagnosticsNotifier,
                  builder: (context, diagInfo, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(context, cs, videoVal),
                        const Divider(height: 1, color: Colors.white12),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildBadgesBar(context, cs, videoVal, diagInfo),
                                const SizedBox(height: 16),
                                if (videoVal.hasError) ...[
                                  _buildErrorAlert(cs, videoVal),
                                  const SizedBox(height: 16),
                                ],
                                _buildSectionHeader(cs, context.l10n.videoDecoderHardwareSection),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.decoderNameLabel,
                                  diagInfo.videoDecoderName,
                                  highlight: true,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.accelerationLabel,
                                  diagInfo.isVideoHardwareAccelerated
                                      ? context.l10n.hardwareGpuDirect
                                      : context.l10n.softwareCpuFallback,
                                  valueColor: diagInfo.isVideoHardwareAccelerated
                                      ? Colors.greenAccent
                                      : Colors.orangeAccent,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.resolutionLabel,
                                  videoVal.size.width > 0
                                      ? '${videoVal.size.width.toInt()} × ${videoVal.size.height.toInt()} (${videoVal.aspectRatio.toStringAsFixed(2)}:1)'
                                      : context.l10n.unknownValue,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.framerateLabel,
                                  diagInfo.frameRate > 0
                                      ? '${diagInfo.frameRate.toStringAsFixed(2)} fps'
                                      : context.l10n.variableOrUnknown,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.videoCodecLabel,
                                  diagInfo.videoMimeType.isNotEmpty
                                      ? diagInfo.videoMimeType
                                      : context.l10n.autoDetected,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.colorFormatLabel,
                                  diagInfo.colorInfo,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.initLatencyLabel,
                                  '${diagInfo.decoderInitTimeMs} ms',
                                ),

                                const SizedBox(height: 16),
                                _buildSectionHeader(cs, context.l10n.audioEngineSection),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.audioDecoderLabel,
                                  diagInfo.audioDecoderName,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.audioCodecLabel,
                                  diagInfo.audioMimeType.isNotEmpty
                                      ? diagInfo.audioMimeType
                                      : context.l10n.autoDetected,
                                ),

                                const SizedBox(height: 16),
                                _buildSectionHeader(cs, context.l10n.pipelineHealthSection),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.playbackStateLabel,
                                  _stateLabel(context, videoVal),
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.decryptedBufferLabel,
                                  context.l10n.secondsCached((diagInfo.bufferedMs / 1000.0).toStringAsFixed(1)),
                                  valueColor: diagInfo.bufferedMs > 2000
                                      ? Colors.greenAccent
                                      : Colors.amberAccent,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.droppedFramesLabel,
                                  context.l10n.nFrames(diagInfo.droppedFrames),
                                  valueColor: diagInfo.droppedFrames == 0
                                      ? Colors.greenAccent
                                      : Colors.orangeAccent,
                                ),
                                _buildDetailRow(
                                  cs,
                                  context.l10n.sourceStorageLabel,
                                  context.l10n.directJniStreamSource(diagInfo.volId),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white12),
                        _buildFooterActions(context, cs, videoVal, diagInfo),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs, NativeVideoValue value) {
    final statusColor = value.hasError
        ? Colors.redAccent
        : (value.isBuffering
            ? Colors.amberAccent
            : (value.isPlaying ? Colors.greenAccent : Colors.white70));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.mediaDiagnosticsTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesBar(
    BuildContext context,
    ColorScheme cs,
    NativeVideoValue val,
    MediaDiagnosticsInfo diag,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildPill(
          label: diag.isVideoHardwareAccelerated
              ? context.l10n.hwAcceleratedBadge
              : context.l10n.swDecoderBadge,
          icon: diag.isVideoHardwareAccelerated
              ? Icons.memory_rounded
              : Icons.computer_rounded,
          color: diag.isVideoHardwareAccelerated ? Colors.greenAccent : Colors.amberAccent,
        ),
        if (diag.frameRate > 0)
          _buildPill(
            label: '${diag.frameRate.toStringAsFixed(1)} FPS',
            icon: Icons.speed_rounded,
            color: cs.primary,
          ),
        _buildPill(
          label: diag.colorInfo,
          icon: Icons.hdr_on_rounded,
          color: diag.colorInfo != 'SDR' ? Colors.purpleAccent : Colors.white60,
        ),
        if (val.size.width > 0)
          _buildPill(
            label: '${val.size.width.toInt()}p',
            icon: Icons.aspect_ratio_rounded,
            color: Colors.lightBlueAccent,
          ),
      ],
    );
  }

  Widget _buildPill({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorAlert(ColorScheme cs, NativeVideoValue value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.errorDescription,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ColorScheme cs, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: cs.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    ColorScheme cs,
    String label,
    String value, {
    bool highlight = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? (highlight ? Colors.white : Colors.white70),
                fontSize: 12,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                fontFamily: highlight ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(
    BuildContext context,
    ColorScheme cs,
    NativeVideoValue value,
    MediaDiagnosticsInfo diag,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(context.l10n.copyDiagnosticsButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _copyDiagnostics(context, value, diag),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            child: Text(context.l10n.closeButton),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Backward-compatibility alias for [MediaDiagnosticsDialog].
typedef MediaDiagnosticsSheet = MediaDiagnosticsDialog;