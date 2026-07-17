import 'package:flutter/material.dart';
import '../../models/file_manager_action.dart';
import '../../models/file_manager_toolbar_config.dart';
import '../../services/file_manager_toolbar_service.dart';
import '../../theme.dart';

/// Lets the user reorder and show/hide the file browser's action-bar
/// entries (the bottom bar in portrait / sidebar rail in landscape).
///
/// Drag the handle to reorder; the switch shows/hides each entry without
/// removing it from the list, so a hidden action can always be turned back
/// on later without losing its place.
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
        title: const Text('File Manager Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'Reset to defaults',
            onPressed: _resetToDefaults,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : ListView(
              padding: AppSpacing.pagePadding,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Toolbar Layout',
                  style: textTheme.titleSmall?.copyWith(color: cs.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drag to reorder. Turn an action off to hide it from the '
                  'toolbar without losing your ordering.',
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Card(
                  color: cs.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _config.order.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, i) {
                      final action = _config.order[i];
                      final visible = !_config.hidden.contains(action);
                      return ListTile(
                        key: ValueKey(action),
                        leading: Icon(
                          action.icon,
                          color: visible
                              ? cs.primary
                              : cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        title: Text(
                          action.label,
                          style: TextStyle(
                            color: visible
                                ? cs.onSurface
                                : cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: visible,
                              onChanged: (v) => _toggleVisible(action, v),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(Icons.drag_handle_rounded, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Browser Layout',
                  style: textTheme.titleSmall?.copyWith(color: cs.primary),
                ),
                const SizedBox(height: 8),
                Card(
                  color: cs.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _config.showBreadcrumbBar,
                        onChanged: (v) {
                          setState(() => _config = _config.copyWith(showBreadcrumbBar: v));
                          _persist();
                        },
                        title: const Text('Show Breadcrumb Bar'),
                        subtitle: const Text('The path navigation bar at the top of the browser.'),
                        secondary: Icon(Icons.linear_scale_rounded, color: cs.primary),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _config.showStatsBar,
                        onChanged: (v) {
                          setState(() => _config = _config.copyWith(showStatsBar: v));
                          _persist();
                        },
                        title: const Text('Show Stats Bar'),
                        subtitle: const Text('The file count and free space banner.'),
                        secondary: Icon(Icons.analytics_outlined, color: cs.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
