import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_sheet.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';

class AppNavigationDrawer extends ConsumerWidget {
  final int? currentVolId;
  final MountedContainer? primaryLocalContainer;
  final int selectedTabIndex;
  final ValueChanged<int>? onSelectTab;
  final ValueChanged<MountedContainer>? onSelectContainer;
  final ValueChanged<VaultListItem>? onUnlockVault;
  final ValueChanged<VaultListItem>? onEditVault;
  final ValueChanged<VaultListItem>? onDeleteVault;
  final VoidCallback? onAddVault;

  const AppNavigationDrawer({
    super.key,
    this.currentVolId,
    this.primaryLocalContainer,
    this.selectedTabIndex = 0,
    this.onSelectTab,
    this.onSelectContainer,
    this.onUnlockVault,
    this.onEditVault,
    this.onDeleteVault,
    this.onAddVault,
  });

  void _navigateToTab(BuildContext context, int tabIndex) {
    Navigator.pop(context); // Close drawer
    // If inside a vault/storage browser, pop it to return to MainShell
    if (currentVolId != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    onSelectTab?.call(tabIndex);
  }

  void _promptRename(BuildContext context, WidgetRef ref, ExternalStorageLocation loc) {
    final ctrl = TextEditingController(text: loc.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.renameStorageLocationTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.displayNameTitle),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                ref.read(externalStorageLocationsProvider.notifier).renameLocation(loc.id, text);
              }
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref, ExternalStorageLocation loc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.removeStorageLocationTitle),
        content: Text(context.l10n.removeStorageLocationConfirm(loc.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(
            onPressed: () {
              ref.read(externalStorageLocationsProvider.notifier).removeLocation(loc.id);
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
  }

  Future<void> _lockSingleVault(BuildContext context, WidgetRef ref, MountedContainer container) async {
    try {
      await ref.read(vaultLifecycleApiProvider).lockContainer(container.uri);
      ref.read(vaultDashboardControllerProvider.notifier).onContainerLocked(container.volId);
    } catch (_) {}
  }

  void _handleEditVault(BuildContext context, WidgetRef ref, VaultListItem item) {
    if (onEditVault != null) {
      onEditVault!(item);
      return;
    }
    final state = ref.read(vaultDashboardControllerProvider);
    final existing = state.records[item.uri];
    MountedContainer? mountedC;
    for (final m in state.mounted) {
      if (m.uri == item.uri) {
        mountedC = m;
        break;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContainerConfigScreen(
          uri: item.uri,
          currentLabel: item.name,
          existingRecord: existing,
          appSettings: state.appSettings,
          mountedContainer: mountedC,
          onSaved: (record) =>
              ref.read(vaultDashboardControllerProvider.notifier).updateContainerRecord(item.uri, record),
        ),
      ),
    );
  }

  void _handleDeleteVault(BuildContext context, WidgetRef ref, VaultListItem item) {
    if (onDeleteVault != null) {
      onDeleteVault!(item);
      return;
    }
    if (item.isMounted) {
      showAppSnackBar(
        context,
        message: context.l10n.lockBeforeRemovingWarning,
        tone: AppBannerTone.warning,
      );
      return;
    }
    ref.read(vaultDashboardControllerProvider.notifier).handleSwipeToRemove(
          item.uri,
          (item as LockedVaultItem).record,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dashboardState = ref.watch(vaultDashboardControllerProvider);
    final displayItems = ref.read(vaultDashboardControllerProvider.notifier).getDisplayItems();
    final externalStorages = ref.watch(externalStorageLocationsProvider);
    // Whole "Storage Locations" section (Local Storage + added locations +
    // the add button) is toggled from Settings. Hiding it only affects this
    // drawer; [primaryLocalContainer] stays resolvable for cross-container
    // paste regardless.
    final showStorageLocations = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.showStorageLocationsInDrawer),
    );
    final primary = primaryLocalContainer;

    final isDashboard = currentVolId == null && selectedTabIndex == 0;
    final isTools = currentVolId == null && selectedTabIndex == 1;
    final isSettings = currentVolId == null && selectedTabIndex == 2;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // 1. Dashboard (Home)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    selected: isDashboard,
                    selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                    leading: Icon(
                      Icons.dashboard_rounded,
                      color: isDashboard ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.dashboardNavLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isDashboard ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    onTap: () => _navigateToTab(context, 0),
                  ),

                  // 2. Encrypted Vaults Section (Swipeable Rows with Lock Button)
                  if (displayItems.isNotEmpty || onAddVault != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 6),
                      child: Text(
                        context.l10n.vaultsSectionTitle,
                        style: textTheme.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    for (final item in displayItems) ...[
                      (() {
                        final isMounted = item.isMounted;
                        final volId = item is MountedVaultItem ? item.container.volId : null;
                        final isCurrent = volId != null && volId == currentVolId;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _DrawerSwipeableVaultRow(
                            key: ValueKey('drawer_vault_${item.uri}'),
                            item: item,
                            isCurrent: isCurrent,
                            onTap: () {
                              Navigator.pop(context); // Close drawer
                              if (isCurrent) return;
                              if (item is MountedVaultItem) {
                                onSelectContainer?.call(item.container);
                              } else {
                                // If inside a vault browser, pop back to Dashboard
                                if (currentVolId != null && Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                                onSelectTab?.call(0);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  onUnlockVault?.call(item);
                                });
                              }
                            },
                            onLock: isMounted
                                ? () async {
                                    final container = (item as MountedVaultItem).container;
                                    Navigator.pop(context); // Close drawer only
                                    await _lockSingleVault(context, ref, container);
                                  }
                                : null,
                            onEdit: () {
                              Navigator.pop(context);
                              _handleEditVault(context, ref, item);
                            },
                            onDelete: () {
                              Navigator.pop(context);
                              _handleDeleteVault(context, ref, item);
                            },
                          ),
                        );
                      })(),
                    ],
                    if (onAddVault != null)
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        leading: Icon(Icons.add, color: cs.primary),
                        title: Text(
                          context.l10n.addAVaultTitle,
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          if (currentVolId != null && Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          onSelectTab?.call(0);
                          onAddVault!();
                        },
                      ),
                  ],

                  if (showStorageLocations) ...[
                    // 3. Storage Locations Section
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 6),
                      child: Text(
                        context.l10n.storageLocationsTitle,
                        style: textTheme.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    if (primary != null)
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        selected: currentVolId == kDecoyLocalVolId,
                        selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                        leading: Icon(
                          Icons.phone_android_rounded,
                          color: currentVolId == kDecoyLocalVolId ? cs.primary : cs.onSurfaceVariant,
                        ),
                        title: Text(
                          context.l10n.localStorageCardTitle,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: currentVolId == kDecoyLocalVolId ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.internalStorageSubtitle,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          if (currentVolId == kDecoyLocalVolId) return;
                          onSelectContainer?.call(primary);
                        },
                      ),

                    for (final loc in externalStorages) ...[
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        selected: currentVolId == loc.volId,
                        selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                        leading: Icon(
                          loc.path.startsWith('content://') ? Icons.cloud_outlined : Icons.sd_card_rounded,
                          color: currentVolId == loc.volId ? cs.primary : cs.secondary,
                        ),
                        title: Text(
                          loc.displayName,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: currentVolId == loc.volId ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          loc.path.startsWith('content://')
                              ? context.l10n.safProviderLabel
                              : loc.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
                          onSelected: (action) {
                            if (action == 'rename') {
                              _promptRename(context, ref, loc);
                            } else if (action == 'remove') {
                              _confirmRemove(context, ref, loc);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'rename', child: Text(context.l10n.rename)),
                            PopupMenuItem(value: 'remove', child: Text(context.l10n.remove)),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          if (currentVolId == loc.volId) return;
                          final isInternal = loc.path.startsWith('/storage/emulated/0') ||
                              loc.path.startsWith('/data/user/0');
                          final targetUri = (!isInternal && loc.treeUri != null && loc.treeUri!.isNotEmpty)
                              ? loc.treeUri!
                              : loc.path;
                          onSelectContainer?.call(buildExternalStorageContainer(
                            rootPath: targetUri,
                            displayName: loc.displayName,
                            volId: loc.volId,
                          ));
                        },
                      ),
                    ],

                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      leading: Icon(Icons.add, color: cs.primary),
                      title: Text(
                        context.l10n.addStorageLocationTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () async {
                        final notifier = ref.read(externalStorageLocationsProvider.notifier);
                        final loc = await notifier.promptAndAddLocation();
                        if (!context.mounted) return;
                        if (loc != null) {
                          Navigator.pop(context);
                          onSelectContainer?.call(buildExternalStorageContainer(
                            rootPath: loc.path,
                            displayName: loc.displayName,
                            volId: loc.volId,
                          ));
                        }
                      },
                    ),
                  ],

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(),
                  ),

                  // 4. Tools Destination
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    selected: isTools,
                    selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                    leading: Icon(
                      Icons.build_rounded,
                      color: isTools ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.navBarToolsLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isTools ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ToolsScreen(
                            mountedContainers: ValueNotifier(dashboardState.mounted),
                          ),
                        ),
                      );
                    },
                  ),

                  // 5A. File Manager Settings (Toolbar, layout, thumbnails)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    leading: Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
                    title: Text(context.l10n.fileManagerSettingsTitle),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FileManagerToolbarSettingsScreen(),
                        ),
                      );
                    },
                  ),

                  // 5B. App & Security Settings (Master password, auto-lock, backup)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    selected: isSettings,
                    selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                    leading: Icon(
                      Icons.settings,
                      color: isSettings ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.settingsMenuItem,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isSettings ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppSettingsScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // 6. Quick Action: Lock All Vaults
                  if (dashboardState.mounted.isNotEmpty)
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      leading: Icon(Icons.lock_rounded, color: cs.error),
                      title: Text(
                        context.l10n.lockAllVaultsTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        for (final c in dashboardState.mounted) {
                          ref.read(vaultLifecycleApiProvider).lockContainer(c.uri);
                          ref.read(vaultDashboardControllerProvider.notifier).onContainerLocked(c.volId);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SWIPEABLE VAULT ROW FOR DRAWER (Swipe Right to Reveal Actions) ───────────

class _DrawerSwipeableVaultRow extends StatefulWidget {
  final VaultListItem item;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onLock;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DrawerSwipeableVaultRow({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onTap,
    required this.onLock,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DrawerSwipeableVaultRow> createState() => _DrawerSwipeableVaultRowState();
}

class _DrawerSwipeableVaultRowState extends State<_DrawerSwipeableVaultRow>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 104.0;
  late final AnimationController _animController;
  double _dx = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    final start = _dx;
    _animController.stop();
    _animController.reset();
    final anim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    void listener() => setState(() => _dx = anim.value);
    anim.addListener(listener);
    _animController.forward().whenComplete(() => anim.removeListener(listener));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMounted = widget.item.isMounted;

    // Fix: Use an opaque solid color so underlying buttons never bleed through
    final tileColor = widget.isCurrent
        ? Color.alphaBlend(cs.secondaryContainer.withValues(alpha: 0.6), cs.surfaceContainerHigh)
        : cs.surfaceContainerHigh;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          // Background action buttons placed on the START/LEFT side
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    _animateTo(0.0);
                    widget.onEdit();
                  },
                  child: Container(
                    width: 52,
                    color: cs.secondaryContainer,
                    alignment: Alignment.center,
                    child: Icon(Icons.edit_outlined, size: 20, color: cs.onSecondaryContainer),
                  ),
                ),
                InkWell(
                  onTap: () {
                    _animateTo(0.0);
                    widget.onDelete();
                  },
                  child: Container(
                    width: 52,
                    color: cs.errorContainer,
                    alignment: Alignment.center,
                    child: Icon(Icons.delete_outline_rounded, size: 20, color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),

          // Front ListTile that translates RIGHT on drag
          RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _RightHorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<_RightHorizontalDragGestureRecognizer>(
                () => _RightHorizontalDragGestureRecognizer(),
                (_RightHorizontalDragGestureRecognizer instance) {
                  instance.dragStartBehavior = DragStartBehavior.start;
                  instance.canDragLeft = () => _dx > 1.0;
                  instance.onDown = (_) {};
                  instance.onStart = (_) {};
                  instance.onUpdate = (details) {
                    setState(() {
                      // Allow positive drag (to the right) up to _revealWidth
                      _dx = (_dx + details.delta.dx).clamp(0.0, _revealWidth);
                    });
                  };
                  instance.onEnd = (details) {
                    if (_dx > _revealWidth / 2) {
                      _animateTo(_revealWidth);
                    } else {
                      _animateTo(0.0);
                    }
                  };
                  instance.onCancel = () {
                    if (_dx > 0.0 && _dx < _revealWidth) {
                      _animateTo(0.0);
                    }
                  };
                },
              ),
            },
            child: Transform.translate(
              offset: Offset(_dx, 0.0),
              child: Material(
                color: tileColor, // Opaque solid color
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  contentPadding: const EdgeInsets.only(left: 12, right: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.isCurrent
                          ? cs.primary.withValues(alpha: 0.2)
                          : (isMounted ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerHighest),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isMounted ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                      size: 18,
                      color: isMounted ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  title: Text(
                    widget.item.name,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: widget.isCurrent ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    isMounted
                        ? context.l10n.vaultStatusMounted
                        : context.l10n.vaultStatusLocked,
                    style: textTheme.labelSmall?.copyWith(
                      color: isMounted ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: widget.onLock != null
                      ? IconButton(
                          icon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.onSurfaceVariant),
                          tooltip: context.l10n.lockVaultTooltip,
                          onPressed: widget.onLock,
                        )
                      : null,
                  onTap: () {
                    if (_dx != 0.0) {
                      _animateTo(0.0);
                    } else {
                      widget.onTap();
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal drag gesture recognizer that yields to parent gestures (such as
/// the drawer close swipe) when a drag starts to the left while the card is closed.
class _RightHorizontalDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  bool Function()? canDragLeft;
  double _accumulatedDx = 0.0;
  bool _isAccepted = false;

  _RightHorizontalDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _accumulatedDx = 0.0;
    _isAccepted = false;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _isAccepted = true;
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _isAccepted = false;
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _isAccepted = false;
    _accumulatedDx = 0.0;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _accumulatedDx += event.delta.dx;
      // If the card is closed and dragging left past 4px, yield immediately
      // so DrawerController can close the drawer smoothly.
      if (!_isAccepted && _accumulatedDx < -4.0 && (canDragLeft == null || !canDragLeft!())) {
        resolve(GestureDisposition.rejected);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  bool isFlingGesture(VelocityEstimate estimate, PointerDeviceKind kind) {
    if ((canDragLeft == null || !canDragLeft!()) && estimate.pixelsPerSecond.dx < 0) {
      return false;
    }
    return super.isFlingGesture(estimate, kind);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final slop = deviceTouchSlop ?? computeHitSlop(pointerDeviceKind, gestureSettings);
    // Accept right drag when opening
    if (_accumulatedDx > slop) {
      return true;
    }
    // Accept left drag only when card is already open and needs to be closed
    if (_accumulatedDx < -slop && (canDragLeft != null && canDragLeft!())) {
      return true;
    }
    return false;
  }
}