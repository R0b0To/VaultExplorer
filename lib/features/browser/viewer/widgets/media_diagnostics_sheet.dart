// File: lib/features/browser/viewer/widgets/media_diagnostics_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../native_video_controller.dart';

class MediaDiagnosticsSheet extends StatelessWidget {
  final String fileName;
  final NativeVideoController controller;
  final double playbackSpeed;

  const MediaDiagnosticsSheet({
    super.key,
    required this.fileName,
    required this.controller,
    required this.playbackSpeed,
  });

  Future<void> _copyDiagnostics(BuildContext context) async {
    final value = controller.value;
    final lines = <String>[
      'File: $fileName',
      'State: ${_stateLabel(value)}',
      'Resolution: ${_formatResolution(value.size.width, value.size.height)}',
      'Aspect Ratio: ${value.size.width > 0 ? value.aspectRatio.toStringAsFixed(3) : 'Unknown'}',
      'Position: ${_formatDuration(value.position)}',
      'Duration: ${_formatDuration(value.duration)}',
      'Playback Speed: ${playbackSpeed.toStringAsFixed(2)}x',
      if (value.hasError) 'Error: ${value.errorDescription}',
      'Engine: ExoPlayer (Android, hardware-accelerated)',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _stateLabel(NativeVideoValue value) {
    if (value.hasError) return 'Error';
    if (value.isBuffering) return 'Buffering';
    return value.isPlaying ? 'Playing' : 'Paused';
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
              _buildHeader(context, cs, textTheme),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionLabel(cs, 'Playback'),
                        ValueListenableBuilder<NativeVideoValue>(
                          valueListenable: controller,
                          builder: (context, value, _) {
                            return Column(
                              children: [
                                _buildStatRow(cs, 'State', _stateLabel(value)),
                                _buildStatRow(cs, 'Resolution', _formatResolution(value.size.width, value.size.height)),
                                _buildStatRow(
                                  cs,
                                  'Aspect Ratio',
                                  value.size.width > 0 ? value.aspectRatio.toStringAsFixed(3) : 'Unknown',
                                ),
                                _buildStatRow(cs, 'Position', _formatDuration(value.position)),
                                _buildStatRow(cs, 'Duration', _formatDuration(value.duration)),
                                _buildStatRow(cs, 'Playback Speed', '${playbackSpeed.toStringAsFixed(2)}x'),
                                if (value.hasError)
                                  _buildStatRow(cs, 'Error', value.errorDescription),
                              ],
                            );
                          },
                        ),
                        _buildSectionLabel(cs, 'Engine'),
                        _buildStatRow(cs, 'Player', 'ExoPlayer (Android)'),
                        _buildStatRow(cs, 'Decoding', 'Hardware-accelerated'),
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

  Widget _buildHeader(BuildContext context, ColorScheme cs, TextTheme textTheme) {
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
          onPressed: () => _copyDiagnostics(context),
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
