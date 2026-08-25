import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

class _CategoryAcc {
  int bytes = 0;
  int count = 0;
}

class StorageAnalyzerScreen extends StatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  const StorageAnalyzerScreen({super.key, required this.mountedContainers});

  @override
  State<StorageAnalyzerScreen> createState() => _StorageAnalyzerScreenState();
}

class _StorageAnalyzerScreenState extends State<StorageAnalyzerScreen> {
  static const _maxEntries = 5000;
  static const _maxDepth = 16;
  static const _heaviestLimit = 10;

  MountedContainer? _selected;
  bool _loading = false;
  int? _totalBytes;
  int? _freeBytes;
  List<StorageEntry> _heaviest = const [];
  List<StorageCategoryBreakdown> _breakdown = const [];
  bool _truncated = false;
  int _scannedCount = 0;

  @override
  void initState() {
    super.initState();
    final list = widget.mountedContainers.value;
    if (list.isNotEmpty) {
      _selected = list.first;
      _load();
    }
    widget.mountedContainers.addListener(_onMountedChanged);
  }

  @override
  void dispose() {
    widget.mountedContainers.removeListener(_onMountedChanged);
    super.dispose();
  }

  void _onMountedChanged() {
    final list = widget.mountedContainers.value;
    final selected = _selected;
    if (list.isEmpty) {
      setState(() {
        _selected = null;
        _resetResults();
      });
    } else if (selected == null || !list.any((c) => c.volId == selected.volId)) {
      _selectTarget(list.first);
    }
  }

  void _resetResults() {
    _totalBytes = null;
    _freeBytes = null;
    _heaviest = const [];
    _breakdown = const [];
    _truncated = false;
    _scannedCount = 0;
  }

  Future<void> _selectTarget(MountedContainer container) async {
    setState(() => _selected = container);
    await _load();
  }

  static String _categorize(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'other';
    final ext = name.substring(dot + 1).toLowerCase();
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'svg'};
    const videos = {'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v', '3gp'};
    const audio = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'};
    const documents = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'odt', 'csv'};
    const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'};

    if (images.contains(ext)) return 'images';
    if (videos.contains(ext)) return 'videos';
    if (audio.contains(ext)) return 'audio';
    if (documents.contains(ext)) return 'documents';
    if (archives.contains(ext)) return 'archives';
    return 'other';
  }

  Future<void> _load() async {
    final target = _selected;
    if (target == null) return;

    setState(() {
      _loading = true;
      _resetResults();
    });

    var total = target.totalSpace;
    var free = target.freeSpace;

    try {
      final space = await vaultExplorerApi.getSpaceInfo(target);
      if (space != null && space.length > 1) {
        if (space[0] >= 0) total = space[0];
        if (space[1] >= 0) free = space[1];
      }
    } catch (_) {
      // total/free above already default to target.totalSpace/freeSpace;
      // a failure here just means the analyzer falls back to those instead
      // of the (possibly more precise) native-reported figures.
    }

    final entries = <StorageEntry>[];
    final categoryTotals = <String, _CategoryAcc>{};
    var truncated = false;

    Future<void> walk(String dirPath, int depth) async {
      if (truncated || depth > _maxDepth) return;
      List<String>? raw;
      try {
        raw = await vaultExplorerApi.listDirectory(target, dirPath);
      } catch (_) {
        return;
      }
      if (raw == null) return;

      for (final entry in RawEntry.parseAll(raw)) {
        if (entries.length >= _maxEntries) {
          truncated = true;
          return;
        }
        final fullPath = dirPath.isEmpty ? entry.name : '$dirPath/${entry.name}';
        if (entry.isDir) {
          await walk(fullPath, depth + 1);
          if (truncated) return;
        } else {
          entries.add(StorageEntry(path: fullPath, name: entry.name, sizeBytes: entry.sizeBytes));
          final acc = categoryTotals.putIfAbsent(_categorize(entry.name), () => _CategoryAcc());
          acc.bytes += entry.sizeBytes;
          acc.count += 1;
        }
      }
    }

    await walk('', 0);

    entries.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final breakdown = categoryTotals.entries
        .map((e) => StorageCategoryBreakdown(category: e.key, sizeBytes: e.value.bytes, fileCount: e.value.count))
        .toList()
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    if (!mounted) return;
    setState(() {
      _loading = false;
      _totalBytes = total;
      _freeBytes = free;
      _heaviest = entries.take(_heaviestLimit).toList();
      _breakdown = breakdown;
      _truncated = truncated;
      _scannedCount = entries.length;
    });
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
                value: _selected?.volId ?? mountedList.first.volId,
                subtitle: _selected?.displayName ?? mountedList.first.displayName,
                prefixIcon: Icons.lock_open_rounded,
                options: mountedList
                    .map((c) => SelectOption(value: c.volId, label: c.displayName))
                    .toList(),
                onChanged: (volId) {
                  final match = mountedList.where((c) => c.volId == volId);
                  if (match.isNotEmpty) _selectTarget(match.first);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_selected != null) ...[
                _buildCapacityGauge(context),
                if (_truncated) ...[
                  const SizedBox(height: AppSpacing.md),
                  InlineBanner(
                    context.l10n.storageAnalyzerScanTruncatedNotice('$_scannedCount'),
                    tone: AppBannerTone.warning,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _buildBreakdownSection(context),
                const SizedBox(height: AppSpacing.lg),
                _buildHeaviestFilesSection(context),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCapacityGauge(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    final total = _totalBytes ?? -1;
    final free = _freeBytes ?? -1;
    final scannedBytes = _breakdown.fold<int>(0, (sum, b) => sum + b.sizeBytes);

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

  Widget _buildBreakdownSection(BuildContext context) {
    final textTheme = context.typography;
    final cs = context.colors;
    if (_breakdown.isEmpty) {
      return Text(
        context.l10n.storageAnalyzerNoFilesFound,
        style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    final totalBytes = _breakdown.fold<int>(0, (sum, b) => sum + b.sizeBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(context.l10n.storageAnalyzerBreakdownHeader),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: 12,
            child: Row(
              children: List.generate(_breakdown.length, (i) {
                final b = _breakdown[i];
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
          children: List.generate(_breakdown.length, (i) {
            final b = _breakdown[i];
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

  Widget _buildHeaviestFilesSection(BuildContext context) {
    final textTheme = context.typography;
    final cs = context.colors;
    if (_heaviest.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(context.l10n.storageAnalyzerHeaviestFilesHeader),
        SectionCard(
          children: _heaviest
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