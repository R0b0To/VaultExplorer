import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';

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

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: cs.primary,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildSectionGroup({required List<Widget> children}) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(children.length, (index) {
        final isFirst = index == 0;
        final isLast = index == children.length - 1;
        final isOnly = children.length == 1;

        BorderRadius radius;
        if (isOnly) {
          radius = BorderRadius.circular(20);
        } else if (isFirst) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(20),
            bottom: Radius.circular(4),
          );
        } else if (isLast) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(4),
            bottom: Radius.circular(20),
          );
        } else {
          radius = BorderRadius.circular(4);
        }

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 2.0),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme(
              tileColor: Colors.transparent,
              child: children[index],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSelectTile<T>({
    required String label,
    required T value,
    required List<_SelectOption<T>> options,
    required ValueChanged<T> onChanged,
    String? subtitle,
    IconData? prefixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final currentOption = options.firstWhere(
      (opt) => opt.value == value,
      orElse: () => options.first,
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: cs.primary)
          : null,
      title: Text(
        label,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                currentOption.label,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ),
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            final dialogTheme = Theme.of(dialogContext);
            final mediaQuery = MediaQuery.of(dialogContext);
            final isLandscape =
                mediaQuery.orientation == Orientation.landscape;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: isLandscape
                      ? mediaQuery.size.height * 0.85
                      : mediaQuery.size.height * 0.75,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          label,
                          style: dialogTheme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: options.map((opt) {
                              final isSelected = opt.value == value;
                              return RadioListTile<T>(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                activeColor: cs.primary,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 0,
                                ),
                                value: opt.value,
                                groupValue: value,
                                title: Text(
                                  opt.label,
                                  style: dialogTheme.textTheme.bodyMedium
                                      ?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isSelected ? cs.primary : null,
                                  ),
                                ),
                                subtitle: opt.subtitle != null
                                    ? Text(
                                        opt.subtitle!,
                                        style: dialogTheme
                                            .textTheme.bodySmall
                                            ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      )
                                    : null,
                                onChanged: (T? newValue) {
                                  if (newValue != null) {
                                    Navigator.of(dialogContext).pop();
                                    onChanged(newValue);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
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
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    children: [
                      // ── SECTION 1: TOOLBAR LAYOUT ──────────────────────────────
                      _buildSectionHeader('Toolbar Layout'),
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
                                  action.label,
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

                      // ── SECTION 2: BROWSER LAYOUT ──────────────────────────────
                      _buildSectionHeader('Browser Layout'),
                      _buildSectionGroup(
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
                            title: Text('Show Breadcrumb Bar',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text('Path navigation bar at top of browser',
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
                            title: Text('Show Stats Bar',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                'File count and free space info banner',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.analytics_outlined,
                                color: cs.primary),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ── SECTION 3: MEDIA VIEWER ────────────────────────────────
                      _buildSectionHeader('Media Viewer'),
                      _buildSectionGroup(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: _config.showMediaCarousel,
                            onChanged: (v) {
                              setState(() => _config =
                                  _config.copyWith(showMediaCarousel: v));
                              _persist();
                            },
                            title: Text('Show Playlist Carousel',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                'Show thumbnail carousel button when viewing media playlists',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            secondary: Icon(Icons.view_carousel_rounded,
                                color: cs.primary),
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

class _SelectOption<T> {
  final T value;
  final String label;
  final String? subtitle;

  const _SelectOption({
    required this.value,
    required this.label,
    this.subtitle,
  });
}