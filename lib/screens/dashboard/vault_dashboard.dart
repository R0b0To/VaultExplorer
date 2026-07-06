import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/mounted_container.dart';
import '../../services/app_settings_service.dart';
import '../../services/cross_container_clipboard.dart';
import '../../services/vaultexplorer_api.dart';
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
  int _currentIndex = 0; // 0: Vaults, 1: Settings

  VaultSortField _sortField = VaultSortField.name;
  bool _sortAscending = true;

  final Map<int, Timer> _autoCloseTimers = {};

  DateTime? _pausedAt;
  Timer? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VaultExplorerApi.addUsbContainerDetachedListener(_onUsbContainerDetached);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _autoCloseTimers.values) t.cancel();
    _autoCloseTimers.clear();
    _autoLockTimer?.cancel();
    VaultExplorerApi.removeUsbContainerDetachedListener(_onUsbContainerDetached);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final c in List<MountedContainer>.from(_mounted)) {
        _refreshContainerSpace(c.volId);
      }

      final pausedAt = _pausedAt;
      _pausedAt = null;

      final mins = _appSettings.autoLockMins;
      final wasAwayTooLong = pausedAt != null &&
          mins > 0 &&
          DateTime.now().difference(pausedAt) >= Duration(minutes: mins);

      if (wasAwayTooLong) {
        _performAutoLock();
      } else {
        _scheduleAutoLock();
      }
    } else if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    }
  }

  void _scheduleAutoLock() {
    _autoLockTimer?.cancel();
    final mins = _appSettings.autoLockMins;
    final hasMasterPassword =
        _appSettings.useMasterPassword && _appSettings.masterPasswordHash != null;
    if (mins <= 0 || (!hasMasterPassword && !_appSettings.lockContainersOnScreenLock)) {
      return;
    }
    _autoLockTimer = Timer(Duration(minutes: mins), _performAutoLock);
  }

  Future<void> _performAutoLock() async {
    _autoLockTimer?.cancel();
    if (_appSettings.lockContainersOnScreenLock) {
      await _lockAllMountedContainers();
    }
    if (!mounted) return;
    final hasMasterPassword =
        _appSettings.useMasterPassword && _appSettings.masterPasswordHash != null;
    if (_appSettings.lockContainersOnScreenLock || hasMasterPassword) {
      await _enforceAppLock();
    }
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
      });
      _scheduleAutoLock();
    }
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
    _scheduleAutoLock();
  }

  void _cancelAutoClose(int volId) {
    _autoCloseTimers[volId]?.cancel();
    _autoCloseTimers.remove(volId);
  }

  // ── Container lifecycle ───────────────────────────────────────────────────

void _onContainerMounted(MountedContainer container, {ContainerRecord? record}) {
    // Safeguard: do not add if already present in state
    if (_mounted.any((c) => c.uri == container.uri)) {
      return;
    }

    setState(() {
      _mounted.add(container);
      // The caller (UnlockSheet / UsbUnlockSheet) already persisted the record
      // (or deliberately didn't, if the user chose not to remember it) — it
      // knows the full picture: cipher/hash, cacheDerivedKey, unlock method,
      // etc. We only mirror it into our in-memory view so the dashboard
      // reflects it immediately. We must NOT fabricate a bare-bones record
      // here: doing so used to (a) ignore the "remember" toggle entirely and
      // (b) clobber the caller's fuller record with a stripped-down one.
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('USB drive disconnected — container locked')),
    );
  }
  void _onUsbContainerReconnected(
    MountedContainer container,
    ContainerRecord migratedRecord,
    String oldUri,
  ) {
    // Safeguard: do not add if already present in state
    if (_mounted.any((c) => c.uri == container.uri)) {
      return;
    }

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
    // If the card is clicked but already mounted, do not navigate
    if (uri != null && _mounted.any((c) => c.uri == uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This container is already mounted.')),
      );
      return;
    }

    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);

    String? rememberedPassword;
    if (uri != null) {
      final record = _records[uri];
      if (record?.unlockMethod == ContainerUnlockMethod.rememberPassword) {
        rememberedPassword = await ContainerRepository.instance.getPassword(
          uri,
        );
      }
    }

    final record = uri != null ? _records[uri] : null;
    final docProvider =
        record?.documentProvider ?? _appSettings.defaultDocumentProvider;

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
            mountedUris: _mounted.map((c) => c.uri).toList(), // <--- Pass the URIs here
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
    if (existingRecord != null &&
        existingRecord.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      rememberedPassword = await ContainerRepository.instance.getPassword(
        existingRecord.uri,
      );
    }

    try {
      await Navigator.push(
        context,
        SlideRightRoute(
          page: UsbUnlockSheet(
            onMounted: _onContainerMounted,
            onReconnected: _onUsbContainerReconnected,
            documentProvider:
                existingRecord?.documentProvider ??
                _appSettings.defaultDocumentProvider,
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

  

void _showContainerConfig({
  required String uri,
  required String currentLabel,
}) {
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
            final newName = record.label.isNotEmpty
                ? record.label
                : record.uri.split('/').last;

            final newContainer = oldContainer.copyWith(displayName: newName);
            if (mounted) setState(() => _mounted[idx] = newContainer);

            await vaultExplorerApi.updateContainerSettings(
              uri,
              newName,
              record.documentProvider,
            );

            _scheduleAutoClose(newContainer);
          }
        },
        onForget: _mounted.any((m) => m.uri == uri)
            ? null
            : () => _forgetContainer(uri, currentLabel),
      ),
    ),
  );
}

  Future<bool> _forgetContainer(String uri, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove container?'),
        content: Text(
          'Remove "$name" from the dashboard? '
          'The container file is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('Removed "${record.label}" from dashboard'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            // Tapping the action doesn't auto-hide a SnackBar in Flutter — without
            // this call the banner just sits there, visible, until its full
            // duration elapses even though the undo already completed.
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

  // ── Sort Helpers ─────────────────────────────────────────────────────────

  String _getItemName(dynamic item) {
    if (item is MountedContainer) {
      return item.displayName;
    } else if (item is ContainerRecord) {
      return item.label.isNotEmpty ? item.label : item.uri.split('/').last;
    }
    return '';
  }

  DateTime _getItemDate(dynamic item) {
    try {
      final dynamic d = item;
      if (d.createdAt != null) return d.createdAt as DateTime;
    } catch (_) {}
    try {
      final dynamic d = item;
      if (d.dateAdded != null) return d.dateAdded as DateTime;
    } catch (_) {}

    final String? uri = item is MountedContainer
        ? item.uri
        : (item is ContainerRecord ? item.uri : null);

    if (uri != null) {
      final idx = _recordsOrder.indexOf(uri);
      if (idx != -1) {
        return DateTime.fromMillisecondsSinceEpoch(idx * 1000);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _getItemSize(dynamic item) {
    if (item is MountedContainer) {
      return item.totalSpace;
    }
    return 0; // Saved/Locked records do not have sizes loaded
  }

  int _getItemStatus(dynamic item) {
    if (item is MountedContainer) {
      return 1; // Mounted is higher
    }
    return 0; // Saved is lower
  }

  // ── Tab Builders ──────────────────────────────────────────────────────────

  Widget _buildVaultsTab(List<dynamic> displayItems, ColorScheme cs, TextTheme textTheme) {
    if (displayItems.isEmpty) {
      return EmptyState(onAdd: () => _showUnlockSheet());
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: displayItems.length,
      separatorBuilder: (_, i) => const SizedBox(height: 16),
      itemBuilder: (_, i) {
        final item = displayItems[i];
        final String uri;
        final String label;
        final bool isMounted;

        if (item is MountedContainer) {
          uri = item.uri;
          label = item.displayName;
          isMounted = true;
        } else {
          final record = item as ContainerRecord;
          uri = record.uri;
          label = record.label.isNotEmpty ? record.label : record.uri.split('/').last;
          isMounted = false;
        }

        return Dismissible(
          key: Key('dismiss_$uri'),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (direction) async {
            if (isMounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lock the container before removing it.')),
              );
              return false;
            }
            return true;
          },
          onDismissed: (direction) {
            _handleSwipeToRemove(uri, item as ContainerRecord);
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
          child: isMounted
              ? ContainerCard(
                  container: item,
                  onLocked: _onContainerLocked,
                  onBrowse: () => _openBrowser(item),
                  onLongPress: () => _showContainerConfig(uri: uri, currentLabel: label),
                )
              : SavedContainerCard(
                  name: label,
                  uri: uri,
                  onUnlock: () => (item as ContainerRecord).isUsbSource
                      ? _showUsbUnlockSheet(existingRecord: item)
                      : _showUnlockSheet(uri: uri, name: label),
                  onLongPress: () => _showContainerConfig(uri: uri, currentLabel: label),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final displayItems = <dynamic>[];
    displayItems.addAll(_mounted);
    for (final entry in _records.entries) {
      if (!_mounted.any((m) => m.uri == entry.key)) {
        displayItems.add(entry.value);
      }
    }

    // Apply sorting selection with potential inverse logic
    displayItems.sort((a, b) {
      int result = 0;
      switch (_sortField) {
        case VaultSortField.name:
          result = _getItemName(a).toLowerCase().compareTo(_getItemName(b).toLowerCase());
          break;
        case VaultSortField.date:
          result = _getItemDate(a).compareTo(_getItemDate(b));
          break;
        case VaultSortField.size:
          result = _getItemSize(a).compareTo(_getItemSize(b));
          break;
        case VaultSortField.status:
          result = _getItemStatus(a).compareTo(_getItemStatus(b));
          break;
      }
      return _sortAscending ? result : -result;
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _scheduleAutoLock(),
      child: Scaffold(
        appBar: _currentIndex == 0
            ? AppBar(
                title: const Text(
                  'Vaults',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  // Sort Field Selector
                  PopupMenuButton<VaultSortField>(
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: 'Sort Options',
                    initialValue: _sortField,
                    onSelected: (VaultSortField selectedField) {
                      setState(() {
                        _sortField = selectedField;
                      });
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<VaultSortField>>[
                      const PopupMenuItem<VaultSortField>(
                        value: VaultSortField.name,
                        child: Row(
                          children: [
                            Icon(Icons.sort_by_alpha_rounded),
                            SizedBox(width: 10),
                            Text('Sort by Name'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<VaultSortField>(
                        value: VaultSortField.date,
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded),
                            SizedBox(width: 10),
                            Text('Sort by Date Added'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<VaultSortField>(
                        value: VaultSortField.size,
                        child: Row(
                          children: [
                            Icon(Icons.sd_card_outlined),
                            SizedBox(width: 10),
                            Text('Sort by Size'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<VaultSortField>(
                        value: VaultSortField.status,
                        child: Row(
                          children: [
                            Icon(Icons.toggle_on_rounded),
                            SizedBox(width: 10),
                            Text('Sort by Mount Status'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Sort Order Inverse Toggle
                  IconButton(
                    icon: Icon(_sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                    tooltip: 'Invert Sorting Order',
                    onPressed: () {
                      setState(() => _sortAscending = !_sortAscending);
                    },
                  ),
                  // Floating Add Menu anchored right below the AppBar action
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    tooltip: 'Add Container',
                    offset: const Offset(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onSelected: (value) {
                      if (value == 'mount_file') {
                        _showUnlockSheet();
                      } else if (value == 'mount_usb') {
                        _showUsbUnlockSheet();
                      } else if (value == 'create_new') {
                        _showCreateSheet();
                      }
                    },
                    itemBuilder: (context) {
                      return [
                        PopupMenuItem(
                          value: 'mount_file',
                          child: Row(
                            children: [
                              Icon(Icons.lock_open_rounded, color: cs.primary),
                              const SizedBox(width: 12),
                              const Text('Mount Existing Container'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'mount_usb',
                          child: Row(
                            children: [
                              Icon(Icons.usb_rounded, color: cs.tertiary),
                              const SizedBox(width: 12),
                              const Text('Mount USB Drive'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'create_new',
                          child: Row(
                            children: [
                              Icon(Icons.add_box_rounded, color: cs.secondary),
                              const SizedBox(width: 12),
                              const Text('Create New Container'),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          height: 64,
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
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: [
                _buildVaultsTab(displayItems, cs, textTheme),
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
            const begin = Offset(-1.0, 0.0); // Start offscreen left
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