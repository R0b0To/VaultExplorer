import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/tools/models/duplicate_finder_models.dart';
import 'package:vaultexplorer/features/tools/services/duplicate_finder_service.dart';

class DuplicateFinderScreen extends StatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const DuplicateFinderScreen({super.key, required this.mountedContainers});

  @override
  State<DuplicateFinderScreen> createState() => _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState extends State<DuplicateFinderScreen> {
  final DuplicateFinderService _service = DuplicateFinderService();
  final TextEditingController _searchController = TextEditingController();

  int _selectedTargetVolId = -1;
  bool _isScanning = false;
  DuplicateScanProgress _progress = const DuplicateScanProgress(stage: DuplicateScanStage.idle);
  List<DuplicateGroup> _groups = const [];
  DuplicateFinderCancellationToken? _cancelToken;
  final Map<String, bool> _selectedForDeletion = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
  }

  List<MountedContainer> _getTargetContainers() {
    final available = widget.mountedContainers.value;
    if (_selectedTargetVolId == -1) {
      return available;
    }
    return available.where((c) => c.volId == _selectedTargetVolId).toList();
  }

  Future<void> _startScan() async {
    final targets = _getTargetContainers();
    if (targets.isEmpty) return;

    _cancelToken?.cancel();
    _cancelToken = DuplicateFinderCancellationToken();

    setState(() {
      _isScanning = true;
      _groups = const [];
      _selectedForDeletion.clear();
      _progress = const DuplicateScanProgress(stage: DuplicateScanStage.indexing);
    });

    try {
      await for (final result in _service.scanVaults(
        containers: targets,
        cancelToken: _cancelToken,
      )) {
        if (!mounted) break;
        setState(() {
          _progress = result.progress;
          _groups = result.groups;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _autoSelectRedundantCopies();
        });
      }
    }
  }

  void _cancelScan() {
    _cancelToken?.cancel();
    setState(() {
      _isScanning = false;
      _progress = const DuplicateScanProgress(stage: DuplicateScanStage.cancelled);
    });
  }

  void _autoSelectRedundantCopies() {
    _selectedForDeletion.clear();
    for (final group in _groups) {
      for (int i = 0; i < group.files.length; i++) {
        final item = group.files[i];
        _selectedForDeletion[item.id] = (i > 0);
      }
    }
  }

  void _selectAllFiles() {
    setState(() {
      for (final group in _groups) {
        for (final item in group.files) {
          _selectedForDeletion[item.id] = true;
        }
      }
    });
  }

  void _deselectAllFiles() {
    setState(() {
      for (final group in _groups) {
        for (final item in group.files) {
          _selectedForDeletion[item.id] = false;
        }
      }
    });
  }

  int get _selectedCount =>
      _selectedForDeletion.values.where((v) => v).length;

  int get _selectedBytesTotal {
    int total = 0;
    for (final group in _groups) {
      for (final item in group.files) {
        if (_selectedForDeletion[item.id] ?? false) {
          total += item.sizeBytes;
        }
      }
    }
    return total;
  }

  Future<void> _deleteSelected() async {
    final itemsToDelete = <VaultFileItem>[];
    for (final group in _groups) {
      for (final item in group.files) {
        if (_selectedForDeletion[item.id] ?? false) {
          itemsToDelete.add(item);
        }
      }
    }

    if (itemsToDelete.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.duplicateFinderConfirmDeleteTitle),
        content: Text(
          context.l10n.duplicateFinderConfirmDeleteMessage(
            itemsToDelete.length,
            formatBytes(_selectedBytesTotal),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
              foregroundColor: ctx.colors.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.duplicateFinderDeletePermanentlyButton),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isScanning = true);
    try {
      final deletedCount = await _service.deleteFiles(itemsToDelete);
      final deletedIds = itemsToDelete.map((e) => e.id).toSet();

      final updatedGroups = <DuplicateGroup>[];
      for (final group in _groups) {
        final remaining = group.files.where((f) => !deletedIds.contains(f.id)).toList();
        if (remaining.length >= 2) {
          updatedGroups.add(group.copyWithFiles(remaining));
        }
      }

      if (mounted) {
        setState(() {
          _groups = updatedGroups;
          _autoSelectRedundantCopies();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.duplicateFinderDeleteSuccessMessage(deletedCount)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _previewFile(VaultFileItem item) async {
    final ext = item.name.contains('.') ? item.name.split('.').last.toLowerCase() : '';
    if (MediaViewerConstants.isSupported(item.name)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            container: item.container,
            mediaFiles: [item.relativePath],
            initialIndex: 0,
            thumbnailCacheMode: ThumbnailCacheMode.appCache,
          ),
        ),
      );
      return;
    }

    if (ext == 'pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            container: item.container,
            filePath: item.relativePath,
          ),
        ),
      );
      return;
    }

    if (ext == 'html' || ext == 'htm') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HtmlViewerScreen(
            container: item.container,
            filePath: item.relativePath,
          ),
        ),
      );
      return;
    }

    const textExts = {'txt', 'md', 'csv', 'json', 'xml', 'log', 'yaml', 'yml', 'dart', 'js', 'css'};
    if (textExts.contains(ext)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextEditorScreen(
            container: item.container,
            filePath: item.relativePath,
          ),
        ),
      );
      return;
    }

    try {
      final ok = await vaultExplorerApi.openWithApp(item.container, item.relativePath);
      if (!ok && mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.duplicateFinderPreviewFailedMessage(item.name),
          tone: AppBannerTone.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.duplicateFinderPreviewErrorMessage(e),
          tone: AppBannerTone.error,
        );
      }
    }
  }

  List<DuplicateGroup> _getFilteredGroups() {
    if (_searchQuery.isEmpty) return _groups;
    final result = <DuplicateGroup>[];
    for (final group in _groups) {
      final matchingFiles = group.files.where((f) {
        return f.name.toLowerCase().contains(_searchQuery) ||
            f.relativePath.toLowerCase().contains(_searchQuery);
      }).toList();
      if (matchingFiles.isNotEmpty) {
        result.add(group.copyWithFiles(matchingFiles));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final wideLayout = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.toolDuplicateFinderTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ValueListenableBuilder<List<MountedContainer>>(
        valueListenable: widget.mountedContainers,
        builder: (context, mountedList, _) {
          if (mountedList.isEmpty) {
            return AppEmptyState(
              icon: Icons.find_in_page_outlined,
              title: context.l10n.duplicateFinderNoVaultsTitle,
              message: context.l10n.duplicateFinderNoVaultsMessage,
            );
          }

          final filteredGroups = _getFilteredGroups();

          if (wideLayout) {
            if (_isScanning) {
              return SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTargetPicker(context, mountedList),
                          const SizedBox(height: AppSpacing.md),
                          _buildIdleIntroInfo(context),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: _buildScanProgressCard(context),
                    ),
                  ],
                ),
              );
            }

            if (_progress.stage == DuplicateScanStage.idle) {
              return SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTargetPicker(context, mountedList),
                          const SizedBox(height: AppSpacing.md),
                          _buildIdleIntroInfo(context),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: _buildIdleActionCard(context),
                    ),
                  ],
                ),
              );
            }

            if (_groups.isEmpty) {
              return SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTargetPicker(context, mountedList),
                    const SizedBox(height: AppSpacing.md),
                    _buildNoDuplicatesCard(context),
                  ],
                ),
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: context.screen.secondaryPaneWidth(fraction: 0.38),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTargetPicker(context, mountedList),
                        const SizedBox(height: AppSpacing.md),
                        _buildSummaryCard(context),
                        const SizedBox(height: AppSpacing.md),
                        _buildSearchBar(context),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 16, 100),
                    itemCount: filteredGroups.isEmpty ? 1 : filteredGroups.length,
                    itemBuilder: (context, i) {
                      if (filteredGroups.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              context.l10n.noResultsTitle,
                              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        );
                      }
                      return _buildGroupTile(
                        context,
                        i + 1,
                        filteredGroups[i],
                        mountedList.length > 1,
                      );
                    },
                  ),
                ),
              ],
            );
          }

          final showGroupList =
              !_isScanning && _progress.stage != DuplicateScanStage.idle && _groups.isNotEmpty;

          return ListView.builder(
            padding: AppSpacing.pagePadding,
            itemCount: 1 + (showGroupList ? filteredGroups.length : 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTargetPicker(context, mountedList),
                    const SizedBox(height: AppSpacing.md),
                    if (_isScanning)
                      _buildScanProgressCard(context)
                    else if (_progress.stage == DuplicateScanStage.idle)
                      _buildIdleCard(context)
                    else if (_groups.isEmpty)
                      _buildNoDuplicatesCard(context)
                    else ...[
                      _buildSummaryCard(context),
                      const SizedBox(height: AppSpacing.md),
                      _buildSearchBar(context),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              }

              return _buildGroupTile(
                context,
                index,
                filteredGroups[index - 1],
                mountedList.length > 1,
              );
            },
          );
        },
      ),
      bottomNavigationBar: (!_isScanning && _selectedCount > 0) ? _buildBottomActionBar(context) : null,
    );
  }

  Widget _buildTargetPicker(BuildContext context, List<MountedContainer> mountedList) {
    final options = <SelectOption<int>>[
      SelectOption(
        value: -1,
        label: mountedList.length > 1
            ? context.l10n.duplicateFinderTargetAllVaults
            : mountedList.first.displayName,
      ),
      if (mountedList.length > 1)
        ...mountedList.map((c) => SelectOption(value: c.volId, label: c.displayName)),
    ];

    return OptionPickerTile<int>(
      label: context.l10n.duplicateFinderTargetLabel,
      value: _selectedTargetVolId,
      subtitle: _selectedTargetVolId == -1
          ? (mountedList.length > 1
              ? context.l10n.duplicateFinderVaultsSelectedLabel(mountedList.length)
              : mountedList.first.displayName)
          : mountedList.firstWhere((c) => c.volId == _selectedTargetVolId, orElse: () => mountedList.first).displayName,
      prefixIcon: Icons.lock_open_rounded,
      options: options,
      enabled: !_isScanning,
      onChanged: (volId) {
        setState(() {
          _selectedTargetVolId = volId;
          _progress = const DuplicateScanProgress(stage: DuplicateScanStage.idle);
          _groups = const [];
        });
      },
    );
  }

  Widget _buildIdleIntroInfo(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.difference_rounded, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.duplicateFinderIntroTitle,
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          context.l10n.duplicateFinderIntroSubtitle,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.duplicateFinderStagesDescription,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdleActionCard(BuildContext context) {
    final textTheme = context.typography;
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Ready to find duplicate files and reclaim storage across your encrypted containers.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(context.l10n.duplicateFinderStartScan),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdleCard(BuildContext context) {
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIdleIntroInfo(context),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(context.l10n.duplicateFinderStartScan),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScanProgressCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    String stageLabel;
    switch (_progress.stage) {
      case DuplicateScanStage.indexing:
        stageLabel = context.l10n.duplicateFinderScanningStage1;
        break;
      case DuplicateScanStage.partialHashing:
        stageLabel = context.l10n.duplicateFinderScanningStage2;
        break;
      case DuplicateScanStage.fullHashing:
        stageLabel = context.l10n.duplicateFinderScanningStage3;
        break;
      default:
        stageLabel = context.l10n.duplicateFinderScanningVaultFallback;
    }

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stageLabel,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _progress.progressFraction,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              const SizedBox(height: 12),
              if (_progress.currentFileName != null)
                Text(
                  context.l10n.duplicateFinderProcessingFileLabel(_progress.currentFileName!),
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              Text(
                context.l10n.duplicateFinderScanStatsLabel(
                  _progress.totalFilesScanned,
                  _progress.duplicateGroupCount,
                  formatBytes(_progress.potentialSavedBytes),
                ),
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _cancelScan,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(context.l10n.duplicateFinderCancelScan),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoDuplicatesCard(BuildContext context) {
    return Column(
      children: [
        AppEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: context.l10n.duplicateFinderNoDuplicatesTitle,
          message: context.l10n.duplicateFinderNoDuplicatesMessage,
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _startScan,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.duplicateFinderRescan),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final totalWaste = _groups.fold<int>(0, (sum, g) => sum + g.totalWasteBytes);
    final totalDupFiles = _groups.fold<int>(0, (sum, g) => sum + g.files.length);

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.cleaning_services_rounded, color: cs.onPrimaryContainer, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.duplicateFinderGroupsFoundLabel(_groups.length),
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          context.l10n.duplicateFinderGroupsSummaryLabel(
                            totalDupFiles,
                            formatBytes(totalWaste),
                          ),
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: context.l10n.duplicateFinderRescan,
                    onPressed: _startScan,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: Text(context.l10n.duplicateFinderSelectRedundant),
                    onPressed: () => setState(_autoSelectRedundantCopies),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.select_all_rounded, size: 16),
                    label: Text(context.l10n.duplicateFinderSelectAll),
                    onPressed: _selectAllFiles,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.deselect_rounded, size: 16),
                    label: Text(context.l10n.duplicateFinderDeselectAll),
                    onPressed: _deselectAllFiles,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = context.colors;
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: context.l10n.duplicateFinderSearchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () => _searchController.clear(),
              )
            : null,
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildGroupTile(
    BuildContext context,
    int groupIndex,
    DuplicateGroup group,
    bool showVaultBadge,
  ) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$groupIndex',
              style: textTheme.labelLarge?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            context.l10n.duplicateFinderGroupTitleLabel(
              groupIndex,
              formatBytes(group.sizeBytes),
              group.files.length,
            ),
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            context.l10n.duplicateFinderRecoverableSpaceLabel(formatBytes(group.totalWasteBytes)),
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          children: group.files.asMap().entries.map((e) {
            final fileIndex = e.key;
            final item = e.value;
            final isChecked = _selectedForDeletion[item.id] ?? false;
            final isOriginal = (fileIndex == 0 && !isChecked);

            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 8, right: 12, top: 4, bottom: 4),
                leading: Checkbox(
                  value: isChecked,
                  onChanged: (val) {
                    setState(() {
                      _selectedForDeletion[item.id] = val ?? false;
                    });
                  },
                ),
                title: Row(
                  children: [
                    Icon(
                      iconForFile(item.name),
                      size: AppIconSize.small,
                      color: colorForFile(item.name),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.relativePath,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: isChecked ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildTagBadge(
                        context,
                        isOriginal ? context.l10n.duplicateFinderOriginalLabel : context.l10n.duplicateFinderDuplicateLabel,
                        isOriginal ? cs.primary : cs.tertiary,
                      ),
                      if (showVaultBadge)
                        _buildTagBadge(context, item.container.displayName, cs.secondary),
                      if (item.modifiedSecs > 0)
                        Text(
                          formatEntryDate(item.modifiedSecs),
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  tooltip: context.l10n.duplicateFinderPreviewFileTooltip,
                  onPressed: () => _previewFile(item),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTagBadge(BuildContext context, String label, Color color) {
    final textTheme = context.typography;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.duplicateFinderFilesSelectedLabel(_selectedCount),
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    context.l10n.duplicateFinderBytesToBeFreedLabel(formatBytes(_selectedBytesTotal)),
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                minimumSize: const Size(0, 48),
              ),
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text(context.l10n.duplicateFinderDeleteSelectedButton(_selectedCount)),
            ),
          ],
        ),
      ),
    );
  }
}