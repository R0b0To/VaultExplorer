import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';

enum FolderDocumentProviderAction { unmount }

class FolderDocumentProviderSheet extends StatefulWidget {
  final String folderName;
  final bool initialAutoMount;
  final ValueChanged<bool> onAutoMountChanged;

  const FolderDocumentProviderSheet({
    super.key,
    required this.folderName,
    required this.initialAutoMount,
    required this.onAutoMountChanged,
  });

  static Future<FolderDocumentProviderAction?> show(
    BuildContext context, {
    required String folderName,
    required bool initialAutoMount,
    required ValueChanged<bool> onAutoMountChanged,
  }) {
    return showModalBottomSheet<FolderDocumentProviderAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FolderDocumentProviderSheet(
        folderName: folderName,
        initialAutoMount: initialAutoMount,
        onAutoMountChanged: onAutoMountChanged,
      ),
    );
  }

  @override
  State<FolderDocumentProviderSheet> createState() =>
      _FolderDocumentProviderSheetState();
}

class _FolderDocumentProviderSheetState
    extends State<FolderDocumentProviderSheet> {
  late bool _autoMount = widget.initialAutoMount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.folder_shared_rounded, color: cs.tertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.folderName,
                  style: textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This folder is exposed as its own storage location, so other '
            'apps can browse and open its files directly.',
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-mount when container unlocks'),
            subtitle: const Text('Expose this folder again automatically next time'),
            value: _autoMount,
            onChanged: (value) {
              setState(() => _autoMount = value);
              widget.onAutoMountChanged(value);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.onErrorContainer,
              ),
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Unmount'),
              onPressed: () => Navigator.of(context)
                  .pop(FolderDocumentProviderAction.unmount),
            ),
          ),
        ],
      ),
    );
  }
}