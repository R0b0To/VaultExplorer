import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/discrete_mode_repository.dart';
import 'package:vaultexplorer/features/decoy/decoy_pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

/// Discrete Mode's decoy reader home screen (docs/architecture.md §8).
///
/// This is what boots up whenever `disguiseModeApi.getMode()` reports
/// [DisguiseMode.decoy] -- i.e. whenever the launcher is currently showing
/// the "PDF Viewer" identity. It works as a usable, offline PDF reader
/// with local file browsing, recent documents history, and individual/bulk
/// item clearing options.
class DecoyPdfHomeScreen extends StatefulWidget {
  const DecoyPdfHomeScreen({super.key});

  @override
  State<DecoyPdfHomeScreen> createState() => _DecoyPdfHomeScreenState();
}

class _DecoyPdfHomeScreenState extends State<DecoyPdfHomeScreen> {
  List<DecoyRecentFile> _recents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshRecents();
  }

  Future<void> _refreshRecents() async {
    final recents = await DiscreteModeRepository.loadRecents();
    if (!mounted) return;
    setState(() {
      _recents = recents;
      _loading = false;
    });
  }

  Future<void> _pickAndOpen() async {
    final picked = await disguiseModeApi.pickLocalPdfFile();
    if (picked == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DecoyPdfViewerScreen(uri: picked.uri, displayName: picked.displayName),
      ),
    );
    if (mounted) unawaited(_refreshRecents());
  }

  Future<void> _openRecent(DecoyRecentFile file) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DecoyPdfViewerScreen(uri: file.uri, displayName: file.displayName),
      ),
    );
    if (mounted) unawaited(_refreshRecents());
  }

  Future<void> _removeRecent(DecoyRecentFile file) async {
    await DiscreteModeRepository.removeRecent(file.uri);
    await _refreshRecents();
    if (mounted) {
      showAppSnackBar(context, message: 'Removed "${file.displayName}" from list');
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Clear Recent History?',
      message: 'This will remove all recent documents from your list. The actual files on your device will not be affected.',
      confirmLabel: 'Clear All',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await DiscreteModeRepository.clearRecents();
    await _refreshRecents();
    if (mounted) {
      showAppSnackBar(context, message: 'Recent history cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const HiddenVaultTrigger(child: Text('PDF Viewer')),
        actions: [
          if (_recents.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'clear') _confirmClearAll();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Clear history'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndOpen,
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text('Open PDF File'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _recents.isEmpty
          ? AppEmptyState(
              icon: Icons.picture_as_pdf_outlined,
              title: 'No documents yet',
              message: 'Open a PDF from your device to start reading.',
              actionLabel: 'Open PDF File',
              actionIcon: Icons.folder_open_rounded,
              onAction: _pickAndOpen,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: _recents.length,
              separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final file = _recents[index];
                return Dismissible(
                  key: Key(file.uri),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.delete_outline_rounded, color: cs.onErrorContainer),
                  ),
                  onDismissed: (_) => _removeRecent(file),
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      leading: Icon(
                        Icons.picture_as_pdf_outlined,
                        color: cs.primary,
                        size: AppIconSize.feature,
                      ),
                      title: Text(file.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_formatOpenedAt(file.openedAt)),
                      trailing: PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant, size: 20),
                        onSelected: (value) {
                          if (value == 'remove') _removeRecent(file);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, size: 20),
                                SizedBox(width: 12),
                                Text('Remove from list'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _openRecent(file),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _formatOpenedAt(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
