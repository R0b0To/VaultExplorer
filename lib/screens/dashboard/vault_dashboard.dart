import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/mounted_container.dart';
import '../../models/vault_list_item.dart';
import '../../services/app_settings_service.dart';
import '../../services/cross_container_clipboard.dart';
import '../../services/session_lock_controller.dart';
import '../../services/vaultexplorer_api.dart';
import '../../widgets/common_widgets.dart';
import '../settings/app_settings_screen.dart';
import '../unlock/unlock_sheet.dart';
import 'widgets/container_card.dart';
import 'widgets/container_config_sheet.dart';
import 'widgets/create_container_sheet.dart';
import 'widgets/empty_state.dart';
import '../browser/file_browser_screen.dart';
import '../unlock/usb_unlock_sheet.dart';
import '../lock/lock_gate_screen.dart';

enum VaultSortField { name, date, size, status }

class SlideRightRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  SlideRightRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        );
}

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({Key? key}) : super(key: key);

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

class _VaultDashboardState extends State<VaultDashboard>
    with WidgetsBindingObserver {
  final List<MountedContainer> _mounted = [];
  Map<String, ContainerRecord> _records = {};
  final List<String> _recordsOrder = [];
  AppSettings _appSettings = AppSettings();
  bool _actionInFlight = false;
  bool _isLoading = true;
  int _currentIndex = 0; // 0: Vaults, 1: Settings

  VaultSortField _sortField = VaultSortField.name;
  bool _sortAscending = true;

  final Map<int, Timer> _autoCloseTimers = {};

  // All auto-lock/lifecycle/screen-off *policy* now lives in this
  // controller — the dashboard just wires it to lifecycle callbacks and
  // gives it a couple of hooks back into dashboard-specific behavior
  // (locking every mounted container, showing the lock-gate screen).
  late final SessionLockController _lockController;

  @override
  void initState() {
    super.initState();
    _lockController = SessionLockController(
      settings: () => _appSettings,
      lockAllMountedContainers: _lockAllMountedContainers,
      enforceAppLock: _enforceAppLock,
    );
    WidgetsBinding.instance.addObserver(this);
    VaultExplorerApi.addUsbContainerDetachedListener(_onUsbContainerDetached);
    VaultExplorerApi.addScreenOffListener(_lockController.handleScreenOff);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _autoCloseTimers.values) t.cancel();
    _autoCloseTimers.clear();
    _lockController.dispose();
    VaultExplorerApi.removeUsbContainerDetachedListener(_onUsbContainerDetached);
    VaultExplorerApi.removeScreenOffListener(_lockController.handleScreenOff);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final c in List<MountedContainer>.from(_mounted)) {
        _refreshContainerSpace(c.volId);
      }
    }
    _lockController.handleAppLifecycleState(state);
  }

  Future<void> _enforceAppLock() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    if (_appSettings.useMasterPassword && _appSettings.masterPasswordHash != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LockGateScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _lockAllMountedContainers() async {
    for (final c in List<MountedContainer>.from(_mounted)) {
      if (!vaultExplorerApi.acquireLockGuard(c.volId)) continue;
      try {
        await vaultExplorerApi.lockContainer(c.uri);
        _onContainerLocked(c.volId);
      } catch (e) {
        debugPrint('Auto-lock failed for volId=${c.volId}: $e');
      } finally {
        vaultExplorerApi.releaseLockGuard(c.volId);
      }
    }
  }

  Future<void> _loadAll() async {
    final settings = await AppSettingsService.loadSettings();
    final records = await ContainerRepository.instance.loadAll();
    if (mounted) {
      setState(() {
        _appSettings = settings;
        _records = Map.from(records);
        _recordsOrder.clear();
        _recordsOrder.addAll(records.keys);
        _isLoading = false;
      });
      _lockController.scheduleAutoLock();
    }
  }

  Future<void> _handleRefresh() async {
    await _loadAll();
    await Future.wait(
      List<MountedContainer>.from(_mounted).map((c) => _refreshContainerSpace(c.volId)),
    );
  }

  // ── Auto-close ────────────────────────────────────────────────────────────

  void _scheduleAutoClose(MountedContainer container) {
    final record = _records[container.uri];
    final mins = record?.autoCloseMins ?? 0;
    if (mins <= 0) {
      _cancelAutoClose(container.volId);
      return;
    }

    _autoCloseTimers[container.volId]?.cancel();
    _autoCloseTimers[container.volId] = Timer(
      Duration(minutes: mins),
      () async {
        if (!mounted) return;

        if (!vaultExplorerApi.acquireLockGuard(container.volId)) {
          if (mounted) {
            _autoCloseTimers[container.volId] = Timer(
              const Duration(seconds: 30),
              () {
                if (mounted) _scheduleAutoClose(container);
              },
            );
          }
          return;
        }

        try {
          await vaultExplorerApi.lockContainer(container.uri);
          if (!mounted) return;
          _onContainerLocked(container.volId);
        } catch (e) {
          debugPrint('Auto-close lock failed for volId=${container.volId}: $e');
        } finally {
          vaultExplorerApi.releaseLockGuard(container.volId);
        }
      },
    );
  }

  void _onUserActivityForContainer(int volId) {
    final idx = _mounted.indexWhere((c) => c.volId == volId);
    if (idx == -1) return;
    final container = _mounted[idx];
    final record = _records[container.uri];
    if ((record?.autoCloseMins ?? 0) > 0) {
      _scheduleAutoClose(container);
    }
    _lockController.scheduleAutoLock();
  }

  void _cancelAutoClose(int volId) {
    _autoCloseTimers[volId]?.cancel();
    _autoCloseTimers.remove(volId);
  }

  // ── Container lifecycle ───────────────────────────────────────────────────

  void _onContainerMounted(MountedContainer container, {ContainerRecord? record}) {
    if (_mounted.any((c) => c.uri == container.uri)) return;

    setState(() {
      _mounted.add(container);
      if (record != null && !_records.containsKey(container.uri)) {
        _records[container.uri] = record;
        _recordsOrder.add(container.uri);
      }
    });
    _scheduleAutoClose(container);
  }

  void _onUsbContainerDetached(int volId) {
    if (!mounted) return;
    if (!_mounted.any((c) => c.volId == volId)) return;
    _onContainerLocked(volId);
    showAppSnackBar(
      context,
      message: 'USB drive disconnected — container locked',
      tone: AppBannerTone.warning,
    );
  }

  void _onUsbContainerReconnected(
    MountedContainer container,
    ContainerRecord migratedRecord,
    String oldUri,
  ) {
    if (_mounted.any((c) => c.uri == container.uri)) return;

    setState(() {
      _mounted.add(container);
      _records.remove(oldUri);
      _recordsOrder.remove(oldUri);
      _records[container.uri] = migratedRecord;
      _recordsOrder.add(container.uri);
    });
    _scheduleAutoClose(container);
  }

  void _onContainerLocked(int volId) {
    _cancelAutoClose(volId);

    final clip = CrossContainerClipboard.instance;
    if (clip.hasItems && clip.sourceVolId == volId) {
      clip.clear();
    }

    if (mounted) {
      setState(() => _mounted.removeWhere((c) => c.volId == volId));
    }
  }

  Future<void> _refreshContainerSpace(int volId) async {
    final idx = _mounted.indexWhere((c) => c.volId == volId);
    if (idx == -1) return;
    final container = _mounted[idx];
    try {
      final space = await vaultExplorerApi.getSpaceInfo(container);
      if (space != null && space.length > 1 && mounted) {
        setState(() {
          final currentIdx = _mounted.indexWhere((c) => c.volId == volId);
          if (currentIdx != -1) {
            _mounted[currentIdx] = container.copyWith(
              totalSpace: space[0],
              freeSpace: space[1],
            );
          }
        });
      }
    } catch (_) {}
  }

  // ── Unlock & Create Actions ───────────────────────────────────────────────

  Future<void> _showUnlockSheet({String? uri, String? name}) async {
    if (uri != null && _mounted.any((c) => c.uri == uri)) {
      showAppSnackBar(context, message: 'This container is already mounted.');
      return;
    }

    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);

    String? rememberedPassword;
    if (uri != null) {
      final record = _records[uri];
      if (record?.unlockMethod == ContainerUnlockMethod.rememberPassword) {
        rememberedPassword = await ContainerRepository.instance.getPassword(uri);
      }
    }

    final record = uri != null ? _records[uri] : null;
    final docProvider = record?.documentProvider ?? _appSettings.defaultDocumentProvider;

    try {
      await Navigator.push(
        context,
        SlideRightRoute(
          page: UnlockSheet(
            onMounted: _onContainerMounted,
            initialUri: uri,
            initialName: name,
            prefillPassword: rememberedPassword,
            documentProvider: docProvider,
            mountedUris: _mounted.map((c) => c.uri).toList(),
          ),
        ),
      );
      await _loadAll();
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  Future<void> _showUsbUnlockSheet({ContainerRecord? existingRecord}) async {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);

    String? rememberedPassword;
    if (existingRecord != null && existingRecord.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      rememberedPassword = await ContainerRepository.instance.getPassword(existingRecord.uri);
    }

    try {
      await Navigator.push(
        context,
        SlideRightRoute(
          page: UsbUnlockSheet(
            onMounted: _onContainerMounted,
            onReconnected: _onUsbContainerReconnected,
            documentProvider: existingRecord?.documentProvider ?? _appSettings.defaultDocumentProvider,
            existingRecord: existingRecord,
            prefillPassword: rememberedPassword,
          ),
        ),
      );
      await _loadAll();
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  void _showCreateSheet() {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    Navigator.push(
      context,
      SlideRightRoute(page: const CreateContainerSheet()),
    ).whenComplete(() {
      if (mounted) setState(() => _actionInFlight = false);
    });
  }

  void _showAddOptionsSheet() {
    HapticFeedback.lightImpact();
    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    showModalBottomSheet(
      context: context,
      isScrollControlled: isLandscape,
      constraints: isLandscape
          ? BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.5,
            )
          : null,
      builder: (sheetContext) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                'Add a vault',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: cs.primary,
              title: 'Mount existing container',
              subtitle: 'Unlock a VeraCrypt file you already have',
              onTap: () {
                Navigator.pop(sheetContext);
                _showUnlockSheet();
              },
            ),
            SheetOptionTile(
              icon: Icons.usb_rounded,
              iconColor: cs.tertiary,
              title: 'Mount USB drive',
              subtitle: 'Unlock a container on an OTG flash drive',
              onTap: () {
                Navigator.pop(sheetContext);
                _showUsbUnlockSheet();
              },
            ),
            SheetOptionTile(
              icon: Icons.add_box_rounded,
              iconColor: cs.secondary,
              title: 'Create new container',
              subtitle: 'Format a brand-new encrypted vault',
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
    final existing = _records[uri];
    Navigator.push(
      context,
      SlideLeftRoute(
        page: ContainerConfigScreen(
          uri: uri,
          currentLabel: currentLabel,
          existingRecord: existing,
          appSettings: _appSettings,
          onSaved: (record) async {
            if (mounted) setState(() => _records[uri] = record);
            final idx = _mounted.indexWhere((m) => m.uri == uri);
            if (idx != -1) {
              final oldContainer = _mounted[idx];
              final newName = record.label.isNotEmpty ? record.label : record.uri.split('/').last;
              final newContainer = oldContainer.copyWith(displayName: newName);
              if (mounted) setState(() => _mounted[idx] = newContainer);

              await vaultExplorerApi.updateContainerSettings(uri, newName, record.documentProvider);
              _scheduleAutoClose(newContainer);
            }
          },
          onForget: _mounted.any((m) => m.uri == uri) ? null : () => _forgetContainer(uri, currentLabel),
        ),
      ),
    );
  }

  Future<bool> _forgetContainer(String uri, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove container?'),
        content: Text('Remove "$name" from the dashboard? The container file is not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ContainerRepository.instance.remove(uri);
      if (mounted) {
        setState(() {
          _records.remove(uri);
          _recordsOrder.remove(uri);
        });
      }
      return true;
    }
    return false;
  }

  void _handleSwipeToRemove(String uri, ContainerRecord record) async {
    setState(() {
      _records.remove(uri);
      _recordsOrder.remove(uri);
    });
    await ContainerRepository.instance.remove(uri);

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('Removed "${record.label}" from dashboard'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            messenger.hideCurrentSnackBar();
            await ContainerRepository.instance.save(record);
            if (mounted) {
              setState(() {
                _records[uri] = record;
                _recordsOrder.add(uri);
              });
            }
          },
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      controller.close();
    });
  }

  // ── Navigate to browser ───────────────────────────────────────────────────

  Future<void> _openBrowser(MountedContainer container) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileBrowserScreen(
          container: container,
          resolveContainer: (int volId) {
            for (final c in _mounted) {
              if (c.volId == volId) return c;
            }
            return null;
          },
          onUserActivity: () {
            if (_mounted.any((c) => c.volId == container.volId)) {
              _onUserActivityForContainer(container.volId);
            }
          },
        ),
      ),
    );
    if (mounted) _refreshContainerSpace(container.volId);
  }

  // ── Display list ─────────────────────────────────────────────────────────

  // "Sort by Date Added" proxy. Neither model has a real timestamp for this:
  //   - MountedContainer only has `mountedAt`, which is a *last-unlocked*
  //     time — using it would make the sort order jump around on every
  //     re-unlock (see mounted_container.dart).
  //   - ContainerRecord has no date field at all — nothing chronological is
  //     even persisted to containers_v2.json (see container_repository.dart).
  // So this stands in for "date added" using the order records come back
  // from ContainerRepository.loadAll(). That's stable across app restarts:
  // _persist() writes `_cache!.values` (a LinkedHashMap, so insertion order),
  // and re-saving an existing record doesn't move its position — Map's `[]=`
  // on an existing key keeps its original slot. So first-added stays first
  // unless the record is removed and re-added.
  //
  // If you want a real "added" date shown/sorted, the fix is upstream: add
  // `final DateTime createdAt` to ContainerRecord (stamped once, on first
  // save — see ContainerRepository.save), default legacy JSON entries that
  // predate the field to whatever this proxy already gives them so existing
  // sort order doesn't jump on upgrade, then this function goes away.
  DateTime _dateAddedProxy(String uri) {
    final idx = _recordsOrder.indexOf(uri);
    if (idx != -1) return DateTime.fromMillisecondsSinceEpoch(idx * 1000);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<VaultListItem> _buildDisplayItems() {
    final items = <VaultListItem>[
      for (final c in _mounted)
        MountedVaultItem(c, sortDate: _dateAddedProxy(c.uri)),
      for (final entry in _records.entries)
        if (!_mounted.any((m) => m.uri == entry.key))
          LockedVaultItem(entry.value, sortDate: _dateAddedProxy(entry.key)),
    ];

    items.sort((a, b) {
      final result = switch (_sortField) {
        VaultSortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        VaultSortField.date => a.sortDate.compareTo(b.sortDate),
        VaultSortField.size => a.size.compareTo(b.size),
        VaultSortField.status => (a.isMounted ? 1 : 0).compareTo(b.isMounted ? 1 : 0),
      };
      return _sortAscending ? result : -result;
    });

    return items;
  }

  // ── Tab Builders ──────────────────────────────────────────────────────────

  List<PopupMenuEntry<VaultSortField>> _sortMenuItems() => const [
        PopupMenuItem(
          value: VaultSortField.name,
          child: Row(
            children: [
              Icon(Icons.sort_by_alpha_rounded),
              SizedBox(width: 10),
              Text('Sort by Name'),
            ],
          ),
        ),
        PopupMenuItem(
          value: VaultSortField.date,
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded),
              SizedBox(width: 10),
              Text('Sort by Date Added'),
            ],
          ),
        ),
        PopupMenuItem(
          value: VaultSortField.size,
          child: Row(
            children: [
              Icon(Icons.sd_card_outlined),
              SizedBox(width: 10),
              Text('Sort by Size'),
            ],
          ),
        ),
        PopupMenuItem(
          value: VaultSortField.status,
          child: Row(
            children: [
              Icon(Icons.toggle_on_rounded),
              SizedBox(width: 10),
              Text('Sort by Mount Status'),
            ],
          ),
        ),
      ];

  List<Widget> _buildAppBarActions() {
    return [
      PopupMenuButton<VaultSortField>(
        icon: const Icon(Icons.sort_rounded),
        tooltip: 'Sort options',
        initialValue: _sortField,
        onSelected: (field) => setState(() => _sortField = field),
        itemBuilder: (_) => _sortMenuItems(),
      ),
      IconButton(
        icon: Icon(_sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
        tooltip: 'Invert sorting order',
        onPressed: () => setState(() => _sortAscending = !_sortAscending),
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _buildVaultsTab(List<VaultListItem> displayItems, ColorScheme cs, TextTheme textTheme, bool isWide) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: CustomScrollView(
        slivers: [
          // Use standard fixed App Bar in landscape to conserve vertical space.
          isWide
              ? SliverAppBar(
                  pinned: true,
                  floating: true,
                  actions: _buildAppBarActions(),
                )
              : SliverAppBar(

                  actions: _buildAppBarActions(),
                ),
          if (displayItems.isEmpty && !_isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(onAdd: _showAddOptionsSheet),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              sliver: isWide
                  ? SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 420, // Forces dynamic column calculation
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: 140, // Reduced for landscape viewport
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _buildVaultListTile(displayItems[i], i, cs),
                        childCount: displayItems.length,
                      ),
                    )
                  : SliverList.separated(
                      itemCount: displayItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (_, i) => _buildVaultListTile(displayItems[i], i, cs),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildVaultListTile(VaultListItem item, int index, ColorScheme cs) {
    final uri = item.uri;
    final label = item.name;

    return StaggeredEntrance(
      index: index,
      child: Dismissible(
        key: Key('dismiss_$uri'),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (direction) async {
          if (item.isMounted) {
            showAppSnackBar(
              context,
              message: 'Lock the container before removing it.',
              tone: AppBannerTone.warning,
            );
            return false;
          }
          return true;
        },
        onDismissed: (direction) {
          _handleSwipeToRemove(uri, (item as LockedVaultItem).record);
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 24),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(Icons.delete_outline_rounded, color: cs.onErrorContainer),
        ),
        // AnimatedSize handles smoothly expanding/collapsing the card's vertical height
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          // AnimatedSwitcher coordinates the fading transition between state-specific keys
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            // The compiler checks this switch is exhaustive over the sealed
            // VaultListItem hierarchy — add a third subtype later and this
            // won't compile until you handle it here too.
            child: switch (item) {
              MountedVaultItem(:final container) => ContainerCard(
                  key: ValueKey('mounted_$uri'),
                  container: container,
                  onLocked: _onContainerLocked,
                  onBrowse: () => _openBrowser(container),
                  onLongPress: () => _showContainerConfig(uri: uri, currentLabel: label),
                ),
              LockedVaultItem(:final record) => SavedContainerCard(
                  key: ValueKey('locked_$uri'),
                  name: label,
                  uri: uri,
                  onUnlock: () => record.isUsbSource
                      ? _showUsbUnlockSheet(existingRecord: record)
                      : _showUnlockSheet(uri: uri, name: label),
                  onLongPress: () => _showContainerConfig(uri: uri, currentLabel: label),
                ),
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Use a >= 600 dp breakpoint (standard Android class boundary for foldables/tablets in landscape)
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    final displayItems = _buildDisplayItems();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lockController.scheduleAutoLock(),
      child: Scaffold(
        extendBody: true,
        // Show the FAB on the Vaults tab in both portrait and landscape
        floatingActionButton: _currentIndex == 0
            ? FloatingActionButton.extended(
                onPressed: _actionInFlight ? null : _showAddOptionsSheet,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add vault'),
              )
            : null,
        bottomNavigationBar: isWide
            ? null
            : NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() => _currentIndex = index);
                  _loadAll();
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Vaults',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: 'Settings',
                  ),
                ],
              ),
        body: Row(
          children: [
            if (isWide)
              NavigationRail(
                backgroundColor: cs.surface,
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() => _currentIndex = index);
                  _loadAll();
                },
                labelType: NavigationRailLabelType.all,
                leading: const SizedBox(height: 8),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: Text('Vaults'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: Text('Settings'),
                  ),
                ],
              ),
            if (isWide)
              VerticalDivider(
                thickness: 1,
                width: 1,
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _currentIndex,
                    children: [
                      _buildVaultsTab(displayItems, cs, textTheme, isWide),
                      const AppSettingsScreen(),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: ListenableBuilder(
                        listenable: CrossContainerClipboard.instance,
                        builder: (context, _) {
                          final clipboard = CrossContainerClipboard.instance;
                          if (!clipboard.hasItems) return const SizedBox.shrink();
                          return _FloatingClipboardDashboardBanner(
                            clipboard: clipboard,
                            onClear: clipboard.clear,
                          );
                        },
                      ),
                    ),
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

class _FloatingClipboardDashboardBanner extends StatelessWidget {
  final CrossContainerClipboard clipboard;
  final VoidCallback onClear;

  const _FloatingClipboardDashboardBanner({
    required this.clipboard,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: cs.inverseSurface,
        elevation: 0,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                clipboard.isCutOperation ? Icons.cut_rounded : Icons.copy_rounded,
                size: 22,
                color: cs.onInverseSurface,
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clipboard.summary,
                      style: textTheme.labelLarge?.copyWith(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Open a container to paste',
                      style: textTheme.labelSmall?.copyWith(
                        color: cs.onInverseSurface.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 1,
                height: 28,
                color: cs.onInverseSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: cs.onInverseSurface,
                ),
                tooltip: 'Cancel',
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SlideLeftRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  SlideLeftRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(-1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        );
}