import 'dart:async';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_empty_state.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_card_row.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_sheet.dart';

class VaultDashboard extends ConsumerStatefulWidget {
  final ValueNotifier<List<MountedContainer>>? mountedNotifier;
  const VaultDashboard({super.key, this.mountedNotifier});

  @override
  ConsumerState<VaultDashboard> createState() => VaultDashboardState();
}

class VaultDashboardState extends ConsumerState<VaultDashboard> with WidgetsBindingObserver {
  SessionLockController get _lockController => ref.read(sessionLockControllerProvider);
  final SwipeRowGroupController _swipeGroup = SwipeRowGroupController();
  bool _isFabVisible = true;

  void reloadDashboard() {
    ref.read(vaultDashboardControllerProvider.notifier).loadAll();
  }

  @override
  void initState() {
    super.initState();
    _lockController.configure(
      settings: () => ref.read(vaultDashboardControllerProvider).appSettings,
      lockAllMountedContainers: _lockAllMountedContainers,
      enforceAppLock: _enforceAppLock,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _swipeGroup.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(vaultDashboardControllerProvider.notifier).handleRefresh();
    }
    _lockController.handleAppLifecycleState(state);
  }

  Future<void> _enforceAppLock() async {
    if (!mounted) return;
    final mode = await disguiseModeApi.getMode();
    if (!mounted) return;

    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);

    if (mode == DisguiseMode.decoy) {
      await SecureScreenPolicy.disableForDecoy();
      return;
    }

    final settings = ref.read(vaultDashboardControllerProvider).appSettings;
    if (settings.useMasterPassword && settings.masterPasswordHash != null) {
      navigator.pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const LockGateScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (route) => false,
      );
    }
  }

  Future<void> _lockAllMountedContainers() async {
    final mountedList = ref.read(vaultDashboardControllerProvider).mounted;
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final controller = ref.read(vaultDashboardControllerProvider.notifier);

    for (final c in List<MountedContainer>.from(mountedList)) {
      if (!controller.acquireLockGuard(c.volId)) continue;
      try {
        await lifecycle.lockContainer(c.uri);
        controller.onContainerLocked(c.volId);
      } finally {
        controller.releaseLockGuard(c.volId);
      }
    }
  }

  Future<void> _showUnlockSheet({String? uri, String? name}) async {
    final state = ref.read(vaultDashboardControllerProvider);
    if (uri != null && state.mounted.any((c) => c.uri == uri)) {
      showAppSnackBar(context, message: context.l10n.containerAlreadyMounted);
      return;
    }
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);

    String? rememberedPassword;
    if (uri != null) {
      final record = state.records[uri];
      if (record?.unlockMethod == ContainerUnlockMethod.rememberPassword) {
        rememberedPassword = await ref.read(containerRepositoryProvider).getPassword(uri);
      }
    }
    final record = uri != null ? state.records[uri] : null;
    final docProvider = record?.documentProvider ?? state.appSettings.defaultDocumentProvider;
    final autoMountFolders = record?.documentProviderFolders
            .where((f) => f.autoMount)
            .map((f) => f.path)
            .toList() ??
        const <String>[];

    MountedContainer? newlyMountedContainer;
    try {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UnlockSheet(
            onMounted: (container, {record}) {
              ref.read(vaultDashboardControllerProvider.notifier).onContainerMounted(container, record: record);
              newlyMountedContainer = container;
            },
            initialUri: uri,
            initialName: name,
            prefillPassword: rememberedPassword,
            documentProvider: docProvider,
            autoMountFolders: autoMountFolders,
            mountedUris: state.mounted.map((c) => c.uri).toList(),
          ),
        ),
      );
      await ref.read(vaultDashboardControllerProvider.notifier).loadAll();
      if (newlyMountedContainer != null && state.appSettings.autoOpenOnUnlock && mounted) {
        _openBrowser(newlyMountedContainer!);
      }
    } finally {
      if (mounted) ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(false);
    }
  }

  Future<void> _showUsbUnlockSheet({ContainerRecord? existingRecord}) async {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);

    String? rememberedPassword;
    if (existingRecord != null && existingRecord.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      rememberedPassword = await ref.read(containerRepositoryProvider).getPassword(existingRecord.uri);
    }

    MountedContainer? newlyMountedContainer;
    try {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UsbUnlockSheet(
            onMounted: (container, {record}) {
              ref.read(vaultDashboardControllerProvider.notifier).onContainerMounted(container, record: record);
              newlyMountedContainer = container;
            },
            onReconnected: (container, migratedRecord, oldUri) {
              ref.read(vaultDashboardControllerProvider.notifier).onUsbContainerReconnected(container, migratedRecord, oldUri);
              newlyMountedContainer = container;
            },
            documentProvider: existingRecord?.documentProvider ?? state.appSettings.defaultDocumentProvider,
            autoMountFolders: existingRecord?.documentProviderFolders
                    .where((f) => f.autoMount)
                    .map((f) => f.path)
                    .toList() ??
                const <String>[],
            existingRecord: existingRecord,
            prefillPassword: rememberedPassword,
          ),
        ),
      );
      await ref.read(vaultDashboardControllerProvider.notifier).loadAll();
      if (newlyMountedContainer != null && state.appSettings.autoOpenOnUnlock && mounted) {
        _openBrowser(newlyMountedContainer!);
      }
    } finally {
      if (mounted) ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(false);
    }
  }

  void _showUsbCreateSheet() {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UsbCreateContainerSheet()),
    ).whenComplete(() {
      if (mounted) ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(false);
    });
  }

  void _showCreateSheet() {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateContainerSheet()),
    ).whenComplete(() {
      if (mounted) ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(false);
    });
  }

  Future<void> _showAddOptionsSheet() async {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);

    bool hasUsb = false;
    try {
      final devices = await ref.read(vaultLifecycleApiProvider).listUsbDevices();
      hasUsb = devices.isNotEmpty;
    } catch (_) {}

    if (!mounted) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(false);
    HapticFeedback.lightImpact();

    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet(
      context: context,
      isScrollControlled: isLandscape,
      constraints: isLandscape ? BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5) : null,
      builder: (sheetContext) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                context.l10n.addAVaultTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: cs.primary,
              title: context.l10n.mountExistingContainerTitle,
              subtitle: context.l10n.mountExistingContainerSubtitle,
              onTap: () {
                Navigator.pop(sheetContext);
                _showUnlockSheet();
              },
            ),
            if (hasUsb) ...[
              SheetOptionTile(
                icon: Icons.usb_rounded,
                iconColor: cs.tertiary,
                title: context.l10n.mountUsbDriveTitle,
                subtitle: context.l10n.mountUsbDriveSubtitle,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showUsbUnlockSheet();
                },
              ),
              SheetOptionTile(
                icon: Icons.usb_off_rounded,
                iconColor: cs.error,
                title: context.l10n.formatUsbDriveTitle,
                subtitle: context.l10n.formatUsbDriveSubtitle,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showUsbCreateSheet();
                },
              ),
            ],
            SheetOptionTile(
              icon: Icons.add_box_rounded,
              iconColor: cs.secondary,
              title: context.l10n.createNewContainerTitle,
              subtitle: context.l10n.createNewContainerSubtitle,
              onTap: () {
                Navigator.pop(sheetContext);
                _showCreateSheet();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showContainerConfig({required String uri, required String currentLabel}) {
    HapticFeedback.mediumImpact();
    final state = ref.read(vaultDashboardControllerProvider);
    final existing = state.records[uri];
    MountedContainer? mountedContainer;
    for (final m in state.mounted) {
      if (m.uri == uri) {
        mountedContainer = m;
        break;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContainerConfigScreen(
          uri: uri,
          currentLabel: currentLabel,
          existingRecord: existing,
          appSettings: state.appSettings,
          mountedContainer: mountedContainer,
          onSaved: (record) =>
              ref.read(vaultDashboardControllerProvider.notifier).updateContainerRecord(uri, record),
        ),
      ),
    );
  }

  Future<void> _openBrowser(MountedContainer container) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileBrowserScreen(
          container: container,
          resolveContainer: (int volId) {
            for (final c in ref.read(vaultDashboardControllerProvider).mounted) {
              if (c.volId == volId) return c;
            }
            return null;
          },
          onUserActivity: () {
            ref.read(vaultDashboardControllerProvider.notifier).onUserActivityForContainer(container.volId);
          },
        ),
      ),
    );
    if (mounted) {
      ref.read(vaultDashboardControllerProvider.notifier).refreshContainerSpace(container.volId);
    }
  }

  void _openItem(VaultListItem item) {
    switch (item) {
      case MountedVaultItem(:final container):
        _openBrowser(container);
      case LockedVaultItem(:final record):
        record.isUsbSource
            ? _showUsbUnlockSheet(existingRecord: record)
            : _showUnlockSheet(uri: item.uri, name: item.name);
    }
  }

  void _requestEdit(VaultListItem item) {
    _showContainerConfig(uri: item.uri, currentLabel: item.name);
  }

  void _requestDelete(VaultListItem item) {
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

  Widget _buildBody(List<VaultListItem> displayItems, VaultDashboardViewState state) {
    if (displayItems.isEmpty && !state.isLoading) {
      return EmptyState(onAdd: _showAddOptionsSheet);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          itemCount: displayItems.length,
          onReorderItem: (oldIndex, newIndex) =>
              ref.read(vaultDashboardControllerProvider.notifier).handleReorder(oldIndex, newIndex),
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final animValue = Curves.easeInOut.transform(animation.value);
                final elevation = Tween<double>(begin: 0, end: 8).transform(animValue);
                return Material(
                  elevation: elevation,
                  color: Colors.transparent,
                  shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  child: child,
                );
              },
              child: child,
            );
          },
          itemBuilder: (context, i) {
            final item = displayItems[i];
            final triggerNudge = i == 0 && !state.appSettings.hasSeenSwipeTutorial;
            return VaultCardRow(
              key: ValueKey(item.uri),
              index: i,
              item: item,
              group: _swipeGroup,
              onOpen: () => _openItem(item),
              onEdit: () => _requestEdit(item),
              onDelete: () => _requestDelete(item),
              onLocked: (volId) =>
                  ref.read(vaultDashboardControllerProvider.notifier).onContainerLocked(volId),
              isRemoving: state.animatingOutUris.contains(item.uri),
              isInserting: state.animatingInUris.contains(item.uri),
              triggerNudge: triggerNudge,
              swapActions: state.appSettings.swapCardActions,
              dragEnabled: state.appSettings.containerSortMode == ContainerSortMode.manual,
              onNudgeComplete: () async {
                final updated = state.appSettings.copyWith(hasSeenSwipeTutorial: true);
                await ref.read(appSettingsServiceProvider).saveSettings(updated);
                ref.read(vaultDashboardControllerProvider.notifier).loadAll();
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultDashboardControllerProvider);
    final displayItems = ref.read(vaultDashboardControllerProvider.notifier).getDisplayItems();

    if (widget.mountedNotifier != null) {
      widget.mountedNotifier!.value = List.unmodifiable(state.mounted);
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final double undoBarHeight = 64.0 + (bottomInset > 0 ? bottomInset : 16.0);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lockController.scheduleAutoLock(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          title: Text(
            context.l10n.appNameVaultExplorer,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: const [
            AppBarTransferButton(),
            AppBarClipboardButton(),
            SizedBox(width: 4),
          ],
        ),
        body: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            final direction = notification.direction;
            if (direction == ScrollDirection.forward) {
              if (!_isFabVisible) setState(() => _isFabVisible = true);
            } else if (direction == ScrollDirection.reverse) {
              if (_isFabVisible) setState(() => _isFabVisible = false);
            }
            return false;
          },
          child: Stack(
            children: [
              _buildBody(displayItems, state),
            ],
          ),
        ),
        floatingActionButton: AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          offset: _isFabVisible ? Offset.zero : const Offset(0, 2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isFabVisible ? 1.0 : 0.0,
            child: SizedBox(
              width: 64,
              height: 64,
              child: FloatingActionButton(
                onPressed: _isFabVisible ? _showAddOptionsSheet : null,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ),
        ),
        bottomNavigationBar: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: state.showUndoBar ? undoBarHeight : 0.0,
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Container(
              height: undoBarHeight,
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? bottomInset : 16.0),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                offset: state.showUndoBar ? Offset.zero : const Offset(0, 1.5),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: state.showUndoBar ? 1.0 : 0.0,
                  child: _FloatingUndoBar(
                    label: state.recentlyDeletedRecord?.label ?? '',
                    onUndo: () => ref.read(vaultDashboardControllerProvider.notifier).handleUndo(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingUndoBar extends StatelessWidget {
  final String label;
  final VoidCallback onUndo;
  const _FloatingUndoBar({required this.label, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return FloatingPill(
      color: cs.inverseSurface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_outline_rounded,
            size: AppIconSize.standard,
            color: cs.onInverseSurface,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: AnimatedSwitcher(
              duration: AppMotion.short2,
              child: Text(
                context.l10n.removedLabelUndo(label),
                key: ValueKey(label),
                style: textTheme.labelLarge?.copyWith(
                  color: cs.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(
              foregroundColor: cs.inversePrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              context.l10n.undo,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}