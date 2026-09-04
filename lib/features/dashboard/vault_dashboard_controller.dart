import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

part 'vault_dashboard_controller.g.dart';

const _kLogTag = 'VaultDashboardController';

class VaultDashboardViewState {
  final List<MountedContainer> mounted;
  final Map<String, ContainerRecord> records;
  final List<String> recordsOrder;
  final AppSettings appSettings;
  final bool isLoading;
  final bool actionInFlight;

  // Undo removal state
  final ContainerRecord? recentlyDeletedRecord;
  final String? recentlyDeletedUri;
  final int? recentlyDeletedIndex;
  final bool showUndoBar;
  final Set<String> animatingOutUris;
  final Set<String> animatingInUris;

  const VaultDashboardViewState({
    this.mounted = const [],
    this.records = const {},
    this.recordsOrder = const [],
    required this.appSettings,
    this.isLoading = true,
    this.actionInFlight = false,
    this.recentlyDeletedRecord,
    this.recentlyDeletedUri,
    this.recentlyDeletedIndex,
    this.showUndoBar = false,
    this.animatingOutUris = const {},
    this.animatingInUris = const {},
  });

  VaultDashboardViewState _copy({
    List<MountedContainer>? mounted,
    Map<String, ContainerRecord>? records,
    List<String>? recordsOrder,
    AppSettings? appSettings,
    bool? isLoading,
    bool? actionInFlight,
    ContainerRecord? recentlyDeletedRecord,
    bool clearRecentlyDeleted = false,
    String? recentlyDeletedUri,
    int? recentlyDeletedIndex,
    bool? showUndoBar,
    Set<String>? animatingOutUris,
    Set<String>? animatingInUris,
  }) => VaultDashboardViewState(
    mounted: mounted ?? this.mounted,
    records: records ?? this.records,
    recordsOrder: recordsOrder ?? this.recordsOrder,
    appSettings: appSettings ?? this.appSettings,
    isLoading: isLoading ?? this.isLoading,
    actionInFlight: actionInFlight ?? this.actionInFlight,
    recentlyDeletedRecord: clearRecentlyDeleted
        ? null
        : (recentlyDeletedRecord ?? this.recentlyDeletedRecord),
    recentlyDeletedUri: clearRecentlyDeleted
        ? null
        : (recentlyDeletedUri ?? this.recentlyDeletedUri),
    recentlyDeletedIndex: clearRecentlyDeleted
        ? null
        : (recentlyDeletedIndex ?? this.recentlyDeletedIndex),
    showUndoBar: showUndoBar ?? this.showUndoBar,
    animatingOutUris: animatingOutUris ?? this.animatingOutUris,
    animatingInUris: animatingInUris ?? this.animatingInUris,
  );
}

@Riverpod(keepAlive: true)
class VaultDashboardController extends _$VaultDashboardController {
  final Map<int, Timer> _autoCloseTimers = {};
  Timer? _undoTimer;
  Future<void>? _loadAllFuture;

  static final Set<int> _activeBatches = {};
  static final Set<int> _lockPending = {};

  bool acquireLockGuard(int volId) {
    if (_activeBatches.contains(volId) || _lockPending.contains(volId)) {
      return false;
    }
    _lockPending.add(volId);
    return true;
  }

  void releaseLockGuard(int volId) {
    _lockPending.remove(volId);
  }

  late final void Function(int) _onUsbDetachedListener;
  late final void Function(int) _onHiddenVolProtectionListener;
  late final void Function(int) _onVaultForceLockedListener;
  late final void Function(MountedContainer) _onVaultAutomationUnlockedListener;
  late final void Function() _onScreenOffListener;

  @override
  VaultDashboardViewState build() {
    final state = VaultDashboardViewState(appSettings: AppSettings());

    final events = ref.read(vaultEngineEventsProvider);
    final lockController = ref.read(sessionLockControllerProvider);

    _onUsbDetachedListener = (volId) => onUsbContainerDetached(volId);
    _onHiddenVolProtectionListener = (volId) =>
        onHiddenVolumeProtectionTriggered(volId);
    _onVaultForceLockedListener = (volId) => onVaultForceLocked(volId);
    _onVaultAutomationUnlockedListener = (container) =>
        onVaultAutomationUnlocked(container);
    _onScreenOffListener = lockController.handleScreenOff;

    events.addUsbContainerDetachedListener(_onUsbDetachedListener);
    events.addHiddenVolumeProtectionTriggeredListener(
      _onHiddenVolProtectionListener,
    );
    events.addVaultForceLockedListener(_onVaultForceLockedListener);
    events.addVaultAutomationUnlockedListener(
      _onVaultAutomationUnlockedListener,
    );
    events.addScreenOffListener(_onScreenOffListener);

    ref.onDispose(() {
      for (final t in _autoCloseTimers.values) {
        t.cancel();
      }
      _autoCloseTimers.clear();
      _undoTimer?.cancel();

      events.removeUsbContainerDetachedListener(_onUsbDetachedListener);
      events.removeHiddenVolumeProtectionTriggeredListener(
        _onHiddenVolProtectionListener,
      );
      events.removeVaultForceLockedListener(_onVaultForceLockedListener);
      events.removeVaultAutomationUnlockedListener(
        _onVaultAutomationUnlockedListener,
      );
      events.removeScreenOffListener(_onScreenOffListener);
    });

    Future.microtask(loadAll);
    return state;
  }

  Future<void> loadAll() {
    return _loadAllFuture ??= _performLoadAll().whenComplete(() {
      _loadAllFuture = null;
    });
  }

  Future<void> _performLoadAll() async {
    // Resolve dependencies before the first await. The initial load is
    // scheduled from build(), so a short-lived ProviderContainer (notably
    // a unit test) can dispose this notifier before the settings read
    // finishes; touching ref after that would throw.
    final appSettingsService = ref.read(appSettingsServiceProvider);
    final containerRepository = ref.read(containerRepositoryProvider);

    final settings = await appSettingsService.loadSettings();
    if (!ref.mounted) return;
    final records = await containerRepository.loadAll();
    if (!ref.mounted) return;
    final savedOrder = await containerRepository.loadOrder();
    if (!ref.mounted) return;

    final orderList = <String>[];
    final baseOrder = savedOrder.isNotEmpty ? savedOrder : state.recordsOrder;

    for (final uri in baseOrder) {
      if (records.containsKey(uri) || state.mounted.any((c) => c.uri == uri)) {
        if (!orderList.contains(uri)) {
          orderList.add(uri);
        }
      }
    }
    for (final uri in records.keys) {
      if (!orderList.contains(uri)) orderList.add(uri);
    }
    for (final c in state.mounted) {
      if (!orderList.contains(c.uri)) orderList.add(c.uri);
    }

    state = state._copy(
      appSettings: settings,
      records: Map.unmodifiable(records),
      recordsOrder: List.unmodifiable(orderList),
    );

    await reconcileActiveSessions();
    if (!ref.mounted) return;

    state = state._copy(isLoading: false);
    _syncSecureScreen();
    ref.read(sessionLockControllerProvider).scheduleAutoLock();
  }

  Future<void> reconcileActiveSessions() async {
    final automation = ref.read(vaultAutomationApiProvider);
    final sessions = await automation.getActiveContainerSessions();
    if (!ref.mounted) return;

    final liveVolIds = sessions.map((s) => s.volId).toSet();
    for (final stale in List<MountedContainer>.from(state.mounted)) {
      if (!liveVolIds.contains(stale.volId)) {
        onContainerLocked(stale.volId);
      }
    }
    for (final session in sessions) {
      onContainerMounted(session, record: state.records[session.uri]);
    }
  }

  Future<void> handleRefresh() async {
    await loadAll();
    await Future.wait(
      List<MountedContainer>.from(
        state.mounted,
      ).map((c) => refreshContainerSpace(c.volId)),
    );
  }

  void _syncSecureScreen() {
    final secureScreenPolicy = ref.read(secureScreenPolicyProvider)
      ..anyContainerMounted = state.mounted.isNotEmpty;
    unawaited(
      secureScreenPolicy.apply(preference: state.appSettings.blockScreenshots),
    );
    unawaited(
      ref
          .read(vaultLifecycleApiProvider)
          .syncBackgroundService(
            enabled: state.appSettings.keepVaultsRunningInBackground,
          ),
    );
  }

  void scheduleAutoClose(MountedContainer container) {
    final record = state.records[container.uri];
    final mins = record?.autoCloseMins ?? 0;
    if (mins <= 0) {
      cancelAutoClose(container.volId);
      return;
    }
    _autoCloseTimers[container.volId]?.cancel();
    _autoCloseTimers[container.volId] = Timer(
      Duration(minutes: mins),
      () async {
        if (!ref.mounted) return;
        if (!acquireLockGuard(container.volId)) {
          if (ref.mounted) {
            _autoCloseTimers[container.volId] = Timer(
              const Duration(seconds: 30),
              () => scheduleAutoClose(container),
            );
          }
          return;
        }
        try {
          await ref
              .read(vaultLifecycleApiProvider)
              .lockContainer(container.uri);
          if (!ref.mounted) return;
          onContainerLocked(container.volId);
        } catch (_) {
        } finally {
          releaseLockGuard(container.volId);
        }
      },
    );
  }

  void cancelAutoClose(int volId) {
    _autoCloseTimers[volId]?.cancel();
    _autoCloseTimers.remove(volId);
  }

  void onUserActivityForContainer(int volId) {
    final idx = state.mounted.indexWhere((c) => c.volId == volId);
    if (idx == -1) return;
    final container = state.mounted[idx];
    final record = state.records[container.uri];
    if ((record?.autoCloseMins ?? 0) > 0) {
      scheduleAutoClose(container);
    }
    ref.read(sessionLockControllerProvider).scheduleAutoLock();
  }

  void onContainerMounted(
    MountedContainer container, {
    ContainerRecord? record,
  }) {
    if (state.mounted.any((c) => c.uri == container.uri)) return;

    final newMounted = List<MountedContainer>.from(state.mounted)
      ..add(container);
    final newRecords = Map<String, ContainerRecord>.from(state.records);
    if (record != null && !newRecords.containsKey(container.uri)) {
      newRecords[container.uri] = record;
    }

    final newOrder = List<String>.from(state.recordsOrder);
    if (!newOrder.contains(container.uri)) newOrder.add(container.uri);

    state = state._copy(
      mounted: List.unmodifiable(newMounted),
      records: Map.unmodifiable(newRecords),
      recordsOrder: List.unmodifiable(newOrder),
    );

    _syncSecureScreen();
    scheduleAutoClose(container);
    refreshContainerSpace(container.volId);
    if (record != null) {
      ref.read(containerRepositoryProvider).saveOrder(newOrder);
    }
  }

  void onVaultForceLocked(int volId) {
    VeLog.i(_kLogTag, 'onVaultForceLocked: received native force-lock event for volId=$volId');
    if (!state.mounted.any((c) => c.volId == volId)) {
      VeLog.d(_kLogTag, 'onVaultForceLocked: volId=$volId not mounted, ignoring');
      return;
    }
    onContainerLocked(volId);
  }

  void onVaultAutomationUnlocked(MountedContainer container) {
    onContainerMounted(container, record: state.records[container.uri]);
  }

  void onUsbContainerDetached(int volId) {
    if (!state.mounted.any((c) => c.volId == volId)) return;
    onContainerLocked(volId);
  }

  Future<void> onHiddenVolumeProtectionTriggered(int volId) async {
    final idx = state.mounted.indexWhere((c) => c.volId == volId);
    if (idx == -1) return;
    final container = state.mounted[idx];
    if (acquireLockGuard(volId)) {
      try {
        await ref.read(vaultLifecycleApiProvider).lockContainer(container.uri);
      } catch (_) {
      } finally {
        releaseLockGuard(volId);
      }
    }
    onContainerLocked(volId);
  }

  void onUsbContainerReconnected(
    MountedContainer container,
    ContainerRecord migratedRecord,
    String oldUri,
  ) {
    if (state.mounted.any((c) => c.uri == container.uri)) return;

    final newMounted = List<MountedContainer>.from(state.mounted)
      ..add(container);
    final newRecords = Map<String, ContainerRecord>.from(state.records);
    final newOrder = List<String>.from(state.recordsOrder);

    final oldIndex = newOrder.indexOf(oldUri);
    newRecords.remove(oldUri);
    newOrder.remove(oldUri);
    newRecords[container.uri] = migratedRecord;

    if (oldIndex != -1 && oldIndex <= newOrder.length) {
      newOrder.insert(oldIndex, container.uri);
    } else {
      newOrder.add(container.uri);
    }

    state = state._copy(
      mounted: List.unmodifiable(newMounted),
      records: Map.unmodifiable(newRecords),
      recordsOrder: List.unmodifiable(newOrder),
    );

    _syncSecureScreen();
    scheduleAutoClose(container);
    ref.read(containerRepositoryProvider).saveOrder(newOrder);
  }

  void onContainerLocked(int volId) {
    VeLog.i(
      _kLogTag,
      'onContainerLocked: volId=$volId, currently mounted=${state.mounted.map((c) => c.volId).toList()}',
    );
    cancelAutoClose(volId);
    final idx = state.mounted.indexWhere((c) => c.volId == volId);
    if (idx != -1) {
      final container = state.mounted[idx];
      unawaited(
        ref
            .read(appSecureStorageProvider)
            .delete(key: 'temp_pw_${container.uri}')
            .catchError((_) {}),
      );
      unawaited(
        ref
            .read(thumbnailCacheServiceProvider)
            .clearAppCache(container)
            .catchError((_) {}),
      );
      MediaAspectRatioCache.clearForUri(container.uri);
    }
    final clip = ref.read(crossContainerClipboardProvider);
    if (clip.hasItems && clip.sourceVolId == volId) {
      ref.read(crossContainerClipboardProvider.notifier).clear();
    }
    ref.read(fileOperationServiceProvider).clearForVolume(volId);
    FullResImageCache.clear();
    ref.read(vaultEngineEventsProvider).notifyContainerLocked(volId);

    final newMounted = state.mounted.where((c) => c.volId != volId).toList();
    state = state._copy(mounted: List.unmodifiable(newMounted));
    VeLog.i(
      _kLogTag,
      'onContainerLocked: volId=$volId removed, remaining mounted='
      '${newMounted.map((c) => c.volId).toList()}',
    );
    _syncSecureScreen();
  }

  Future<void> refreshContainerSpace(int volId) async {
    final idx = state.mounted.indexWhere((c) => c.volId == volId);
    if (idx == -1) return;
    final container = state.mounted[idx];
    try {
      final space = await ref
          .read(vaultFileIoApiProvider)
          .getSpaceInfo(container);
      if (space != null &&
          space.length > 1 &&
          space[0] >= 0 &&
          space[1] >= 0 &&
          ref.mounted) {
        final currentIdx = state.mounted.indexWhere((c) => c.volId == volId);
        if (currentIdx != -1) {
          final newMounted = List<MountedContainer>.from(state.mounted);
          newMounted[currentIdx] = container.copyWith(
            totalSpace: space[0],
            freeSpace: space[1],
          );
          state = state._copy(mounted: List.unmodifiable(newMounted));
        }
      }
    } catch (_) {}
  }

  void handleSwipeToRemove(String uri, ContainerRecord record) {
    final originalIndex = state.recordsOrder.indexOf(uri);
    final animatingOut = Set<String>.from(state.animatingOutUris)..add(uri);

    state = state._copy(
      animatingOutUris: animatingOut,
      recentlyDeletedRecord: record,
      recentlyDeletedUri: uri,
      recentlyDeletedIndex: originalIndex,
      showUndoBar: true,
    );

    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 5), dismissUndo);

    Future.delayed(const Duration(milliseconds: 300), () async {
      await ref.read(containerRepositoryProvider).remove(uri);
      if (!ref.mounted) return;

      final newOut = Set<String>.from(state.animatingOutUris)..remove(uri);
      final newRecords = Map<String, ContainerRecord>.from(state.records)
        ..remove(uri);
      final newOrder = List<String>.from(state.recordsOrder)..remove(uri);

      state = state._copy(
        animatingOutUris: newOut,
        records: Map.unmodifiable(newRecords),
        recordsOrder: List.unmodifiable(newOrder),
      );
      await ref.read(containerRepositoryProvider).saveOrder(newOrder);
    });
  }

  void dismissUndo() {
    _undoTimer?.cancel();
    state = state._copy(showUndoBar: false);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (ref.mounted) {
        state = state._copy(clearRecentlyDeleted: true);
      }
    });
  }

  Future<void> handleUndo() async {
    final record = state.recentlyDeletedRecord;
    final uri = state.recentlyDeletedUri;
    final index = state.recentlyDeletedIndex;
    if (record == null || uri == null) return;

    _undoTimer?.cancel();
    state = state._copy(showUndoBar: false);
    await ref.read(containerRepositoryProvider).save(record);
    if (!ref.mounted) return;

    final newRecords = Map<String, ContainerRecord>.from(state.records)
      ..[uri] = record;
    final newIn = Set<String>.from(state.animatingInUris)..add(uri);
    final newOrder = List<String>.from(state.recordsOrder);

    if (index != null && index >= 0 && index <= newOrder.length) {
      newOrder.insert(index, uri);
    } else {
      newOrder.add(uri);
    }

    state = state._copy(
      records: Map.unmodifiable(newRecords),
      animatingInUris: newIn,
      recordsOrder: List.unmodifiable(newOrder),
    );
    await ref.read(containerRepositoryProvider).saveOrder(newOrder);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (ref.mounted) {
        final clearedIn = Set<String>.from(state.animatingInUris)..remove(uri);
        state = state._copy(
          animatingInUris: clearedIn,
          clearRecentlyDeleted: true,
        );
      }
    });
  }

  Future<void> handleReorder(int oldIndex, int newIndex) async {
    if (state.appSettings.containerSortMode != ContainerSortMode.manual) return;
    final items = getDisplayItems();
    if (oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex >= items.length) {
      return;
    }
    final movedItem = items.removeAt(oldIndex);
    items.insert(newIndex, movedItem);

    final newOrder = items.map((item) => item.uri).toList();
    state = state._copy(recordsOrder: List.unmodifiable(newOrder));
    await ref.read(containerRepositoryProvider).saveOrder(newOrder);
  }

  void setActionInFlight(bool inFlight) =>
      state = state._copy(actionInFlight: inFlight);

  Future<void> updateContainerRecord(String uri, ContainerRecord record) async {
    final newRecords = Map<String, ContainerRecord>.from(state.records)
      ..[uri] = record;
    state = state._copy(records: Map.unmodifiable(newRecords));

    final idx = state.mounted.indexWhere((m) => m.uri == uri);
    if (idx != -1) {
      final oldContainer = state.mounted[idx];
      final newName = record.label.isNotEmpty
          ? record.label
          : record.uri.split('/').last;
      final newContainer = oldContainer.copyWith(displayName: newName);

      final newMounted = List<MountedContainer>.from(state.mounted)
        ..[idx] = newContainer;
      state = state._copy(mounted: List.unmodifiable(newMounted));

      await ref
          .read(vaultLifecycleApiProvider)
          .updateContainerSettings(uri, newName, record.documentProvider);
      scheduleAutoClose(newContainer);
    }
  }

  DateTime _dateAddedProxy(String uri) {
    final idx = state.recordsOrder.indexOf(uri);
    if (idx != -1) return DateTime.fromMillisecondsSinceEpoch(idx * 1000);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<VaultListItem> getDisplayItems() {
    final byUri = <String, VaultListItem>{
      for (final c in state.mounted)
        c.uri: MountedVaultItem(c, sortDate: _dateAddedProxy(c.uri)),
      for (final entry in state.records.entries)
        if (!state.mounted.any((m) => m.uri == entry.key))
          entry.key: LockedVaultItem(
            entry.value,
            sortDate: _dateAddedProxy(entry.key),
          ),
    };

    final ordered = <VaultListItem>[
      for (final uri in state.recordsOrder)
        if (byUri[uri] != null) byUri[uri]!,
    ];
    for (final entry in byUri.entries) {
      if (!state.recordsOrder.contains(entry.key)) ordered.add(entry.value);
    }
    return _applySortMode(ordered);
  }

  List<VaultListItem> _applySortMode(List<VaultListItem> items) {
    final sorted = List<VaultListItem>.from(items);
    switch (state.appSettings.containerSortMode) {
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
      case ContainerSortMode.nameZA:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
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
}