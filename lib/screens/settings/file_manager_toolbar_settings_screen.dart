import 'package:flutter/material.dart';
import '../../models/file_manager_action.dart';
import '../../models/file_manager_toolbar_config.dart';
import '../../services/file_manager_toolbar_service.dart';
import '../../theme.dart';

/// Lets the user reorder and show/hide the file browser's action-bar
/// entries (the bottom bar in portrait / sidebar rail in landscape).
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
        title: const Text(
          'File Manager Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'Reset to defaults',
            onPressed: _resetToDefaults,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // ── CARD 1: TOOLBAR LAYOUT ─────────────────────────────────
                  _ExpressiveCard(
                    children: [
                      const _ExpressiveSectionHeader(
                        title: 'Toolbar Layout',
                        subtitle: 'Drag handles to reorder actions or toggle visibility',
                        icon: Icons.tune_rounded,
                      ),
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
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: cs.surfaceContainerHigh,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
                                        : cs.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                ),
                                title: Text(
                                  action.label,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
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
                                    const SizedBox(width: 4),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(10),
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
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── CARD 2: BROWSER LAYOUT ─────────────────────────────────
                  _ExpressiveCard(
                    children: [
                      const _ExpressiveSectionHeader(
                        title: 'Browser Layout',
                        subtitle: 'Top navigation path and storage statistics bars',
                        icon: Icons.space_dashboard_rounded,
                      ),
                      Material(
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          value: _config.showBreadcrumbBar,
                          onChanged: (v) {
                            setState(() => _config = _config.copyWith(showBreadcrumbBar: v));
                            _persist();
                          },
                          title: Text('Show Breadcrumb Bar', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text('Path navigation bar at top of browser.', style: textTheme.bodySmall),
                          secondary: Icon(Icons.linear_scale_rounded, color: cs.primary),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          value: _config.showStatsBar,
                          onChanged: (v) {
                            setState(() => _config = _config.copyWith(showStatsBar: v));
                            _persist();
                          },
                          title: Text('Show Stats Bar', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text('File count and free space info banner.', style: textTheme.bodySmall),
                          secondary: Icon(Icons.analytics_outlined, color: cs.primary),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── CARD 3: MEDIA VIEWER ──────────────────────────────────
                  _ExpressiveCard(
                    children: [
                      const _ExpressiveSectionHeader(
                        title: 'Media Viewer',
                        subtitle: 'Playback controls and gallery playlist options',
                        icon: Icons.play_circle_outline_rounded,
                      ),
                      Material(
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          value: _config.showMediaCarousel,
                          onChanged: (v) {
                            setState(() => _config = _config.copyWith(showMediaCarousel: v));
                            _persist();
                          },
                          title: Text('Show Playlist Carousel', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text('Show thumbnail carousel button when viewing media playlists.', style: textTheme.bodySmall),
                          secondary: Icon(Icons.view_carousel_rounded, color: cs.primary),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

// ── Android 16/17 Expressive Card Wrapper ──────────────────────────────────────

class _ExpressiveCard extends StatelessWidget {
  final List<Widget> children;
  const _ExpressiveCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

// ── Expressive Section Header ────────────────────────────────────────────────

class _ExpressiveSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ExpressiveSectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}