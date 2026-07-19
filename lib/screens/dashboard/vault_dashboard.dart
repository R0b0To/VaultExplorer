import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/mounted_container.dart';
import '../../models/vault_list_item.dart';
import '../../services/app_settings_service.dart';
import '../../services/cross_container_clipboard.dart';
import '../../services/session_lock_controller.dart';
import '../../services/vaultexplorer_api.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/floating_activity_stack.dart';
import '../settings/app_settings_screen.dart';
import '../unlock/unlock_sheet.dart';
import 'widgets/container_config_sheet.dart';
import 'widgets/create_container_sheet.dart';
import 'widgets/empty_state.dart';
import 'widgets/vault_card_row.dart';
import '../browser/file_browser_screen.dart';
import '../unlock/usb_unlock_sheet.dart';
import '../lock/lock_gate_screen.dart';
import 'widgets/usb_create_container_sheet.dart';
import '../../models/container_sort_mode.dart';

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
  const VaultDashboard({super.key});

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

  final Map<int, Timer> _autoCloseTimers = {};

  late final SessionLockController _lockController;
  final SwipeRowGroupController _swipeGroup = SwipeRowGroupController();

  // Undo action, animation, and layout state
  ContainerRecord? _recentlyDeletedRecord;
  String? _recentlyDeletedUri;
  int? _recentlyDeletedIndex;
  bool _showUndoBar = false;
  Timer? _undoTimer;

  // Track cards currently animating
  final Set<String> _animatingOutUris = {};
  final Set<String> _animatingInUris = {};

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
    for (final t in _autoCloseTimers.values) {
      t.cancel();
    }
    _autoCloseTimers.clear();
    _lockController.dispose();
    VaultExplorerApi.removeUsbContainerDetachedListener(_onUsbContainerDetached);
    VaultExplorerApi.removeScreenOffListener(_lockController.handleScreenOff);
    _swipeGroup.dispose();
    _undoTimer?.cancel();
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
    if (!mounted) return;
    setState(() {
      _appSettings = settings;
      _records = Map.from(records);
      _recordsOrder.removeWhere(
        (uri) => !_records.containsKey(uri) && !_mounted.any((c) => c.uri == uri),
      );
      for (final uri in records.keys) {
        _ensureOrdered(uri);
      }
      _isLoading = false;
    });
    _lockController.scheduleAutoLock();
  }

  Future<void> _handleRefresh() async {
    await _loadAll();
    await Future.wait(
      List<MountedContainer>.from(_mounted).map((c) => _refreshContainerSpace(c.volId)),
    );
  }

  void _ensureOrdered(String uri) {
    if (!_recordsOrder.contains(uri)) _recordsOrder.add(uri);
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
      }
      _ensureOrdered(container.uri);
    });
    _scheduleAutoClose(container);
    _refreshContainerSpace(container.volId); 
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
      final oldIndex = _recordsOrder.indexOf(oldUri);
      _records.remove(oldUri);
      _recordsOrder.remove(oldUri);
      _records[container.uri] = migratedRecord;
      if (oldIndex != -1 && oldIndex <= _recordsOrder.length) {
        _recordsOrder.insert(oldIndex, container.uri);
      } else {
        _recordsOrder.add(container.uri);
      }
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
if (space != null && space.length > 1 && space[0] >= 0 && space[1] >= 0 && mounted) {
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
      if (!mounted) return; 
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
      if (!mounted) return; 
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

void _showUsbCreateSheet() {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    Navigator.push(
      context,
      SlideRightRoute(page: const UsbCreateContainerSheet()),
    ).whenComplete(() {
      if (mounted) setState(() => _actionInFlight = false);
    });
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

  Future<void> _showAddOptionsSheet() async {
    if (_actionInFlight) return;
    
    // Briefly lock the UI to prevent double-taps while we query the USB manager
    setState(() => _actionInFlight = true);
    
    bool hasUsb = false;
    try {
      final devices = await vaultExplorerApi.listUsbDevices();
      hasUsb = devices.isNotEmpty;
    } catch (e) {
      debugPrint('Failed to check USB devices: $e');
    }

    if (!mounted) return;
    setState(() => _actionInFlight = false);

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
              subtitle: 'Unlock a file container you already have',
              onTap: () {
                Navigator.pop(sheetContext);
                _showUnlockSheet();
              },
            ),
            
            // Only show USB options if an OTG flash drive is actually plugged in
            if (hasUsb) ...[
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
                icon: Icons.usb_off_rounded,
                iconColor: cs.error,
                title: 'Format USB drive',
                subtitle: 'Erase a drive and create a new encrypted container on it',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showUsbCreateSheet();
                },
              ),
            ],
            
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
      SlideRightRoute(
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
        ),
      ),
    );
  }

  void _handleSwipeToRemove(String uri, ContainerRecord record) async {
    final originalIndex = _recordsOrder.indexOf(uri);

    setState(() {
      _animatingOutUris.add(uri);
      _recentlyDeletedRecord = record;
      _recentlyDeletedUri = uri;
      _recentlyDeletedIndex = originalIndex;
      _showUndoBar = true;
    });

    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 5), () {
      _dismissUndo();
    });

    // We delay the final data deletion until the exit animation finishes
    Future.delayed(const Duration(milliseconds: 300), () async {
      await ContainerRepository.instance.remove(uri);
      if (mounted) {
        setState(() {
          _animatingOutUris.remove(uri);
          _records.remove(uri);
          _recordsOrder.remove(uri);
        });
      }
    });
  }

  void _dismissUndo() {
    _undoTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showUndoBar = false;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _recentlyDeletedRecord = null;
          _recentlyDeletedUri = null;
          _recentlyDeletedIndex = null;
        });
      }
    });
  }

  void _handleUndo() async {
    final record = _recentlyDeletedRecord;
    final uri = _recentlyDeletedUri;
    final index = _recentlyDeletedIndex;

    if (record == null || uri == null) return;

    _undoTimer?.cancel();
    setState(() {
      _showUndoBar = false;
    });

    await ContainerRepository.instance.save(record);

    if (mounted) {
      setState(() {
        _records[uri] = record;
        _animatingInUris.add(uri);
        if (index != null && index >= 0 && index <= _recordsOrder.length) {
          _recordsOrder.insert(index, uri);
        } else {
          _recordsOrder.add(uri);
        }
      });
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _animatingInUris.remove(uri);
          _recentlyDeletedRecord = null;
          _recentlyDeletedUri = null;
          _recentlyDeletedIndex = null;
        });
      }
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

  // ── Card actions (tap / swipe-edit / swipe-delete) ────────────────────────

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
        message: 'Lock the container before removing it.',
        tone: AppBannerTone.warning,
      );
      return;
    }
    _handleSwipeToRemove(item.uri, (item as LockedVaultItem).record);
  }

  // ── Display list & reordering ─────────────────────────────────────────────

  DateTime _dateAddedProxy(String uri) {
    final idx = _recordsOrder.indexOf(uri);
    if (idx != -1) return DateTime.fromMillisecondsSinceEpoch(idx * 1000);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

List<VaultListItem> _buildDisplayItems() {
    final byUri = <String, VaultListItem>{
      for (final c in _mounted) c.uri: MountedVaultItem(c, sortDate: _dateAddedProxy(c.uri)),
      for (final entry in _records.entries)
        if (!_mounted.any((m) => m.uri == entry.key))
          entry.key: LockedVaultItem(entry.value, sortDate: _dateAddedProxy(entry.key)),
    };

    final ordered = <VaultListItem>[
      for (final uri in _recordsOrder)
        if (byUri[uri] != null) byUri[uri]!,
    ];
    for (final entry in byUri.entries) {
      if (!_recordsOrder.contains(entry.key)) ordered.add(entry.value);
    }
    return _applySortMode(ordered);
  }

  /// Applies [_appSettings.containerSortMode] on top of the manually-tracked
  /// [_recordsOrder]. [ContainerSortMode.manual] returns [items] untouched
  /// (drag order); every other mode derives a fresh order every build, so
  /// [_handleReorder] is a no-op while one of them is active — see there.
  List<VaultListItem> _applySortMode(List<VaultListItem> items) {
    final sorted = List<VaultListItem>.from(items);
    switch (_appSettings.containerSortMode) {
      case ContainerSortMode.manual:
        return items;
      case ContainerSortMode.unlockStatus:
        sorted.sort((a, b) {
          if (a.isMounted == b.isMounted) return 0;
          return a.isMounted ? -1 : 1;
        });
        return sorted;
      case ContainerSortMode.nameAZ:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return sorted;
      case ContainerSortMode.newest:
        sorted.sort((a, b) => b.sortDate.compareTo(a.sortDate));
        return sorted;
      case ContainerSortMode.oldest:
        sorted.sort((a, b) => a.sortDate.compareTo(b.sortDate));
        return sorted;
    }
  }

void _handleReorder(int oldIndex, int newIndex) {
    if (_appSettings.containerSortMode != ContainerSortMode.manual) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final items = _buildDisplayItems();
    final movedUri = items[oldIndex].uri;

    setState(() {
      _recordsOrder.remove(movedUri);
      _recordsOrder.insert(newIndex.clamp(0, _recordsOrder.length), movedUri);
    });
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(List<VaultListItem> displayItems) {
    if (displayItems.isEmpty && !_isLoading) {
      return EmptyState(onAdd: _showAddOptionsSheet);
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            itemCount: displayItems.length,
            onReorderItem: _handleReorder,
            itemBuilder: (context, i) {
              final item = displayItems[i];
               final bool triggerNudge = i == 0 && !_appSettings.hasSeenSwipeTutorial;
              return VaultCardRow(
                key: ValueKey(item.uri),
                index: i,
                item: item,
                group: _swipeGroup,
                onOpen: () => _openItem(item),
                onEdit: () => _requestEdit(item),
                onDelete: () => _requestDelete(item),
                onLocked: _onContainerLocked,
                isRemoving: _animatingOutUris.contains(item.uri),
                isInserting: _animatingInUris.contains(item.uri),
                triggerNudge: triggerNudge,
                swapActions: _appSettings.swapCardActions,                                   
                dragEnabled: _appSettings.containerSortMode == ContainerSortMode.manual,  
                onNudgeComplete: () async {
                  final updated = _appSettings.copyWith(hasSeenSwipeTutorial: true);
                  await AppSettingsService.saveSettings(updated);
                  if (mounted) {
                    setState(() {
                      _appSettings = updated;
                    });
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayItems = _buildDisplayItems();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final double undoBarHeight = 64.0 + (bottomInset > 0 ? bottomInset : 16.0);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lockController.scheduleAutoLock(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vault Explorer'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'Settings',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
                );
                if (mounted) _loadAll();
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _actionInFlight ? null : _showAddOptionsSheet,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add vault'),
        ),
        body: Stack(
          children: [
            _buildBody(displayItems),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 88,
              child: Center(
                child: FloatingActivityStack(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: _showUndoBar ? undoBarHeight : 0.0,
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Container(
              height: undoBarHeight,
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? bottomInset : 16.0),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                offset: _showUndoBar ? Offset.zero : const Offset(0, 1.5),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _showUndoBar ? 1.0 : 0.0,
                  child: _FloatingUndoBar(
                    label: _recentlyDeletedRecord?.label ?? '',
                    onUndo: _handleUndo,
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

  const _FloatingUndoBar({
    required this.label,
    required this.onUndo,
  });

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
                'Removed "$label"',
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
            child: const Text(
              'Undo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
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