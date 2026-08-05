import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';

class ThumbnailQualityTile extends StatelessWidget {
  final String label;
  final ThumbnailQuality value;
  final ValueChanged<ThumbnailQuality> onChanged;
  final IconData? prefixIcon;
  final bool enabled;

  const ThumbnailQualityTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.prefixIcon = Icons.photo_size_select_actual_outlined,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: prefixIcon != null
          ? Icon(prefixIcon, size: AppIconSize.standard, color: cs.primary)
          : null,
      title: Text(
        label,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${value.size} px · ${value.quality}% quality',
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ),
      onTap: enabled ? () => _showDialog(context) : null,
    );
  }

  void _showDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _ThumbnailQualityDialog(
          label: label,
          initialValue: value,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _ThumbnailQualityDialog extends StatefulWidget {
  final String label;
  final ThumbnailQuality initialValue;
  final ValueChanged<ThumbnailQuality> onChanged;

  const _ThumbnailQualityDialog({
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_ThumbnailQualityDialog> createState() =>
      _ThumbnailQualityDialogState();
}

class _ThumbnailQualityDialogState extends State<_ThumbnailQualityDialog> {
  late int _size;
  late int _quality;

  @override
  void initState() {
    super.initState();
    _size = widget.initialValue.size;
    _quality = widget.initialValue.quality;
  }

  void _update() {
    widget.onChanged(ThumbnailQuality(size: _size, quality: _quality));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // ── Thumbnail Size (Resolution) ──
              Text(
                context.l10n.thumbnailSizeResolutionLabel,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: _size > 100
                        ? () {
                            setState(() {
                              _size = (_size - 20).clamp(100, 500);
                              _update();
                            });
                          }
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '$_size px',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _size < 500
                        ? () {
                            setState(() {
                              _size = (_size + 20).clamp(100, 500);
                              _update();
                            });
                          }
                        : null,
                  ),
                ],
              ),
              Slider(
                value: _size.toDouble(),
                min: 100.0,
                max: 500.0,
                divisions: 20,
                label: '$_size px',
                onChanged: (val) {
                  setState(() {
                    _size = val.round();
                    _update();
                  });
                },
              ),

              const SizedBox(height: 16),

              // ── Compression Quality ──
              Text(
                context.l10n.jpegCompressionQualityLabel,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: _quality > 10
                        ? () {
                            setState(() {
                              _quality = (_quality - 5).clamp(10, 100);
                              _update();
                            });
                          }
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '$_quality %',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _quality < 100
                        ? () {
                            setState(() {
                              _quality = (_quality + 5).clamp(10, 100);
                              _update();
                            });
                          }
                        : null,
                  ),
                ],
              ),
              Slider(
                value: _quality.toDouble(),
                min: 10.0,
                max: 100.0,
                divisions: 18,
                label: '$_quality%',
                onChanged: (val) {
                  setState(() {
                    _quality = val.round();
                    _update();
                  });
                },
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.done),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}