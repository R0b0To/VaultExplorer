import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';

class StorageAnalyzerScreen extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  const StorageAnalyzerScreen({super.key, required this.mountedContainers});

  @override
  ConsumerState<StorageAnalyzerScreen> createState() =>
      _StorageAnalyzerScreenState();
}

class _StorageAnalyzerScreenState
    extends ConsumerState<StorageAnalyzerScreen> {
  @override
  void initState() {
    super.initState();
    final list = widget.mountedContainers.value;
    if (list.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(storageAnalyzerProvider.notifier).selectTarget(list.first);
      });
    }
    widget.mountedContainers.addListener(_onMountedChanged);
  }

  @override
  void dispose() {
    widget.mountedContainers.removeListener(_onMountedChanged);
    super.dispose();
  }

  void _onMountedChanged() {
    ref
        .read(storageAnalyzerProvider.notifier)
        .onMountedListChanged(widget.mountedContainers.value);
  }

  String _categoryLabel(BuildContext context, String category) => switch (category) {
        'images' => context.l10n.storageCategoryImages,
        'videos' => context.l10n.storageCategoryVideos,
        'audio' => context.l10n.storageCategoryAudio,
        'documents' => context.l10n.storageCategoryDocuments,
        'archives' => context.l10n.storageCategoryArchives,
        _ => context.l10n.storageCategoryOther,
      };

  Color _categoryColor(BuildContext context, int index) {
    final cs = context.colors;
    final semantic = context.semanticColors;
    final palette = [cs.primary, cs.tertiary, semantic.warning, cs.secondary, semantic.success, cs.outline];
    return palette[index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final analyzerState = ref.watch(storageAnalyzerProvider);
    final selected = analyzerState.selected;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.surfaceContainerHigh,
        title: Text(
          context.l10n.toolStorageAnalyzerTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ValueListenableBuilder<List<MountedContainer>>(
        valueListenable: widget.mountedContainers,
        builder: (context, mountedList, _) {
          if (mountedList.isEmpty) {
            return AppEmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: context.l10n.storageAnalyzerNoTargetsTitle,
              message: context.l10n.storageAnalyzerNoTargetsMessage,
            );
          }
          return ListView(
            padding: AppSpacing.pagePadding,
            children: [
              OptionPickerTile<int>(
                label: context.l10n.storageAnalyzerTargetLabel,
                value: selected?.volId ?? mountedList.first.volId,
                subtitle: selected?.displayName ?? mountedList.first.displayName,
                prefixIcon: Icons.lock_open_rounded,
                options: mountedList
                    .map((c) => SelectOption(value: c.volId, label: c.displayName))
                    .toList(),
                onChanged: (volId) {
                  final match = mountedList.where((c) => c.volId == volId);
                  if (match.isNotEmpty) {
                    ref
                        .read(storageAnalyzerProvider.notifier)
                        .selectTarget(match.first);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (analyzerState.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (selected != null) ...[
                _buildCapacityGauge(context, analyzerState),
                if (analyzerState.truncated) ...[
                  const SizedBox(height: AppSpacing.md),
                  InlineBanner(
                    context.l10n.storageAnalyzerScanTruncatedNotice('${analyzerState.scannedCount}'),
                    tone: AppBannerTone.warning,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _buildBreakdownSection(context, analyzerState),
                const SizedBox(height: AppSpacing.lg),
                _buildHeaviestFilesSection(context, analyzerState),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCapacityGauge(BuildContext context, StorageAnalyzerState analyzerState) {
    final cs = context.colors;
    final textTheme = context.typography;

    final total = analyzerState.totalBytes ?? -1;
    final free = analyzerState.freeBytes ?? -1;
    final scannedBytes = analyzerState.breakdown.fold<int>(0, (sum, b) => sum + b.sizeBytes);

    if (total > 0 && free >= 0) {
      final used = (total - free).clamp(0, total);
      final fraction = (used / total).clamp(0.0, 1.0);
      return Center(
        child: Column(
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: fraction,
                      strokeWidth: 14,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(fraction * 100).round()}%',
                        style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.storageAnalyzerUsedOfTotal(formatBytes(used), formatBytes(total)),
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Fallback for Folder Vaults or containers with unknown/unbounded capacity
    return Center(
      child: Column(
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_shared_rounded, size: 36, color: cs.primary),
                const SizedBox(height: 6),
                Text(
                  formatBytes(scannedBytes),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Total Vault Content Size: ${formatBytes(scannedBytes)}',
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection(BuildContext context, StorageAnalyzerState analyzerState) {
    final textTheme = context.typography;
    final cs = context.colors;
    final breakdown = analyzerState.breakdown;
    if (breakdown.isEmpty) {
      return Text(
        context.l10n.storageAnalyzerNoFilesFound,
        style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    final totalBytes = breakdown.fold<int>(0, (sum, b) => sum + b.sizeBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(context.l10n.storageAnalyzerBreakdownHeader),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: 12,
            child: Row(
              children: List.generate(breakdown.length, (i) {
                final b = breakdown[i];
                final flex = totalBytes > 0 ? (b.sizeBytes * 1000 ~/ totalBytes).clamp(1, 1000) : 1;
                return Expanded(
                  flex: flex,
                  child: Container(color: _categoryColor(context, i)),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: List.generate(breakdown.length, (i) {
            final b = breakdown[i];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: _categoryColor(context, i), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_categoryLabel(context, b.category)} · ${formatBytes(b.sizeBytes)}',
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildHeaviestFilesSection(BuildContext context, StorageAnalyzerState analyzerState) {
    final textTheme = context.typography;
    final cs = context.colors;
    final heaviest = analyzerState.heaviest;
    if (heaviest.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(context.l10n.storageAnalyzerHeaviestFilesHeader),
        SectionCard(
          children: heaviest
              .map(
                (e) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(Icons.insert_drive_file_outlined, color: cs.primary),
                  title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(e.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(
                    formatBytes(e.sizeBytes),
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}