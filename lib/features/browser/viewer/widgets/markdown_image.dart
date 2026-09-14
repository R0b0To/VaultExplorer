import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

class MarkdownImage extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String resolvedPath;
  final String alt;

  const MarkdownImage({
    super.key,
    required this.container,
    required this.resolvedPath,
    required this.alt,
  });

  @override
  ConsumerState<MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends ConsumerState<MarkdownImage> {
  static const _decodableExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolvedPath != widget.resolvedPath ||
        oldWidget.container.volId != widget.container.volId) {
      _load();
    }
  }

  void _load() {
    _future = ref
        .read(vaultFileIoApiProvider)
        .readWholeFile(widget.container, widget.resolvedPath);
  }

  bool get _isDecodable {
    final dot = widget.resolvedPath.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = widget.resolvedPath.substring(dot + 1).toLowerCase();
    return _decodableExtensions.contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_isDecodable) {
      return _fallbackCard(cs, context.l10n.archivePreviewNotAvailableMessage);
    }

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: 160,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }

        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _fallbackCard(cs, context.l10n.encryptedImageLoadFailedMessage);
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _fallbackCard(cs, context.l10n.invalidOrCorruptedImageMessage),
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackCard(ColorScheme cs, String message) {
    final name = widget.resolvedPath.contains('/')
        ? widget.resolvedPath.substring(widget.resolvedPath.lastIndexOf('/') + 1)
        : widget.resolvedPath;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.alt.isNotEmpty ? widget.alt : name,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}