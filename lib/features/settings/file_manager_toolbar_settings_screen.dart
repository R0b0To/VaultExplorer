import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';

class FileManagerToolbarSettingsScreen extends StatefulWidget {
  const FileManagerToolbarSettingsScreen({super.key});

  @override
  State<FileManagerToolbarSettingsScreen> createState() =>
      _FileManagerToolbarSettingsScreenState();
}

class _FileManagerToolbarSettingsScreenState
    extends State<FileManagerToolbarSettingsScreen> {
  FileManagerToolbarConfig _config = FileManagerToolbarConfig.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await FileManagerToolbarService.instance.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await FileManagerToolbarService.instance.save(_config);
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final order = List<FileManagerAction>.from(_config.order);
      final moved = order.removeAt(oldIndex);
      order.insert(newIndex, moved);
      _config = _config.copyWith(order: order);
    });
    _persist();
  }

  void _toggleVisible(FileManagerAction action, bool visible) {
    setState(() {
      final hidden = Set<FileManagerAction>.from(_config.hidden);
      if (visible) {
        hidden.remove(action);
      } else {
        hidden.add(action);
      }
      _config = _config.copyWith(hidden: hidden);
    });
    _persist();
  }

  void _onReorderDetailColumns(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final order = List<FileDetailColumn>.from(_config.detailColumnsOrder);
      final moved = order.removeAt(oldIndex);
      order.insert(newIndex, moved);
      _config = _config.copyWith(detailColumnsOrder: order);
    });
    _persist();
  }

  void _toggleDetailColumnVisible(FileDetailColumn col, bool visible) {
    setState(() {
      final hidden = Set<FileDetailColumn>.from(_config.hiddenDetailColumns);
      if (visible) {
        hidden.remove(col);
      } else {
        hidden.add(col);
      }
      _config = _config.copyWith(hiddenDetailColumns: hidden);
    });
    _persist();
  }

  Future<void> _resetToDefaults() async {
    setState(() => _config = FileManagerToolbarConfig.defaults());
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.fileManagerSettingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: context.l10n.resetToDefaultsTooltip,
            onPressed: _resetToDefaults,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    children: [
                      SectionHeader(context.l10n.toolbarLayoutSectionHeader),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _config.order.length,
                        onReorder: _onReorder,
                        itemBuilder: (context, i) {
                          final action = _config.order[i];
                          final visible = !_config.hidden.contains(action);
                          return Padding(
                            key: ValueKey(action),
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Material(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(i == 0 ? 20 : 4),
                                bottom: Radius.circular(
                                    i == _config.order.length - 1 ? 20 : 4),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 2),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: visible
                                        ? cs.primaryContainer.withValues(alpha: 0.5)
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    action.icon,
                                    size: 20,
                                    color: visible
                                        ? cs.primary
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                  ),
                                ),
                                title: Text(
                                  action.getLocalizedLabel(context.l10n),
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: visible
                                        ? cs.onSurface
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: visible,
                                      onChanged: (v) =>
                                          _toggleVisible(action, v),
                                    ),
                                    const SizedBox(width: 4),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          color: cs.onSurfaceVariant,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      SectionHeader(context.l10n.listViewOptionsSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: _config.showListThumbnails,
                            onChanged: (v) {
                              setState(() => _config =
                                  _config.copyWith(showListThumbnails: v));
                              _persist();
                            },
                            title: Text(context.l10n.showMediaThumbnailsLabel,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                context.l10n.showMediaThumbnailsDesc,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.image_outlined,
                                color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SectionHeader(context.l10n.detailedListViewColumnsSectionHeader),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _config.detailColumnsOrder.length,
                        onReorder: _onReorderDetailColumns,
                        itemBuilder: (context, i) {
                          final col = _config.detailColumnsOrder[i];
                          final visible =
                              !_config.hiddenDetailColumns.contains(col);
                          return Padding(
                            key: ValueKey(col),
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Material(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(i == 0 ? 20 : 4),
                                bottom: Radius.circular(
                                    i == _config.detailColumnsOrder.length - 1
                                        ? 20
                                        : 4),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 2),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: visible
                                        ? cs.primaryContainer.withValues(alpha: 0.5)
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    col.icon,
                                    size: 20,
                                    color: visible
                                        ? cs.primary
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                  ),
                                ),
                                title: Text(
                                  col.getLocalizedLabel(context.l10n),
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: visible
                                        ? cs.onSurface
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: visible,
                                      onChanged: (v) =>
                                          _toggleDetailColumnVisible(col, v),
                                    ),
                                    const SizedBox(width: 4),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          color: cs.onSurfaceVariant,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      SectionHeader(context.l10n.galleryGridViewSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: _config.showGridFileNames,
                            onChanged: (v) {
                              setState(() =>
                                  _config = _config.copyWith(showGridFileNames: v));
                              _persist();
                            },
                            title: Text(context.l10n.showFileNamesLabel,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                context.l10n.showFileNamesDesc,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.label_outlined,
                                color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SectionHeader(context.l10n.browserLayoutSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: _config.showBreadcrumbBar,
                            onChanged: (v) {
                              setState(() => _config =
                                  _config.copyWith(showBreadcrumbBar: v));
                              _persist();
                            },
                            title: Text(context.l10n.showBreadcrumbBarLabel,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(context.l10n.showBreadcrumbBarDesc,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.linear_scale_rounded,
                                color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: _config.showStatsBar,
                            onChanged: (v) {
                              setState(() =>
                                  _config = _config.copyWith(showStatsBar: v));
                              _persist();
                            },
                            title: Text(context.l10n.showStatsBarLabel,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                context.l10n.showStatsBarDesc,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.analytics_outlined,
                                color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SectionHeader(context.l10n.mediaViewerSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: _config.autoStartPlaylistMode,
                            onChanged: (v) {
                              setState(() => _config =
                                  _config.copyWith(autoStartPlaylistMode: v));
                              _persist();
                            },
                            title: Text(context.l10n.autoStartPlaylistModeLabel,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                context.l10n.autoStartPlaylistModeDesc,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.playlist_play_rounded,
                                color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: _config.showMediaCarousel,
                            onChanged: (v) {
                              setState(() => _config =
                                  _config.copyWith(showMediaCarousel: v));
                              _persist();
                            },
                            title: Text(context.l10n.showPlaylistCarouselLabel,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                context.l10n.showPlaylistCarouselDesc,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.view_carousel_rounded,
                                color: cs.primary),
                          ),
                          OptionPickerTile<PlaylistTransitionEffect>(
                            label: context.l10n.playlistTransitionAnimationLabel,
                            value: _config.playlistTransitionEffect,
                            options: PlaylistTransitionEffect.values.map((effect) {
                              return SelectOption(
                                value: effect,
                                label: effect.getLocalizedLabel(context.l10n),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(() => _config =
                                  _config.copyWith(playlistTransitionEffect: v));
                              _persist();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}