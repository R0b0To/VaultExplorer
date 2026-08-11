// File: lib/features/browser/viewer/widgets/media_diagnostics_sheet.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import '../native_video_controller.dart';

/// Floating, non-intrusive HUD overlay displaying real-time video diagnostics,
/// hardware vs software decoder status, framerate, dropped frames, buffer health,
/// and pipeline failure indicators without blocking player gesture interactions.
class MediaDiagnosticsHUD extends StatefulWidget {
  final String fileName;
  final NativeVideoController controller;
  final double playbackSpeed;
  final VoidCallback? onClose;

  const MediaDiagnosticsHUD({
    super.key,
    required this.fileName,
    required this.controller,
    required this.playbackSpeed,
    this.onClose,
  });

  @override
  State<MediaDiagnosticsHUD> createState() => _MediaDiagnosticsHUDState();
}

class _MediaDiagnosticsHUDState extends State<MediaDiagnosticsHUD> {
  Timer? _periodicDiagnosticsTimer;

  @override
  void initState() {
    super.initState();
    // Poll diagnostics periodically while the HUD is visible
    _periodicDiagnosticsTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) {
        if (mounted && !widget.controller.isDisposed) {
          widget.controller.fetchDiagnostics();
        }
      },
    );
  }

  @override
  void dispose() {
    _periodicDiagnosticsTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyDiagnostics(
    BuildContext context,
    NativeVideoValue val,
    MediaDiagnosticsInfo diag,
  ) async {
    final text = '''
=== VAULTEXPLORER MEDIA DIAGNOSTICS ===
File: ${widget.fileName}
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
Playback Speed: ${widget.playbackSpeed.toStringAsFixed(2)}x
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

    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 320,
            constraints: const BoxConstraints(maxHeight: 440),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ValueListenableBuilder<NativeVideoValue>(
              valueListenable: widget.controller,
              builder: (context, videoVal, _) {
                return ValueListenableBuilder<MediaDiagnosticsInfo>(
                  valueListenable: widget.controller.diagnosticsNotifier,
                  builder: (context, diagInfo, _) {
                    final statusColor = videoVal.hasError
                        ? Colors.redAccent
                        : (videoVal.isBuffering
                            ? Colors.amberAccent
                            : (videoVal.isPlaying ? Colors.greenAccent : Colors.white70));

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // HUD Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.6),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Diagnostics HUD',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                tooltip: 'Copy Diagnostics',
                                onPressed: () => _copyDiagnostics(context, videoVal, diagInfo),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                tooltip: 'Close HUD',
                                onPressed: widget.onClose ?? () {},
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white12),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildBadgesRow(cs, videoVal, diagInfo),
                                const SizedBox(height: 10),
                                _buildCompactRow('Decoder', diagInfo.videoDecoderName, highlight: true),
                                _buildCompactRow(
                                  'Acceleration',
                                  diagInfo.isVideoHardwareAccelerated ? 'Hardware (GPU)' : 'Software (CPU)',
                                  valueColor: diagInfo.isVideoHardwareAccelerated
                                      ? Colors.greenAccent
                                      : Colors.orangeAccent,
                                ),
                                _buildCompactRow(
                                  'Resolution',
                                  videoVal.size.width > 0
                                      ? '${videoVal.size.width.toInt()}×${videoVal.size.height.toInt()} (${videoVal.aspectRatio.toStringAsFixed(2)}:1)'
                                      : 'Unknown',
                                ),
                                _buildCompactRow(
                                  'Framerate',
                                  diagInfo.frameRate > 0 ? '${diagInfo.frameRate.toStringAsFixed(1)} fps' : 'Auto',
                                ),
                                _buildCompactRow('Codec', diagInfo.videoMimeType.isNotEmpty ? diagInfo.videoMimeType : 'Auto'),
                                _buildCompactRow('Color Space', diagInfo.colorInfo),
                                _buildCompactRow('Init Latency', '${diagInfo.decoderInitTimeMs} ms'),
                                const SizedBox(height: 8),
                                const Divider(height: 1, color: Colors.white12),
                                const SizedBox(height: 8),
                                _buildCompactRow('Audio Decoder', diagInfo.audioDecoderName),
                                _buildCompactRow('Audio Codec', diagInfo.audioMimeType.isNotEmpty ? diagInfo.audioMimeType : 'Auto'),
                                const SizedBox(height: 8),
                                const Divider(height: 1, color: Colors.white12),
                                const SizedBox(height: 8),
                                _buildCompactRow('Buffer Health', '${(diagInfo.bufferedMs / 1000.0).toStringAsFixed(1)} s cached'),
                                _buildCompactRow(
                                  'Dropped Frames',
                                  '${diagInfo.droppedFrames} frames',
                                  valueColor: diagInfo.droppedFrames == 0 ? Colors.greenAccent : Colors.orangeAccent,
                                ),
                                _buildCompactRow('State', _stateLabel(context, videoVal)),
                              ],
                            ),
                          ),
                        ),
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

  Widget _buildBadgesRow(ColorScheme cs, NativeVideoValue val, MediaDiagnosticsInfo diag) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _buildPill(
          label: diag.isVideoHardwareAccelerated ? 'HW ACCEL' : 'SW CPU',
          color: diag.isVideoHardwareAccelerated ? Colors.greenAccent : Colors.amberAccent,
        ),
        if (diag.frameRate > 0)
          _buildPill(
            label: '${diag.frameRate.toStringAsFixed(0)} FPS',
            color: cs.primary,
          ),
        _buildPill(
          label: diag.colorInfo,
          color: diag.colorInfo.contains('HDR') ? Colors.purpleAccent : Colors.white70,
        ),
        if (val.size.width > 0)
          _buildPill(
            label: '${val.size.height.toInt()}p',
            color: Colors.lightBlueAccent,
          ),
      ],
    );
  }

  Widget _buildPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCompactRow(String label, String value, {bool highlight = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? (highlight ? Colors.white : Colors.white70),
                fontSize: 11,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                fontFamily: highlight ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Backward compatibility aliases
typedef MediaDiagnosticsDialog = MediaDiagnosticsHUD;
typedef MediaDiagnosticsSheet = MediaDiagnosticsHUD;