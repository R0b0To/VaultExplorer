import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/mounted_container.dart';
import '../../services/app_settings_service.dart';
import '../../services/cross_container_clipboard.dart';
import '../../services/vaultexplorer_api.dart';
import '../../theme.dart';
import '../settings/app_settings_screen.dart';
import '../unlock/unlock_sheet.dart';
import 'widgets/container_card.dart';
import 'widgets/container_config_sheet.dart';
import 'widgets/create_container_sheet.dart';
import 'widgets/empty_state.dart';
import '../browser/file_browser_screen.dart';
import '../unlock/usb_unlock_sheet.dart';
import '../lock/lock_gate_screen.dart';

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({Key? key}) : super(key: key);

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

class _VaultDashboardState extends State<VaultDashboard>
    with WidgetsBindingObserver {
  final List<MountedContainer> _mounted = [];
  Map<String, ContainerRecord> _records = {};
  AppSettings _appSettings = AppSettings();
  bool _actionInFlight = false;

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

  void _onContainerMounted(MountedContainer container, {bool remember = true}) {
    setState(() => _mounted.add(container));
    _scheduleAutoClose(container);

    if (remember && !_records.containsKey(container.uri)) {
      final record = ContainerRecord(
        uri: container.uri,
        label: container.displayName,
        documentProvider: _appSettings.defaultDocumentProvider,
      );
      _records[container.uri] = record;
      ContainerRepository.instance.save(record);
    }
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
    setState(() {
      _mounted.add(container);
      _records.remove(oldUri);
      _records[container.uri] = migratedRecord;
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
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true, // Modern Android requirement for full-screen bottom sheets
        showDragHandle: true, // Native MD3 handle
        builder: (_) => UnlockSheet(
          onMounted: _onContainerMounted,
          initialUri: uri,
          initialName: name,
          prefillPassword: rememberedPassword,
          documentProvider: docProvider,
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
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => UsbUnlockSheet(
          onMounted: _onContainerMounted,
          onReconnected: _onUsbContainerReconnected,
          documentProvider:
              existingRecord?.documentProvider ??
              _appSettings.defaultDocumentProvider,
          existingRecord: existingRecord,
          prefillPassword: rememberedPassword,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const CreateContainerSheet(),
    ).whenComplete(() {
      if (mounted) setState(() => _actionInFlight = false);
    });
  }

  /// Modern MD3 Creation Bottom Sheet triggered by the Floating Action Button
  void _showAddContainerMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      showDragHandle: true, // Standard OS-level grab handle
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        // Much softer plush top corners standard in Android 15/16
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    'Add Container',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ModernListTile(
                  icon: Icons.lock_open_rounded,
                  iconColor: cs.onPrimaryContainer,
                  iconBackground: cs.primaryContainer,
                  title: 'Mount Existing Container',
                  subtitle: 'Unlock an encrypted vault from storage',
                  onTap: () {
                    Navigator.pop(context);
                    _showUnlockSheet();
                  },
                ),
                const SizedBox(height: 4),
                _ModernListTile(
                  icon: Icons.usb_rounded,
                  iconColor: cs.onTertiaryContainer,
                  iconBackground: cs.tertiaryContainer,
                  title: 'Mount USB Drive',
                  subtitle: 'Unlock a fully-encrypted external drive',
                  onTap: () {
                    Navigator.pop(context);
                    _showUsbUnlockSheet();
                  },
                ),
                const SizedBox(height: 4),
                _ModernListTile(
                  icon: Icons.add_box_rounded,
                  iconColor: cs.onSecondaryContainer,
                  iconBackground: cs.secondaryContainer,
                  title: 'Create New Container',
                  subtitle: 'Generate a new encrypted volume',
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateSheet();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showContainerConfig({
    required String uri,
    required String currentLabel,
  }) {
    HapticFeedback.mediumImpact();
    final existing = _records[uri];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ContainerConfigSheet(
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
    );
  }

  Future<void> _forgetContainer(String uri, String name) async {
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
    if (confirmed != true) return;

    await ContainerRepository.instance.remove(uri);
    if (mounted) setState(() => _records.remove(uri));
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

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _scheduleAutoLock(),
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0, // Flat standard M3 interaction
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg - 1),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Vault Explorer',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.2, // Modern typography tweak
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.settings_outlined, size: AppIconSize.action),
              tooltip: 'App Settings',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
                );
                _loadAll();
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddContainerMenu,
          elevation: 2, // Modern low-lift tonal standard
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Vault'),
        ),

        // ── Body: list + floating clipboard pill ────────────────────────────
        body: Stack(
          children: [
            // 1. The main list
            Positioned.fill(
              child: displayItems.isEmpty
                  ? EmptyState(onAdd: () => _showUnlockSheet())
                  : ListView.separated(
                      // Pushed top padding and side paddings to give large radii room
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                      itemCount: displayItems.length,
                      // Increased separator height to balance the plush new 24dp cards
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (_, i) {
                        final item = displayItems[i];
                        if (item is MountedContainer) {
                          return ContainerCard(
                            container: item,
                            onLocked: _onContainerLocked,
                            onBrowse: () => _openBrowser(item),
                            onLongPress: () => _showContainerConfig(
                              uri: item.uri,
                              currentLabel: item.displayName,
                            ),
                          );
                        } else {
                          final record = item as ContainerRecord;
                          return SavedContainerCard(
                            name: record.label.isNotEmpty
                                ? record.label
                                : record.uri.split('/').last,
                            uri: record.uri,
                            onUnlock: () => record.isUsbSource
                                ? _showUsbUnlockSheet(existingRecord: record)
                                : _showUnlockSheet(
                                    uri: record.uri,
                                    name: record.label,
                                  ),
                            onLongPress: () => _showContainerConfig(
                              uri: record.uri,
                              currentLabel: record.label,
                            ),
                          );
                        }
                      },
                    ),
            ),

            // 2. The Floating Clipboard Pill
            Positioned(
              left: 0,
              right: 0,
              bottom: 88,
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

// ── Internal Widget for Add Menu ──────────────────────────────────────────────

class _ModernListTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModernListTile({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), // Rounded ripples
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: iconBackground,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
    );
  }
}

// ── Floating Clipboard Banner for Dashboard (MD3 Pill) ──────────────────────

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
        // Replaced heavy shadow/elevation with flat inverse surface mapping
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